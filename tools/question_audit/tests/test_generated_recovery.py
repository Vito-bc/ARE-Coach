"""PR #54 recovery regressions; all data and CLI paths are synthetic.

The subprocess tests run the real ``python -m src.merge_accepted`` entry point.
A temporary sitecustomize only pauses cleanup through a socket handshake; it
does not replace CLI, recovery, or locking code. No timing sleeps are used.
"""
from __future__ import annotations

import contextlib
import io
import json
import os
import socket
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from openpyxl import load_workbook

from src import generated_import as gi
from src.generated_approval import write_review_workbook
from src.merge_accepted import main
from tests import test_generated_import as fixtures


TOOL_DIR = Path(__file__).resolve().parents[1]
PAUSE_CLEANUP = '''
import os, socket
from pathlib import Path
original_unlink = Path.unlink
paused = False
def unlink(path, *args, **kwargs):
    global paused
    if str(path) == os.environ['TEST_PENDING_PATH'] and not paused:
        paused = True
        with socket.create_connection(('127.0.0.1', int(os.environ['TEST_PORT'])), timeout=20) as connection:
            connection.sendall(b'cleanup\\n')
            if connection.recv(1) != b'G':
                raise RuntimeError('test did not release cleanup')
    return original_unlink(path, *args, **kwargs)
Path.unlink = unlink
'''


class GeneratedRecoveryTest(unittest.TestCase):
    def setUp(self):
        self.f = fixtures.GeneratedImportTest()
        self.f.setUp()
        self.addCleanup(self.f.tearDown)
        self.f._edit_review(**{"REVIEW: verdict": "Approve"})
        self.pointer = gi.transaction_pointer_for(self.f.journal)

    def argv(self, source=None, review=None, *, apply=True, bank=None, journal=None):
        result = [
            "--input", str(source or self.f.source),
            "--review-book", str(review or self.f.review),
            "--bank", str(bank or self.f.bank),
            "--journal", str(journal or self.f.journal),
            "--backups-dir", str(self.f.backups),
        ]
        return result + (["--apply"] if apply else [])

    def run_main(self, **kwargs):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = main(self.argv(**kwargs))
        return result, output.getvalue()

    def batch(self, label):
        source = self.f.root / (label + ".json")
        review = self.f.root / (label + ".xlsx")
        candidates = [fixtures._candidate(label, "Question " + label + "?")]
        source.write_text(json.dumps(candidates), encoding="utf-8")
        write_review_workbook(candidates, review, source_path=source)
        workbook = load_workbook(review)
        workbook["review"]["A2"] = "Approve"
        workbook.save(review)
        workbook.close()
        return source, review

    def assert_consistent(self, candidate_ids):
        bank = gi.load_bank(self.f.bank)
        journal = gi.load_journal(self.f.journal)
        gi.verify_bank_journal_consistency(bank, journal)
        self.assertEqual({entry["candidate_id"] for entry in journal["imports"]}, set(candidate_ids))
        self.assertEqual(len(bank), 1 + len(candidate_ids))

    def leave_cleanup_pending(self):
        original = Path.unlink
        def fail(path, *args, **kwargs):
            if path == self.pointer:
                raise OSError("synthetic interruption before cleanup")
            return original(path, *args, **kwargs)
        with patch.object(Path, "unlink", fail), self.assertRaises(OSError):
            gi.apply_import_plan(self.f._plan(), bank_path=self.f.bank,
                                 journal_path=self.f.journal, backups_dir=self.f.backups)
        self.assertTrue(self.pointer.exists())

    def manifest_path(self):
        return Path(json.loads(self.pointer.read_text())["manifest_path"])

    def test_unknown_current_journal_refuses_before_bank_write(self):
        self.f._leave_partial_transaction(fail_target=self.f.bank)
        self.f.journal.write_text('{"external":"unknown state"}', encoding="utf-8")
        before = self.f.bank.read_bytes(), self.f.journal.read_bytes()
        result, output = self.run_main()
        self.assertEqual(result, 2, output)
        self.assertEqual((self.f.bank.read_bytes(), self.f.journal.read_bytes()), before)
        self.assertTrue(self.pointer.exists())

    def test_damaged_staged_journal_refuses_before_bank_write(self):
        self.f._leave_partial_transaction(fail_target=self.f.bank)
        manifest = json.loads(self.manifest_path().read_text())
        Path(manifest["journal_staged_path"]).write_bytes(b"truncated")
        before = self.f.bank.read_bytes()
        result, output = self.run_main()
        self.assertEqual(result, 2, output)
        self.assertEqual(self.f.bank.read_bytes(), before)
        self.assertFalse(self.f.journal.exists())
        self.assertTrue(self.pointer.exists())

    def test_cleanup_interruption_preserves_manifest_and_allows_next_import(self):
        original_write, original_unlink = Path.write_bytes, Path.unlink
        def interrupt_write(path, data):
            # The reviewed HEAD destroys its only manifest at this boundary.
            if path.name == "manifest.json" and b'"complete"' in data:
                with path.open("wb"):
                    pass
                raise OSError("synthetic interruption after manifest truncation")
            return original_write(path, data)
        def interrupt_unlink(path, *args, **kwargs):
            if path == self.pointer:
                raise OSError("synthetic interruption before cleanup")
            return original_unlink(path, *args, **kwargs)
        with patch.object(Path, "write_bytes", interrupt_write), patch.object(Path, "unlink", interrupt_unlink):
            result, _ = self.run_main()
        self.assertEqual(result, 2)
        self.assert_consistent(["gen_0"])
        result, output = self.run_main()
        self.assertEqual(result, 0, output)
        self.assertFalse(self.pointer.exists())
        source, review = self.batch("next")
        result, output = self.run_main(source=source, review=review)
        self.assertEqual(result, 0, output)
        self.assert_consistent(["gen_0", "next"])

    def test_failed_validation_after_recovery_does_not_claim_no_addition(self):
        self.f._leave_partial_transaction(fail_target=self.f.bank)
        self.f.source.write_bytes(b"invalid JSON")
        result, output = self.run_main()
        self.assertEqual(result, 2)
        self.assert_consistent(["gen_0"])
        self.assertNotIn("No candidate was added", output)
        self.assertIn("RECOVERY:", output)

    def test_dry_run_does_not_recover_or_create_files(self):
        def snapshot():
            return {str(p.relative_to(self.f.root)): p.read_bytes()
                    for p in self.f.root.rglob("*") if p.is_file()}
        before = snapshot()
        self.assertEqual(self.run_main(apply=False)[0], 0)
        self.assertEqual(snapshot(), before)
        self.f._leave_partial_transaction(fail_target=self.f.journal)
        before = snapshot()
        self.assertEqual(self.run_main(apply=False)[0], 2)
        self.assertEqual(snapshot(), before)

    def cli(self, argv, *, cwd=TOOL_DIR):
        env = os.environ.copy()
        env["PYTHONPATH"] = str(TOOL_DIR)
        return subprocess.run([sys.executable, "-m", "src.merge_accepted", *argv],
                              cwd=cwd, env=env, capture_output=True, text=True, timeout=30)

    @contextlib.contextmanager
    def paused_cli(self, argv):
        hooks = self.f.root / "hooks"
        hooks.mkdir(exist_ok=True)
        (hooks / "sitecustomize.py").write_text(PAUSE_CLEANUP, encoding="utf-8")
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            listener.settimeout(20)
            env = os.environ.copy()
            env.update(PYTHONPATH=os.pathsep.join([str(hooks), str(TOOL_DIR)]),
                       TEST_PENDING_PATH=str(self.pointer), TEST_PORT=str(listener.getsockname()[1]))
            process = subprocess.Popen([sys.executable, "-m", "src.merge_accepted", *argv],
                                       cwd=TOOL_DIR, env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, text=True)
            try:
                connection, _ = listener.accept()
                with connection:
                    connection.settimeout(20)
                    with connection.makefile("rb") as incoming:
                        self.assertEqual(incoming.readline(), b"cleanup\n")
                    yield process, connection
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate(timeout=20)

    def test_two_real_clis_serialize_old_pending_recovery_and_import(self):
        self.leave_cleanup_pending()
        a_source, a_review = self.batch("A")
        b_source, b_review = self.batch("B")
        with self.paused_cli(self.argv(a_source, a_review)) as (owner, connection):
            before = self.f.bank.read_bytes(), self.f.journal.read_bytes(), self.pointer.read_bytes()
            contender = self.cli(self.argv(b_source, b_review))
            self.assertEqual(contender.returncode, 2, contender.stdout + contender.stderr)
            self.assertIn("lock", contender.stdout.lower())
            self.assertEqual((self.f.bank.read_bytes(), self.f.journal.read_bytes(), self.pointer.read_bytes()), before)
            connection.sendall(b"G")
            out, err = owner.communicate(timeout=20)
            self.assertEqual(owner.returncode, 0, out + err)
        self.assert_consistent(["gen_0", "A"])
        retry = self.cli(self.argv(b_source, b_review))
        self.assertEqual(retry.returncode, 0, retry.stdout + retry.stderr)
        self.assert_consistent(["gen_0", "A", "B"])
        self.assertFalse(self.pointer.exists())

    def test_killed_cli_owner_releases_bank_lock(self):
        self.leave_cleanup_pending()
        source, review = self.batch("after_crash")
        with self.paused_cli(self.argv()) as (owner, _):
            contender = self.cli(self.argv(source, review))
            self.assertEqual(contender.returncode, 2, contender.stdout + contender.stderr)
            self.assertIn("lock", contender.stdout.lower())
            owner.kill()  # TerminateProcess on Windows, SIGKILL on Linux: no finally.
            owner.communicate(timeout=20)
        retry = self.cli(self.argv(source, review))
        self.assertEqual(retry.returncode, 0, retry.stdout + retry.stderr)
        self.assert_consistent(["gen_0", "after_crash"])

    def test_bank_lock_covers_path_aliases_and_different_journal(self):
        self.leave_cleanup_pending()
        source, review = self.batch("alias")
        # Relative paths and '..' must converge on the same lock. On Windows,
        # also exercise case normalization; Unix additionally tests symlinks.
        # Run the contender from the data directory: the Windows runner keeps
        # its checkout on D: and TEMP on C:, which have no relative path.
        aliases = [Path(self.f.bank.name),
                   self.f.root / ".." / self.f.root.name / self.f.bank.name]
        if os.name == "nt":
            aliases.append(Path(str(self.f.bank).upper()))
            aliases.append(Path(self.f.temp.name) / self.f.bank.name)  # TEMP's possible 8.3 alias
        else:
            link = self.f.root / "bank-alias.json"
            link.symlink_to(self.f.bank)
            aliases.append(link)
        other_journal = self.f.root / "other-journal.json"
        with self.paused_cli(self.argv()) as (owner, connection):
            for alias in aliases:
                with self.subTest(alias=alias):
                    result = self.cli(self.argv(source, review, bank=alias, journal=other_journal), cwd=self.f.root)
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    self.assertIn("lock", result.stdout.lower())
            self.assertFalse(other_journal.exists())
            before = self.f.bank.read_bytes(), self.f.journal.read_bytes(), self.pointer.read_bytes()
            dry_run = self.cli(self.argv(apply=False))
            self.assertEqual(dry_run.returncode, 2, dry_run.stdout + dry_run.stderr)
            self.assertEqual((self.f.bank.read_bytes(), self.f.journal.read_bytes(), self.pointer.read_bytes()), before)
            connection.sendall(b"G")
            out, err = owner.communicate(timeout=20)
            self.assertEqual(owner.returncode, 0, out + err)
        self.assert_consistent(["gen_0"])

    def test_preflight_checks_manifest_and_prepared_cross_references(self):
        self.f._leave_partial_transaction(fail_target=self.f.bank)
        manifest_path = self.manifest_path()
        manifest = json.loads(manifest_path.read_text())
        before = self.f.bank.read_bytes()
        for field, value in (("bank_after_sha256", "bad hash"),
                             ("journal_staged_path", manifest["bank_path"]),
                             ("journal_before_sha256", [])):
            with self.subTest(field=field):
                manifest_path.write_text(json.dumps({**manifest, field: value}), encoding="utf-8")
                self.assertEqual(self.run_main()[0], 2)
                self.assertEqual(self.f.bank.read_bytes(), before)
                self.assertFalse(self.f.journal.exists())
        # Even matching file hashes must not accept a pair with inconsistent
        # candidate -> bank references. No replacement may precede this check.
        staged = Path(manifest["journal_staged_path"])
        journal = json.loads(staged.read_text())
        journal["imports"][0]["bank_id"] = "missing"
        data = gi._pretty_json(journal)
        staged.write_bytes(data)
        manifest["journal_after_sha256"] = gi._hash_bytes(data)
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        self.assertEqual(self.run_main()[0], 2)
        self.assertEqual(self.f.bank.read_bytes(), before)
        self.assertFalse(self.f.journal.exists())

    def test_replace_boundaries_and_cleanup_are_repeatable(self):
        for target in ("bank", "journal"):
            for boundary in ("before", "after"):
                with self.subTest(target=target, boundary=boundary):
                    f = fixtures.GeneratedImportTest()
                    f.setUp()
                    try:
                        f._edit_review(**{"REVIEW: verdict": "Approve"})
                        plan = f._plan()
                        def fail_replace(source, destination):
                            if Path(destination) == getattr(f, target) and boundary == "before":
                                raise OSError("synthetic boundary failure")
                            os.replace(source, destination)
                            if Path(destination) == getattr(f, target) and boundary == "after":
                                raise OSError("synthetic boundary failure")
                        with self.assertRaises(OSError):
                            gi.apply_import_plan(plan, bank_path=f.bank, journal_path=f.journal,
                                                 backups_dir=f.backups, replace_target=fail_replace)
                        pointer = gi.transaction_pointer_for(f.journal)
                        manifest_path = Path(json.loads(pointer.read_text())["manifest_path"])
                        manifest_before = manifest_path.read_bytes()
                        result = self.cli(["--input", str(f.source), "--review-book", str(f.review),
                                           "--bank", str(f.bank), "--journal", str(f.journal),
                                           "--backups-dir", str(f.backups), "--apply"])
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertEqual(manifest_path.read_bytes(), manifest_before)
                        self.assertFalse(gi.recover_pending_transaction(pointer, expected_bank_path=f.bank))
                        gi.verify_bank_journal_consistency(gi.load_bank(f.bank), gi.load_journal(f.journal))
                        self.assertEqual(gi.load_journal(f.journal)["imports"][0]["candidate_snapshot"], f.candidates[0])
                    finally:
                        f.tearDown()


if __name__ == "__main__":
    unittest.main()
