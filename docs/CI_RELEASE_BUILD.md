# CI Release Builds

The **Release Build** workflow (`.github/workflows/release-build.yml`) produces
installable artifacts in the cloud, so you don't need a local Android SDK or a
Mac. It builds a signed Android `.aab` and compile-checks iOS.

## One-time setup: add GitHub Secrets

Go to **GitHub repo → Settings → Secrets and variables → Actions → Secrets**
and add:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Base64 of your `upload-keystore.jks` (command below) |
| `ANDROID_STORE_PASSWORD` | The keystore password |
| `ANDROID_KEY_PASSWORD` | The key password (same as store password unless you set a separate one) |
| `ANDROID_KEY_ALIAS` | `upload` |

Generate the base64 of your keystore (PowerShell, from the project root):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\app\upload-keystore.jks")) | Set-Clipboard
```

That copies the base64 string to your clipboard — paste it as the
`ANDROID_KEYSTORE_BASE64` secret value.

> Without these secrets the workflow still runs but produces a **debug-signed**
> bundle (useful to test the pipeline; **not** uploadable to Play).

## Repo Variables

Set these under **Settings → Secrets and variables → Actions → Variables**
(not secrets — none of them are sensitive).

| Variable | Default | What it does |
|---|---|---|
| `ANDROID_PURCHASES_ENABLED` | `false` | Opens the Google Play storefront in the built app. **Only set this to `true` after the server has `GOOGLE_PLAY_SERVICE_ACCOUNT`** — see below. |
| `VALIDATE_RECEIPT_URL` | `…cloudfunctions.net/validateReceipt` | Receipt/purchase validation endpoint |
| `DELETE_ACCOUNT_URL` | `…cloudfunctions.net/deleteAccount` | Account deletion endpoint |
| `COACH_API_URL` | `…cloudfunctions.net/askCoach` | AI Coach endpoint |

The URL defaults use the `https://us-central1-architect-study-app.cloudfunctions.net/<name>`
form. Don't guess the `*.a.run.app` hostname — the predicted one for
`deleteAccount` turned out to be wrong, and a bad `VALIDATE_RECEIPT_URL` means
every purchase silently fails to validate: the buyer is charged and stays free.
Confirm the real URLs in the output of `firebase deploy --only functions`.

### Turning on Android purchases

The app refuses to sell on Android until `ANDROID_PURCHASES_ENABLED=true`,
because before that the server has no way to verify a Play purchase. The order
matters:

1. Deploy the functions with the Play service account set
   (`firebase functions:secrets:set GOOGLE_PLAY_SERVICE_ACCOUNT < sa.json`) —
   full steps in [MONETIZATION_PREP.md](MONETIZATION_PREP.md).
2. Buy the subscription once with a Play **license tester** account and confirm
   the user doc flips to `role: premium`.
3. *Then* set the `ANDROID_PURCHASES_ENABLED` variable to `true` and rebuild.

Doing it in the other order takes real money from real users and delivers
nothing — that exact bug is why the switch exists.

## Running it

- **Manually:** Actions tab → *Release Build* → *Run workflow*.
- **By tag:** push a version tag, e.g.
  ```powershell
  git tag v1.3.0; git push origin v1.3.0
  ```

When it finishes, download the **`app-release-aab`** artifact from the run page
and upload `app-release.aab` to the Play Console.

## iOS

The `ios` job only **compile-checks** (`--no-codesign`) — it proves the app
builds on macOS but produces no uploadable `.ipa`. A signed App Store build from
CI additionally needs Apple signing assets wired as secrets (distribution
certificate, provisioning profile, App Store Connect API key). Set those up when
you're ready to ship iOS from CI; until then, archive/upload iOS from Xcode on a
Mac.
