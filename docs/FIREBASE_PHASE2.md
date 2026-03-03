# Firebase Phase 2 Setup

## 1) Configure Firebase app
1. Create Firebase project (for example: `are-coach-nyc`).
2. Enable Authentication -> `Anonymous` (for MVP bootstrap).
3. Add Android/iOS/Web apps in Firebase console.
4. Run:
   - `dart pub global activate flutterfire_cli`
   - `flutterfire configure`
5. Commit generated `lib/firebase_options.dart`.

## 2) Deploy Firestore rules and indexes
1. Install Firebase CLI:
   - `npm install -g firebase-tools`
2. Login:
   - `firebase login`
3. In project root:
   - `firebase use <your_project_id>`
   - `firebase deploy --only firestore:rules`
   - `firebase deploy --only firestore:indexes`

## 3) Collections used in app
- `questions/{questionId}`
- `users/{uid}`
- `attempts/{uid}/sessions/{sessionId}`
- `analytics/{uid}/weakTopics/{topicId}`
- `coach_chats/{uid}/threads/{threadId}/messages/{messageId}`
- `usage/{uid}/daily/{yyyy_mm_dd}`
- `subscriptions/{uid}`

## 4) Import NYC seed questions
Option A (Console):
1. Open `assets/seeds/questions_ny.json`.
2. Create docs manually in `questions` collection.

Option B (extension/script later):
1. Use Admin SDK script or Cloud Function to batch write JSON into `questions`.
2. Keep `state = "NY"` for MVP filtering.

## 5) Runtime behavior in app
- If Firebase is configured and available:
  - App signs user in anonymously.
  - Tests screen loads from Firestore `questions` where `state == NY`.
- If Firebase is missing/unavailable:
  - App falls back to local seed questions.
