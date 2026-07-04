"""The quality graders. Each grades ONE question and never edits it.

Graders 1-4 are single Claude calls returning structured JSON. Each is described
by a GraderSpec (system prompt + payload builder + verdict model + finalize),
so the live runner and the batch runner share exactly the same prompts.

The duplicate check (grader 5) is bank-wide and lives elsewhere (no API).
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from difflib import SequenceMatcher
from typing import Callable, Literal, Type

from pydantic import BaseModel

from src.schema import Question

Score = Literal[1, 2, 3, 4, 5]


@dataclass(frozen=True)
class GraderSpec:
    name: str
    system: str
    build_payload: Callable[[Question], str]
    out_model: Type[BaseModel]
    finalize: Callable[[Question, BaseModel], dict]


def _passthrough(_q: Question, v: BaseModel) -> dict:
    return v.model_dump()


# ── Grader 1: judgment vs factual ────────────────────────────────────────────
class JudgmentVerdict(BaseModel):
    label: Literal["judgment", "factual"]
    reason: str


_JUDGMENT_SYS = (
    "You classify ARE 5.0 (architect licensing) multiple-choice questions.\n"
    "- 'judgment': tests what an architect should DO in a situation, weighing priorities, "
    "sequence, ethics, or code application. This is the high-value type.\n"
    "- 'factual': tests shallow recall of a single definition, number, name, or which-document. "
    "This is the low-value failure mode.\n"
    "Return {\"label\": \"judgment\"|\"factual\", \"reason\": \"one short sentence\"}."
)


def _judgment_payload(q: Question) -> str:
    return f"Question: {q.question}\nOptions: {q.options}\nCorrect: {q.correctOption}"


# ── Grader 2: distractor plausibility ────────────────────────────────────────
class DistractorScore(BaseModel):
    option: str
    plausibility: Score
    reason: str


class DistractorVerdict(BaseModel):
    distractors: list[DistractorScore]


_DISTRACTOR_SYS = (
    "You score the WRONG options (distractors) of an ARE 5.0 question for how plausible each "
    "is to a knowledgeable test-taker. 5 = very plausible / tempting; 1 = obviously wrong or "
    "throwaway. Score ONLY the three wrong options (skip the correct one).\n"
    "Return {\"distractors\": [{\"option\": \"<text>\", \"plausibility\": 1-5, "
    "\"reason\": \"short\"}, ...]}."
)


def _distractor_payload(q: Question) -> str:
    wrong = [o for o in q.options if o != q.correctOption]
    return (
        f"Question: {q.question}\nCorrect answer (do NOT score): {q.correctOption}\n"
        f"Distractors to score: {wrong}"
    )


# ── Grader 3: internal consistency ───────────────────────────────────────────
class ConsistencyVerdict(BaseModel):
    verdict: Literal["pass", "fail"]
    reason: str


_CONSISTENCY_SYS = (
    "You check an ARE 5.0 question for internal consistency. FAIL if any of these hold:\n"
    "- the stated correct answer contradicts the explanation, or\n"
    "- the explanation actually argues for a different option, or\n"
    "- the cited source/standard clearly does not support the stated answer.\n"
    "Otherwise PASS. Judge only consistency, not whether the fact is ultimately true.\n"
    "Return {\"verdict\": \"pass\"|\"fail\", \"reason\": \"short\"}."
)


def _consistency_payload(q: Question) -> str:
    return (
        f"Question: {q.question}\nStated correct answer: {q.correctOption}\n"
        f"Explanation: {q.explanation}\nCited source: {q.codeReference}"
    )


# ── Grader 4: answer leakage (adversarial "AI student") ──────────────────────
class LeakageAnswer(BaseModel):
    answer: str
    confidence: Score  # how sure the model is, seeing ONLY the stem


class LeakageResult(BaseModel):
    model_answer: str
    confidence: int
    best_match_option: str
    similarity: float
    leakage_prone: bool


_LEAKAGE_SYS = (
    "You are a knowledgeable ARE 5.0 test-taker. You are shown ONLY the question stem, with NO "
    "answer options. Give your single best answer in a few words, and how confident you are "
    "(1=guessing, 5=certain).\n"
    "Return {\"answer\": \"<your answer>\", \"confidence\": 1-5}."
)


def _leakage_payload(q: Question) -> str:
    # The model sees only the stem — never the options.
    return f"Question: {q.question}"


def _finalize_leakage(q: Question, ans: BaseModel) -> dict:
    """Compare the stem-only answer to each option locally (no extra API call).

    Token coverage handles the common case where the model wraps the exact answer
    in extra words ("AIA C401 (Standard Form...)"), which plain string similarity
    would miss; we take the max with a sequence ratio as a backstop.
    """
    assert isinstance(ans, LeakageAnswer)
    ans_tokens = set(re.findall(r"[a-z0-9]+", ans.answer.lower()))

    def match(opt: str) -> float:
        opt_tokens = set(re.findall(r"[a-z0-9]+", opt.lower()))
        coverage = len(opt_tokens & ans_tokens) / len(opt_tokens) if opt_tokens else 0.0
        ratio = SequenceMatcher(None, ans.answer.lower(), opt.lower()).ratio()
        return max(coverage, ratio)

    best_opt = max(q.options, key=match)
    best_sim = round(match(best_opt), 3)
    leak = best_opt == q.correctOption and best_sim >= 0.7 and ans.confidence >= 4
    return LeakageResult(
        model_answer=ans.answer,
        confidence=ans.confidence,
        best_match_option=best_opt,
        similarity=best_sim,
        leakage_prone=leak,
    ).model_dump()


# ── Registry ─────────────────────────────────────────────────────────────────
GRADER_SPECS: list[GraderSpec] = [
    GraderSpec("judgment", _JUDGMENT_SYS, _judgment_payload, JudgmentVerdict, _passthrough),
    GraderSpec("distractors", _DISTRACTOR_SYS, _distractor_payload, DistractorVerdict, _passthrough),
    GraderSpec("consistency", _CONSISTENCY_SYS, _consistency_payload, ConsistencyVerdict, _passthrough),
    GraderSpec("leakage", _LEAKAGE_SYS, _leakage_payload, LeakageAnswer, _finalize_leakage),
]
