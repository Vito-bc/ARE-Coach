from __future__ import annotations

import copy
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from dataclasses import replace
from io import StringIO
from pathlib import Path
from unittest.mock import patch

from src.build_coach_index import build_index_plan, main as index_main
from src.corpus import (
    LEGACY_SOURCE_METADATA_SCHEMA,
    SOURCE_METADATA_SCHEMA,
    Chunk,
    CorpusMetadataError,
    load_chunks,
)
from src.generate import candidate_record, main as generate_main, plan_grounded_generation
from src.schema import Question
from src.source_policy import (
    PURPOSE_COACH_INDEX,
    PURPOSE_HUMAN_REVIEW,
    PURPOSE_QUESTION_GENERATION,
    PolicyRequest,
    evaluate_source,
    selection_report,
    select_sources,
)


PROFILE = "are-coach.are5-2026.v1"
PCM = "Practice Management"
PJM = "Project Management"
NYC = "NYC Building Codes"


def _chunk(**changes) -> Chunk:
    values = {
        "source": "standard.pdf",
        "ref": "1.1",
        "text": "Substantive synthetic policy source sentence. " * 14,
        "source_metadata_schema": "are-coach.corpus-chunk.v1",
        "source_document": "doc:synthetic-policy",
        "source_sha256": "sha256:" + "a" * 64,
        "source_path": "standards/standard.pdf",
        "source_page": 7,
        "source_locator": "pdf-page:7:section:1:piece:1",
        "source_chunk_id": "chunk:synthetic-policy",
        "source_extraction_version": "are-coach.pypdf-page-chunker.v1;min_len=80;max_len=1200",
        "source_edition": "2021",
        "source_revision": "R2",
        "source_missing_metadata": (),
        "source_not_applicable_metadata": (),
        "source_policy_schema": "are-coach.source-policy.v1",
        "source_family_id": "model.standard",
        "source_title": "Synthetic Model Standard",
        "source_issuing_authority": "Synthetic Authority",
        "source_jurisdictions": ("ARE",),
        "source_scope": "Synthetic test scope",
        "source_exam_divisions": (PCM,),
        "source_applicability_status": "approved",
        "source_applicability_evidence": "Owner-reviewed synthetic evidence",
        "source_usage_permission_status": "approved",
        "source_permitted_uses": (
            PURPOSE_HUMAN_REVIEW,
            PURPOSE_QUESTION_GENERATION,
            PURPOSE_COACH_INDEX,
        ),
        "source_usage_permission_note": "Synthetic fixture is permitted",
        "source_policy_profiles": (PROFILE,),
    }
    values.update(changes)
    return Chunk(**values)


def _request(
    purpose: str = PURPOSE_QUESTION_GENERATION,
    division: str = PCM,
    jurisdiction: str = "ARE",
    *,
    edition: str | None = "2021",
    revision: str | None = "R2",
) -> PolicyRequest:
    return PolicyRequest(purpose, division, jurisdiction, PROFILE, edition, revision)


def _manifest_entry(**changes):
    value = {
        "family_id": "model.standard",
        "title": "Synthetic Model Standard",
        "issuing_authority": "Synthetic Authority",
        "edition": "2021",
        "revision": "R2",
        "jurisdictions": ["ARE"],
        "scope": "Synthetic test scope",
        "exam_divisions": [PCM],
        "applicability_status": "approved",
        "applicability_evidence": "Owner-reviewed synthetic evidence",
        "usage_permission_status": "approved",
        "permitted_uses": [
            PURPOSE_HUMAN_REVIEW,
            PURPOSE_QUESTION_GENERATION,
            PURPOSE_COACH_INDEX,
        ],
        "usage_permission_note": "Synthetic fixture is permitted",
        "policy_profiles": [PROFILE],
    }
    value.update(changes)
    return value


class SourcePolicyTest(unittest.TestCase):
    def test_exact_edition_revision_and_profile_match(self) -> None:
        decision = evaluate_source(_chunk(), _request())
        self.assertTrue(decision.eligible)
        self.assertEqual(decision.reasons, ())

    def test_edition_or_revision_mismatch_is_excluded(self) -> None:
        edition = evaluate_source(_chunk(), _request(edition="2018"))
        revision = evaluate_source(_chunk(), _request(revision="R3"))
        self.assertEqual(edition.outcome, "excluded")
        self.assertIn("edition_mismatch", edition.reasons)
        self.assertIn("revision_mismatch", revision.reasons)

    def test_missing_or_unknown_edition_never_means_approved(self) -> None:
        # None and "" are the obviously-missing cases; "unknown"/"pending" (in
        # any case, with incidental whitespace) are RESERVED PLACEHOLDERS an
        # owner might type after seeing those exact words used for the status
        # enums elsewhere in this same manifest -- they must fail exactly the
        # same way, never be treated as a real edition.
        for edition in (None, "", "unknown", " UNKNOWN ", "pending", " Pending "):
            with self.subTest(edition=edition):
                decision = evaluate_source(_chunk(source_edition=edition), _request())
                self.assertFalse(decision.eligible)
                self.assertIn("edition_unknown", decision.reasons)

    def test_missing_or_placeholder_revision_never_means_approved(self) -> None:
        for revision in (None, "", "unknown", " UNKNOWN ", "pending", " Pending "):
            with self.subTest(revision=revision):
                decision = evaluate_source(_chunk(source_revision=revision), _request())
                self.assertFalse(decision.eligible)
                self.assertIn("revision_unknown", decision.reasons)

    def test_placeholder_identity_fields_never_count_as_known(self) -> None:
        # Same reserved-placeholder principle for the free-text identity
        # fields: an owner writing "unknown"/"pending" instead of leaving the
        # field null must not silently pass as a real family id, title,
        # issuing authority, or scope.
        cases = (
            ("source_family_id", "family_identity_unknown"),
            ("source_title", "source_title_unknown"),
            ("source_issuing_authority", "issuing_authority_unknown"),
            ("source_scope", "scope_unknown"),
        )
        for field, reason in cases:
            for placeholder in ("unknown", " UNKNOWN ", "pending", " Pending "):
                with self.subTest(field=field, placeholder=placeholder):
                    decision = evaluate_source(_chunk(**{field: placeholder}), _request())
                    self.assertFalse(decision.eligible)
                    self.assertIn(reason, decision.reasons)

    def test_ordinary_prose_containing_the_word_unknown_is_not_rejected(self) -> None:
        # The placeholder check is an exact match, not a substring search --
        # a scope that merely discusses "unknown" conditions is real prose,
        # not a stand-in for "not decided", and must not be excluded by it.
        decision = evaluate_source(
            _chunk(source_scope="Covers known and unknown seismic hazard zones"),
            _request(),
        )
        self.assertTrue(decision.eligible)
        self.assertNotIn("scope_unknown", decision.reasons)

    def test_manifest_rejects_reserved_placeholder_edition_and_revision(self) -> None:
        # The loader is the first line of defense: prefer refusing the
        # ambiguous input outright over silently accepting it and relying
        # only on the pure selector downstream.
        for field, placeholder in (
            ("edition", "unknown"),
            ("edition", " UNKNOWN "),
            ("revision", "pending"),
            ("revision", " Pending "),
            ("family_id", "unknown"),
            ("title", "pending"),
            ("issuing_authority", "UNKNOWN"),
            ("scope", "Pending"),
        ):
            with self.subTest(field=field, placeholder=placeholder):
                with tempfile.TemporaryDirectory() as td:
                    root = Path(td)
                    (root / "source.txt").write_text("Synthetic text " * 30, encoding="utf-8")
                    entry = _manifest_entry(**{field: placeholder})
                    (root / "source_metadata.json").write_text(
                        json.dumps({"schema": SOURCE_METADATA_SCHEMA, "sources": {"source.txt": entry}}),
                        encoding="utf-8",
                    )
                    with self.assertRaisesRegex(CorpusMetadataError, "reserved placeholder"):
                        load_chunks(min_len=1, corpus_dir=root)

    def test_manifest_does_not_reject_placeholder_in_evidence_or_note_fields(self) -> None:
        # Evidence/note are audit prose, not identity -- "pending" legitimately
        # describes their own review status and must not be rejected.
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "source.txt").write_text("Synthetic text " * 30, encoding="utf-8")
            entry = _manifest_entry(applicability_evidence="pending", usage_permission_note="unknown")
            entry["applicability_status"] = "pending"
            entry["usage_permission_status"] = "pending"
            (root / "source_metadata.json").write_text(
                json.dumps({"schema": SOURCE_METADATA_SCHEMA, "sources": {"source.txt": entry}}),
                encoding="utf-8",
            )
            chunk = load_chunks(min_len=1, corpus_dir=root)[0]
            self.assertEqual(chunk.source_applicability_evidence, "pending")
            self.assertEqual(chunk.source_usage_permission_note, "unknown")

    def test_manifest_prefers_null_for_unknown_edition_or_revision(self) -> None:
        # Documents that null (not the loader's rejection) is the supported,
        # eligibility-safe way to record an undecided edition/revision.
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "source.txt").write_text("Synthetic text " * 30, encoding="utf-8")
            entry = _manifest_entry(edition=None, revision=None)
            (root / "source_metadata.json").write_text(
                json.dumps({"schema": SOURCE_METADATA_SCHEMA, "sources": {"source.txt": entry}}),
                encoding="utf-8",
            )
            chunk = load_chunks(min_len=1, corpus_dir=root)[0]
            self.assertIsNone(chunk.source_edition)
            self.assertIsNone(chunk.source_revision)
            decision = evaluate_source(chunk, _request(edition=None, revision=None))
            self.assertIn("edition_unknown", decision.reasons)
            self.assertIn("revision_unknown", decision.reasons)

    def test_legacy_v1_manifest_is_unaffected_by_the_placeholder_check(self) -> None:
        # "Do not apply new strict requirements to legacy v1 entries; they
        # have no policy eligibility in any case." A literal "unknown" in a
        # v1 edition/revision is unchanged pre-existing behavior, not a new
        # rejection -- and the resulting chunk still has zero eligibility.
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "source.txt").write_text("Synthetic text " * 30, encoding="utf-8")
            (root / "source_metadata.json").write_text(
                json.dumps(
                    {
                        "schema": LEGACY_SOURCE_METADATA_SCHEMA,
                        "sources": {"source.txt": {"edition": "unknown", "revision": "pending"}},
                    }
                ),
                encoding="utf-8",
            )
            chunk = load_chunks(min_len=1, corpus_dir=root)[0]
            self.assertEqual(chunk.source_edition, "unknown")
            self.assertEqual(chunk.source_revision, "pending")
            self.assertIsNone(chunk.source_policy_schema)
            for purpose in (PURPOSE_HUMAN_REVIEW, PURPOSE_QUESTION_GENERATION, PURPOSE_COACH_INDEX):
                decision = evaluate_source(chunk, _request(purpose))
                self.assertEqual(decision.outcome, "excluded")
                self.assertEqual(decision.reasons, ("source_policy_missing",))

    # --- Legacy v1 manifest compatibility regression tests ------------------

    def test_legacy_v1_manifest_accepts_edition_only(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "source.txt").write_text("Synthetic text " * 30, encoding="utf-8")
            (root / "source_metadata.json").write_text(
                json.dumps(
                    {
                        "schema": LEGACY_SOURCE_METADATA_SCHEMA,
                        "sources": {"source.txt": {"edition": "Ed1"}},
                    }
                ),
                encoding="utf-8",
            )
            chunk = load_chunks(min_len=1, corpus_dir=root)[0]
            self.assertEqual(chunk.source_edition, "Ed1")
            self.assertIsNone(chunk.source_revision)

    def test_legacy_v1_manifest_accepts_revision_only(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "source.txt").write_text("Synthetic text " * 30, encoding="utf-8")
            (root / "source_metadata.json").write_text(
                json.dumps(
                    {
                        "schema": LEGACY_SOURCE_METADATA_SCHEMA,
                        "sources": {"source.txt": {"revision": "R1"}},
                    }
                ),
                encoding="utf-8",
            )
            chunk = load_chunks(min_len=1, corpus_dir=root)[0]
            self.assertIsNone(chunk.source_edition)
            self.assertEqual(chunk.source_revision, "R1")

    def test_legacy_v1_manifest_accepts_empty_object(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "source.txt").write_text("Synthetic text " * 30, encoding="utf-8")
            (root / "source_metadata.json").write_text(
                json.dumps(
                    {"schema": LEGACY_SOURCE_METADATA_SCHEMA, "sources": {"source.txt": {}}}
                ),
                encoding="utf-8",
            )
            chunk = load_chunks(min_len=1, corpus_dir=root)[0]
            self.assertIsNone(chunk.source_edition)
            self.assertIsNone(chunk.source_revision)

    def test_legacy_v1_manifest_accepts_both_fields_null(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "source.txt").write_text("Synthetic text " * 30, encoding="utf-8")
            (root / "source_metadata.json").write_text(
                json.dumps(
                    {
                        "schema": LEGACY_SOURCE_METADATA_SCHEMA,
                        "sources": {"source.txt": {"edition": None, "revision": None}},
                    }
                ),
                encoding="utf-8",
            )
            chunk = load_chunks(min_len=1, corpus_dir=root)[0]
            self.assertIsNone(chunk.source_edition)
            self.assertIsNone(chunk.source_revision)

    def test_legacy_v1_manifest_still_rejects_unknown_extra_key(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "source.txt").write_text("Synthetic text " * 30, encoding="utf-8")
            (root / "source_metadata.json").write_text(
                json.dumps(
                    {
                        "schema": LEGACY_SOURCE_METADATA_SCHEMA,
                        "sources": {"source.txt": {"edition": "Ed1", "jurisdiction": "NYC"}},
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(CorpusMetadataError, "unknown source metadata fields"):
                load_chunks(min_len=1, corpus_dir=root)

    def test_malformed_metadata_is_a_separate_outcome(self) -> None:
        decision = evaluate_source(
            _chunk(source_permitted_uses=(PURPOSE_QUESTION_GENERATION, "magic")),
            _request(),
        )
        self.assertEqual(decision.outcome, "invalid_metadata")
        self.assertEqual(
            decision.reasons,
            ("metadata_field_invalid:source_permitted_uses",),
        )

    def test_nyc_only_source_is_not_eligible_for_an_are_division(self) -> None:
        decision = evaluate_source(
            _chunk(source_jurisdictions=("NYC",)),
            _request(jurisdiction="ARE"),
        )
        self.assertIn("jurisdiction_mismatch", decision.reasons)

    def test_model_code_source_is_not_nyc_authority(self) -> None:
        decision = evaluate_source(
            _chunk(source_jurisdictions=("ARE",), source_exam_divisions=(NYC,)),
            _request(division=NYC, jurisdiction="NYC"),
        )
        self.assertIn("jurisdiction_mismatch", decision.reasons)

    def test_explicit_dual_applicability_is_allowed(self) -> None:
        dual = _chunk(
            source_jurisdictions=("ARE", "NYC"),
            source_exam_divisions=(PCM, NYC),
        )
        self.assertTrue(evaluate_source(dual, _request()).eligible)
        self.assertTrue(
            evaluate_source(dual, _request(division=NYC, jurisdiction="NYC")).eligible
        )

    def test_human_review_can_see_pending_with_explicit_restrictions(self) -> None:
        source = _chunk(
            source_applicability_status="pending",
            source_permitted_uses=(PURPOSE_HUMAN_REVIEW,),
        )
        review = evaluate_source(source, _request(PURPOSE_HUMAN_REVIEW))
        generation = evaluate_source(source, _request(PURPOSE_QUESTION_GENERATION))
        self.assertTrue(review.eligible)
        self.assertIn("applicability_pending", review.restrictions)
        self.assertFalse(generation.eligible)
        self.assertIn("purpose_not_permitted", generation.reasons)
        self.assertIn("applicability_pending", generation.reasons)

    def test_generation_and_index_permissions_are_independent(self) -> None:
        generation_only = _chunk(
            source_permitted_uses=(PURPOSE_HUMAN_REVIEW, PURPOSE_QUESTION_GENERATION)
        )
        index_only = _chunk(
            source_permitted_uses=(PURPOSE_HUMAN_REVIEW, PURPOSE_COACH_INDEX)
        )
        self.assertTrue(
            evaluate_source(generation_only, _request(PURPOSE_QUESTION_GENERATION)).eligible
        )
        self.assertFalse(evaluate_source(generation_only, _request(PURPOSE_COACH_INDEX)).eligible)
        self.assertFalse(
            evaluate_source(index_only, _request(PURPOSE_QUESTION_GENERATION)).eligible
        )
        self.assertTrue(evaluate_source(index_only, _request(PURPOSE_COACH_INDEX)).eligible)

    def test_missing_permission_field_fails_closed(self) -> None:
        decision = evaluate_source(
            _chunk(source_usage_permission_status=None),
            _request(),
        )
        self.assertFalse(decision.eligible)
        self.assertIn("usage_permission_missing", decision.reasons)

    def test_new_revision_is_not_automatic_equivalence(self) -> None:
        decision = evaluate_source(
            _chunk(source_edition="2024", source_revision="R1"),
            _request(edition="2021", revision="R2"),
        )
        self.assertIn("edition_mismatch", decision.reasons)
        self.assertIn("revision_mismatch", decision.reasons)

    def test_legacy_chunk_has_no_assumed_eligibility(self) -> None:
        legacy = _chunk(
            source_policy_schema=None,
            source_family_id=None,
            source_permitted_uses=None,
        )
        for purpose in (PURPOSE_QUESTION_GENERATION, PURPOSE_COACH_INDEX):
            decision = evaluate_source(legacy, _request(purpose))
            self.assertEqual(decision.outcome, "excluded")
            self.assertEqual(decision.reasons, ("source_policy_missing",))

    def test_selection_report_and_reason_order_are_deterministic(self) -> None:
        sources = [
            _chunk(source_path="z.pdf", source_chunk_id="chunk:z"),
            _chunk(
                source_path="a.pdf",
                source_chunk_id="chunk:a",
                source_applicability_status="pending",
            ),
        ]
        first = selection_report(select_sources(sources, _request()))
        second = selection_report(select_sources(list(reversed(sources)), _request()))
        self.assertEqual(first, second)
        self.assertEqual(
            [row["source_path"] for row in first["decisions"]],
            ["a.pdf", "z.pdf"],
        )

    def test_generation_selects_division_before_chunk(self) -> None:
        pcm = _chunk(source_path="pcm.pdf", source_chunk_id="chunk:pcm")
        pjm = _chunk(
            source_path="pjm.pdf",
            source_chunk_id="chunk:pjm",
            source_exam_divisions=(PJM,),
        )
        plan = plan_grounded_generation(
            [pjm, pcm], n=2, seed=7, policy_profile=PROFILE
        )
        self.assertEqual(plan.refusals, ())
        self.assertEqual(
            [(item.division, item.chunk.source_path) for item in plan.assignments],
            [(PCM, "pcm.pdf"), (PJM, "pjm.pdf")],
        )

    def test_no_eligible_generation_refuses_before_api_or_embeddings(self) -> None:
        legacy = _chunk(source_policy_schema=None)
        with (
            patch("src.corpus.load_chunks", return_value=[legacy]),
            patch("src.generate.load_env") as load_env,
            patch("src.generate.make_client") as make_client,
            redirect_stdout(StringIO()),
        ):
            result = generate_main(
                ["--grounded", "--n", "1", "--source-policy-profile", PROFILE]
            )
        self.assertEqual(result, 2)
        load_env.assert_not_called()
        make_client.assert_not_called()

    def test_malformed_manifest_is_a_clean_cli_refusal_before_api(self) -> None:
        with (
            patch(
                "src.corpus.load_chunks",
                side_effect=CorpusMetadataError("synthetic malformed metadata"),
            ),
            patch("src.generate.load_env") as load_env,
            patch("src.generate.make_client") as make_client,
            redirect_stdout(StringIO()) as output,
        ):
            result = generate_main(
                ["--grounded", "--n", "1", "--source-policy-profile", PROFILE]
            )
        self.assertEqual(result, 2)
        self.assertIn("REFUSED: invalid source metadata", output.getvalue())
        load_env.assert_not_called()
        make_client.assert_not_called()

    def test_repair_serialization_preserves_original_provenance_and_decision(self) -> None:
        original = Question(
            id="gen_0",
            state="NY",
            section=PCM,
            difficulty="medium",
            question="What should the architect do?",
            options=["A", "B", "C", "D"],
            correctOption="B",
            explanation="B is correct.",
            codeReference="Synthetic 1.1",
            examWeight=10,
            topic="Contracts",
        )
        repaired = Question(**{**original.model_dump(), "options": ["E", "B", "F", "G"]})
        decision = evaluate_source(_chunk(), _request()).to_dict()
        metadata = {
            **_chunk().candidate_source_metadata(),
            "source_policy_decision": copy.deepcopy(decision),
        }
        before = candidate_record(
            original,
            section=PCM,
            grounded_on="synthetic",
            source_metadata=metadata,
            repaired=False,
            verdicts={},
            dup_sim=0.1,
            accepted=True,
            reject_reasons=[],
        )
        after = candidate_record(
            repaired,
            section=PCM,
            grounded_on="synthetic",
            source_metadata=metadata,
            repaired=True,
            verdicts={},
            dup_sim=0.1,
            accepted=True,
            reject_reasons=[],
        )
        for field in _chunk().candidate_source_metadata():
            self.assertEqual(after[field], before[field])
        self.assertEqual(after["source_policy_decision"], decision)

    def test_v2_manifest_does_not_change_page_hash_or_chunk_identity(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            source = root / "guide_2099.txt"
            source.write_text("Stable synthetic identity text. " * 20, encoding="utf-8")
            legacy = load_chunks(min_len=1, corpus_dir=root)[0]
            (root / "source_metadata.json").write_text(
                json.dumps(
                    {
                        "schema": SOURCE_METADATA_SCHEMA,
                        "sources": {"guide_2099.txt": _manifest_entry()},
                    }
                ),
                encoding="utf-8",
            )
            governed = load_chunks(min_len=1, corpus_dir=root)[0]
        self.assertEqual(governed.source_document, legacy.source_document)
        self.assertEqual(governed.source_sha256, legacy.source_sha256)
        self.assertEqual(governed.source_chunk_id, legacy.source_chunk_id)
        self.assertEqual(governed.source_locator, legacy.source_locator)
        self.assertEqual(governed.source_edition, "2021")
        self.assertEqual(governed.source_family_id, "model.standard")
        self.assertIsNone(governed.source_page)
        self.assertIn("source_page", governed.source_not_applicable_metadata)

    def test_v2_manifest_rejects_missing_or_malformed_fields(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "source.txt").write_text("Synthetic text " * 30, encoding="utf-8")
            entry = _manifest_entry()
            del entry["usage_permission_status"]
            (root / "source_metadata.json").write_text(
                json.dumps(
                    {"schema": SOURCE_METADATA_SCHEMA, "sources": {"source.txt": entry}}
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(CorpusMetadataError, "missing=.*usage_permission_status"):
                load_chunks(min_len=1, corpus_dir=root)

    def test_index_plan_reports_exclusions_and_dry_run_never_writes_index(self) -> None:
        request = _request(PURPOSE_COACH_INDEX)
        excluded = _chunk(
            source_path="blocked.pdf",
            source_chunk_id="chunk:blocked",
            source_permitted_uses=(PURPOSE_HUMAN_REVIEW,),
        )
        plan = build_index_plan([excluded], [request])
        self.assertEqual(plan.rows, ())
        self.assertEqual(plan.report["counts"]["excluded_chunks"], 1)
        self.assertEqual(plan.report["excluded_sources"][0]["source_path"], "blocked.pdf")
        self.assertIn(
            "purpose_not_permitted",
            plan.report["excluded_sources"][0]["reasons"],
        )

        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / "coach_index.json"
            report = Path(td) / "report.json"
            output.write_text("PRESERVE", encoding="utf-8")
            with patch("src.build_coach_index.load_chunks", return_value=[excluded]), redirect_stdout(StringIO()):
                result = index_main(
                    [
                        "--division",
                        PCM,
                        "--jurisdiction",
                        "ARE",
                        "--policy-profile",
                        PROFILE,
                        "--output",
                        str(output),
                        "--report",
                        str(report),
                    ]
                )
            self.assertEqual(result, 2)
            self.assertEqual(output.read_text(encoding="utf-8"), "PRESERVE")
            self.assertFalse(report.exists())

    # --- Coach index/report write-safety (--output/--report collisions and
    # atomic replacement) ----------------------------------------------------

    def _excluded_chunk(self) -> Chunk:
        """A chunk with zero eligible purposes -- an "empty eligible corpus"."""
        return _chunk(
            source_path="blocked.pdf",
            source_chunk_id="chunk:blocked",
            source_permitted_uses=(PURPOSE_HUMAN_REVIEW,),
        )

    def _invalid_metadata_chunk(self) -> Chunk:
        return _chunk(
            source_path="bad.pdf",
            source_chunk_id="chunk:bad",
            source_permitted_uses=(PURPOSE_QUESTION_GENERATION, "not-a-real-purpose"),
        )

    def _eligible_chunk(self) -> Chunk:
        return _chunk(source_path="good.pdf", source_chunk_id="chunk:good")

    def _run_index_main(self, chunks, *, output: Path, report: Path, apply: bool = True):
        argv = [
            "--division", PCM,
            "--jurisdiction", "ARE",
            "--policy-profile", PROFILE,
            "--output", str(output),
            "--report", str(report),
        ]
        if apply:
            argv.append("--apply")
        with patch("src.build_coach_index.load_chunks", return_value=chunks), redirect_stdout(StringIO()):
            return index_main(argv)

    def test_same_output_report_path_refused_with_empty_eligible_corpus(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            same = Path(td) / "coach_index.json"
            same.write_text("PRESERVE", encoding="utf-8")
            result = self._run_index_main([self._excluded_chunk()], output=same, report=same)
            self.assertEqual(result, 2)
            self.assertEqual(same.read_text(encoding="utf-8"), "PRESERVE")

    def test_same_output_report_path_refused_with_invalid_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            same = Path(td) / "coach_index.json"
            same.write_text("PRESERVE", encoding="utf-8")
            result = self._run_index_main([self._invalid_metadata_chunk()], output=same, report=same)
            self.assertEqual(result, 2)
            self.assertEqual(same.read_text(encoding="utf-8"), "PRESERVE")

    def test_same_output_report_path_refused_before_a_successful_run_too(self) -> None:
        # Even when every chunk WOULD be eligible, the collision must refuse
        # before any work happens -- an existing index must never become a
        # policy report just because the operator reused one path.
        with tempfile.TemporaryDirectory() as td:
            same = Path(td) / "coach_index.json"
            same.write_text("PRESERVE", encoding="utf-8")
            result = self._run_index_main([self._eligible_chunk()], output=same, report=same)
            self.assertEqual(result, 2)
            self.assertEqual(same.read_text(encoding="utf-8"), "PRESERVE")

    def test_distinct_paths_write_refusal_report_but_preserve_index_on_invalid_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / "coach_index.json"
            report = Path(td) / "report.json"
            output.write_text("PRESERVE", encoding="utf-8")
            result = self._run_index_main([self._invalid_metadata_chunk()], output=output, report=report)
            self.assertEqual(result, 2)
            self.assertEqual(output.read_text(encoding="utf-8"), "PRESERVE")
            self.assertTrue(report.exists())
            written = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual(written["counts"]["invalid_metadata_chunks"], 1)

    def test_dry_run_writes_neither_output_nor_report(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / "coach_index.json"
            report = Path(td) / "report.json"
            output.write_text("PRESERVE", encoding="utf-8")
            result = self._run_index_main(
                [self._eligible_chunk()], output=output, report=report, apply=False
            )
            self.assertEqual(result, 0)
            self.assertEqual(output.read_text(encoding="utf-8"), "PRESERVE")
            self.assertFalse(report.exists())

    def test_successful_apply_replaces_index_and_writes_report(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / "coach_index.json"
            report = Path(td) / "report.json"
            output.write_text("STALE", encoding="utf-8")
            result = self._run_index_main([self._eligible_chunk()], output=output, report=report)
            self.assertEqual(result, 0)
            rows = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["source_path"], "good.pdf")
            written_report = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual(written_report["counts"]["eligible_index_rows"], 1)
            # No leftover temp files from the atomic writer.
            leftovers = [p for p in Path(td).iterdir() if p.suffix == ".tmp"]
            self.assertEqual(leftovers, [])

    def test_simulated_replace_failure_leaves_existing_files_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / "coach_index.json"
            report = Path(td) / "report.json"
            output.write_text("EXISTING INDEX", encoding="utf-8")
            report.write_text("EXISTING REPORT", encoding="utf-8")
            with patch("src.build_coach_index.os.replace", side_effect=OSError("simulated disk failure")):
                with self.assertRaises(OSError):
                    self._run_index_main([self._eligible_chunk()], output=output, report=report)
            self.assertEqual(output.read_text(encoding="utf-8"), "EXISTING INDEX")
            self.assertEqual(report.read_text(encoding="utf-8"), "EXISTING REPORT")
            # The temp file used for the failed replace must not be left behind.
            leftovers = [p for p in Path(td).iterdir() if p.suffix == ".tmp"]
            self.assertEqual(leftovers, [], f"temp file(s) not cleaned up: {leftovers}")

    @unittest.skipUnless(sys.platform.startswith("win"), "case-insensitive filesystem collision is Windows-specific")
    def test_windows_case_only_alias_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / "INDEX.JSON"
            output.write_text("PRESERVE", encoding="utf-8")
            report = Path(td) / "index.json"  # same file on a case-insensitive filesystem
            result = self._run_index_main([self._eligible_chunk()], output=output, report=report)
            self.assertEqual(result, 2)
            self.assertEqual(output.read_text(encoding="utf-8"), "PRESERVE")

    def test_hardlink_alias_is_refused_if_supported_else_skipped(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / "coach_index.json"
            output.write_text("PRESERVE", encoding="utf-8")
            report = Path(td) / "report_alias.json"
            try:
                os.link(output, report)  # a second name for the SAME file
            except (OSError, NotImplementedError) as exc:
                self.skipTest(f"hardlinks are not supported in this environment: {exc}")
            result = self._run_index_main([self._eligible_chunk()], output=output, report=report)
            self.assertEqual(result, 2)
            self.assertEqual(output.read_text(encoding="utf-8"), "PRESERVE")


if __name__ == "__main__":
    unittest.main()
