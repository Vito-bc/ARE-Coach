# Architectula Education App

NYC-first ARE preparation app with AI coach, voice interaction, test workflows, and readiness tracking.

## Implemented MVP scaffold
- Splash -> Onboarding -> Home shell (Dashboard, Tests, Coach, Profile)
- Seed question flow with code reference and exam point value
- Coach chat with API-ready service (`--dart-define=COACH_API_URL=...`)
- Voice support (STT + TTS) for coach interaction
- Firebase and Hive initialization entry point

## Run
```bash
flutter pub get
flutter run --dart-define=COACH_API_URL=https://<region>-<project>.cloudfunctions.net/coach
```

If `COACH_API_URL` is not set, the app responds with a safe local fallback answer.

## Next technical steps
1. Configure Firebase (`flutterfire configure`) and add `firebase_options.dart`.
2. Move AI calls behind Cloud Functions with auth + rate limiting by subscription tier.
3. Add Stripe/Apple in-app purchases and enforce daily token quotas in backend.
4. Persist test attempts and weak-topic analytics in Firestore.
