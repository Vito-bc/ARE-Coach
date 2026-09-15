"""Plan and transactionally apply human-approved generated candidates."""
from __future__ import annotations

import hashlib
import json
import os
import re
import threading
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, BinaryIO, Callable, Iterator

from src.generated_approval import ReviewDecision, ReviewResult, candidate_fingerprint
from src.schema import Question


JOURNAL_SCHEMA = "are-coach.generated-import-journal.v1"
BANK_FINGERPRINT_SCHEMA = "are-coach.bank-question.v1"
ENTRY_FINGERPRINT_SCHEMA = "are-coach.generated-import-entry.v1"
BANK_FIELDS = (
    "id",
    "state",
    "section",
    "difficulty",
    "question",
    "options",
    "correctOption",
    "explanation",
    "codeReference",
    "examWeight",
    "topic",
)
SOURCE_PROVENANCE_FIELDS = (
    "source_document",
    "source_edition",
    "source_page",
    "source_sha256",
)
OPTIONAL_SOURCE_PROVENANCE_FIELDS = (
    "source_metadata_schema",
    "source_path",
    "source_locator",
    "source_chunk_id",
    "source_extraction_version",
    "source_revision",
    "source_missing_metadata",
    "source_not_applicable_metadata",
)


class ImportSafetyError(RuntimeError):
    """An import invariant failed; no new import should proceed."""


def _normalized_path(path: Path) -> Path:
    # Resolve relative paths, '..', symlinks/junctions, and Windows case aliases.
    return Path(os.path.normcase(path.resolve()))


@dataclass(frozen=True)
class BankImportLock:
    bank_path: Path
    stream: BinaryIO
    owner: tuple[int, int]

    def check(self, bank_path: Path) -> None:
        if (self.stream.closed or self.bank_path != _normalized_path(bank_path)
                or self.owner != (os.getpid(), threading.get_ident())):
            raise ImportSafetyError("an active lock for this bank and caller is required")


@contextmanager
def bank_import_lock(
    bank_path: Path, held: BankImportLock | None = None,
) -> Iterator[BankImportLock]:
    """Nonblocking OS lock, held across recovery, planning, commit and cleanup.

    The separate lock file is permanent: unlinking it could let another process
    lock a different inode. Closing the descriptor (including process death)
    releases ownership. Its existence or age never means a lock is held.
    """
    bank_path = _normalized_path(bank_path)
    if held is not None:
        held.check(bank_path)
        yield held
        return
    lock_path = bank_path.with_name(f".{bank_path.name}.generated-import.lock")
    with lock_path.open("a+b") as stream:
        try:
            if os.name == "nt":
                import msvcrt
                stream.seek(0)
                # Windows permits a byte-range lock beyond EOF; no initialization
                # write is needed, even when concurrent openers create the file.
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            raise ImportSafetyError(
                f"cannot acquire bank import lock {lock_path}: {exc}; "
                "retry after the current owner exits; do not delete the lock file"
            ) from exc
        yield BankImportLock(bank_path, stream, (os.getpid(), threading.get_ident()))


@dataclass(frozen=True)
class ImportItem:
    candidate_id: str
    fingerprint: str
    status: str  # add, blocked, already_imported
    reason: str
    bank_id: str | None = None
    bank_row: dict[str, Any] | None = None
    journal_entry: dict[str, Any] | None = None


@dataclass(frozen=True)
class ImportPlan:
    items: list[ImportItem]
    bank_before: list[dict[str, Any]]
    journal_before: dict[str, Any]

    @property
    def additions(self) -> list[ImportItem]:
        return [item for item in self.items if item.status == "add"]

    @property
    def blocked(self) -> list[ImportItem]:
        return [item for item in self.items if item.status == "blocked"]

    @property
    def already_imported(self) -> list[ImportItem]:
        return [item for item in self.items if item.status == "already_imported"]

    @property
    def bank_after(self) -> list[dict[str, Any]]:
        return self.bank_before + [item.bank_row for item in self.additions if item.bank_row]

    @property
    def journal_after(self) -> dict[str, Any]:
        result = json.loads(json.dumps(self.journal_before))
        result["imports"].extend(
            item.journal_entry for item in self.additions if item.journal_entry
        )
        return result


def _canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def _pretty_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def _hash_bytes(data: bytes) -> str:
    return f"sha256:{hashlib.sha256(data).hexdigest()}"


def _file_hash(path: Path) -> str | None:
    if not path.exists():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return f"sha256:{digest.hexdigest()}"


def bank_fingerprint(row: dict[str, Any]) -> str:
    return _hash_bytes(
        _canonical_json({"schema": BANK_FINGERPRINT_SCHEMA, "question": row})
    )


def _entry_fingerprint(entry: dict[str, Any]) -> str:
    content = {key: value for key, value in entry.items() if key != "record_fingerprint"}
    return _hash_bytes(
        _canonical_json({"schema": ENTRY_FINGERPRINT_SCHEMA, "entry": content})
    )


def load_bank(path: Path) -> list[dict[str, Any]]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ImportSafetyError(f"cannot read bank {path}: {exc}") from exc
    return _validate_bank(raw)


def _validate_bank(raw: Any) -> list[dict[str, Any]]:
    if not isinstance(raw, list):
        raise ImportSafetyError("question bank must be a top-level list")
    seen: set[str] = set()
    bank: list[dict[str, Any]] = []
    for index, row in enumerate(raw):
        if not isinstance(row, dict) or not isinstance(row.get("id"), str):
            raise ImportSafetyError(f"invalid bank row at index {index}")
        if row["id"] in seen:
            raise ImportSafetyError(f"duplicate bank id: {row['id']}")
        seen.add(row["id"])
        bank.append(row)
    return bank


def empty_journal() -> dict[str, Any]:
    return {"schema": JOURNAL_SCHEMA, "imports": []}


def load_journal(path: Path) -> dict[str, Any]:
    if not path.exists():
        return empty_journal()
    try:
        journal = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ImportSafetyError(f"cannot read provenance journal {path}: {exc}") from exc
    return _validate_journal(journal)


def _validate_journal(journal: Any) -> dict[str, Any]:
    if not isinstance(journal, dict) or journal.get("schema") != JOURNAL_SCHEMA:
        raise ImportSafetyError("unsupported or invalid provenance journal schema")
    if not isinstance(journal.get("imports"), list):
        raise ImportSafetyError("provenance journal imports must be a list")
    return journal


def verify_bank_journal_consistency(
    bank: list[dict[str, Any]], journal: dict[str, Any]
) -> None:
    by_bank_id = {row["id"]: row for row in bank}
    candidate_ids: set[str] = set()
    bank_ids: set[str] = set()
    for index, entry in enumerate(journal["imports"]):
        if not isinstance(entry, dict):
            raise ImportSafetyError(f"invalid provenance journal entry at index {index}")
        if entry.get("record_fingerprint") != _entry_fingerprint(entry):
            raise ImportSafetyError(f"provenance journal entry {index} fingerprint mismatch")
        candidate_id = entry.get("candidate_id")
        bank_id = entry.get("bank_id")
        if not isinstance(candidate_id, str) or not isinstance(bank_id, str):
            raise ImportSafetyError(f"journal entry {index} has invalid candidate_id/bank_id")
        if candidate_id in candidate_ids:
            raise ImportSafetyError(f"duplicate/conflicting journal candidate id: {candidate_id}")
        if bank_id in bank_ids:
            raise ImportSafetyError(f"duplicate/conflicting journal bank id: {bank_id}")
        candidate_ids.add(candidate_id)
        bank_ids.add(bank_id)
        bank_row = by_bank_id.get(bank_id)
        if bank_row is None:
            raise ImportSafetyError(
                f"journal maps {candidate_id} to missing bank row {bank_id}; recovery required"
            )
        if entry.get("bank_fingerprint") != bank_fingerprint(bank_row):
            raise ImportSafetyError(
                f"bank row {bank_id} differs from its provenance journal; recovery required"
            )
        snapshot = entry.get("candidate_snapshot")
        if not isinstance(snapshot, dict):
            raise ImportSafetyError(f"journal entry for {candidate_id} has no candidate snapshot")
        if snapshot.get("id") != candidate_id:
            raise ImportSafetyError(
                f"journal candidate ID does not match its snapshot for {candidate_id}"
            )
        if entry.get("candidate_fingerprint") != candidate_fingerprint(snapshot):
            raise ImportSafetyError(
                f"candidate snapshot/fingerprint mismatch in journal for {candidate_id}"
            )
        try:
            expected_bank_row = _candidate_bank_row(snapshot, bank_id)
        except Exception as exc:
            raise ImportSafetyError(
                f"journal candidate snapshot is not a valid bank question for {candidate_id}: {exc}"
            ) from exc
        if expected_bank_row != bank_row:
            raise ImportSafetyError(
                f"journal candidate snapshot does not reproduce bank row {bank_id}"
            )
        if entry.get("source_provenance") != _source_provenance(snapshot):
            raise ImportSafetyError(
                f"source provenance does not match candidate snapshot for {candidate_id}"
            )
        human_review = entry.get("human_review")
        if not isinstance(human_review, dict) or human_review.get("verdict") != "Approve":
            raise ImportSafetyError(f"journal entry for {candidate_id} lacks explicit Approve evidence")


def _gen_ids(existing: set[str]):
    number = max(
        (int(match.group(1)) for item in existing if (match := re.fullmatch(r"gen_q(\d+)", item))),
        default=0,
    )
    while True:
        number += 1
        yield f"gen_q{number}"


def _candidate_bank_row(candidate: dict[str, Any], bank_id: str) -> dict[str, Any]:
    row = {field: candidate.get(field) for field in BANK_FIELDS}
    row["id"] = bank_id
    # The current app bank is state-scoped to NY.  The original state remains in
    # candidate_snapshot, so this normalization is visible in provenance.
    row["state"] = "NY"
    Question.model_validate(row)
    return row


def _notes_hash(notes: str) -> str:
    return _hash_bytes(notes.encode("utf-8"))


def _source_provenance(candidate: dict[str, Any]) -> dict[str, Any]:
    source_values = {
        "grounded_on": candidate.get("grounded_on"),
        **{field: candidate.get(field) for field in SOURCE_PROVENANCE_FIELDS},
    }
    source_values.update(
        {
            field: candidate.get(field)
            for field in OPTIONAL_SOURCE_PROVENANCE_FIELDS
            if field in candidate
        }
    )
    not_applicable = candidate.get("source_not_applicable_metadata", [])
    if not isinstance(not_applicable, list):
        not_applicable = []
    missing = [
        field
        for field, value in source_values.items()
        if value in (None, "") and field not in not_applicable
    ]
    return {
        **source_values,
        "complete": not missing,
        "missing_fields": missing,
    }


def _journal_entry(
    decision: ReviewDecision,
    bank_id: str,
    bank_row: dict[str, Any],
    review: ReviewResult,
    review_path: Path,
    imported_at: str,
) -> dict[str, Any]:
    candidate = decision.candidate
    entry = {
        "candidate_id": str(candidate["id"]),
        "bank_id": bank_id,
        "candidate_fingerprint": decision.fingerprint,
        "bank_fingerprint": bank_fingerprint(bank_row),
        "candidate_snapshot": candidate,
        "source_provenance": _source_provenance(candidate),
        "human_review": {
            "verdict": "Approve",
            "workbook_sha256": review.workbook_sha256,
            "source_snapshot_sha256": review.source_sha256,
            "sheet": "review",
            "row": decision.row_number,
            "notes_present": bool(decision.notes),
            "notes_sha256": _notes_hash(decision.notes),
            "workbook_filename": review_path.name,
        },
        "imported_at": imported_at,
    }
    entry["record_fingerprint"] = _entry_fingerprint(entry)
    return entry


def build_import_plan(
    bank: list[dict[str, Any]],
    journal: dict[str, Any],
    review: ReviewResult,
    *,
    review_path: Path,
    imported_at: str | None = None,
) -> ImportPlan:
    verify_bank_journal_consistency(bank, journal)
    imported_at = imported_at or datetime.now(timezone.utc).isoformat()
    existing_by_candidate = {entry["candidate_id"]: entry for entry in journal["imports"]}
    existing_fingerprints = {
        entry["candidate_fingerprint"]: entry for entry in journal["imports"]
    }
    ids = _gen_ids({row["id"] for row in bank})
    items: list[ImportItem] = []
    pending_content: dict[str, str] = {}

    for decision in review.decisions:
        candidate = decision.candidate
        candidate_id = str(candidate["id"])
        if not decision.approved:
            items.append(
                ImportItem(candidate_id, decision.fingerprint, "blocked", decision.reason or "blocked")
            )
            continue
        if candidate.get("accepted") is not True:
            items.append(
                ImportItem(
                    candidate_id,
                    decision.fingerprint,
                    "blocked",
                    "candidate is not marked accepted by the automated gate",
                )
            )
            continue

        prior = existing_by_candidate.get(candidate_id)
        if prior:
            if prior["candidate_fingerprint"] == decision.fingerprint:
                items.append(
                    ImportItem(
                        candidate_id,
                        decision.fingerprint,
                        "already_imported",
                        "this approved version is already mapped",
                        bank_id=prior["bank_id"],
                    )
                )
            else:
                items.append(
                    ImportItem(
                        candidate_id,
                        decision.fingerprint,
                        "blocked",
                        "candidate ID was previously imported with different content",
                    )
                )
            continue
        same_fingerprint = existing_fingerprints.get(decision.fingerprint)
        if same_fingerprint:
            items.append(
                ImportItem(
                    candidate_id,
                    decision.fingerprint,
                    "blocked",
                    f"identical approved candidate is already mapped as {same_fingerprint['candidate_id']}",
                )
            )
            continue

        try:
            candidate_content = _candidate_bank_row(candidate, "<pending>")
        except Exception as exc:
            items.append(
                ImportItem(candidate_id, decision.fingerprint, "blocked", f"schema validation failed: {exc}")
            )
            continue
        content_key = bank_fingerprint(candidate_content)
        if content_key in pending_content:
            items.append(
                ImportItem(
                    candidate_id,
                    decision.fingerprint,
                    "blocked",
                    f"duplicate content in this batch with {pending_content[content_key]}",
                )
            )
            continue
        pending_content[content_key] = candidate_id
        bank_id = next(ids)
        bank_row = _candidate_bank_row(candidate, bank_id)
        entry = _journal_entry(
            decision, bank_id, bank_row, review, review_path, imported_at
        )
        items.append(
            ImportItem(
                candidate_id,
                decision.fingerprint,
                "add",
                "explicit Approve matches candidate fingerprint and visible review row",
                bank_id=bank_id,
                bank_row=bank_row,
                journal_entry=entry,
            )
        )
    return ImportPlan(items=items, bank_before=bank, journal_before=journal)


def transaction_pointer_for(journal_path: Path) -> Path:
    return journal_path.with_name(f".{journal_path.name}.pending.json")


def _write_new(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())


def _load_manifest(pointer_path: Path) -> tuple[Path, dict[str, Any]]:
    try:
        pointer = json.loads(pointer_path.read_text(encoding="utf-8"))
        if not isinstance(pointer, dict) or not isinstance(pointer.get("manifest_path"), str):
            raise ValueError("pending pointer must name a manifest")
        manifest_path = Path(pointer["manifest_path"])
        if not manifest_path.is_absolute():
            raise ValueError("manifest path must be absolute")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if not isinstance(manifest, dict):
            raise ValueError("manifest must be an object")
    except (OSError, ValueError) as exc:
        raise ImportSafetyError(f"invalid pending import transaction {pointer_path}: {exc}") from exc
    if manifest.get("schema") != "are-coach.generated-import-transaction.v1":
        raise ImportSafetyError(f"unsupported pending transaction schema: {manifest_path}")
    required = {
        "bank_path",
        "journal_path",
        "bank_before_sha256",
        "journal_before_sha256",
        "bank_after_sha256",
        "journal_after_sha256",
        "bank_staged_path",
        "journal_staged_path",
    }
    missing = sorted(required - set(manifest))
    if missing:
        raise ImportSafetyError(f"pending transaction is missing fields: {missing}")
    paths = [pointer_path, manifest_path]
    for field in ("bank_path", "journal_path", "bank_staged_path", "journal_staged_path"):
        value = manifest[field]
        if not isinstance(value, str) or not value or not Path(value).is_absolute():
            raise ImportSafetyError(f"invalid transaction path: {field}")
        paths.append(Path(value))
    if len({_normalized_path(path) for path in paths}) != len(paths):
        raise ImportSafetyError("transaction target, staged, manifest and pointer paths must be distinct")
    for field in ("bank_before_sha256", "journal_before_sha256", "bank_after_sha256", "journal_after_sha256"):
        value = manifest[field]
        if field == "journal_before_sha256" and value is None:
            continue
        if not isinstance(value, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", value):
            raise ImportSafetyError(f"invalid transaction hash: {field}")
    return manifest_path, manifest


def pending_transaction_state(pointer_path: Path) -> str | None:
    if not pointer_path.exists():
        return None
    _, manifest = _load_manifest(pointer_path)
    bank_current = _file_hash(Path(manifest["bank_path"]))
    journal_current = _file_hash(Path(manifest["journal_path"]))
    if bank_current == manifest["bank_after_sha256"] and journal_current == manifest["journal_after_sha256"]:
        return "both targets contain the committed state; cleanup is pending"
    if bank_current == manifest["bank_after_sha256"] and journal_current == manifest["journal_before_sha256"]:
        return "bank was written but provenance journal still needs recovery"
    if bank_current == manifest["bank_before_sha256"] and journal_current == manifest["journal_after_sha256"]:
        return "provenance journal was written but bank still needs recovery"
    if bank_current == manifest["bank_before_sha256"] and journal_current == manifest["journal_before_sha256"]:
        return "transaction was staged but neither target was written"
    return "target contents do not match transaction before/after hashes; manual recovery required"


def recover_pending_transaction(
    pointer_path: Path,
    *,
    expected_bank_path: Path | None = None,
    expected_journal_path: Path | None = None,
    replace_target: Callable[[str | Path, str | Path], Any] = os.replace,
    lock: BankImportLock | None = None,
) -> bool:
    """Roll a known partial transaction forward; reject unknown target states."""
    if not pointer_path.exists():
        return False
    if expected_bank_path is None:
        _, manifest = _load_manifest(pointer_path)
        expected_bank_path = Path(manifest["bank_path"])
    with bank_import_lock(expected_bank_path, lock):
        return _recover_pending_transaction_locked(
            pointer_path, expected_bank_path=expected_bank_path,
            expected_journal_path=expected_journal_path, replace_target=replace_target,
        )


def _recover_pending_transaction_locked(
    pointer_path: Path, *, expected_bank_path: Path,
    expected_journal_path: Path | None,
    replace_target: Callable[[str | Path, str | Path], Any],
) -> bool:
    if not pointer_path.exists():
        return False
    _, manifest = _load_manifest(pointer_path)
    bank_path = _normalized_path(Path(manifest["bank_path"]))
    journal_path = _normalized_path(Path(manifest["journal_path"]))
    if _normalized_path(bank_path) != _normalized_path(expected_bank_path):
        raise ImportSafetyError("pending transaction points to an unexpected bank path")
    if expected_journal_path is not None and _normalized_path(journal_path) != _normalized_path(expected_journal_path):
        raise ImportSafetyError("pending transaction points to an unexpected journal path")

    # Preflight BOTH targets and every after-image still needed, before the
    # first mutation. Completed replacements consumed their staged file, so in
    # that case the hash-verified target itself supplies the prepared image.
    replacements: list[tuple[str, Path, Path, str]] = []
    prepared: dict[str, Any] = {}
    for name, target in (("bank", bank_path), ("journal", journal_path)):
        before = manifest[f"{name}_before_sha256"]
        after = manifest[f"{name}_after_sha256"]
        current = _file_hash(target)
        if current == after:
            image = target
        elif current == before:
            image = Path(manifest[f"{name}_staged_path"])
            replacements.append((name, image, target, after))
        else:
            raise ImportSafetyError(
                f"cannot recover {name}: current target matches neither before nor after hash"
            )
        try:
            data = image.read_bytes()
        except OSError as exc:
            raise ImportSafetyError(f"cannot recover {name}: prepared image is unavailable: {exc}") from exc
        if _hash_bytes(data) != after:
            raise ImportSafetyError(f"cannot recover {name}: staged file is missing or changed")
        try:
            prepared[name] = json.loads(data.decode("utf-8-sig"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ImportSafetyError(f"cannot recover {name}: invalid prepared JSON: {exc}") from exc

    prepared_bank = _validate_bank(prepared["bank"])
    prepared_journal = _validate_journal(prepared["journal"])
    verify_bank_journal_consistency(prepared_bank, prepared_journal)

    for name, staged, target, after in replacements:
        target.parent.mkdir(parents=True, exist_ok=True)
        replace_target(staged, target)
        if _file_hash(target) != after:
            raise ImportSafetyError(f"recovered {name} did not match expected hash")

    # Keep the prepared manifest immutable. If cleanup fails or the process
    # dies, the next owner verifies both after-hashes and retries only unlink.
    pointer_path.unlink()
    return True


def apply_import_plan(
    plan: ImportPlan,
    *,
    bank_path: Path,
    journal_path: Path,
    backups_dir: Path,
    transaction_pointer: Path | None = None,
    replace_target: Callable[[str | Path, str | Path], Any] = os.replace,
    lock: BankImportLock | None = None,
) -> Path | None:
    """Stage bank+journal together and commit with a recoverable marker."""
    if not plan.additions:
        return None
    with bank_import_lock(bank_path, lock) as held:
        return _apply_import_plan_locked(
            plan, bank_path=bank_path, journal_path=journal_path,
            backups_dir=backups_dir, transaction_pointer=transaction_pointer,
            replace_target=replace_target, lock=held,
        )


def _apply_import_plan_locked(
    plan: ImportPlan, *, bank_path: Path, journal_path: Path, backups_dir: Path,
    transaction_pointer: Path | None,
    replace_target: Callable[[str | Path, str | Path], Any], lock: BankImportLock,
) -> Path:
    transaction_pointer = transaction_pointer or transaction_pointer_for(journal_path)
    if transaction_pointer.exists():
        raise ImportSafetyError(
            f"pending import transaction exists: {transaction_pointer}; recover it before another import"
        )
    # Refuse a stale plan before staging anything.
    try:
        bank_before_bytes = bank_path.read_bytes()
        current_bank = _validate_bank(json.loads(bank_before_bytes.decode("utf-8-sig")))
        journal_before_bytes = journal_path.read_bytes() if journal_path.exists() else None
        current_journal = (
            _validate_journal(json.loads(journal_before_bytes.decode("utf-8-sig")))
            if journal_before_bytes is not None
            else empty_journal()
        )
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ImportSafetyError(f"cannot capture bank/journal pre-import state: {exc}") from exc
    if current_bank != plan.bank_before or current_journal != plan.journal_before:
        raise ImportSafetyError("bank or provenance journal changed after the dry-run plan")

    bank_after_bytes = _pretty_json(plan.bank_after)
    journal_after_bytes = _pretty_json(plan.journal_after)
    transaction_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:10]
    transaction_dir = backups_dir / "generated_import_transactions" / transaction_id
    transaction_dir.mkdir(parents=True, exist_ok=False)
    bank_staged = transaction_dir / "bank.after.json"
    journal_staged = transaction_dir / "journal.after.json"
    _write_new(bank_staged, bank_after_bytes)
    _write_new(journal_staged, journal_after_bytes)

    _write_new(transaction_dir / "bank.before.json", bank_before_bytes)
    if journal_before_bytes is not None:
        _write_new(transaction_dir / "journal.before.json", journal_before_bytes)

    manifest_path = transaction_dir / "manifest.json"
    manifest = {
        "schema": "are-coach.generated-import-transaction.v1",
        "status": "pending",
        "bank_path": str(bank_path.resolve()),
        "journal_path": str(journal_path.resolve()),
        "bank_before_sha256": _hash_bytes(bank_before_bytes),
        "journal_before_sha256": (
            _hash_bytes(journal_before_bytes) if journal_before_bytes is not None else None
        ),
        "bank_after_sha256": _hash_bytes(bank_after_bytes),
        "journal_after_sha256": _hash_bytes(journal_after_bytes),
        "bank_staged_path": str(bank_staged.resolve()),
        "journal_staged_path": str(journal_staged.resolve()),
    }
    _write_new(manifest_path, _pretty_json(manifest))
    _write_new(
        transaction_pointer,
        _pretty_json({"manifest_path": str(manifest_path.resolve())}),
    )
    recover_pending_transaction(
        transaction_pointer,
        expected_bank_path=bank_path,
        expected_journal_path=journal_path,
        replace_target=replace_target,
        lock=lock,
    )

    # Read back both targets and re-check their cross-reference after the commit.
    committed_bank = load_bank(bank_path)
    committed_journal = load_journal(journal_path)
    verify_bank_journal_consistency(committed_bank, committed_journal)
    return transaction_dir
