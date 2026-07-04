"""Pydantic schema + loader for the ARE question bank.

This module is the *gate*: every question is validated here before any costly
grading happens. It NEVER mutates the source data — it only reads and reports.

Why a schema at all?
    Garbage-in protection. If a question is malformed (wrong option count,
    correct answer missing from the options, etc.) we want to catch it cheaply
    *here* with a clear message, instead of paying for API calls that then
    crash halfway through a 1,100-item run.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ValidationError, field_validator, model_validator


class Question(BaseModel):
    """One multiple-choice question, mirroring questions_ny.json exactly."""

    id: str
    state: str
    section: str
    difficulty: Literal["easy", "medium", "hard"]
    question: str
    options: list[str]
    correctOption: str
    explanation: str
    codeReference: str
    # Intended as a 1-20 "exam-criticality" weight. Currently unused by the
    # Flutter app; we carry it through as metadata / a possible signal.
    examWeight: int
    topic: str

    @field_validator("options")
    @classmethod
    def _exactly_four_unique(cls, v: list[str]) -> list[str]:
        if len(v) != 4:
            raise ValueError(f"expected 4 options, got {len(v)}")
        if len(set(v)) != len(v):
            raise ValueError("duplicate option text within the question")
        return v

    @model_validator(mode="after")
    def _correct_in_options(self) -> "Question":
        if self.correctOption not in self.options:
            raise ValueError("correctOption is not one of the options")
        return self

    @property
    def correct_index(self) -> int:
        """1-based position of the correct answer (for position-bias checks)."""
        return self.options.index(self.correctOption) + 1


class LoadResult(BaseModel):
    """Outcome of loading the bank: what parsed, and what didn't."""

    valid: list[Question]
    errors: list[dict]  # each: {"id": str, "error": str}

    @property
    def total(self) -> int:
        return len(self.valid) + len(self.errors)


def load_questions(path: str | Path) -> LoadResult:
    """Read the bank and validate every entry. Never writes anything."""
    raw = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    if not isinstance(raw, list):
        raise ValueError("expected the top-level JSON to be a list of questions")

    valid: list[Question] = []
    errors: list[dict] = []
    for i, item in enumerate(raw):
        qid = item.get("id", f"<index {i}>") if isinstance(item, dict) else f"<index {i}>"
        try:
            valid.append(Question.model_validate(item))
        except ValidationError as e:
            errors.append({"id": qid, "error": _short_error(e)})
    return LoadResult(valid=valid, errors=errors)


def _short_error(e: ValidationError) -> str:
    parts = []
    for err in e.errors():
        loc = ".".join(str(x) for x in err["loc"]) or "<root>"
        parts.append(f"{loc}: {err['msg']}")
    return "; ".join(parts)
