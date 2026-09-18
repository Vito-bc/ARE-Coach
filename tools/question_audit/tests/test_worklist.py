from __future__ import annotations

import csv
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from dataclasses import dataclass
from io import StringIO
from pathlib import Path
from unittest.mock import patch

from src.worklist import load_live_duplicates, main, queue_for


@dataclass
class _Q:
    id: str


def _dup_csv(path: Path, rows: list[tuple[str, str, str]]) -> None:
    path.write_text(
        "id_a,id_b,similarity,section_a,section_b,question_a,question_b\n"
        + "\n".join(f"{a},{b},{s},NYC,NYC,q,q" for a, b, s in rows),
        encoding="utf-8",
    )


class LoadLiveDuplicatesTest(unittest.TestCase):
    def test_missing_file_returns_empty(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            dup = load_live_duplicates(Path(td) / "duplicates_090.csv", {"a": _Q("a")})
        self.assertEqual(dup, {})

    def test_both_sides_present_tags_both_ways(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "duplicates_090.csv"
            _dup_csv(p, [("a", "b", "0.95")])
            dup = load_live_duplicates(p, {"a": _Q("a"), "b": _Q("b")})
        self.assertEqual(dup["a"], ["b (0.95)"])
        self.assertEqual(dup["b"], ["a (0.95)"])

    def test_partner_removed_from_bank_drops_both_sides(self) -> None:
        # "a" is still in the bank; "b" was removed by a dedup pass since the
        # report was generated. Neither side is a live duplicate any more.
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "duplicates_090.csv"
            _dup_csv(p, [("a", "b", "0.95")])
            dup = load_live_duplicates(p, {"a": _Q("a")})
        self.assertEqual(dup, {})

    def test_one_live_one_stale_pair_only_the_live_pair_tags(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "duplicates_090.csv"
            _dup_csv(p, [("a", "b", "0.95"), ("c", "d", "0.92")])
            dup = load_live_duplicates(p, {"a": _Q("a"), "b": _Q("b"), "c": _Q("c")})  # d missing
        self.assertEqual(dup["a"], ["b (0.95)"])
        self.assertEqual(dup["b"], ["a (0.95)"])
        self.assertNotIn("c", dup)
        self.assertNotIn("d", dup)


def _question(id_: str, severity_hint: str = "") -> dict:
    return {
        "id": id_,
        "state": "NY",
        "section": "Construction & Evaluation",
        "difficulty": "medium",
        "question": f"Synthetic question for {id_} {severity_hint}".strip(),
        "options": ["Alpha", "Beta", "Gamma", "Delta"],
        "correctOption": "Alpha",
        "explanation": "Synthetic explanation.",
        "codeReference": "Synthetic 1.1",
        "examWeight": 5,
        "topic": "Synthetic",
    }


def _audit_row(id_: str, *, severity: float, factual: bool = False) -> dict:
    return {
        "id": id_,
        "section": "Construction & Evaluation",
        "difficulty": "medium",
        "judgment": {"label": "factual" if factual else "judgment", "reason": "synthetic"},
        "distractors": {
            "distractors": [
                {"option": "Beta", "plausibility": 4, "reason": "synthetic"},
                {"option": "Gamma", "plausibility": 4, "reason": "synthetic"},
                {"option": "Delta", "plausibility": 4, "reason": "synthetic"},
            ]
        },
        "consistency": {"verdict": "pass", "reason": ""},
        "leakage": {
            "model_answer": "Alpha",
            "confidence": 1,
            "best_match_option": "Alpha",
            "similarity": 0.1,
            "leakage_prone": False,
        },
        "severity": severity,
    }


class WorklistRedTriageIntegrationTest(unittest.TestCase):
    """Runs the real, unmodified main() against a synthetic bank + audit +
    duplicates report to prove the re-triage end to end -- not just the
    load_live_duplicates() unit above."""

    def _run(self, tmp: Path) -> list[dict]:
        with (
            patch("src.worklist.config.REPORTS_DIR", tmp),
            patch("src.worklist.config.QUESTIONS_PATH", tmp / "questions_ny.json"),
            patch.object(sys, "argv", ["worklist.py", "--queue", "RED"]),
            redirect_stdout(StringIO()),
        ):
            main()
        out = tmp / "maryana_red_queue.csv"
        if not out.exists():
            return []  # main() prints "No rows in the RED queue." and writes nothing
        with out.open(encoding="utf-8-sig") as f:
            return list(csv.DictReader(f))

    def test_stale_duplicate_only_reason_leaves_red_entirely(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            (tmp / "questions_ny.json").write_text(
                json.dumps([_question("q_lowsev")]), encoding="utf-8"
            )
            (tmp / "audit_1100.json").write_text(
                json.dumps({"results": [_audit_row("q_lowsev", severity=3.0)]}),
                encoding="utf-8",
            )
            # q_lowsev's only partner, q_ghost, no longer exists in the bank.
            _dup_csv(tmp / "duplicates_090.csv", [("q_lowsev", "q_ghost", "0.95")])
            rows = self._run(tmp)
        self.assertEqual(rows, [])  # below min-severity, no live tag left to force it in

    def test_independently_severe_question_stays_red_without_the_misleading_tag(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            (tmp / "questions_ny.json").write_text(
                json.dumps([_question("q_highsev")]), encoding="utf-8"
            )
            (tmp / "audit_1100.json").write_text(
                json.dumps({"results": [_audit_row("q_highsev", severity=8.0, factual=True)]}),
                encoding="utf-8",
            )
            _dup_csv(tmp / "duplicates_090.csv", [("q_highsev", "q_ghost", "0.93")])
            rows = self._run(tmp)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], "q_highsev")
        self.assertEqual(rows[0]["priority"], "RED")
        self.assertNotIn("DUPLICATE", rows[0]["issues"].split(","))
        self.assertEqual(rows[0]["duplicate_of"], "")

    def test_live_pair_is_unaffected_by_the_stale_partner_fix(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            (tmp / "questions_ny.json").write_text(
                json.dumps([_question("q_live1"), _question("q_live2")]), encoding="utf-8"
            )
            (tmp / "audit_1100.json").write_text(
                json.dumps(
                    {
                        "results": [
                            _audit_row("q_live1", severity=5.0),
                            _audit_row("q_live2", severity=5.0),
                        ]
                    }
                ),
                encoding="utf-8",
            )
            _dup_csv(tmp / "duplicates_090.csv", [("q_live1", "q_live2", "0.91")])
            rows = self._run(tmp)
        ids = {r["id"] for r in rows}
        self.assertEqual(ids, {"q_live1", "q_live2"})
        for r in rows:
            self.assertIn("DUPLICATE", r["issues"].split(","))
            self.assertEqual(r["priority"], "RED")


class QueueForThresholdsUnchangedTest(unittest.TestCase):
    """Part 2 must not touch queue_for()'s own thresholds or semantics."""

    def test_duplicate_alone_is_red(self) -> None:
        self.assertEqual(queue_for(["DUPLICATE"], 1.0), "RED")

    def test_consistency_alone_is_red(self) -> None:
        self.assertEqual(queue_for(["CONSISTENCY"], 1.0), "RED")

    def test_severity_7_with_no_tags_is_red(self) -> None:
        self.assertEqual(queue_for([], 7.0), "RED")

    def test_severity_just_under_7_with_no_hard_tag_is_not_red(self) -> None:
        self.assertEqual(queue_for([], 6.99), "GREEN")
        self.assertEqual(queue_for(["WEAK_DISTRACTORS"], 6.99), "YELLOW")

    def test_weak_distractors_or_leakage_alone_is_yellow(self) -> None:
        self.assertEqual(queue_for(["WEAK_DISTRACTORS"], 1.0), "YELLOW")
        self.assertEqual(queue_for(["LEAKAGE"], 1.0), "YELLOW")

    def test_no_flags_is_green(self) -> None:
        self.assertEqual(queue_for(["FACTUAL"], 1.0), "GREEN")


if __name__ == "__main__":
    unittest.main()
