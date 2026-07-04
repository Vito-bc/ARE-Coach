"""Phase 2a — generate NEW candidate questions, then AUTO-FILTER each through the
SAME 5 graders + a dedup check against the bank. No RAG yet (grounds on the
model's own knowledge); retrieval from a real corpus is added in phase 2b.

Only candidates that pass every gate survive; a human reviews a sample of those.
COSTS MONEY (1 generation + 4 grader calls per candidate).

Usage (from tools/question_audit/):
    python -m src.generate --n 7          # ~1 per division (smoke test)
    python -m src.generate --n 28
"""
from __future__ import annotations

import argparse
import json
from typing import Literal

from pydantic import BaseModel

from src import config
from src.graders import GRADER_SPECS
from src.llm import Usage, grade, make_client
from src.run_audit import load_env
from src.schema import Question, load_questions

DIVISIONS = [
    "Practice Management",
    "Project Management",
    "Programming & Analysis",
    "Project Planning & Design",
    "Project Docs & Delivery",
    "Construction & Evaluation",
    "NYC Building Codes",
]

# Acceptance thresholds. Bank average distractor plausibility is ~2.2, so 3.3
# with no throwaway (each >= 2) is clearly above the existing bank.
MIN_DISTRACTOR_AVG = 3.3
MIN_DISTRACTOR_EACH = 2
MAX_DUP_SIM = 0.85

SPEC_BY_NAME = {s.name: s for s in GRADER_SPECS}


class GenQuestion(BaseModel):
    section: str
    difficulty: Literal["easy", "medium", "hard"]
    question: str
    options: list[str]
    correctOption: str
    explanation: str
    codeReference: str
    examWeight: int
    topic: str


_GEN_SYS = (
    "You are an expert item-writer for the NCARB ARE 5.0 exam, writing for candidates in New "
    "York State. Write ONE original, high-quality multiple-choice question. Hard requirements:\n"
    "1. SCENARIO / JUDGMENT, not recall: a realistic professional situation where the architect "
    "must decide what to DO (priorities, correct sequence, ethical/contractual/code-driven "
    "choice). Do NOT ask 'what is X' or 'which document/number is Y'.\n"
    "2. Exactly 4 options. ALL THREE wrong options must be genuinely TEMPTING to a knowledgeable "
    "candidate — each a real misconception, a defensible-but-second-best action, or a choice that "
    "is correct in a different context. Do NOT include any option that is off-topic or that a "
    "prepared candidate would immediately rule out. If a wrong option is merely 'not the first "
    "step', make it more tempting (e.g. an action that sounds responsible but subtly violates "
    "code, contract, or sequence).\n"
    "3. Exactly one defensible correct answer.\n"
    "4. explanation: why the correct answer is right AND why the others are wrong.\n"
    "5. codeReference: cite a real, specific standard (AIA document + section, IBC/NYC code "
    "section, ADA, or NCARB) — cite it, do NOT reproduce its text.\n"
    "6. Accurate to real ARE content and NY practice.\n"
    "Return JSON: {section, difficulty (easy|medium|hard), question, options (array of 4 "
    "strings), correctOption (must exactly equal one of options), explanation, codeReference, "
    "examWeight (integer 1-20), topic}."
)

_DIVISIONS_STR = ", ".join(DIVISIONS)
_GROUNDED_SYS = _GEN_SYS + (
    "\n\nGROUNDING: Base the question strictly on the SOURCE text the user provides. Do NOT state "
    "any fact that contradicts it. In codeReference, cite that source exactly as labeled. "
    f"'section' must be exactly one of: {_DIVISIONS_STR}."
)


def gate(verdicts: dict, dup_sim: float) -> tuple[bool, list[str]]:
    reasons = []
    if verdicts["judgment"]["label"] != "judgment":
        reasons.append("factual")
    d = verdicts["distractors"]["distractors"]
    scores = [x["plausibility"] for x in d]
    davg = sum(scores) / len(scores) if scores else 0
    if davg < MIN_DISTRACTOR_AVG:
        reasons.append(f"weak-distractors({davg:.1f})")
    if scores and min(scores) < MIN_DISTRACTOR_EACH:
        reasons.append(f"throwaway({min(scores)})")
    if verdicts["consistency"]["verdict"] != "pass":
        reasons.append("inconsistent")
    if verdicts["leakage"]["leakage_prone"]:
        reasons.append("leakage")
    if dup_sim >= MAX_DUP_SIM:
        reasons.append(f"duplicate({dup_sim:.2f})")
    return (not reasons), reasons


# ── Distractor repair ────────────────────────────────────────────────────────
class RepairedOptions(BaseModel):
    options: list[str]


_REPAIR_SYS = (
    "You strengthen the WRONG options of an ARE 5.0 multiple-choice question. You are given the "
    "question, the correct answer (which MUST remain), the strong wrong options to keep, and the "
    "weak wrong options to replace. Replace ONLY the weak options with new, genuinely TEMPTING "
    "wrong answers — plausible misconceptions or defensible-but-second-best actions a knowledgeable "
    "candidate could choose. Keep the question, the correct answer, and the strong options exactly. "
    "Return {\"options\": [4 strings total: the correct answer, the kept strong options, and the "
    "new replacements, in any order]}."
)


def repair_distractors(client, model: str, q: Question, dverdict: dict) -> tuple[Question | None, Usage]:
    """Regenerate only the weak (< 3/5) distractors, keeping everything else."""
    weak = [d["option"] for d in dverdict["distractors"] if d["plausibility"] < 3]
    strong = [d["option"] for d in dverdict["distractors"] if d["plausibility"] >= 3]
    if not weak:
        return None, Usage()
    payload = (
        f"Question: {q.question}\n"
        f"Correct answer (KEEP exactly): {q.correctOption}\n"
        f"Strong wrong options (KEEP exactly): {strong}\n"
        f"Weak wrong options (REPLACE): {weak}"
    )
    parsed, u = grade(client, model, _REPAIR_SYS, payload, RepairedOptions)
    try:
        newq = Question(**{**q.model_dump(), "options": parsed.options})
    except Exception:
        return None, u  # bad options (not 4 / correct missing) — repair failed
    return newq, u


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=7)
    ap.add_argument("--model", default="claude-opus-4-8")
    ap.add_argument("--grounded", action="store_true", help="RAG: ground each question in a corpus chunk")
    ap.add_argument("--repair-attempts", type=int, default=1, help="repair weak distractors (0 = off)")
    args = ap.parse_args()

    load_env()
    client = make_client()

    corpus_chunks = []
    if args.grounded:
        from src.corpus import load_chunks

        corpus_chunks = load_chunks()
        if not corpus_chunks:
            print("Corpus is empty — add sources to corpus/ or drop --grounded.")
            return
        print(f"RAG mode: grounding on {len(corpus_chunks)} corpus chunks.")

    import numpy as np
    from sentence_transformers import SentenceTransformer

    bank = load_questions(config.QUESTIONS_PATH).valid
    st = SentenceTransformer("all-MiniLM-L6-v2")
    bank_emb = st.encode([q.question for q in bank], normalize_embeddings=True)

    records: list[dict] = []
    accepted_emb: list = []
    total = Usage()

    print(f"Generating {args.n} candidates with {args.model}, gating each ...")
    for i in range(args.n):
        grounded_on = None
        if args.grounded:
            chunk = corpus_chunks[i % len(corpus_chunks)]
            grounded_on = f"{chunk.source} :: {chunk.ref}"
            sys_prompt = _GROUNDED_SYS
            payload = (
                f"SOURCE ({grounded_on}):\n{chunk.text}\n\n"
                "Write ONE judgment-style ARE 5.0 question grounded in this source — a realistic "
                "scenario where an architect must apply this requirement and decide what to do."
            )
        else:
            section = DIVISIONS[i % len(DIVISIONS)]
            sys_prompt = _GEN_SYS
            payload = (
                f"Division: {section}. Write ONE new judgment-style question for this division, "
                f"distinct from common textbook phrasings."
            )
        try:
            gen, u = grade(client, args.model, sys_prompt, payload, GenQuestion)
            total += u
        except Exception as e:
            print(f"  [{i + 1}/{args.n}]: generation failed ({e})")
            continue
        section = gen.section

        # Validate into the real schema (4 options, correct present, etc.).
        try:
            q = Question(id=f"gen_{i}", state="NY", **gen.model_dump())
        except Exception as e:
            print(f"  [{i + 1}/{args.n}] {section}: REJECT malformed ({e})")
            records.append({"id": f"gen_{i}", "section": section, "accepted": False,
                            "reject_reasons": ["malformed"], "error": str(e)})
            continue

        verdicts = {}
        for spec in GRADER_SPECS:
            parsed, u = grade(client, args.model, spec.system, spec.build_payload(q), spec.out_model)
            total += u
            verdicts[spec.name] = spec.finalize(q, parsed)

        emb = st.encode([q.question], normalize_embeddings=True)[0]
        dup_sim = float((bank_emb @ emb).max())
        if accepted_emb:
            dup_sim = max(dup_sim, max(float(e @ emb) for e in accepted_emb))

        ok, reasons = gate(verdicts, dup_sim)

        # Distractor-repair: if the ONLY problem is weak/throwaway distractors, and
        # the question is otherwise good, regenerate just the weak options.
        repaired = False
        if not ok and args.repair_attempts and all(
            r.startswith(("weak-distractors", "throwaway")) for r in reasons
        ):
            dspec = SPEC_BY_NAME["distractors"]
            for _ in range(args.repair_attempts):
                newq, ru = repair_distractors(client, args.model, q, verdicts["distractors"])
                total += ru
                if newq is None:
                    break
                q = newq
                parsed, u2 = grade(client, args.model, dspec.system, dspec.build_payload(q), dspec.out_model)
                total += u2
                verdicts["distractors"] = dspec.finalize(q, parsed)
                repaired = True
                ok, reasons = gate(verdicts, dup_sim)  # stem unchanged → dup_sim still valid
                if ok:
                    break

        records.append(
            {
                "id": q.id, "section": section, "difficulty": q.difficulty,
                "question": q.question, "options": q.options, "correctOption": q.correctOption,
                "explanation": q.explanation, "codeReference": q.codeReference,
                "examWeight": q.examWeight, "topic": q.topic, "state": "NY",
                "grounded_on": grounded_on, "repaired": repaired,
                "verdicts": verdicts, "dup_sim": round(dup_sim, 3),
                "accepted": ok, "reject_reasons": reasons,
            }
        )
        if ok:
            accepted_emb.append(emb)
        status = ("ACCEPT (repaired)" if repaired else "ACCEPT") if ok else "REJECT " + ",".join(reasons)
        print(f"  [{i + 1}/{args.n}] {section}: {status}")

    accepted = [r for r in records if r.get("accepted")]
    config.REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    (config.REPORTS_DIR / "generated_candidates.json").write_text(
        json.dumps(records, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    (config.REPORTS_DIR / "generated_accepted.json").write_text(
        json.dumps(accepted, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    n = len(records)
    print("\n" + "-" * 60)
    print(f"Generated {n} | ACCEPTED {len(accepted)} ({len(accepted) * 100 // n if n else 0}%) "
          f"| rejected {n - len(accepted)}")
    from collections import Counter
    rej: Counter = Counter()
    for r in records:
        for reason in r.get("reject_reasons", []):
            rej[reason.split("(")[0]] += 1
    print("Reject reasons:", dict(rej))
    cost = total.cost(args.model)
    print(f"COST: ${cost:.2f}  (~${cost / n:.3f}/candidate)  |  ~${cost / max(len(accepted),1):.3f}/accepted")
    print("Reports: generated_candidates.json, generated_accepted.json")


if __name__ == "__main__":
    main()
