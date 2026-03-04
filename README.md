# Architectula Education App

NYC-first ARE preparation app with AI coach, voice interaction, test workflows, and readiness tracking.

## Implemented MVP scaffold
- Splash -> Onboarding -> Home shell (Dashboard, Tests, Coach, Profile)
- Seed question flow with code reference and exam point value
- Coach chat with API-ready service (`--dart-define=COACH_API_URL=...`)
- Voice support (STT + TTS) for coach interaction
- Firebase and Hive initialization entry point
- Phase 2 foundation: anonymous auth bootstrap + Firestore question repository
- Firestore config files: `firestore.rules`, `firestore.indexes.json`
- NYC seed dataset: `assets/seeds/questions_ny.json`

## Run
```bash
flutter pub get
flutter run --dart-define=COACH_API_URL=https://<region>-<project>.cloudfunctions.net/coach
```

If `COACH_API_URL` is not set, the app responds with a safe local fallback answer.

## Next technical steps
1. Follow [docs/FIREBASE_PHASE2.md](docs/FIREBASE_PHASE2.md) to configure and deploy Firebase.
2. Set up Phase 4 AI backend with quotas: [docs/PHASE4_BACKEND.md](docs/PHASE4_BACKEND.md).
3. Add Stripe/Apple in-app purchases and enforce daily token quotas in backend.
4. Persist test attempts and weak-topic analytics in Firestore.

## Collaboration and Design Docs
- Branching workflow: [CONTRIBUTING.md](CONTRIBUTING.md)
- System architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Security audit checklist: [docs/SECURITY_AUDIT.md](docs/SECURITY_AUDIT.md)
- Monetization early prep: [docs/MONETIZATION_PREP.md](docs/MONETIZATION_PREP.md)
