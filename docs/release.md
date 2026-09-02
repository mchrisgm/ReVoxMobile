# Releasing to TestFlight

This guide is for the repository owner. It explains what the TestFlight workflow does, the one-time Apple setup, the GitHub secrets it needs, the two signing paths, what happens before the secrets exist, what to do in App Store Connect after an upload, and how to fix the usual failures.

## What the workflow does

[`.github/workflows/testflight.yml`](../.github/workflows/testflight.yml) runs on every push to `main`, and on demand from the **Actions** tab (**TestFlight** → **Run workflow**, where you can also choose the signing path). Two jobs:

1. **`preflight`** (Linux, seconds): checks that the four App Store Connect secrets exist. If any is missing it prints a notice and the `upload` job is skipped (see [Before the secrets exist](#before-the-secrets-exist)).
2. **`upload`** (macOS runner `macos-26`, Xcode 26.6 selected by `scripts/ci/select-xcode.sh`, up to 90 minutes), step by step:
   1. **Generate**: `brew install xcodegen xcbeautify`, then `xcodegen generate` writes `ReVoxMobile.xcodeproj` from `project.yml`.
   2. **Resolve packages**: `xcodebuild -resolvePackageDependencies` into `.spm/`, cached between runs by the hash of `project.yml`.
   3. **Test**: `xcodebuild test` with the `ReVoxMobile` scheme on the newest available iPhone simulator (`scripts/ci/pick-simulator.sh`). A failing test stops the workflow before anything is signed or uploaded.
   4. **Write the API key**: `ASC_KEY_P8` is decoded to `~/private_keys/AuthKey_<ASC_KEY_ID>.p8`.
   5. **Import signing material** (manual signing only): the distribution certificate goes into a temporary keychain and the two provisioning profiles are installed; their names are exported as `REVOX_PROFILE_APP` and `REVOX_PROFILE_EXTENSION`.
   6. **Archive**: `xcodebuild archive` (Release, `generic/platform=iOS`) to `build/ReVoxMobile.xcarchive`, with `DEVELOPMENT_TEAM=$APPLE_TEAM_ID`, `REVOX_BUNDLE_PREFIX` and the build number passed in as build settings.
   7. **Export**: `ci/ExportOptions.plist` is copied to `ci/ExportOptions.generated.plist`, the team id (and, for manual signing, the certificate and the two profiles) are filled in, then `xcodebuild -exportArchive` writes the `.ipa` to `build/export/`.
   8. **Upload**: `xcrun altool --upload-app` sends the `.ipa` to App Store Connect using the API key.
   9. **Keep the artefacts**: the `.ipa` and the test, archive and export logs are attached to the run as `revox-mobile-build-<run number>` for 14 days, even when a step failed.
   10. **Clean up**: the API key, the generated export options and the temporary keychain are removed.

Version numbers:

- **Build number** (`CFBundleVersion`) = `github.run_number`, passed as `CURRENT_PROJECT_VERSION`. Every new run gets a higher number, so a new run never collides with an earlier upload. Re-running an existing run (**Re-run jobs** / **Re-run failed jobs**) reuses that run's number: if its upload step had already succeeded, App Store Connect rejects the second upload as a duplicate (ITMS-90189, redundant binary). To upload again, start a new run (push to `main`, or **Actions** → **Run workflow**) instead of re-running the old one. `manageAppVersionAndBuildNumber` is `false` in `ci/ExportOptions.plist`, so App Store Connect does not renumber it.
- **Marketing version** (`CFBundleShortVersionString`) = `MARKETING_VERSION` in `project.yml` (currently `0.1.0`). Change it there when you start a new version; TestFlight groups builds by this number.

Only one TestFlight run executes at a time (`concurrency: testflight`); further pushes wait rather than cancelling a running upload.

## One-time Apple setup

You need a paid Apple Developer Program membership. Then, in this order:

1. **App Group.** In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list/applicationGroup) create an App Group with identifier `group.com.mchrisgm.revox` (or `group.<your prefix>.revox` if you use a different `REVOX_BUNDLE_PREFIX`). The app and the broadcast extension use it to share audio and settings.
2. **Two App IDs with the App Groups capability.** Under **Identifiers** register two explicit App IDs:
   - `com.mchrisgm.revox` for the app;
   - `com.mchrisgm.revox.broadcast` for the broadcast extension.

   On each one enable the **App Groups** capability and assign the group from step 1. Nothing else is required at this milestone (no push, no iCloud).
3. **Team ID.** Copy the 10-character Team ID from [Membership details](https://developer.apple.com/account#MembershipDetailsCard). It becomes the `APPLE_TEAM_ID` secret.
4. **Agreements.** In App Store Connect open **Business** (or **Agreements, Tax, and Banking**) and make sure the Apple Developer Program License Agreement is accepted by the Account Holder. Uploads fail until it is, every time Apple issues a new version of the agreement.
5. **App Store Connect API key with the App Manager role.** In App Store Connect go to **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys** and generate a key with access **App Manager**. Download the `AuthKey_XXXX.p8` file immediately (it can be downloaded only once) and note the **Key ID** and the **Issuer ID** shown on that page. App Manager is the lowest role that can both create signing assets and upload builds.
6. **App record.** In **My Apps** click **+** → **New App**: platform iOS, name `ReVox`, primary language English, Bundle ID `com.mchrisgm.revox` (the app id, not the extension's), SKU `revox-mobile`, full user access. The extension does not get its own app record.

## GitHub configuration

Add these under **Settings** → **Secrets and variables** → **Actions** → **Secrets** (repository secrets). The names must match exactly.

| Secret | Value |
|--------|-------|
| `ASC_KEY_ID` | The Key ID of the App Store Connect API key (10 characters). |
| `ASC_ISSUER_ID` | The Issuer ID shown above the key list (a UUID). |
| `ASC_KEY_P8` | The `.p8` file, base64-encoded as a single line. See the command below. |
| `APPLE_TEAM_ID` | Your 10-character Team ID. |

To produce the value of `ASC_KEY_P8` on macOS (this copies it to the clipboard, ready to paste into the secret):

```bash
base64 -i AuthKey_XXXX.p8 | pbcopy
```

On Linux use `base64 -w0 AuthKey_XXXX.p8` instead. Never commit the `.p8` file; `.gitignore` already excludes `AuthKey_*.p8`.

Optional **repository variable** (same page, **Variables** tab):

| Variable | Value |
|----------|-------|
| `REVOX_BUNDLE_PREFIX` | The prefix of your bundle ids, for example `com.example`. Needed only if the bundle ids differ from `com.mchrisgm.revox`; the workflow defaults to `com.mchrisgm`. |

## Path A: automatic (cloud-managed) signing

This is the default (`signing = automatic`) and needs nothing beyond the four secrets. `xcodebuild archive` and `xcodebuild -exportArchive` run with `-allowProvisioningUpdates` plus the API key (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`). With those flags Xcode is allowed to talk to App Store Connect on the runner: it registers the bundle ids if they are missing, creates or renews a cloud-managed Apple Distribution certificate (the private key stays with Apple, nothing is stored in the repository), and creates the App Store provisioning profiles for the app and the extension. `CODE_SIGN_STYLE=Automatic` and `DEVELOPMENT_TEAM` are passed on the command line so the project needs no per-team edits.

Cloud signing has a known weak spot: the App Group entitlement. It works when the App IDs from the one-time setup already carry the App Groups capability with the right group. Two symptoms mean it cannot handle the entitlement on the runner and you need Path B:

1. The archive step fails while creating a profile with an error that mentions the `com.apple.security.application-groups` entitlement (for example that the provisioning profile "doesn't include" or "doesn't support" it).
2. The archive or export step fails with `No profiles for 'com.mchrisgm.revox' were found` (or the same for `com.mchrisgm.revox.broadcast`), even though the App IDs exist.

In both cases first re-check step 2 of the one-time setup (both App IDs, capability enabled, group assigned). If it still fails, switch to manual signing.

## Path B: manual signing

Manual signing uses a certificate and two profiles that you create once and store as secrets.

1. **Apple Distribution certificate.**
   1. On a Mac open **Keychain Access** → **Certificate Assistant** → **Request a Certificate From a Certificate Authority**. Enter your email, choose **Saved to disk**, and save the `.certSigningRequest` file.
   2. In [Certificates](https://developer.apple.com/account/resources/certificates/list) click **+**, choose **Apple Distribution**, upload the request, and download the `.cer` file.
   3. Double-click the `.cer` file to add it to your login keychain.
2. **Export the `.p12`.** In Keychain Access, **My Certificates**, right-click the `Apple Distribution: <your name>` entry → **Export**, format **Personal Information Exchange (.p12)**, and set a password. The `.p12` contains the private key; keep it off the repository (`*.p12` is git-ignored).
3. **Two App Store provisioning profiles.** In [Profiles](https://developer.apple.com/account/resources/profiles/list) click **+**, choose **App Store Connect** under Distribution, pick the App ID `com.mchrisgm.revox`, pick the certificate from step 1, name it (for example `ReVox Mobile App Store`), and download the `.mobileprovision` file. Repeat for `com.mchrisgm.revox.broadcast` (for example `ReVox Broadcast App Store`). The workflow reads each profile's name from the file itself, so the names are yours to choose.
4. **Add four more secrets** (base64 as above, `base64 -i FILE | pbcopy`):

   | Secret | Value |
   |--------|-------|
   | `DIST_CERT_P12` | The `.p12` from step 2, base64-encoded. |
   | `DIST_CERT_PASSWORD` | The password you set when exporting the `.p12`. |
   | `PROFILE_APP` | The app's `.mobileprovision`, base64-encoded. |
   | `PROFILE_EXTENSION` | The extension's `.mobileprovision`, base64-encoded. |

5. **Run the workflow manually**: **Actions** → **TestFlight** → **Run workflow**, branch `main`, **signing** = `manual`. Pushes to `main` still use automatic signing; to make manual the default for pushes, change the fallback in the `SIGNING` line near the top of `testflight.yml` from `|| 'automatic'` to `|| 'manual'` (changing the `default` of the `signing` workflow_dispatch input only affects manual runs, because `github.event.inputs` is empty on push events).

The manual archive passes `CODE_SIGN_STYLE=Manual`, `CODE_SIGN_IDENTITY="Apple Distribution"` and the two profile names; the export options gain `signingStyle = manual`, `signingCertificate = Apple Distribution` and a `provisioningProfiles` dictionary mapping each bundle id to its profile. The four secrets are only read when `signing = manual`; the API key is still required for the upload. Apple Distribution certificates expire after one year and profiles with them; when the archive step reports an expired or revoked certificate, repeat steps 1 to 4.

## Before the secrets exist

Until `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` and `APPLE_TEAM_ID` are all set, the `preflight` job prints

```
TestFlight upload skipped: missing repository secrets: ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 APPLE_TEAM_ID (see docs/release.md)
```

as a notice on the run, the `upload` job is skipped, and the workflow finishes successfully. `main` stays green and nothing else changes. The moment the four secrets exist the next push to `main` (or a manual run) performs the real upload; no workflow edit is needed. The everyday CI workflow (`ci.yml`) never needs any secret.

## After the upload

1. **Processing.** The run's last line reports the build number. App Store Connect processes the upload for usually 5 to 15 minutes (occasionally longer) and emails you when it is done or if it was rejected. The build then appears under **TestFlight** → **iOS Builds**. Because `ITSAppUsesNonExemptEncryption` is `false` in both Info.plists, there is no "Missing Compliance" question to answer.
2. **Internal testing group.** Under **TestFlight** → **Internal Testing** create a group (for example `ReVox team`), enable **Automatic distribution** so every new build reaches it, and add testers. Internal testers must be users of your App Store Connect team (up to 100); they get an email invitation immediately and no review is needed.
3. **External testing group with a public link.** Under **External Testing** create a group, add the build, and click **Enable Public Link**; set a tester limit if you want one (up to 10,000). Fill in **Test Information** first (what to test, a description, feedback email, contact details); the build cannot be submitted without it.
4. **Beta App Review.** The first build in an external group, and any later build with a new marketing version, goes through Beta App Review before external testers can install it (usually within a day or two). Later builds with the same marketing version are normally available right away. Share the public link only after the build shows **Ready to Test**.

Hand testers [docs/testing.md](testing.md).

## Troubleshooting

- **"Missing required icon" / ITMS-90704 or similar during processing.** App Store Connect requires a 1024×1024 app icon without transparency. The repository ships one at `ReVoxMobile/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, generated by `scripts/make_icon.py`. If you replace it, keep it 1024×1024, RGB, no alpha channel, and keep the name `AppIcon` in the asset catalog (`ASSETCATALOG_COMPILER_APPICON_NAME` in `project.yml`).
- **"Missing Compliance" status or a question about encryption after every upload.** Both Info.plists set `ITSAppUsesNonExemptEncryption` to `false`, which answers the export-compliance question automatically. If a build still asks, check that the key survived in both `ReVoxMobile/Info.plist` and `ReVoxBroadcast/Info.plist`. If you ever add encryption beyond what iOS provides, this answer must change.
- **Privacy manifest warnings by email (ITMS-91053 "Missing API declaration" or ITMS-91061 "Missing privacy manifest").** Both targets include a `PrivacyInfo.xcprivacy` declaring the required-reason APIs they use (UserDefaults, file timestamps, disk space). A warning naming a different API means new code uses it: add the API category and reason to both manifests. A warning naming a third-party framework means that package ships without a manifest; check for a newer version of the package. These are warnings and do not stop the build from reaching TestFlight, but Apple treats them as errors at App Store submission.
- **Upload fails with an agreement error** ("You must accept the ... agreement", "ITMS-90xxx: agreement not accepted", or the API returning 403). The Account Holder must accept the latest Apple Developer Program License Agreement in App Store Connect (**Business** / **Agreements, Tax, and Banking**). Nothing in the repository can fix this; re-run the workflow afterwards.
- **`altool` deprecation.** The upload step uses `xcrun altool --upload-app` with the API key. Apple has marked `altool` as deprecated and may remove it from a future Xcode. If the step starts failing with a message to that effect, switch the upload to `-exportArchive` itself: set `destination` to `upload` (instead of `export`) in `ci/ExportOptions.plist` and delete the "Upload to TestFlight" step; `xcodebuild -exportArchive` then uploads the archive directly using the same `-authenticationKey*` flags and no `.ipa` is written to `build/export/` (the artefact step tolerates this). `notarytool` is for macOS notarisation only and is not an alternative; Apple's Transporter app can upload the `.ipa` from the run's artefact by hand, but not from CI.
- **"No profiles for … were found" or an error mentioning `application-groups`.** See [Path A](#path-a-automatic-cloud-managed-signing) and switch to [Path B](#path-b-manual-signing).
- **Xcode 26.6 not on the runner image.** `scripts/ci/select-xcode.sh` prints a warning and falls back to the newest Xcode 26.x on the image. Update `XCODE_VERSION` in both workflows once you have verified the build with the newer Xcode.
- **The run failed but you need the logs.** Every run keeps `test.log`, `archive.log` and `export.log` (and the `.ipa` when it got that far) as the artefact `revox-mobile-build-<run number>` for 14 days.
