"""Tiny on-disk cache keyed by (grader, model, question-content-hash).

Re-running the audit does not re-grade — and does not re-pay for — questions
whose text/options/explanation haven't changed since last time.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from src.schema import Question

_CACHE_DIR = Path(__file__).resolve().parent.parent / ".cache"


def _key(grader: str, model: str, q: Question) -> str:
    payload = json.dumps(
        {
            "q": q.question,
            "options": q.options,
            "correct": q.correctOption,
            "explanation": q.explanation,
            "ref": q.codeReference,
        },
        sort_keys=True,
        ensure_ascii=False,
    )
    digest = hashlib.sha256(f"{grader}|{model}|{payload}".encode("utf-8")).hexdigest()[:20]
    return f"{grader}_{digest}"


def load(grader: str, model: str, q: Question) -> dict | None:
    path = _CACHE_DIR / f"{_key(grader, model, q)}.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return None


def save(grader: str, model: str, q: Question, value: dict) -> None:
    _CACHE_DIR.mkdir(exist_ok=True)
    path = _CACHE_DIR / f"{_key(grader, model, q)}.json"
    path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
