# ARE Coach — NYC ARE 5.0 Exam Prep

A Flutter mobile app for architects preparing for the **NCARB ARE 5.0** exam, with a NYC-specific focus. Includes practice tests, an AI study coach, readiness analytics, and a 213-question bank across all six ARE divisions — each with explanations and code references to official public sources.

---

## Features

| Feature | Status |
|---|---|
| Practice tests — Quick Quiz, By Division, Timed Exam | ✅ |
| 213-question NYC bank with explanations & references | ✅ |
| AI Coach chat (text + voice STT/TTS) | ✅ |
| Readiness score & weak-section analytics | ✅ |
| Section trends across attempt history | ✅ |
| Firebase Auth (email + anonymous) | ✅ |
| Firestore attempt persistence & weak-topic tracking | ✅ |
| Dark / light theme toggle | ✅ |
| Offline fallback (bundled JSON + Hive cache) | ✅ |
| In-app purchase paywall scaffold | ✅ |

---

## Question Bank

**213 questions** — all with 4-option multiple choice, detailed explanations, and citations to publicly available official standards.

### By Division

| Division | Questions | ARE 5.0 Exam |
|---|---|---|
| Practice Management (PcM) | 50 | ✅ |
| Project Management (PjM) | 30 | ✅ |
| Programming & Analysis (PA) | 31 | ✅ |
| Project Planning & Design (PPD) | 30 | ✅ |
| Project Docs & Delivery (PDD) | 32 | ✅ |
| Construction & Evaluation (CE) | 32 | ✅ |
| NYC Building Codes (bonus) | 8 | NYC-specific |

### By Difficulty

| Difficulty | Count |
|---|---|
| Easy | 41 |
| Medium | 110 |
| Hard | 62 |

### Code Reference Sources

Every question cites a specific section of an official public standard. Sources used:

| Source | Questions | Public URL |
|---|---|---|
| **AIA Contract Documents** (A101, A201, B101, C401, etc.) | 99 | [aia.org/contractdocs](https://www.aia.org/resources/64176-contract-documents) |
| **NCARB ARE 5.0 Guidelines** | 45 | [ncarb.org/ARE](https://www.ncarb.org/pass-the-are/are-5) |
| **NYC Building Code 2022** | 30 | [nyc.gov/buildings](https://www.nyc.gov/site/buildings/codes/building-code.page) |
| **IBC 2021 (International Building Code)** | 20 | [codes.iccsafe.org](https://codes.iccsafe.org/content/IBC2021P1) |
| **ASHRAE Standards** (90.1, 62.1) | 3 | [ashrae.org/standards](https://www.ashrae.org/technical-resources/bookstore/standards-62-1-62-2) |
| **ADA Standards for Accessible Design** (2010) | 4 | [ada.gov/law-and-regs](https://www.ada.gov/law-and-regs/design-standards/) |
| **ASCE 7-22 / ASCE 24** | 1 | [asce.org/publications](https://www.asce.org/publications-and-news/asce-7) |

#### Sample references by division

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
- ASCE 24-14; FEMA NFIP — Flood-resistant construction

**Project Planning & Design (PPD)**
- ASHRAE 62.1-2022; IBC 2021 §1202; NYC Mechanical Code — Ventilation
- ASHRAE 90.1-2019 §6 — HVAC energy efficiency
- ASCE 7-22 Table 12.2-1; IBC 2021 Chapter 16 — Seismic design categories
- ACI 318-19 Chapter 26 — Concrete construction documents

**Project Docs & Delivery (PDD)**
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

---

## Architecture

```
lib/
├── main.dart               Firebase + Hive bootstrap, auth stream
├── app.dart                Root MaterialApp, theme management
├── core/
│   ├── theme/app_theme.dart
│   └── ui/app_chrome.dart  Shared glass-card widgets, backdrop
├── models/
│   ├── quiz_question.dart
│   └── chat_message.dart
├── services/
│   ├── auth_service.dart
│   ├── coach_service.dart   HTTP → Cloud Function; local fallback
│   ├── voice_service.dart   speech_to_text + flutter_tts
│   ├── question_repository.dart  Firestore → JSON asset → seed fallback
│   └── progress_repository.dart  Attempt save, weak-topic analytics
├── screens/
│   ├── dashboard_screen.dart
│   ├── tests_screen.dart
│   ├── coach_screen.dart
│   ├── profile_screen.dart
│   ├── attempt_history_screen.dart
│   ├── paywall_screen.dart
│   ├── onboarding_screen.dart
│   ├── splash_screen.dart
│   └── auth/
│       ├── login_screen.dart
│       └── register_screen.dart
└── data/seed_questions.dart  3-question emergency fallback
assets/
└── seeds/questions_ny.json  213-question bank
```

---

## Run

```bash
flutter pub get
flutter run
```

With AI Coach connected:
```bash
flutter run --dart-define=COACH_API_URL=https://<region>-<project>.cloudfunctions.net/coach
```

---

## Firebase Setup

Follow [docs/FIREBASE_PHASE2.md](docs/FIREBASE_PHASE2.md) for full setup.

Required services:
- **Firebase Auth** — email/password + anonymous
- **Firestore** — attempts, analytics, usage collections
- **Firebase App Check** — Play Integrity / DeviceCheck / reCAPTCHA v3
- **Cloud Functions** — secure AI coach endpoint with daily quotas

Firestore rules and indexes are pre-configured in `firestore.rules` and `firestore.indexes.json`.

---

## Backend (AI Coach)

See [docs/PHASE4_BACKEND.md](docs/PHASE4_BACKEND.md).

- Cloud Function validates Firebase ID token on every request
- Daily token quota enforced server-side (atomic Firestore counter)
- Per-minute throttle to prevent abuse
- AI API key stored in Cloud Secret Manager — never in client

---

## Monetization

See [docs/MONETIZATION_PREP.md](docs/MONETIZATION_PREP.md).

- Free tier: 10 questions/day, 50 AI coach messages/day
- Premium ($7.99/mo): unlimited questions + priority AI responses
- Token top-up: 100 extra coach messages ($2.99)
- IAP via `in_app_purchase` Flutter plugin; receipt validation server-side

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

Questions and explanations are AI-assisted study aids. Always verify against official NCARB ARE 5.0 exam content, current AIA contract documents, and the applicable edition of the NYC Building Code. This app is not affiliated with NCARB, AIA, or the City of New York.
