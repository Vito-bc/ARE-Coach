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

## Optional: override the function URLs

The workflow defaults to the known deployed URLs. If your `deleteAccount` (or
receipt) function URL differs after deploy, set repo **Variables** (not secrets):

| Variable | Example |
|---|---|
| `VALIDATE_RECEIPT_URL` | `https://validatereceipt-izodv6upya-uc.a.run.app` |
| `DELETE_ACCOUNT_URL` | `https://deleteaccount-izodv6upya-uc.a.run.app` |

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
