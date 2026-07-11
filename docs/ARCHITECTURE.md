# Architecture Overview

## High-level
```
Flutter App (UI + State)
  -> Firebase Auth (anonymous, email/password, Apple)
  -> Bundled JSON assets (1,100 questions, 300 flashcards)
  -> Hive (flashcard progress, reminder/exam-date preferences)
  -> Firestore (questions, attempts, analytics, usage)
  -> Cloud Functions (askCoach, quota enforcement, billing hooks)
  -> Anthropic Claude API (server-side key) + RAG retrieval over the ARE source corpus
```

## Client Layers
- `screens/`: presentation and user flows
- `services/`: data/network access (`question_repository`, `flashcard_repository`, `progress_repository`, `coach_service`)
- `models/`: domain objects (`quiz_question`, `flashcard`, chat models)
- `core/`: theme and shared UI chrome

## Data Model (Firestore)
- `questions/{questionId}`
- `users/{uid}`
- `attempts/{uid}/sessions/{sessionId}`
- `analytics/{uid}/weakTopics/{topicId}`
- `coach_chats/{uid}/threads/{threadId}/messages/{messageId}`
- `usage/{uid}/daily/{yyyy_mm_dd}`
- `usage/{uid}/minute/{yyyyMMdd_HHmm}`
- `subscriptions/{uid}`
- `reports/{reportId}`

## Runtime Flow
1. App boots, initializes Hive, notifications, Firebase, App Check, and auth state.
2. Test screen loads the bundled NYC question bank through `allQuestionsProvider`.
3. Completed test writes attempt + weak-topic analytics.
4. Dashboard computes readiness and trends from attempts.
5. Flashcards load from bundled JSON and store spaced-repetition progress in Hive.
6. Coach calls Cloud Function with Firebase ID token and App Check token.
7. Cloud Function enforces daily/per-minute limits and calls AI provider.

## Deployment Units
- Flutter app (mobile/web)
- Firebase Firestore rules/indexes
- Cloud Functions (Node.js 22)
