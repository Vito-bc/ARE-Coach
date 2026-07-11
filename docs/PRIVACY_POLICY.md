<!--
  TEMPLATE — NOT LEGAL ADVICE.
  This draft is generated from the app's actual data flows (verified against
  the codebase on 2026-06-02) to save you work, but it is a starting point,
  not a substitute for review by a qualified attorney. Before publishing:
    1. Fill every {{PLACEHOLDER}}.
    2. Have counsel review it (especially if you target EU/UK users → GDPR,
       California → CCPA/CPRA, or minors).
    3. Host it at a public URL and link that URL in both App Store Connect
       and Google Play Console (both stores require a reachable policy URL).
-->

# Privacy Policy — ARE Coach

**Effective date:** {{EFFECTIVE_DATE}}
**Provided by:** {{COMPANY_OR_DEVELOPER_NAME}} ("we", "us", "our")
**Contact:** {{CONTACT_EMAIL}}

ARE Coach ("the App") helps architects prepare for the NCARB ARE 5.0 exam.
This policy explains what data the App collects, how it is used, who it is
shared with, and the choices you have.

---

## 1. Information we collect

### 1.1 Account information
- **Email/password sign-in:** your email address.
- **Sign in with Apple:** an Apple-provided user identifier and, if you allow
  it, your name and an email address (which may be Apple's private relay
  address). We never receive your Apple password.
- **Anonymous use:** you may use the App without creating an account. In that
  case we generate a random anonymous identifier and do **not** collect your
  email or name.

### 1.2 Profile information
- Your display name and target exam date, if you choose to provide them.

### 1.3 Study activity
- Quiz and mock-exam attempts: questions seen, answers selected, scores,
  time spent, and per-division accuracy ("weak topic") analytics.
- Flashcard progress and study-streak data.

### 1.4 AI Coach content
- When you use the AI Coach, the text you type (your prompt) is sent to
  **Anthropic's Claude API** to generate a response. Your prompts and the
  generated answers are stored in your account so your chat history persists.
- If you use **voice input**, your device's speech-recognition service
  (provided by Apple or Google, depending on your device) converts your
  speech to text; that text is then used as your Coach prompt. Audio handling
  is governed by your device platform's privacy policy.

### 1.5 Purchases
- If you buy a subscription or token pack, the purchase is processed by the
  **Apple App Store** or **Google Play**. We receive the purchase/subscription
  status and a receipt, which we validate on our server to unlock premium
  features. We do **not** receive or store your full payment card details.

### 1.6 Diagnostics and security
- **Crash and error reports** (via Firebase Crashlytics): crash stack traces,
  device model, operating-system version, and app version, used to diagnose
  and fix bugs.
- **Abuse prevention** (via Firebase App Check): a device-integrity
  attestation token used to confirm requests come from a genuine instance of
  the App.
- **Usage metadata:** daily and per-minute request counts and AI token counts,
  used to enforce free-tier limits and prevent abuse. (Message content is not
  included in these operational logs.)

### 1.7 Stored only on your device
- App settings, flashcard progress, and your study-reminder time are stored
  locally on your device (via Hive) and are not transmitted to us.
- Study reminders use **local notifications** scheduled on your device. The
  App does not use push notifications and does not collect a push token.

### 1.8 What we do NOT collect
- We do **not** collect your precise or coarse location.
- We do **not** use advertising or third-party analytics/tracking SDKs, and we
  do **not** collect an advertising identifier.
- We do **not** access your contacts, photos, or files.

---

## 2. How we use your information
- Provide and operate the App (accounts, sign-in, saving your progress).
- Generate AI Coach responses to your questions.
- Process and validate purchases and unlock premium features.
- Enforce free-tier usage limits and prevent abuse.
- Diagnose crashes and improve reliability and quality.

We do **not** sell your personal information, and we do **not** use it for
third-party advertising.

---

## 3. Who we share information with (sub-processors)
We share data only with service providers that help us run the App:

| Provider | Purpose | Data involved |
|---|---|---|
| **Google Firebase** (Authentication, Cloud Firestore, Crashlytics, App Check) | Accounts, data storage, crash diagnostics, abuse prevention | Account ID/email, study data, Coach history, diagnostics |
| **Anthropic** (Claude API) | Generate AI Coach answers | The prompt text you send to the Coach |
| **Apple** | Sign in with Apple, App Store purchases, on-device speech recognition | Apple user ID, purchase receipts, voice→text |
| **Google Play** | Purchases, on-device speech recognition | Purchase receipts, voice→text |

These providers process data under their own privacy policies and our
agreements with them. We do not authorize them to use your data for their own
unrelated purposes.

---

## 4. Data retention
- Account, profile, study, and Coach data are retained while your account is
  active.
- You may request deletion of your account and associated data (see Section 6).
- Diagnostic data is retained per the service provider's standard retention
  period.

---

## 5. Children's privacy
The App is intended for adult exam candidates and is **not** directed to
children under {{MINIMUM_AGE — e.g., 13/16}}. We do not knowingly collect data
from children. If you believe a child has provided us data, contact us and we
will delete it.

---

## 6. Your choices and rights
- **Access / deletion:** request a copy or deletion of your data by emailing
  {{CONTACT_EMAIL}}. {{Describe any in-app delete-account control if present.}}
- **Use anonymously:** you can use the App without providing your email or name.
- **Voice input:** optional — you can type instead of using the microphone.
- Depending on your location, you may have additional rights (e.g., under
  **GDPR/UK GDPR** or **CCPA/CPRA**). {{Add jurisdiction-specific rights and
  your legal basis for processing after counsel review.}}

---

## 7. Data security
We use industry-standard measures including encrypted transport (HTTPS),
server-side receipt validation, App Check attestation, and access-controlled
database security rules. No method of transmission or storage is 100% secure,
but we work to protect your information.

---

## 8. International transfers
Our service providers (including Google and Apple) may process data on servers
located in the United States and other countries. {{Add transfer-mechanism
language (e.g., Standard Contractual Clauses) if you serve EU/UK users.}}

---

## 9. Changes to this policy
We may update this policy from time to time. Material changes will be reflected
by updating the "Effective date" above and, where appropriate, an in-app notice.

---

## 10. Contact
Questions or requests: **{{CONTACT_EMAIL}}**
{{COMPANY_OR_DEVELOPER_NAME}}
{{OPTIONAL_MAILING_ADDRESS}}

---

> This App is an independent study aid and is not affiliated with, endorsed by,
> or sponsored by NCARB, the AIA, Apple, Google, or the City of New York.
