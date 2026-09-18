from __future__ import annotations

import tempfile
import unittest
from dataclasses import dataclass
from pathlib import Path
from unittest.mock import patch

from src.check_bank import Report, check_duplicates_report_is_live


@dataclass
class _Q:
    """Only `.id` is read by check_duplicates_report_is_live -- no need for a
    full schema.Question fixture."""

    id: str


QS = [_Q("nyc_q1"), _Q("nyc_q2"), _Q("ce_q1")]


def _write_duplicates_csv(path: Path, rows: list[tuple[str, str, str]]) -> None:
    path.write_text(
        "id_a,id_b,similarity,section_a,section_b,question_a,question_b\n"
        + "\n".join(f"{a},{b},{s},NYC,NYC,q,q" for a, b, s in rows),
        encoding="utf-8",
    )


class CheckDuplicatesReportIsLiveTest(unittest.TestCase):
    def test_no_report_file_is_a_silent_ok(self) -> None:
        # duplicates_090.csv is a local, gitignored artifact -- absent in a
        # fresh checkout, so this must never fail just because it's missing.
        with tempfile.TemporaryDirectory() as td:
            with patch("src.check_bank.config.REPORTS_DIR", Path(td)):
                rep = Report()
                check_duplicates_report_is_live(rep, QS)
        self.assertEqual(rep.failures, [])
        self.assertEqual(len(rep.notes), 1)

    def test_every_referenced_id_still_in_bank_is_ok(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            _write_duplicates_csv(root / "duplicates_090.csv", [("nyc_q1", "nyc_q2", "0.95")])
            with patch("src.check_bank.config.REPORTS_DIR", root):
                rep = Report()
                check_duplicates_report_is_live(rep, QS)
        self.assertEqual(rep.failures, [])
        self.assertEqual(len(rep.notes), 1)

    def test_id_removed_from_bank_since_the_report_was_built_fails(self) -> None:
        # The actual defect: duplicates_090.csv predates the dedup pass that
        # removed some of the ids it still references.
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            _write_duplicates_csv(
                root / "duplicates_090.csv",
                [("nyc_q1", "nyc_q99", "0.95")],  # nyc_q99 no longer exists
            )
            with patch("src.check_bank.config.REPORTS_DIR", root):
                rep = Report()
                check_duplicates_report_is_live(rep, QS)
        self.assertEqual(rep.notes, [])
        self.assertEqual(len(rep.failures), 1)
        self.assertIn("nyc_q99", rep.failures[0])
        self.assertIn("1 id(s)", rep.failures[0])

    def test_stale_id_on_either_side_of_the_pair_is_caught(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            _write_duplicates_csv(
                root / "duplicates_090.csv",
                [("nyc_q99", "nyc_q1", "0.95")],  # stale id_a this time, not id_b
            )
            with patch("src.check_bank.config.REPORTS_DIR", root):
                rep = Report()
                check_duplicates_report_is_live(rep, QS)
        self.assertEqual(len(rep.failures), 1)
        self.assertIn("nyc_q99", rep.failures[0])

    def test_multiple_stale_ids_are_all_reported_and_deduplicated(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            _write_duplicates_csv(
                root / "duplicates_090.csv",
                [
                    ("nyc_q1", "nyc_q99", "0.95"),
                    ("nyc_q99", "ce_q1", "0.91"),  # nyc_q99 appears twice -- must count once
                    ("nyc_q2", "nyc_q88", "0.90"),
                ],
            )
            with patch("src.check_bank.config.REPORTS_DIR", root):
                rep = Report()
                check_duplicates_report_is_live(rep, QS)
        self.assertEqual(len(rep.failures), 1)
        self.assertIn("2 id(s)", rep.failures[0])
        self.assertIn("nyc_q99", rep.failures[0])
        self.assertIn("nyc_q88", rep.failures[0])


if __name__ == "__main__":
    unittest.main()
