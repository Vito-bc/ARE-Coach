"""CI guard for the content: fail the build before a known defect ships again.

Every check here exists because the defect it catches actually reached main once.
Adding a check is cheap; re-finding the bug in an audit six months later is not.

Run:
    python -m src.check_bank          # exit 1 on any failure
    python -m src.check_bank --warn   # report only (never fails the build)
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter

from src import config
from src.schema import load_questions

# --- encoding -----------------------------------------------------------------
# UTF-8 bytes decoded as cp1252 leave one of these as the lead character. 14
# flashcards shipped this way (CO2, !=, <=, >=, ~=, minus, span^4); an earlier
# fix only caught em-dashes, so nobody noticed the math symbols were broken.
MOJIBAKE_LEADS = ("â", "Ã", "Â")
REPLACEMENT_CHAR = "�"  # irrecoverable damage

# --- superseded sources -------------------------------------------------------
# A citation to a code edition that is no longer in force is worse than no
# citation: the candidate studies the wrong rule. We ingested the 2020 NYCECC
# into the RAG corpus months after the 2025 edition took effect (2026-03-30).
SUPERSEDED = {
    "2020 NYCECC": "2025 NYCECC has been in force since 2026-03-30",
    "2020 NYC Energy": "2025 NYCECC has been in force since 2026-03-30",
}

# --- answer position ----------------------------------------------------------
# The bank once had 38% of correct answers at option 1 and 14% at option 4 —
# guessable without reading the question.
MAX_POSITION_SHARE = 0.32  # even would be 0.25


class Report:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.notes: list[str] = []

    def fail(self, check: str, detail: str) -> None:
        self.failures.append(f"FAIL  {check}: {detail}")

    def ok(self, check: str, detail: str) -> None:
        self.notes.append(f"ok    {check}: {detail}")


def _mojibake_in(text: str) -> bool:
    return any(ch in text for ch in MOJIBAKE_LEADS) or REPLACEMENT_CHAR in text


def check_schema(rep: Report, res) -> None:
    if res.errors:
        rep.fail("schema", f"{len(res.errors)} invalid question(s): {res.errors[:3]}")
    else:
        rep.ok("schema", f"{len(res.valid)} questions valid (4 unique options, answer among them)")


def check_unique_ids(rep: Report, qs) -> None:
    dupes = [i for i, n in Counter(q.id for q in qs).items() if n > 1]
    if dupes:
        rep.fail("unique-ids", f"duplicate ids: {dupes[:5]}")
    else:
        rep.ok("unique-ids", f"{len(qs)} ids unique")


def check_unique_stems(rep: Report, qs) -> None:
    norm = lambda s: " ".join(s.lower().split())
    dupes = [s for s, n in Counter(norm(q.question) for q in qs).items() if n > 1]
    if dupes:
        rep.fail("unique-stems", f"{len(dupes)} identical question stem(s), e.g. {dupes[0][:60]!r}")
    else:
        rep.ok("unique-stems", "no identical stems")


def check_encoding(rep: Report, qs) -> None:
    bad = [
        q.id
        for q in qs
        if _mojibake_in(" ".join([q.question, q.explanation, q.codeReference, *q.options]))
    ]
    if bad:
        rep.fail("encoding", f"{len(bad)} question(s) with mojibake/replacement chars: {bad[:5]}")
    else:
        rep.ok("encoding", "question bank is clean UTF-8")

    # Flashcards live outside the Question schema but ship in the same app.
    fc_path = config.REPO_ROOT / "assets" / "seeds" / "flashcards_ny.json"
    if fc_path.exists():
        cards = json.loads(fc_path.read_text(encoding="utf-8-sig"))
        bad_fc = [c.get("id") for c in cards if _mojibake_in(json.dumps(c, ensure_ascii=False))]
        if bad_fc:
            rep.fail("encoding", f"{len(bad_fc)} flashcard(s) with mojibake: {bad_fc[:5]}")
        else:
            rep.ok("encoding", f"{len(cards)} flashcards clean")


def check_superseded_sources(rep: Report, qs) -> None:
    hits = []
    for q in qs:
        blob = f"{q.codeReference} {q.explanation}"
        for marker, why in SUPERSEDED.items():
            if marker.lower() in blob.lower():
                hits.append(f"{q.id} cites '{marker}' ({why})")
    if hits:
        rep.fail("superseded-sources", f"{len(hits)} citation(s) to a dead edition: {hits[:3]}")
    else:
        rep.ok("superseded-sources", "no citations to superseded code editions")


def check_answer_positions(rep: Report, qs) -> None:
    # NOTE: Question.correct_index is 1-BASED (1..4), not 0-based.
    positions = Counter(q.correct_index for q in qs)
    total = sum(positions.values())
    shares = {p: positions[p] / total for p in (1, 2, 3, 4)}
    worst = max(shares, key=shares.get)
    pretty = " / ".join(f"{shares[p]:.0%}" for p in (1, 2, 3, 4))
    if shares[worst] > MAX_POSITION_SHARE:
        rep.fail(
            "answer-position",
            f"option {worst} holds {shares[worst]:.0%} of correct answers "
            f"(cap {MAX_POSITION_SHARE:.0%}) — distribution {pretty}. Run `python -m src.fix_positions --apply`.",
        )
    else:
        rep.ok("answer-position", f"even enough — {pretty}")


def check_docs_match_bank(rep: Report, qs) -> None:
    """README once advertised 1,100 questions while the bank held 1,082."""
    n = len(qs)
    readme = (config.REPO_ROOT / "README.md").read_text(encoding="utf-8")
    claimed = {
        int(m.replace(",", ""))
        for m in re.findall(r"([\d,]{3,6})[- ]question", readme)
        + re.findall(r"\*\*([\d,]{3,6}) questions\*\*", readme)
    }
    wrong = {c for c in claimed if c != n}
    if wrong:
        rep.fail("docs-match-bank", f"README claims {sorted(wrong)} question(s); the bank holds {n}")
    else:
        rep.ok("docs-match-bank", f"README agrees with the bank ({n})")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--warn", action="store_true", help="report only; never exit non-zero")
    args = ap.parse_args()

    res = load_questions(config.QUESTIONS_PATH)
    qs = res.valid
    rep = Report()

    check_schema(rep, res)
    if qs:
        check_unique_ids(rep, qs)
        check_unique_stems(rep, qs)
        check_encoding(rep, qs)
        check_superseded_sources(rep, qs)
        check_answer_positions(rep, qs)
        check_docs_match_bank(rep, qs)

    for line in rep.notes:
        print(line)
    for line in rep.failures:
        print(line)

    if rep.failures:
        print(f"\n{len(rep.failures)} check(s) FAILED.")
        sys.exit(0 if args.warn else 1)
    print(f"\nAll {len(rep.notes)} content checks passed.")


if __name__ == "__main__":
    main()
