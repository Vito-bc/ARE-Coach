<!--
  Store data-disclosure mapping, derived from the App's actual SDKs and data
  flows (verified against the codebase on 2026-06-02). Use this to fill:
    - Google Play Console → App content → Data safety
    - App Store Connect → App Privacy
  Re-verify before each submission; answers must match real behavior.
-->

# Store Data-Disclosure Mapping — ARE Coach

This translates the App's real data flows into the answers each store's
privacy questionnaire expects. Source SDKs: Firebase Auth, Cloud Firestore,
Crashlytics, App Check; Sign in with Apple; in_app_purchase; speech_to_text;
Google Gemini API (server-side, AI Coach). **No analytics SDK, no ads SDK, no
advertising identifier, no location, no push messaging.**

---

## Key cross-store facts
- **Tracking / advertising:** NONE. The App contains no ad networks and no
  third-party analytics/tracking SDK, and collects no advertising ID.
  → Apple: *"Data is not used to track you."*
  → Play: *No data shared for advertising/marketing; not used for tracking.*
- **AI Coach content:** the text a user sends to the Coach is transmitted to
  **Google's Gemini API** (a third-party processor) and stored in Firestore.
  Declare this as collecting **user-generated content**, shared with a service
  provider for app functionality.
- **Voice input:** speech-to-text runs through the **device platform's**
  recognizer (Apple/Google). The App does not upload raw audio to our servers;
  only the resulting text (used as a Coach prompt). See "Audio" note below.
- **Purchases:** handled by Apple/Google billing; we receive purchase status +
  receipt, not card numbers.
- **Linkage:** most data is linked to a user/account ID (when signed in).
  Anonymous users have a random ID and no email/name.

---

## Google Play — Data safety form

For each type: **Collected** (sent off device), **Shared** (to a third party),
purpose, and whether it is required.

| Data type (Play category) | Collected | Shared | Purpose | Required? |
|---|---|---|---|---|
| **Email address** (Personal info) | Yes | No¹ | Account management | Optional² |
| **Name** (Personal info) | Yes | No¹ | Account management, personalization | Optional |
| **User IDs** (Personal info) | Yes | No¹ | Account management, app functionality | Yes |
| **Purchase history** (Financial info) | Yes | No¹ | App functionality (premium unlock) | Optional |
| **App interactions** (App activity) | Yes | No¹ | App functionality, analytics-of-progress | Optional |
| **Other user-generated content** (Coach prompts, question reports) | Yes | **Yes³** | App functionality (AI responses, moderation) | Optional |
| **Crash logs** (App info & performance) | Yes | No¹ | Diagnostics / stability | Yes |
| **Diagnostics** (App info & performance) | Yes | No¹ | Diagnostics / stability | Yes |

¹ "No" = not shared with a third party for their own use. Google Firebase acts
   as our **processor/service provider**, which Play does not count as
   "sharing." Confirm this characterization against current Play definitions.
² "Required?" = whether the user can use the App without providing it. Email is
   optional because anonymous use is supported.
³ **Shared = Yes** specifically because Coach prompt text is sent to the Google
   Gemini API to generate a response. Disclose the data-handling purpose as
   "app functionality."

**Security practices to check in the form:**
- Data encrypted in transit: **Yes** (HTTPS).
- Users can request data deletion: **Yes** — provide the deletion path
  ({{in-app control and/or {{CONTACT_EMAIL}}}}).

**Audio note:** If the form asks about "Voice or sound recordings," answer
based on actual behavior: raw audio is processed by the on-device/platform
speech recognizer and is **not collected by us**; only transcribed text is
sent (as user content). If you ever record/upload audio yourself, you must
update this.

---

## Apple App Store — App Privacy

Apple groups answers as **Data Used to Track You**, **Data Linked to You**, and
**Data Not Linked to You**.

### Data Used to Track You
- **None.** (No ads/tracking SDK, no advertising identifier, no cross-app/site
  tracking.)

### Data Linked to You (signed-in users)
| Apple data type | Why | Purpose |
|---|---|---|
| Email Address | Auth (email or Apple relay) | App Functionality |
| Name | Optional profile | App Functionality |
| User ID | Account identifier | App Functionality |
| Purchases | Subscription/token status | App Functionality |
| User Content (Coach messages, reports) | AI Coach + moderation | App Functionality |
| Product Interaction / Usage Data | Study activity, limits | App Functionality |
| Crash Data | Crashlytics | App Functionality / Diagnostics² |
| Performance Data | Crashlytics | Diagnostics |

² Apple lists Crash/Performance under "App Functionality" or "Diagnostics" —
  pick "Diagnostics." Crashlytics data can be associated with the user ID, so
  list these as **Linked**.

### Data Not Linked to You
- For **anonymous users**, the same study/diagnostic data is tied only to a
  random ID with no email/name. If you want to reflect this, you may declare
  the diagnostic/usage categories as "Not Linked" for the anonymous path — but
  the simplest, safe approach is to declare them **Linked** (covers both cases).

### Third-party processors to mention in your privacy answers/policy
- Google (Firebase + Gemini API), Apple (Sign in with Apple, billing, speech).

---

## Pre-submission checklist
- [ ] Privacy Policy hosted at a public URL; URL added in **both** stores.
- [ ] Play Data safety form completed per table above.
- [ ] Apple App Privacy completed per tables above; "Not used to track."
- [ ] Account-deletion path documented (Apple requires in-app account deletion
      for apps that support account creation).
- [ ] IAP products created + approved in App Store Connect and Play Console.
- [ ] Age rating questionnaires completed.
- [ ] Confirm the AI Coach (Gemini) disclosure appears in the privacy policy.
