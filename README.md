# ARE Coach — NYC ARE 5.0 Exam Prep

> Flutter mobile app for architects preparing for **NCARB ARE 5.0** — 1,082 questions, 300 flashcards, mock exam, AI coach, and progress analytics with an NYC Building Code focus.

[![CI](https://github.com/Vito-bc/ARE-Coach/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/Vito-bc/ARE-Coach/actions/workflows/flutter-ci.yml)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-Auth%20%7C%20Firestore%20%7C%20Crashlytics-FFCA28?logo=firebase&logoColor=black)
![Version](https://img.shields.io/badge/version-1.3.0-brightgreen)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey)

---

## Screenshots

> _Screenshots coming once the app is on TestFlight / Play Store internal track._
> See the [Getting Started](#getting-started) section to run it locally now.

---

## Features

| Feature | Status |
|---|---|
| **1,082-question bank** — 6 ARE divisions + NYC codes, with explanations & NCARB topic tags | ✅ |
| **Mock Exam Mode** — 65 Qs, 130-min countdown, per-division score report | ✅ |
| Practice tests — Quick Quiz, By Division, Timed session | ✅ |
| **Flashcards** — 300 cards, basic review scheduling, exam tips | ✅ |
| **Progress Insights** — score trend chart, accuracy by division, weak spots | ✅ |
| **Study Plan** — exam countdown, daily card & question targets | ✅ |
| **AI Coach** — chat + voice (STT / TTS); Claude, grounded by RAG in the real code corpus and required to cite only sections it can actually see | ✅ |
| **Daily study reminder** — time-picker, persisted, rescheduled on change | ✅ |
| Readiness score & section trend analytics | ✅ |
| Attempt history with pagination | ✅ |
| NCARB scaled-score calculator | ✅ |
| Firebase Auth — email/password + anonymous | ✅ |
| Firestore attempt persistence & weak-topic tracking | ✅ |
| Offline fallback — bundled JSON + Hive cache | ✅ |
| Dark theme | ✅ |
| In-app purchase paywall (premium + token top-up) | ✅ |
| Question flag / report pipeline | ✅ |

---

## Question Bank

**1,082 questions** — 4-option MCQ, detailed explanations, citations to official standards, and NCARB-aligned topic tags for sub-division analytics.

### By Division

| Division | Code | Questions |
|---|---|---|
| Practice Management | PcM | 161 |
| Project Management | PjM | 165 |
| Programming & Analysis | PA | 165 |
| Project Planning & Design | PPD | 165 |
| Project Docs & Delivery | PDD | 165 |
| Construction & Evaluation | CE | 165 |
| NYC Building Codes | NYC | 114 |
| **Total** | | **1,082** |

### By Difficulty

| Level | Count | Share |
|---|---|---|
| Easy | 248 | 23% |
| Medium | 538 | 49% |
| Hard | 314 | 29% |

### examWeight

`examWeight` is a 1-20 relative topic-priority score used as metadata for future weighted study selection, mock-exam balancing, and weak-area analytics. It is not a point value, not a scoring percentage, and not an NCARB-published weight. Higher values mean the question covers a more exam-critical, high-yield, or code/contract-risk-heavy concept.

### Reference Sources

Many questions cite more than one source, so the counts below overlap and sum to more than 1,082.

| Source | Qs | Link |
|---|---|---|
| NCARB ARE 5.0 Guidelines | 859 | [ncarb.org/ARE](https://www.ncarb.org/pass-the-are/are-5) |
| AIA Contract Documents (A101, A201, B101, C401…) | 394 | [aia.org](https://www.aia.org/resources/64176-contract-documents) |
| NYC Building Code / DOB / Zoning / Local Laws | 147 | [nyc.gov/buildings](https://www.nyc.gov/site/buildings/codes/building-code.page) |
| IBC (2021; NYC-amended 2015) | 98 | [codes.iccsafe.org](https://codes.iccsafe.org/content/IBC2021P1) |
| ASHRAE 90.1 / 62.1 / 55 | 61 | [ashrae.org](https://www.ashrae.org/technical-resources/bookstore/standards-62-1-62-2) |
| CSI MasterFormat / Specifications | 48 | [csiresources.org](https://www.csiresources.org/) |
| ASCE 7-22 / ACI / FEMA | 36 | [asce.org](https://www.asce.org/publications-and-news/asce-7) |
| ADA Standards for Accessible Design 2010 | 18 | [ada.gov](https://www.ada.gov/law-and-regs/design-standards/) |
| NFPA 13 / 70 / 110 | 9 | [nfpa.org](https://www.nfpa.org/codes-and-standards) |

<details>
<summary>Sample questions by division</summary>

**Practice Management (PcM)**
- AIA B101-2017 §2.2 — Standard of care and professional liability
- AIA Code of Ethics Canon IV, Rule 4.101 — Conflict of interest disclosure
- NCARB Model Law §14; NY Education Law §7304 — Stamping plans in NY

**Project Management (PjM)**
- AIA A201-2017 §4.2.14 — Architect's authority during construction administration
- AIA A201-2017 §7.3 — Construction change directives vs. change orders
- AIA A201-2017 §9.8 — Substantial completion and punch lists

**Programming & Analysis (PA)**
- IBC 2021 Chapter 11; 2010 ADA §101 — Accessible route requirements
- FEMA FIRM; IBC 2021 §1612; ASCE 7-22 Ch.5 — Flood hazard areas
- ASHRAE 90.1 — Energy use intensity benchmarks

**Project Planning & Design (PPD)**
- ASHRAE 62.1-2022; IBC 2021 §1202 — Minimum ventilation rates
- ASCE 7-22 Table 12.2-1; IBC 2021 Ch.16 — Seismic design categories
- ACI 318-19 Ch.26 — Concrete mix design documentation

**Project Docs & Delivery (PDD)**
- NYC Building Code 2022 §1005.1 — Means of egress width calculations
- NYC Building Code 2022 §903.2.8 — Automatic sprinkler requirements
- CSI Project Delivery Practice Guide — Division 01 general requirements

**Construction & Evaluation (CE)**
- AIA A201-2017 §7.2 + AIA G701 — Change order execution
- NYC Building Code 2022 §1705.2 — Special inspection programs
- AIA A201-2017 §15.1.4 — Claim and dispute resolution sequence

**NYC Building Codes**
- NYC Local Law 97 (2019) — Carbon emissions limits for large buildings
- NYC Local Law 11/1998 (FISP) — Facade inspection safety program cycles
- NYC Zoning Resolution §52-00 — Non-conforming uses and lot coverage

</details>

---

## Flashcard Deck

**300 cards** — front/back format, exam tip on every card, basic review scheduling (fresh / learning / mastered, with mastered cards resurfacing after 7 days). Not a full SM-2 implementation.

| Division | Cards |
|---|---|
| Project Planning & Design | 50 |
| Practice Management | 45 |
| Project Management | 45 |
| Programming & Analysis | 45 |
| NYC Building Codes | 45 |
| Project Docs & Delivery | 35 |
| Construction & Evaluation | 35 |
| **Total** | **300** |

---

## Architecture

```
are_coach/
├── lib/
│   ├── main.dart                         Firebase + Hive bootstrap, auth stream
│   ├── app.dart                          Root MaterialApp, theme management
│   ├── core/
│   │   ├── providers.dart                Riverpod providers (auth, questions, progress, insights)
│   │   ├── readiness.dart                Readiness score computation
│   │   ├── result.dart                   Result<T, E> type
│   │   ├── theme/app_theme.dart          Design tokens — colors, typography
│   │   └── ui/app_chrome.dart            Shared glass-card widgets
│   ├── models/
│   │   ├── quiz_question.dart
│   │   ├── flashcard.dart
│   │   └── chat_message.dart
│   ├── services/
│   │   ├── auth_service.dart
│   │   ├── coach_service.dart            HTTP → Cloud Function with local fallback
│   │   ├── voice_service.dart            speech_to_text + flutter_tts
│   │   ├── question_repository.dart      Firestore → JSON asset → seed fallback chain
│   │   ├── flashcard_repository.dart     Hive-backed review scheduling
│   │   ├── progress_repository.dart      Attempt save, weak-topic analytics, insights
│   │   ├── iap_service.dart              In-app purchase + server-side receipt validation
│   │   ├── notification_service.dart     Daily reminder — schedule, persist, cancel
│   │   └── report_repository.dart        Question flag / report pipeline
│   ├── screens/
│   │   ├── home_shell.dart               Bottom-nav shell (5 tabs)
│   │   ├── dashboard_screen.dart         Readiness score, study plan, weak sections, trends
│   │   ├── insights_screen.dart          Score trend chart, accuracy by division, flashcard mastery
│   │   ├── tests_screen.dart             Quick / Section / Timed / Mock exam config
│   │   ├── test_session_screen.dart      Live quiz session with timer
│   │   ├── test_result_screen.dart       Post-quiz result (section / timed mode)
│   │   ├── mock_exam_result_screen.dart  Post-mock verdict + per-division breakdown
│   │   ├── flashcards_screen.dart        Flashcard deck browser and stats
│   │   ├── flashcard_session_screen.dart Flashcard study session (flip + rating)
│   │   ├── attempt_history_screen.dart   Paginated session history
│   │   ├── ncarb_calculator_screen.dart  NCARB scaled-score calculator
│   │   ├── coach_screen.dart             AI Coach chat (text + voice)
│   │   ├── profile_screen.dart           Settings, theme, exam date, reminder, purchases
│   │   ├── paywall_screen.dart           Premium upgrade screen
│   │   ├── onboarding_screen.dart
│   │   ├── splash_screen.dart
│   │   └── auth/
│   │       ├── login_screen.dart
│   │       └── register_screen.dart
│   ├── widgets/
│   │   └── flag_question_sheet.dart      Question flag bottom sheet
│   └── data/
│       └── seed_questions.dart           3-question emergency fallback
├── assets/
│   ├── seeds/
│   │   ├── questions_ny.json             1,082-question bank
│   │   └── flashcards_ny.json           300-card flashcard deck
│   └── images/                          App icons
├── functions/                           Firebase Cloud Functions (AI Coach, quota)
├── firestore.rules                      Firestore security rules
├── firestore.indexes.json
└── docs/
    ├── ARCHITECTURE.md
    ├── FIREBASE_PHASE2.md
    ├── PHASE4_BACKEND.md
    ├── SECURITY_AUDIT.md
    └── MONETIZATION_PREP.md
```

---

## Getting Started

### Prerequisites

| Tool | Version |
|---|---|
| Flutter | ≥ 3.x (`flutter --version`) |
| Dart | ≥ 3.x |
| Android Studio or Xcode | for emulator / simulator |
| Firebase CLI | `npm install -g firebase-tools` |

### Run in offline / demo mode

No Firebase project required. The app loads the bundled 1,082-question JSON bank.

```bash
flutter pub get
flutter run
```

### Run with full Firebase features

```bash
# 1. Add your GoogleService-Info.plist (iOS) and google-services.json (Android)
# 2. Deploy Firestore rules
firebase deploy --only firestore:rules,firestore:indexes

# 3. Build the Coach's retrieval index (once; needs the RAG corpus present)
cd tools/question_audit && python -m src.build_coach_index && cd ../..

# 4. Set the model key and deploy the function
firebase functions:secrets:set ANTHROPIC_API_KEY
firebase deploy --only functions

# 5. Run with the AI Coach endpoint
flutter run --dart-define=COACH_API_URL=https://<region>-<project>.cloudfunctions.net/askCoach
```

---

## Firebase Setup

Full guide → [docs/FIREBASE_PHASE2.md](docs/FIREBASE_PHASE2.md)

| Service | Purpose |
|---|---|
| Firebase Auth | Email/password + anonymous sign-in |
| Firestore | Attempt history, weak-topic analytics, usage counters |
| Firebase App Check | Play Integrity / DeviceCheck anti-abuse |
| Firebase Crashlytics | Production error reporting |
| Cloud Functions | Secure AI Coach — Claude + RAG grounding, token-quota + per-minute throttle |

---

## Backend & Security

Full guide → [docs/PHASE4_BACKEND.md](docs/PHASE4_BACKEND.md) · [docs/SECURITY_AUDIT.md](docs/SECURITY_AUDIT.md)

- Firebase ID token validated on every Cloud Function request
- Daily AI quota enforced server-side via atomic Firestore counter
- AI API key stored in Cloud Secret Manager — never in the client bundle
- Firestore rules deny all client writes except the user's own data
- App Check blocks non-genuine clients (emulators, proxies)

---

## Monetization

Full guide → [docs/MONETIZATION_PREP.md](docs/MONETIZATION_PREP.md)

| Tier | Price | Includes |
|---|---|---|
| Free | — | 10 questions/day · 50 AI messages/day |
| Premium | $9.99 / month | Unlimited questions · priority AI |
| Token top-up | $2.99 | +100 AI Coach messages |

IAP via `in_app_purchase` Flutter plugin. Receipt validation is server-side.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full branching and PR workflow.

**Quick rules:**
- No direct commits to `main` — all changes via PR
- `flutter analyze` must return 0 issues before merge
- `flutter test` must pass
- No secrets in the repo

---

## Docs

| File | Purpose |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design and data flow |
| [FIREBASE_PHASE2.md](docs/FIREBASE_PHASE2.md) | Firebase configuration guide |
| [PHASE4_BACKEND.md](docs/PHASE4_BACKEND.md) | Secure AI backend setup |
| [SECURITY_AUDIT.md](docs/SECURITY_AUDIT.md) | Security checklist and findings |
| [MONETIZATION_PREP.md](docs/MONETIZATION_PREP.md) | IAP and quota design |
| [CODE_REVIEW.md](docs/CODE_REVIEW.md) | Architecture review notes |

---

## Disclaimer

Questions and explanations are AI-assisted study aids. Always verify against official NCARB ARE 5.0 exam content outlines, current AIA contract documents, and the applicable edition of the NYC Building Code. This app is not affiliated with NCARB, AIA, or the City of New York.
