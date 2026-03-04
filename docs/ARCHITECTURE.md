# Architecture Overview

## High-level
```
Flutter App (UI + State)
  -> Firebase Auth (anonymous now, social/email later)
  -> Firestore (questions, attempts, analytics, usage)
  -> Cloud Functions (askCoach, quota enforcement, billing hooks)
  -> AI Provider API (Gemini via server-side key)
```

## Client Layers
- `screens/`: presentation and user flows
- `services/`: data/network access (`question_repository`, `progress_repository`, `coach_service`)
- `models/`: domain objects (`quiz_question`, chat models)
- `core/`: theme and shared UI chrome

## Data Model (Firestore)
- `questions/{questionId}`
- `users/{uid}`
- `attempts/{uid}/sessions/{sessionId}`
- `analytics/{uid}/weakTopics/{topicId}`
- `coach_chats/{uid}/threads/{threadId}/messages/{messageId}`
- `usage/{uid}/daily/{yyyy_mm_dd}`
- `subscriptions/{uid}`

## Runtime Flow
1. App boots, initializes Firebase and signs in user anonymously.
2. Test screen loads NYC questions from Firestore (fallback: local seed data).
3. Completed test writes attempt + weak-topic analytics.
4. Dashboard computes readiness and trends from attempts.
5. Coach calls Cloud Function with Firebase ID token.
6. Cloud Function enforces daily limits and calls AI provider.

## Deployment Units
- Flutter app (mobile/web)
- Firebase Firestore rules/indexes
- Cloud Functions (Node.js 20)
