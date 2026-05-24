# ARE Coach — NYC ARE 5.0 Exam Prep

> A Flutter mobile app for architects preparing for the **NCARB ARE 5.0** exam, with a NYC-specific focus.

[![CI](https://github.com/Vito-bc/ARE-Coach/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/Vito-bc/ARE-Coach/actions/workflows/flutter-ci.yml)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-Firestore%20%7C%20Auth%20%7C%20Crashlytics-FFCA28?logo=firebase&logoColor=black)
![Version](https://img.shields.io/badge/version-1.3.0-brightgreen)
![License](https://img.shields.io/badge/License-Proprietary-red)

---

## What it does

ARE Coach covers every ARE 5.0 division with 500 exam-quality questions, a 300-card spaced-repetition flashcard deck, a full 65-question mock exam, an AI study coach, and a personalized dashboard that tracks your readiness over time — all with an NYC Building Code overlay for New York candidates.

---

## Screenshots

> _Add screenshots here once the app is on TestFlight / Play Store internal track._

---

## Features

| Feature | Status |
|---|---|
| Practice tests — Quick Quiz, By Division, Timed Exam | ✅ |
| **Mock Exam Mode** — 65 Qs, 130-min countdown, per-division score report | ✅ |
| 500-question NYC bank with explanations & code references | ✅ |
| **Flashcards** — 300 cards, spaced repetition (SM-2), session stats | ✅ |
| **Progress Insights** — score trend chart, accuracy by division, weak spots | ✅ |
| **Study Plan** — exam countdown + daily card & question targets on Dashboard | ✅ |
| AI Coach chat (text + voice STT/TTS) | ✅ |
| Readiness score & weak-section analytics | ✅ |
| Section trends across attempt history | ✅ |
| Attempt history with pagination | ✅ |
| NCARB Score Calculator | ✅ |
| Firebase Auth (email + anonymous) | ✅ |
| Firestore attempt persistence & weak-topic tracking | ✅ |
| Dark / light theme toggle | ✅ |
| Offline fallback (bundled JSON + Hive cache) | ✅ |
| In-app purchase paywall scaffold | ✅ |
| Push notification / study reminder scaffold | ✅ |

---

## Question Bank

**500 questions** — all with 4-option multiple choice, detailed explanations, and citations to publicly available official standards.

### By Division

| Division | Questions | ARE 5.0 Exam |
|---|---|---|
| Practice Management (PcM) | 75 | ✅ |
| Project Management (PjM) | 75 | ✅ |
| Programming & Analysis (PA) | 75 | ✅ |
| Project Planning & Design (PPD) | 75 | ✅ |
| Project Docs & Delivery (PDD) | 75 | ✅ |
| Construction & Evaluation (CE) | 75 | ✅ |
| NYC Building Codes (bonus) | 50 | NYC-specific |

### By Difficulty

| Difficulty | Count |
|---|---|
| Easy | 83 |
| Medium | 289 |
| Hard | 128 |

### Code Reference Sources

Every question cites a specific section or public source. Counts below are broad primary-reference buckets.

| Source | Questions | Public URL |
|---|---|---|
| **NCARB ARE 5.0 Guidelines** | 237 | [ncarb.org/ARE](https://www.ncarb.org/pass-the-are/are-5) |
| **AIA Contract Documents** (A101, A201, B101, C401, etc.) | 177 | [aia.org/contractdocs](https://www.aia.org/resources/64176-contract-documents) |
| **NYC Codes / DOB / Local Laws** | 57 | [nyc.gov/buildings](https://www.nyc.gov/site/buildings/codes/building-code.page) |
| **IBC 2021** | 9 | [codes.iccsafe.org](https://codes.iccsafe.org/content/IBC2021P1) |
| **ADA / Accessibility Standards** | 5 | [ada.gov/law-and-regs](https://www.ada.gov/law-and-regs/design-standards/) |
| **ASHRAE Standards** (90.1, 62.1) | 3 | [ashrae.org/standards](https://www.ashrae.org/technical-resources/bookstore/standards-62-1-62-2) |
| **Engineering / Hazard Standards** (ASCE, ACI, FEMA) | 3 | [asce.org/publications](https://www.asce.org/publications-and-news/asce-7) |
| **CSI / Specifications** | 3 | [csinet.org](https://www.csiresources.org/) |
| **Other public standards** | 6 | Varies by reference |

<details>
<summary>Sample references by division</summary>

**Practice Management**
- AIA B101-2017 §2.2 — Standard of care
- AIA B101-2017 §7.2 — Ownership of instruments of service
- AIA Code of Ethics Canon IV, Rule 4.101 — Conflict of interest
- NCARB Model Law §14; NY Education Law §7304 — Plan stamping

**Project Management**
- AIA A201-2017 §4.2.14 — Architect's authority during construction administration
- AIA A201-2017 §7.3 — Construction change directives
- AIA A201-2017 §9.8 — Substantial completion
- NCARB ARE 5.0 PjM Guidelines — Earned value, CPM scheduling

**Programming & Analysis**
- IBC 2021 Chapter 11; 2010 ADA Standards §101 — Accessibility
- FEMA FIRM; IBC 2021 §1612; ASCE 7-22 Chapter 5 — Flood zones
- ASHRAE 90.1; NCARB PA Guidelines — Energy analysis

**Project Planning & Design**
- ASHRAE 62.1-2022; IBC 2021 §1202; NYC Mechanical Code — Ventilation
- ASHRAE 90.1-2019 §6 — HVAC energy efficiency
- ASCE 7-22 Table 12.2-1; IBC 2021 Chapter 16 — Seismic design categories
- ACI 318-19 Chapter 26 — Concrete construction documents

**Project Docs & Delivery**
- 2022 NYC Building Code §1005.1 — Means of egress capacity
- 2022 NYC Building Code §903.2.8 — Sprinkler requirements
- AIA A201-2017 §3.11 — As-built documents
- CSI Project Delivery Practice Guide — Specifications format

**Construction & Evaluation**
- AIA A201-2017 §7.2; AIA G701 — Change orders
- AIA A201-2017 §4.2.2 — Site observation
- 2022 NYC Building Code §1705.2 — Special inspections
- AIA A201-2017 §15.1.4 — Dispute resolution

**NYC Building Codes**
- NYC Local Law 97 of 2019; NYC Administrative Code §28-320 — Carbon emissions
- NYC Local Law 26 of 2004; NYC Building Code §403 — High-rise fire safety
- NYC Administrative Code §28-302; Local Law 11/1998 (FISP) — Facade inspection
- NYC Zoning Resolution Article V; §52-00 — Non-conforming uses

</details>

---

## Architecture

```
lib/
├── main.dart                         Firebase + Hive bootstrap, auth stream
├── app.dart                          Root MaterialApp, theme management
├── core/
│   ├── providers.dart                Riverpod providers (auth, questions, progress, insights)
│   ├── readiness.dart                Readiness score computation
│   ├── result.dart                   Result<T,E> type
│   ├── theme/app_theme.dart
│   └── ui/app_chrome.dart            Shared glass-card widgets, backdrop
├── models/
│   ├── quiz_question.dart
│   ├── flashcard.dart
│   └── chat_message.dart
├── services/
│   ├── auth_service.dart
│   ├── coach_service.dart            HTTP → Cloud Function; local fallback
│   ├── voice_service.dart            speech_to_text + flutter_tts
│   ├── question_repository.dart      Firestore → JSON asset → seed fallback
│   ├── flashcard_repository.dart     Hive-backed SM-2 spaced repetition
│   ├── progress_repository.dart      Attempt save, weak-topic analytics, insights data
│   ├── iap_service.dart              In-app purchase + receipt validation
│   ├── notification_service.dart     Local push notification scheduling
│   └── report_repository.dart        Question flag / report pipeline
├── screens/
│   ├── home_shell.dart               Bottom-nav shell (Dashboard, Tests, Flashcards, Coach, Profile)
│   ├── dashboard_screen.dart         Readiness score, study plan, weak sections, trends
│   ├── insights_screen.dart          Score trend chart, accuracy by division, flashcard mastery
│   ├── tests_screen.dart             Quick / Section / Timed / Mock exam configuration
<<<<<<< HEAD
│   ├── _test_session_screen.dart     Live quiz session with timer
│   ├── _test_result_screen.dart      Post-quiz result (section mode)
=======
│   ├── test_session_screen.dart      Live quiz session with timer
│   ├── test_result_screen.dart       Post-quiz result (section mode)
>>>>>>> bdf72e1d673411092cab3cc4102ad3cd5cc852c7
│   ├── mock_exam_result_screen.dart  Post-mock verdict + per-division breakdown
│   ├── flashcards_screen.dart        Flashcard deck browser and stats
│   ├── flashcard_session_screen.dart Flashcard study session (flip + SM-2 rating)
│   ├── attempt_history_screen.dart   Paginated session history
│   ├── ncarb_calculator_screen.dart  NCARB scaled-score calculator
│   ├── coach_screen.dart             AI Coach chat (text + voice)
│   ├── profile_screen.dart           Settings, theme, exam date, restore purchases
│   ├── paywall_screen.dart           Premium upgrade screen
│   ├── onboarding_screen.dart
│   ├── splash_screen.dart
│   └── auth/
│       ├── login_screen.dart
│       └── register_screen.dart
├── widgets/
│   └── flag_question_sheet.dart      Question flag / report bottom sheet
└── data/
    └── seed_questions.dart           3-question emergency fallback
assets/
├── seeds/
│   ├── questions_ny.json             500-question bank
│   └── flashcards_ny.json           300-card flashcard deck
└── images/                          App icons
```

---

## Getting Started

### Prerequisites

- Flutter ≥ 3.x (`flutter --version`)
- Dart ≥ 3.x
- A Firebase project with Auth, Firestore, App Check, and Crashlytics enabled

### Run (offline / demo mode)

```bash
flutter pub get
flutter run
```

The app runs fully offline using the bundled JSON question bank. Firebase features (auth, progress sync, AI coach) are disabled until a real Firebase project is wired up.

### Run with AI Coach

```bash
flutter run --dart-define=COACH_API_URL=https://<region>-<project>.cloudfunctions.net/coach
```

---

## Firebase Setup

See [docs/FIREBASE_PHASE2.md](docs/FIREBASE_PHASE2.md) for the complete setup guide.

**Required services:**

| Service | Purpose |
|---|---|
| Firebase Auth | Email/password + anonymous sign-in |
| Firestore | Attempt history, weak-topic analytics, usage counters |
| Firebase App Check | Play Integrity / DeviceCheck / reCAPTCHA v3 |
| Firebase Crashlytics | Production error reporting |
| Cloud Functions | Secure AI Coach endpoint with daily quotas |

Firestore security rules and composite indexes are pre-configured in `firestore.rules` and `firestore.indexes.json`.

---

## Backend (AI Coach)

See [docs/PHASE4_BACKEND.md](docs/PHASE4_BACKEND.md).

- Cloud Function validates a Firebase ID token on every request
- Daily token quota enforced server-side via atomic Firestore counter
- Per-minute throttle to prevent abuse
- AI API key stored in Cloud Secret Manager — never shipped in the client

---

## Monetization

See [docs/MONETIZATION_PREP.md](docs/MONETIZATION_PREP.md).

| Tier | Price | Limits |
|---|---|---|
| Free | — | 10 questions/day, 50 AI Coach messages/day |
| Premium | $7.99/mo | Unlimited questions + priority AI responses |
| Token top-up | $2.99 | +100 AI Coach messages |

IAP via the `in_app_purchase` Flutter plugin; receipt validation is server-side.

---

## Docs

| Doc | Purpose |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design and data flow |
| [FIREBASE_PHASE2.md](docs/FIREBASE_PHASE2.md) | Firebase configuration guide |
| [PHASE4_BACKEND.md](docs/PHASE4_BACKEND.md) | Secure AI backend setup |
| [SECURITY_AUDIT.md](docs/SECURITY_AUDIT.md) | Security checklist |
| [MONETIZATION_PREP.md](docs/MONETIZATION_PREP.md) | IAP and quota design |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Branching and PR workflow |

---

## Disclaimer

Questions and explanations are AI-assisted study aids. Always verify against official NCARB ARE 5.0 exam content, current AIA contract documents, and the applicable edition of the NYC Building Code. ARE Coach is an independent study tool and is not endorsed by, sponsored by, or affiliated with NCARB, AIA, or the City of New York.
