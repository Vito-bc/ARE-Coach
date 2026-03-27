# Phase 4 Hardening Setup

This document matches the current implementation in `feature/phase4-hardening`.

## Implemented in code
1. Atomic quota enforcement (Firestore transaction) in `functions/askCoach`.
2. Per-minute throttle (`3/min`) + daily limit (`10 free / 200 premium`).
3. App Check verification in function (`x-firebase-appcheck` token required).
4. Structured logs with uid, model, usage, latency.
5. Secret Manager integration (`GEMINI_API_KEY`) instead of plain env var.
6. Flutter app initializes App Check and sends token in coach requests.

## 1) Install Functions dependencies
```powershell
cd functions
npm install
cd ..
```

## 2) Set secret in Firebase/Google Secret Manager
```powershell
firebase functions:secrets:set GEMINI_API_KEY
```

## 3) Deploy function
```powershell
firebase deploy --only functions
```

## 4) Enable App Check enforcement
1. Firebase Console -> App Check.
2. Register providers:
   - Android: Play Integrity
   - iOS: DeviceCheck
   - Web: reCAPTCHA v3
3. Enable enforcement for Cloud Functions (start in staging/dev first).

## 5) Run app with required defines
```powershell
flutter run -d chrome --dart-define=COACH_API_URL=https://us-central1-architect-study-app.cloudfunctions.net/askCoach --dart-define=RECAPTCHA_SITE_KEY=<your_web_recaptcha_site_key>
```

## 6) Firestore data paths used
- `users/{uid}`:
  - `role: free|premium`
  - `subscriptionStatus`
  - `premiumUntil`
- `usage/{uid}/daily/{yyyy_mm_dd}`
- `usage/{uid}/minute/{yyyyMMdd_HHmm}`
- `coach_chats/{uid}/threads/default/messages/*`

## 7) Optional hardening actions (console)
1. Configure Firestore TTL for `usage/{uid}/minute/*` via `expiresAt`.
2. Create budgets/alerts in Google Cloud Billing:
   - thresholds: `$10`, `$25`, `$50`
3. Add alerting dashboard for Cloud Logging on `coach_request`.
