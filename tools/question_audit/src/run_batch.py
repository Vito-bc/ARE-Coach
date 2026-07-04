"""Full-bank audit via the Message Batches API (~50% cheaper than live).

Usage (from tools/question_audit/):
    python -m src.run_batch                      # all questions, one batch
    python -m src.run_batch --limit 200          # smaller batch (testing)
    python -m src.run_batch --batch-id msgbatch_..   # resume a submitted batch

Builds one request per (question, grader) that isn't already cached, submits the
batch, waits, then routes results back by custom_id. Any request that errors is
retried live so the report is complete. Never edits the question bank.
"""
from __future__ import annotations

import argparse
import time

from src import cache, config, report
from src.graders import GRADER_SPECS
from src.llm import Usage, full_system, grade, make_client, message_text, parse_verdict, usage_of
from src.run_audit import load_env
from src.schema import Question, load_questions

_SPEC_BY_NAME = {s.name: s for s in GRADER_SPECS}
_PENDING = config.REPORTS_DIR / "pending_batch.txt"


def _cid(qid: str, grader: str) -> str:
    return f"{qid}__{grader}"  # qids use single underscores, so '__' is a safe split


def _split_cid(cid: str) -> tuple[str, str]:
    qid, grader = cid.rsplit("__", 1)
    return qid, grader


def build_requests(model: str, questions: list[Question]) -> list[dict]:
    """One request per (question, grader) not already in the cache."""
    reqs: list[dict] = []
    for q in questions:
        for spec in GRADER_SPECS:
            if cache.load(spec.name, model, q) is not None:
                continue
            reqs.append(
                {
                    "custom_id": _cid(q.id, spec.name),
                    "params": {
                        "model": model,
                        "max_tokens": 1024,
                        "system": full_system(spec.system),
                        "messages": [{"role": "user", "content": spec.build_payload(q)}],
                    },
                }
            )
    return reqs


def wait_for(client, batch_id: str, poll: int = 60) -> None:
    """Poll until the batch ends. Survives transient network drops (won't crash)."""
    slow = client.with_options(timeout=30, max_retries=2)
    while True:
        try:
            b = slow.messages.batches.retrieve(batch_id)
        except Exception as e:  # network blip — log and keep waiting
            print(f"  (transient {type(e).__name__} while polling — retrying)", flush=True)
            time.sleep(poll)
            continue
        c = b.request_counts
        print(
            f"  status={b.processing_status} "
            f"processing={c.processing} succeeded={c.succeeded} errored={c.errored}",
            flush=True,
        )
        if b.processing_status == "ended":
            return
        time.sleep(poll)


def apply_results(client, model: str, batch_id: str, by_qid: dict[str, Question]) -> Usage:
    """Route succeeded results into the cache; return batch token usage.

    Retries the whole stream on a mid-fetch network drop. cache.save is
    idempotent, and any gaps are backfilled by live_fallback afterward.
    """
    slow = client.with_options(timeout=120, max_retries=2)
    total = Usage()
    for attempt in range(5):
        total = Usage()
        ok = errored = 0
        try:
            for result in slow.messages.batches.results(batch_id):
                qid, grader = _split_cid(result.custom_id)
                spec = _SPEC_BY_NAME[grader]
                q = by_qid[qid]
                if result.result.type != "succeeded":
                    errored += 1
                    continue
                msg = result.result.message
                total += usage_of(msg)
                try:
                    parsed = parse_verdict(message_text(msg), spec.out_model)
                    cache.save(spec.name, model, q, spec.finalize(q, parsed))
                    ok += 1
                except Exception:
                    errored += 1
            print(f"Applied batch results: ok={ok}, errored/unparseable={errored}", flush=True)
            return total
        except Exception as e:  # network drop mid-stream — re-stream from the top
            print(f"  (transient {type(e).__name__} fetching results — retry {attempt + 1}/5)", flush=True)
            time.sleep(15)
    print("Could not fully fetch results after retries; live_fallback will fill gaps.", flush=True)
    return total


def live_fallback(client, model: str, questions: list[Question]) -> Usage:
    """Grade any (question, grader) still missing from the cache, live."""
    total = Usage()
    missing = [
        (q, s) for q in questions for s in GRADER_SPECS if cache.load(s.name, model, q) is None
    ]
    if not missing:
        return total
    print(f"Live fallback for {len(missing)} missing grader results ...")
    for q, spec in missing:
        parsed, usage = grade(client, model, spec.system, spec.build_payload(q), spec.out_model)
        total += usage
        cache.save(spec.name, model, q, spec.finalize(q, parsed))
    return total


def build_rows(model: str, questions: list[Question]) -> list[dict]:
    rows = []
    for q in questions:
        row = {"id": q.id, "section": q.section, "difficulty": q.difficulty}
        for spec in GRADER_SPECS:
            row[spec.name] = cache.load(spec.name, model, q)
        rows.append(row)
    return rows


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", default="all", help="'all' or an integer")
    ap.add_argument("--model", default="claude-opus-4-8")
    ap.add_argument("--batch-id", default=None, help="resume an already-submitted batch")
    args = ap.parse_args()

    load_env()
    res = load_questions(config.QUESTIONS_PATH)
    questions = res.valid
    if args.limit != "all":
        questions = questions[: int(args.limit)]
    by_qid = {q.id: q for q in questions}

    client = make_client()
    config.REPORTS_DIR.mkdir(parents=True, exist_ok=True)

    batch_id = args.batch_id
    if batch_id is None:
        reqs = build_requests(args.model, questions)
        print(f"{len(questions)} questions | {len(reqs)} uncached grader-requests to submit.")
        if reqs:
            batch = client.messages.batches.create(requests=reqs)
            batch_id = batch.id
            _PENDING.write_text(batch_id, encoding="utf-8")
            print(f"Submitted batch {batch_id} (results also cached; safe to resume).")

    batch_usage = Usage()
    if batch_id:
        wait_for(client, batch_id)
        batch_usage = apply_results(client, args.model, batch_id, by_qid)
        _PENDING.unlink(missing_ok=True)

    live_usage = live_fallback(client, args.model, questions)

    rows = build_rows(args.model, questions)
    report.write_and_print(rows, args.model, tag=str(len(rows)))

    # Batch tokens bill at 50%; any live-fallback tokens at full price.
    cost = batch_usage.cost(args.model) * 0.5 + live_usage.cost(args.model)
    print("\n" + "-" * 64)
    print(
        f"Batch tokens: in={batch_usage.input_tokens:,} out={batch_usage.output_tokens:,} (billed 50%)\n"
        f"Live-fallback tokens: in={live_usage.input_tokens:,} out={live_usage.output_tokens:,}\n"
        f"TOTAL COST: ${cost:.2f}"
    )


if __name__ == "__main__":
    main()
