# Firestore backup & restore

Written for whoever is at the keyboard during an incident, not for leisurely reading.
If you are here because production data got deleted or corrupted, read **"Real
recovery, right now"** first and come back for the rest later.

Tool: `tools/backup_restore/` (Node, `firebase-admin` only). Not deployed and not a
Cloud Function -- it is a standalone script pair you run from your own machine or a
Cloud Shell. Its tests *are* wired into CI (`.github/workflows/flutter-ci.yml`): the
51 unit tests run in the "Backup/restore tool unit tests" job, and the 12 emulator
tests run in the "Apple verifier and Firestore integration" job, on the same emulator
the other integration specs use. This tool cannot silently rot between incidents.

## Real recovery, right now

You need: the most recent archive directory (a folder full of `.json` files plus a
`manifest.json`), and either `GOOGLE_APPLICATION_CREDENTIALS` pointing at a service
account with Firestore write access, or to be logged in via `gcloud auth
application-default login` as someone who has it.

```bash
cd tools/backup_restore
npm install   # only if node_modules isn't already there

node bin/restore_firestore.js \
  --archive /path/to/the/archive/2026-09-17T231045Z \
  --project architect-study-app \
  --allow-production
```

It will print the exact target and ask you to **type the project id back**
(`architect-study-app`) before writing anything. That prompt cannot be skipped for
production, with or without `--yes` — it is the one thing standing between a
mistyped command and overwriting real data. Nothing else about this command is
interactive.

**If it immediately refuses with "FIRESTORE_EMULATOR_HOST is already set..."** — this
means that exact environment variable is already set in your current shell, probably
left over from practicing against the emulator earlier (see "Running a restore into
the emulator" below). The tool will not guess what you meant. Either:
- run `unset FIRESTORE_EMULATOR_HOST` (or close this shell and open a fresh one) and
  re-run the command above, or
- if you actually did mean to target that host, pass it back explicitly with
  `--emulator-host <the value the error printed>`.

Either way, nothing was written — this check runs before the tool ever touches
Firestore.

What this does NOT do: delete documents that exist in the target but aren't in the
archive. If the incident is "some documents are corrupted," this restore fixes those
document paths byte-for-byte. If the incident is "the whole project is gone," restore
into a **fresh** project (or after the collections have been wiped) so nothing stale
is left mixed in with the restored data — see "What isn't covered" below for why a
fresh project also needs its Auth users and rules redeployed separately.

Where do archives live? This tool does not manage where archives are stored or
scheduled — that's explicitly out of scope for this slice (see the top of
`tools/backup_restore/`). Right now, "the most recent archive" means the most recent
one someone ran `export_firestore.js` and kept. Check with whoever last ran an export,
or wherever your team has been copying the `--out` directory to (this doc will be
updated once that's decided).

## What's covered, and why

The archive contains exactly these top-level collections (see
`tools/backup_restore/src/collections.js` for the single source of truth both scripts
read from):

| Collection | What it is |
|---|---|
| `users` | Profile, role, entitlement snapshot, Terms/Privacy assent record |
| `subscriptions` | Secondary per-user subscription record |
| `attempts` | Per-user question-attempt history (`attempts/{uid}/sessions/{id}`) |
| `analytics` | Per-user weak-topic analytics |
| `coach_chats` | AI Coach chat history (`threads/{id}/messages/{id}`) |
| `usage` | Daily/minute rate-limit counters |
| `reports` | User-submitted question-flag reports |
| `appleBilling` | Apple purchase ownership/idempotency ledger — the source of truth for entitlement decisions. `firestore.rules` denies ALL client read/write on it; this tool reaches it only because the Admin SDK bypasses rules. |

**Deliberately NOT covered:**

- **`questions`** (the exam bank) — already durable. It lives in git at
  `assets/seeds/questions_ny.json`, independent of Firestore.
- **Firebase Auth users** (accounts, password hashes, Apple provider links) — this is
  a Firestore tool; Auth has its own store. A full account-level recovery also needs
  `firebase auth:export accounts.json --project architect-study-app` (and
  `firebase auth:import` to restore). Restoring Firestore `users/{uid}` documents
  without also restoring the matching Auth accounts leaves orphaned profiles nobody
  can sign into.
- **Cloud Storage** — not currently used by this app. If that changes, this doc and
  the tool both need updating.
- **Secrets** (API keys, service account credentials, Apple/Anthropic keys) — never
  touched by this tool, and never Firestore data in the first place.
- **`firestore.rules`** — a fresh/restored project needs rules deployed separately
  (`firebase deploy --only firestore:rules`). This tool never touches the rules file.

## Running an export (routine backup)

```bash
cd tools/backup_restore
node bin/export_firestore.js --project architect-study-app --out /path/to/backups
```

This is **read-only against production**, in two independent ways: the credential
used should hold only `roles/datastore.viewer` in IAM (this tool cannot itself grant
or check that — set it up once, ahead of time), and the code itself wraps the
Firestore client in a guard (`src/read_only_db.js`) that throws if anything ever calls
a write method, regardless of what IAM allows. Both would have to fail for this
script to write anything.

Output: a new timestamped directory (e.g. `2026-09-17T231045Z/`) containing one
`.json` file per covered collection plus a `manifest.json` (source project, export
time, per-collection document counts, and a warning if Firestore has grown a
collection this tool doesn't yet know about). Re-exporting identical data produces
byte-identical files — the archive is deterministic, so two exports can be diffed
directly to see what actually changed.

## Running a restore into the emulator (safe to practice anytime)

Default target is the local emulator — no `--project` needed:

```bash
firebase emulators:start --only firestore   # in one terminal
cd tools/backup_restore                      # in another
node bin/restore_firestore.js --archive /path/to/the/archive/2026-09-17T231045Z
```

This targets `demo-are-coach` on `127.0.0.1:8087` and cannot reach real Firestore.
Practice here as often as you want.

## Timing

The drill (below) restores 16 synthetic documents across 8 collections, including a
3-level-deep nested ledger, in a few seconds end to end against the emulator. Real
restore time scales with document count, not collection count — a production account
base in the thousands should still be low minutes, not hours, but this has not been
load-tested against production-scale data. If a real restore is taking dramatically
longer than that, something is wrong (check for emulator/network throttling) rather
than assuming it's normal.

## The drill

**A restore nobody has ever verified is not a backup.** This tool ships with an
automated test that proves the whole pipeline actually works, using only synthetic
data against the local emulator — it seeds synthetic users with progress, attempts,
entitlements and chat history, runs the real `export_firestore.js` CLI, wipes the
emulator, runs the real `restore_firestore.js` CLI, then re-reads everything and
asserts it is `deepStrictEqual` to what was seeded — same document paths, same
`exists` flags (including documents that only exist implicitly, as the parent of a
subcollection), same field values with exact types (a restored Timestamp must still
be a `Timestamp`, not a string), same arrays, same nested maps, at every depth.

Run it yourself (from the repo root):

```bash
npx --yes firebase-tools@15.8.0 emulators:exec --only firestore \
  --project demo-are-coach --config firebase.test.json \
  "node --test tools/backup_restore/integration/drill.spec.cjs \
     tools/backup_restore/integration/read_only_escape.spec.cjs"
```

CI runs exactly this, chained after the `functions/` emulator specs inside the same
emulator start. Keep it a *separate* `node --test` invocation from those specs:
`node --test` runs its files concurrently, and these two groups share one emulator
database -- the drill wipes and reseeds every covered collection, while
`functions/integration/apple_ownership.spec.cjs` calls `clearFirestore()` between its
own tests. Interleaving them would make both flaky.

It also proves the production guard from the CLI side, not just as a unit test: it
runs `restore_firestore.js --project architect-study-app` (no `--allow-production`)
and asserts the process exits non-zero with the refusal message, and that this
happens before `firebase-admin` is ever initialized — so it's safe to run even though
it names the real project id.

Pure unit tests (no emulator needed) live in `tools/backup_restore/test/` and cover
the type-preserving JSON codec, the read-only Firestore wrapper, and the
production-refusal guard's decision logic in isolation:

```bash
cd tools/backup_restore && npm ci && node --test
```

(`npm ci` because `test/serialize.test.js` needs real `firebase-admin`
`Timestamp`/`GeoPoint`/`DocumentReference` instances at import time. `node --test`
from the package root picks up `test/*.test.js` only -- `integration/*.spec.cjs` does
not match Node's default test-file patterns, so the emulator specs above stay
opt-in.)

## Why this exists

The write side of this app has strong gates: `firestore.rules`, entitlement checks,
fail-closed source policy. None of that protects against data *loss* — a bad
migration, an accidental `recursiveDelete`, a bug in an admin script. This tool is
the other half: a proven way to get the non-reproducible data back. The question bank
is already safe (it's in git). Per-user progress, attempts, entitlement state, chat
history, and reports are not reproducible if lost — this is what protects them.
