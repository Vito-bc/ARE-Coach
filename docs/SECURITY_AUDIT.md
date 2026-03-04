# Security Audit Notes (Pre-Production)

Date: 2026-03-04

## 1) Cloud Functions Surface
Status:
- `askCoach` verifies Firebase ID token.
- Daily per-user quota is enforced in backend.
- AI key remains server-side.

Gaps:
- No App Check enforcement yet.
- No IP-level throttling/WAF rules yet.

Action:
1. Enable App Check on web/mobile clients.
2. Reject requests without valid App Check token.
3. Add budget alerts and function invocation alerts.

## 2) Firestore Rules
Status:
- Rules are not `allow read, write: if true`.
- User data is scoped by `request.auth.uid`.
- `questions` write requires admin.
- `subscriptions` write requires admin.

Risk:
- Client currently can write owner-scoped `usage`, `attempts`, and `analytics`.
  This is acceptable for MVP but can be tampered by modified clients.

Action:
1. Move critical writes (usage/billing-related counters) to Cloud Functions only.
2. Reduce direct client writes for monetization-sensitive fields.
3. Add automated emulator tests for rules before release.

## 3) Secrets
Status:
- `serviceAccountKey.json` is in `.gitignore`.
- AI key expected in server env, not client.

Action:
1. Rotate any leaked local keys.
2. Store production keys in managed secret store.

## 4) Abuse & Cost
Status:
- Daily quotas in backend implemented.

Action:
1. Add per-minute throttle.
2. Add anomaly detection (sudden spikes by uid/ip).
3. Add hard monthly spend limits in provider dashboards.

## 5) Release Gate
Before production launch:
1. Pass Firestore rules audit + tests.
2. Pass function auth/app-check audit.
3. Verify paid role transitions are server-authoritative.
