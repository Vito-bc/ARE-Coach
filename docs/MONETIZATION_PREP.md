# Monetization Prep (Do Early)

## Why now
Stripe and Apple/Google billing have different requirements and review timelines.
Do setup early so release is not blocked later.

## Immediate checklist
1. Create App Store Connect app entry.
2. Create Google Play Console app entry.
3. Reserve product IDs now:
   - `are_coach_monthly`
   - `are_coach_yearly`
4. Draft subscription metadata/screenshots for review.
5. Configure Stripe test products for web checkout.
6. Define server source of truth:
   - `users/{uid}.role`
   - `subscriptions/{uid}.status`

## Architecture decision
- iOS/Android in-app subscriptions: use platform IAP.
- Web subscriptions: Stripe checkout portal.
- Backend validates receipts/webhooks and updates Firestore role.

## Target timeline
- Week 1: console setup + product IDs + test purchases.
- Week 2: webhook/receipt validation in backend.
- Week 3: QA + store review buffer.
