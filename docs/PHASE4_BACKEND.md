# Phase 4 Backend (AI Coach + Quotas)

## What is implemented
- `functions/askCoach` HTTPS endpoint with Firebase Auth verification.
- Daily quota enforcement by user role:
  - `free`: 10 AI messages/day
  - `premium`: 200 AI messages/day
- Usage counter storage in:
  - `usage/{uid}/daily/{yyyy_mm_dd}.aiMessagesUsed`
- Chat persistence in:
  - `coach_chats/{uid}/threads/default/messages/*`
- Flutter `CoachService` now sends Firebase ID token and handles `401` / `429`.

## 1) Install functions dependencies
From project root:

```powershell
cd functions
npm install
cd ..
```

## 2) Configure Gemini API key for Cloud Functions
Option A (recommended in production): set as environment variable in Cloud Run/Functions config.

For quick setup, deploy with env var:

```powershell
firebase deploy --only functions
```

Then in Google Cloud Console, set env var for function `askCoach`:
- `GEMINI_API_KEY=<your_key>`

If not set, function returns deterministic fallback coaching answer.

## 3) Deploy
```powershell
firebase deploy --only functions
```

## 4) Use endpoint in Flutter
Run app with function URL:

```powershell
flutter run -d chrome --dart-define=COACH_API_URL=https://us-central1-architect-study-app.cloudfunctions.net/askCoach
```

## 5) Subscription role
In Firestore:
- `users/{uid}.role = "premium"` for premium users.
- Any other value or missing role => free tier.

## 6) Verify
1. Ask coach question in app.
2. Check:
   - `usage/{uid}/daily/*` increments.
   - `coach_chats/{uid}/threads/default/messages` contains user+coach messages.
3. Exceed free quota and confirm app gets limit message.
