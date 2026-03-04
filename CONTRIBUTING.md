# Contributing Guide

## Branching Strategy
Use a lightweight Git Flow:

- `main`: production-stable only
- `dev`: integration branch for completed features
- `feature/<name>`: implementation branches
- `hotfix/<name>`: urgent production fixes from `main`

## Workflow
1. Branch from `dev`: `feature/phase4-rate-limit`.
2. Open PR into `dev`.
3. Run checks before merge:
   - `flutter analyze`
   - `flutter test`
4. Squash merge to keep history clean.
5. Release by merging `dev` into `main` with release notes.

## Rules
- No direct commits to `main`.
- No force-push to `main` or `dev`.
- Require at least one review for PRs.
- Keep secrets out of repo (`serviceAccountKey.json`, API keys).
