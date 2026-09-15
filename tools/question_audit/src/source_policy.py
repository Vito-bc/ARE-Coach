"""Fail-closed source eligibility policy for review, generation, and Coach.

This module is deliberately pure: it does not read the corpus, call an API, load
an embedding model, or write an index.  The source owner records applicability
and usage permission; this code only validates and enforces that declaration.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterable


SOURCE_POLICY_SCHEMA = "are-coach.source-policy.v1"
PURPOSE_HUMAN_REVIEW = "human_review"
PURPOSE_QUESTION_GENERATION = "question_generation"
PURPOSE_COACH_INDEX = "coach_index"
PIPELINE_PURPOSES = (
    PURPOSE_HUMAN_REVIEW,
    PURPOSE_QUESTION_GENERATION,
    PURPOSE_COACH_INDEX,
)
APPROVED = "approved"
APPLICABILITY_STATUSES = (APPROVED, "pending", "rejected", "unknown")
PERMISSION_STATUSES = (APPROVED, "pending", "denied", "unknown")

POLICY_SOURCE_FIELDS = (
    "source_policy_schema",
    "source_family_id",
    "source_title",
    "source_issuing_authority",
    "source_jurisdictions",
    "source_scope",
    "source_exam_divisions",
    "source_applicability_status",
    "source_applicability_evidence",
    "source_usage_permission_status",
    "source_permitted_uses",
    "source_usage_permission_note",
    "source_policy_profiles",
)


@dataclass(frozen=True)
class PolicyRequest:
    purpose: str
    target_division: str
    target_jurisdiction: str
    policy_profile: str
    expected_edition: str | None = None
    expected_revision: str | None = None

    def __post_init__(self) -> None:
        if self.purpose not in PIPELINE_PURPOSES:
            raise ValueError(f"unsupported pipeline purpose: {self.purpose!r}")
        for field in ("target_division", "target_jurisdiction", "policy_profile"):
            value = getattr(self, field)
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f"{field} must be a non-empty string")
        for field in ("expected_edition", "expected_revision"):
            value = getattr(self, field)
            if value is not None and (not isinstance(value, str) or not value.strip()):
                raise ValueError(f"{field} must be a non-empty string or null")

    def to_dict(self) -> dict[str, Any]:
        return {
            "purpose": self.purpose,
            "target_division": self.target_division,
            "target_jurisdiction": self.target_jurisdiction,
            "policy_profile": self.policy_profile,
            "expected_edition": self.expected_edition,
            "expected_revision": self.expected_revision,
        }


@dataclass(frozen=True)
class PolicyDecision:
    outcome: str
    reasons: tuple[str, ...]
    restrictions: tuple[str, ...]
    request: PolicyRequest
    source_path: str | None
    source_document: str | None
    source_chunk_id: str | None

    @property
    def eligible(self) -> bool:
        return self.outcome == "eligible"

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema": "are-coach.source-policy-decision.v1",
            "outcome": self.outcome,
            "reasons": list(self.reasons),
            "restrictions": list(self.restrictions),
            "request": self.request.to_dict(),
            "source_path": self.source_path,
            "source_document": self.source_document,
            "source_chunk_id": self.source_chunk_id,
        }


@dataclass(frozen=True)
class SelectionResult:
    eligible: tuple[tuple[Any, PolicyDecision], ...]
    excluded: tuple[tuple[Any, PolicyDecision], ...]
    invalid_metadata: tuple[tuple[Any, PolicyDecision], ...]

    @property
    def decisions(self) -> tuple[tuple[Any, PolicyDecision], ...]:
        return self.eligible + self.excluded + self.invalid_metadata


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _string_list(value: Any) -> bool:
    return isinstance(value, (list, tuple)) and all(_nonempty(item) for item in value)


def _invalid_metadata_reasons(chunk: Any) -> list[str]:
    schema = getattr(chunk, "source_policy_schema", None)
    if schema is None:
        return []
    if schema != SOURCE_POLICY_SCHEMA:
        return ["metadata_schema_unsupported"]

    invalid: list[str] = []
    for field in (
        "source_family_id",
        "source_title",
        "source_issuing_authority",
        "source_scope",
        "source_applicability_evidence",
        "source_usage_permission_note",
    ):
        value = getattr(chunk, field, None)
        if value is not None and not _nonempty(value):
            invalid.append(f"metadata_field_invalid:{field}")
    for field in (
        "source_jurisdictions",
        "source_exam_divisions",
        "source_permitted_uses",
        "source_policy_profiles",
    ):
        value = getattr(chunk, field, None)
        if value is not None and not _string_list(value):
            invalid.append(f"metadata_field_invalid:{field}")
    applicability = getattr(chunk, "source_applicability_status", None)
    if applicability is not None and applicability not in APPLICABILITY_STATUSES:
        invalid.append("metadata_field_invalid:source_applicability_status")
    permission = getattr(chunk, "source_usage_permission_status", None)
    if permission is not None and permission not in PERMISSION_STATUSES:
        invalid.append("metadata_field_invalid:source_usage_permission_status")
    permitted = getattr(chunk, "source_permitted_uses", None)
    if _string_list(permitted) and any(item not in PIPELINE_PURPOSES for item in permitted):
        invalid.append("metadata_field_invalid:source_permitted_uses")
    if applicability == APPROVED and not _nonempty(
        getattr(chunk, "source_applicability_evidence", None)
    ):
        invalid.append("metadata_field_missing:source_applicability_evidence")
    if permission == APPROVED and not _nonempty(
        getattr(chunk, "source_usage_permission_note", None)
    ):
        invalid.append("metadata_field_missing:source_usage_permission_note")
    if permission == APPROVED and not _string_list(permitted):
        invalid.append("metadata_field_missing:source_permitted_uses")
    return invalid


def evaluate_source(chunk: Any, request: PolicyRequest) -> PolicyDecision:
    """Evaluate one chunk without inferring policy from its filename or content."""
    source_path = getattr(chunk, "source_path", None)
    source_document = getattr(chunk, "source_document", None)
    source_chunk_id = getattr(chunk, "source_chunk_id", None)
    schema = getattr(chunk, "source_policy_schema", None)
    if schema is None:
        return PolicyDecision(
            "excluded",
            ("source_policy_missing",),
            (),
            request,
            source_path,
            source_document,
            source_chunk_id,
        )

    invalid = _invalid_metadata_reasons(chunk)
    if invalid:
        return PolicyDecision(
            "invalid_metadata",
            tuple(invalid),
            (),
            request,
            source_path,
            source_document,
            source_chunk_id,
        )

    reasons: list[str] = []
    restrictions: list[str] = []
    permission = getattr(chunk, "source_usage_permission_status", None)
    permitted = getattr(chunk, "source_permitted_uses", None)
    if permission != APPROVED:
        reasons.append(
            "usage_permission_missing"
            if permission is None
            else f"usage_permission_{permission}"
        )
    if not isinstance(permitted, (list, tuple)) or request.purpose not in permitted:
        reasons.append("purpose_not_permitted")

    applicability = getattr(chunk, "source_applicability_status", None)
    jurisdictions = getattr(chunk, "source_jurisdictions", None)
    divisions = getattr(chunk, "source_exam_divisions", None)
    profiles = getattr(chunk, "source_policy_profiles", None)
    edition = getattr(chunk, "source_edition", None)
    revision = getattr(chunk, "source_revision", None)

    if request.purpose == PURPOSE_HUMAN_REVIEW:
        if applicability != APPROVED:
            restrictions.append(
                "applicability_missing"
                if applicability is None
                else f"applicability_{applicability}"
            )
        if not _nonempty(edition):
            restrictions.append("edition_unknown")
        if not _nonempty(revision):
            restrictions.append("revision_unknown")
        for field, code in (
            ("source_family_id", "family_identity_unknown"),
            ("source_title", "source_title_unknown"),
            ("source_issuing_authority", "issuing_authority_unknown"),
            ("source_scope", "scope_unknown"),
        ):
            if not _nonempty(getattr(chunk, field, None)):
                restrictions.append(code)
        if not isinstance(jurisdictions, (list, tuple)) or request.target_jurisdiction not in jurisdictions:
            restrictions.append("jurisdiction_not_confirmed")
        if not isinstance(divisions, (list, tuple)) or request.target_division not in divisions:
            restrictions.append("division_not_confirmed")
        if not isinstance(profiles, (list, tuple)) or request.policy_profile not in profiles:
            restrictions.append("policy_profile_not_confirmed")
        if request.expected_edition is not None and edition != request.expected_edition:
            restrictions.append("edition_mismatch")
        if request.expected_revision is not None and revision != request.expected_revision:
            restrictions.append("revision_mismatch")
    else:
        if applicability != APPROVED:
            reasons.append(
                "applicability_missing"
                if applicability is None
                else f"applicability_{applicability}"
            )
        if not _nonempty(getattr(chunk, "source_family_id", None)):
            reasons.append("family_identity_unknown")
        if not _nonempty(getattr(chunk, "source_title", None)):
            reasons.append("source_title_unknown")
        if not _nonempty(getattr(chunk, "source_issuing_authority", None)):
            reasons.append("issuing_authority_unknown")
        if not _nonempty(getattr(chunk, "source_scope", None)):
            reasons.append("scope_unknown")
        if not _nonempty(edition):
            reasons.append("edition_unknown")
        if not _nonempty(revision):
            reasons.append("revision_unknown")
        if not isinstance(jurisdictions, (list, tuple)) or request.target_jurisdiction not in jurisdictions:
            reasons.append("jurisdiction_mismatch")
        if not isinstance(divisions, (list, tuple)) or request.target_division not in divisions:
            reasons.append("division_mismatch")
        if not isinstance(profiles, (list, tuple)) or request.policy_profile not in profiles:
            reasons.append("policy_profile_mismatch")
        if request.expected_edition is not None and edition != request.expected_edition:
            reasons.append("edition_mismatch")
        if request.expected_revision is not None and revision != request.expected_revision:
            reasons.append("revision_mismatch")

    outcome = "excluded" if reasons else "eligible"
    return PolicyDecision(
        outcome,
        tuple(dict.fromkeys(reasons)),
        tuple(dict.fromkeys(restrictions)),
        request,
        source_path,
        source_document,
        source_chunk_id,
    )


def select_sources(chunks: Iterable[Any], request: PolicyRequest) -> SelectionResult:
    eligible: list[tuple[Any, PolicyDecision]] = []
    excluded: list[tuple[Any, PolicyDecision]] = []
    invalid: list[tuple[Any, PolicyDecision]] = []
    for chunk in chunks:
        decision = evaluate_source(chunk, request)
        if decision.outcome == "eligible":
            eligible.append((chunk, decision))
        elif decision.outcome == "invalid_metadata":
            invalid.append((chunk, decision))
        else:
            excluded.append((chunk, decision))
    return SelectionResult(tuple(eligible), tuple(excluded), tuple(invalid))


def selection_report(result: SelectionResult) -> dict[str, Any]:
    """Return a deterministic report; excluded sources remain visible to review."""
    rows = [decision.to_dict() for _, decision in result.decisions]
    rows.sort(
        key=lambda row: (
            row["source_path"] or "",
            row["source_chunk_id"] or "",
            row["outcome"],
        )
    )
    return {
        "schema": "are-coach.source-policy-selection-report.v1",
        "counts": {
            "eligible": len(result.eligible),
            "excluded": len(result.excluded),
            "invalid_metadata": len(result.invalid_metadata),
        },
        "decisions": rows,
    }
