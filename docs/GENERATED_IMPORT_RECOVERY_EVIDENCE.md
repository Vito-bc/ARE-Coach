# Generated import recovery: PR #54 follow-up

Reviewed implementation: `8f9fd6f2c43fb0eeb98d7d45fa6dfddac00f62f8`.
Base: `d5e192c856986fa8c145647f2a56bc896e3ac0af`.

This change addresses the three confirmed recovery defects. It does not change
the question bank, source corpus, expert review workbooks, or the local review
package. Existing recovery/inventory documents are retained.

## Regressions before and after the fix

The independent reviewer's `review_repros.py` was read from the supplied temporary
directory. Its unknown-journal, damaged-staged-journal, manifest-truncation and
overlapping-recovery cases are now permanent tests in
`tools/question_audit/tests/test_generated_recovery.py`.

Before implementation changes, the initial seven regression methods ran against
the reviewed HEAD: five failures, one error, one passing dry-run test. The error
was the truncated manifest also crashing the CLI's error-reporting path. After
the suite was expanded, all ten new methods were also run against an isolated
copy of the reviewed HEAD: **16 failing assertions/subtests and one error**.
The dry-run method passed; the other nine methods exposed the old behavior.

After the fix, **all 25 tests pass** (15 existing approval/import tests plus ten
new recovery methods, including their parameterized cases). Local environment:
Windows, Python 3.13.5, Pydantic 2.11.7, openpyxl 3.1.5.

Commands, from `tools/question_audit`:

```text
python -m unittest tests.test_generated_recovery -v
python -m unittest discover -s tests -v
python -m src.check_bank
```

The content command is read-only: all eight checks passed (1,082 questions and
300 flashcards). `git diff --check` passed. All import/recovery experiments use
`TemporaryDirectory` fixtures with explicit synthetic bank, journal, candidate,
workbook and backup paths.

## Boundaries exercised

| Scenario | Required result |
| --- | --- |
| Two real CLI processes with different approved batches and an old committed pending transaction | While A pauses at old-marker cleanup, B gets a lock refusal before any recovery/write. A succeeds; retrying B preserves both imports and consistent provenance. |
| Unknown current journal | Refuse before changing the bank or journal; retain the pending evidence. |
| Damaged prepared journal | Refuse before changing the bank; no journal is created. |
| Invalid manifest fields or inconsistent prepared bank/journal references | Reject before the first target replacement, even when the supplied after-image hash matches. |
| Interruption at manifest completion/marker cleanup | Manifest remains intact; retry completes cleanup and a subsequent candidate imports successfully. |
| Kill the CLI holding the bank lock | A competing CLI is refused while the owner is alive. `Popen.kill()` terminates the owner without Python cleanup; the next CLI acquires ownership, recovers and imports. |
| Bank/journal replacement, before and after each replace | Four fault boundaries recover using the exact prepared candidate snapshot; the manifest bytes stay unchanged, and another cleanup is a no-op. |
| Candidate validation fails after successful recovery | Report recovery/current state; never claim that no candidate was added. |
| Relative/`..` bank paths, Windows case aliases, Linux symlinks, alternative journal path | All contenders for the same normalized bank use the same lock. |
| Fresh, pending, and concurrently pending dry-run | No recovery or data changes; a fresh dry-run does not create a lock file. |

Subprocess tests execute `python -m src.merge_accepted`, not a replacement CLI.
A temporary `sitecustomize.py` pauses only the pending-marker unlink operation.
Parent/child synchronization uses a local socket handshake with bounded timeouts;
there are no random delays or sleeps. Production code contains no test hooks.

## Implementation and platform coverage

The bank lock spans pending inspection, recovery, loading bank/journal, planning,
application, error-state inspection and cleanup. Direct mutation APIs acquire
the same lock or validate an existing caller-owned lock. Lock identity resolves
relative paths, symlinks/junctions and Windows case aliases. The persistent lock
file is never removed or reclaimed by age. Ownership is held by the operating
system (`msvcrt.locking` on Windows; `fcntl.flock` on Linux) and released when the
descriptor closes or its process terminates.

Recovery preflights both current target hashes, all after-images still needed,
manifest structure/paths/hashes, and prepared bank/journal consistency. A target
already at its after-hash supplies its prepared image because replacement has
consumed the corresponding staged file. Recovery never rebuilds content from a
possibly changed candidate file. The manifest remains immutable; absence of the
pending marker records completed cleanup, rather than a rewritten status field.

The existing content CI job now runs on **ubuntu-latest and windows-latest**,
using Python 3.12, Pydantic 2.9.2 and openpyxl 3.1.5. Both run all 25 tests and
content checks. The existing Linux check name `Content checks` is preserved;
the additional check is `Content checks (Windows)`. Consult the checks attached
to the final PR HEAD for the actual CI outcome; local Windows results alone do
not establish Linux behavior.

## Limits

- This is a cooperative, single-host lock on a local filesystem. Cross-machine
  cloud-sync replicas, network filesystems, and writers bypassing the importer
  are not coordinated by it. Do not manually remove the lock file.
- The tests cover process termination and injected write/cleanup failures, not
  physical power loss or filesystem durability under device failure.
- Unknown/corrupted recovery evidence is refused for manual inspection; the
  importer does not guess a replacement snapshot or silently delete evidence.
- `--apply` can create the persistent lock file even when there are no eligible
  additions. Dry-run creates no lock file and is not an atomic read snapshot
  while another process is writing; a later apply always reloads under the lock.
