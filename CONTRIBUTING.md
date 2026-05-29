# Contributing Guide

## Branching

| Branch pattern | Purpose |
|---|---|
| `main` | Production-stable. Protected — PRs only, CI must pass. |
| `feat/<name>` | New features |
| `fix/<name>` | Bug fixes |
| `chore/<name>` | Config, deps, tooling |
| `docs/<name>` | Documentation only |

## Workflow

1. Branch from `main`:
   ```bash
   git checkout -b feat/your-feature
   ```
2. Make your changes
3. Run checks locally:
   ```bash
   flutter analyze   # must return 0 issues
   flutter test      # must pass
   ```
4. Open a PR into `main` — the PR template will guide you
5. CI runs automatically (`flutter analyze` + `flutter test`)

## Rules

- No direct commits to `main`
- No force-push to `main`
- `flutter analyze` must be clean before requesting review
- Keep secrets out of the repo — `GoogleService-Info.plist`, `google-services.json`, API keys, `.env` files
- Firestore rules must be updated if the data schema changes
