"""Thin Claude wrapper for the graders: one call, structured JSON out, cost tracked.

Design notes
------------
* We ask each grader to return ONLY a JSON object and validate it with pydantic.
  This is portable across anthropic SDK versions (doesn't depend on the newer
  `messages.parse` helper) while still giving us schema validation.
* Opus 4.8 rejects `temperature`/`top_p` and `budget_tokens`; we send none of
  them. Thinking is off by default on 4.8, which is what we want for cheap,
  bounded grading.
* Every call returns its token usage so the runner can report real cost.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Type, TypeVar

from pydantic import BaseModel

# Price per 1M tokens (input, output), from the Claude API skill (2026-06).
PRICES: dict[str, dict[str, float]] = {
    "claude-opus-4-8": {"input": 5.0, "output": 25.0},
    "claude-sonnet-4-6": {"input": 3.0, "output": 15.0},
    "claude-haiku-4-5": {"input": 1.0, "output": 5.0},
}

T = TypeVar("T", bound=BaseModel)

_JSON_RE = re.compile(r"\{.*\}", re.DOTALL)


@dataclass
class Usage:
    input_tokens: int = 0
    output_tokens: int = 0

    def cost(self, model: str) -> float:
        p = PRICES.get(model, PRICES["claude-opus-4-8"])
        return (self.input_tokens * p["input"] + self.output_tokens * p["output"]) / 1_000_000

    def __iadd__(self, other: "Usage") -> "Usage":
        self.input_tokens += other.input_tokens
        self.output_tokens += other.output_tokens
        return self


class LLMError(RuntimeError):
    pass


def make_client():
    """Create an Anthropic client. Raises a clear error if the SDK or key is missing."""
    try:
        import anthropic  # noqa: F401
    except ImportError as e:
        raise LLMError(
            "The 'anthropic' package is not installed. Run:\n"
            "  pip install -r requirements.txt"
        ) from e
    import os

    if not os.environ.get("ANTHROPIC_API_KEY"):
        raise LLMError(
            "ANTHROPIC_API_KEY is not set. Copy .env.example to .env, add your key, "
            "and load it (the runner loads .env automatically)."
        )
    from anthropic import Anthropic

    return Anthropic()


JSON_INSTRUCTION = (
    "\n\nRespond with ONLY a single JSON object matching the requested fields. "
    "No prose, no markdown, no code fences."
)


def full_system(system: str) -> str:
    """The exact system string sent to the API (shared by live + batch paths)."""
    return system + JSON_INSTRUCTION


def parse_verdict(text: str, out_model: Type[T]) -> T:
    """Extract + validate a JSON verdict from a model's text response."""
    raw = _JSON_RE.search(text or "")
    if not raw:
        raise LLMError(f"no JSON found in response: {(text or '')[:200]!r}")
    return out_model.model_validate(json.loads(raw.group(0)))


def message_text(msg) -> str:
    return "".join(b.text for b in msg.content if getattr(b, "type", None) == "text").strip()


def usage_of(msg) -> Usage:
    return Usage(
        input_tokens=getattr(msg.usage, "input_tokens", 0) or 0,
        output_tokens=getattr(msg.usage, "output_tokens", 0) or 0,
    )


def grade(client, model: str, system: str, payload: str, out_model: Type[T]) -> tuple[T, Usage]:
    """One live grader call: send `payload`, parse a JSON object into `out_model`.

    Retries once if the model returns something we can't parse.
    """
    last_err: Exception | None = None
    for _ in range(2):
        msg = client.messages.create(
            model=model,
            max_tokens=1024,
            system=full_system(system),
            messages=[{"role": "user", "content": payload}],
        )
        usage = usage_of(msg)
        try:
            return parse_verdict(message_text(msg), out_model), usage
        except Exception as e:  # no JSON / invalid JSON / schema mismatch
            last_err = e
    raise LLMError(f"grader failed to return valid JSON after 2 tries: {last_err}")
