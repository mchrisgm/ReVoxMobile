# Releasing to TestFlight

This guide is for the repository owner. It explains what the TestFlight workflow does, the one-time Apple setup, the GitHub secrets it needs, the two signing paths, what happens before the secrets exist, what to do in App Store Connect after an upload, and how to fix the usual failures.

## What the workflow does

[`.github/workflows/testflight.yml`](../.github/workflows/testflight.yml) runs on **every push to `main`** — which in practice means every merged pull request — and also on a `v*` tag and on demand from the **Actions** tab (**TestFlight** → **Run workflow**, where you can also choose the signing path).

**What it costs.** The `upload` job archives, tests and uploads on a macOS runner, which bills at **ten times** the minute rate — roughly 200 billed minutes per merge, on top of the macOS job `ci.yml` already runs for every push on every branch. That is affordable for milestone-sized merges to `main` and is not affordable at per-push frequency, which is why the push trigger names `main` and nothing else. This trigger existed before, was removed after it exhausted the account's Actions allowance twice (runs 33811704361 and 33819325082 died in seconds with no readable log — a job that was never started), and was reinstated deliberately. If the allowance runs short again, the first thing to reconsider is `ci.yml`'s macOS job on every branch, not this one.

Two jobs:

1. **`preflight`** (Linux, seconds): checks that the four App Store Connect secrets exist. If any is missing it prints a notice and the `upload` job is skipped (see [Before the secrets exist](#before-the-secrets-exist)).
2. **`upload`** (macOS runner `macos-26`, Xcode 26.6 selected by `scripts/ci/select-xcode.sh`, up to 90 minutes), step by step:
   1. **Generate**: `brew install xcodegen xcbeautify`, then `xcodegen generate` writes `ReVoxMobile.xcodeproj` from `project.yml`.
   2. **Resolve packages**: `xcodebuild -resolvePackageDependencies` into `.spm/`, cached between runs by the hash of `project.yml`.
   3. **Test**: `xcodebuild test` with the `ReVoxMobile` scheme on the newest available iPhone simulator (`scripts/ci/pick-simulator.sh`). A failing test stops the workflow before anything is signed or uploaded.
   4. **Write the API key**: `ASC_KEY_P8` is decoded to `~/private_keys/AuthKey_<ASC_KEY_ID>.p8`.
   5. **Import signing material** (manual signing only): the distribution certificate goes into a temporary keychain and the two provisioning profiles are installed; their names are exported as `REVOX_PROFILE_APP` and `REVOX_PROFILE_EXTENSION`.
   6. **Archive**: `xcodebuild archive` (Release, `generic/platform=iOS`) to `build/ReVoxMobile.xcarchive`, with `DEVELOPMENT_TEAM=$APPLE_TEAM_ID`, `REVOX_BUNDLE_PREFIX` and the build number passed in as build settings.
   7. **Export**: `ci/ExportOptions.plist` is copied to `ci/ExportOptions.generated.plist`, the team id (and, for manual signing, the certificate and the two profiles) are filled in, then `xcodebuild -exportArchive` writes the `.ipa` to `build/export/`. This export is kept only for the `.ipa` artefact; it does not upload anything.
   8. **Upload**: the same archive is exported a second time, this time with `destination = upload` set on a copy of the export options plist. That second `xcodebuild -exportArchive` run performs the upload itself, authenticated with the same API key, and writes `build/upload/DistributionSummary.plist`; its console output goes to `upload.log`, and the step fails unless `upload.log` contains `** EXPORT SUCCEEDED **`.
   9. **Keep the artefacts**: the `.ipa`, `build/upload/DistributionSummary.plist`, and the test, archive, export and upload logs are attached to the run as `revox-mobile-build-<run number>` for 14 days, even when a step failed.
   10. **Clean up**: the API key, the generated export options and the temporary keychain are removed.

Version numbers:

- **Build number** (`CFBundleVersion`) = `github.run_number`, passed as `CURRENT_PROJECT_VERSION`. Every new run gets a higher number, so a new run never collides with an earlier upload. Re-running an existing run (**Re-run jobs** / **Re-run failed jobs**) reuses that run's number: if its upload step had already succeeded, App Store Connect rejects the second upload as a duplicate (ITMS-90189, redundant binary). To upload again, start a new run (**Actions** → **Run workflow**, or push a `v*` tag) instead of re-running the old one. `manageAppVersionAndBuildNumber` is `false` in `ci/ExportOptions.plist`, so App Store Connect does not renumber it.
- **Marketing version** (`CFBundleShortVersionString`) = `MARKETING_VERSION` in `project.yml` (currently `0.1.0`). Change it there when you start a new version; TestFlight groups builds by this number.

Only one TestFlight run executes at a time (`concurrency: testflight`); further pushes wait rather than cancelling a running upload.

## Transitive package versions

Only WhisperKit and FluidAudio are pinned to an exact version (`exactVersion` in `project.yml`); their own dependencies, and any other transitive Swift packages, are resolved at build time and can float between runs. The CI job (`.github/workflows/ci.yml`) prints the exact versions it resolved with a "Show resolved package versions" step that `cat`s `ReVoxMobile.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, and uploads that same file as part of the `xcodebuild-log` artefact, so the transitive versions used by any given run are visible in the log and downloadable afterwards. Pinning them for real, by committing a `Package.resolved` to the repository, is planned for the hardening milestone.

## One-time Apple setup

You need a paid Apple Developer Program membership. Then, in this order:

1. **App Group.** In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list/applicationGroup) create an App Group with identifier `group.com.mchrisgm.revox` (or `group.<your prefix>.revox` if you use a different `REVOX_BUNDLE_PREFIX`). The app and the broadcast extension use it to share audio and settings.
2. **Two App IDs with the App Groups capability.** Under **Identifiers** register two explicit App IDs:
   - `com.mchrisgm.revox` for the app;
   - `com.mchrisgm.revox.broadcast` for the broadcast extension.

   On each one enable the **App Groups** capability **and** assign the group from step 1 — two separate actions in that UI, and it is easy to do the first without the second. Ticking the capability without assigning the group produces a profile with no group in it, and the archive fails with:

   ```
   error: Provisioning profile "iOS Team Provisioning Profile: com.mchrisgm.revox" doesn't match
   the entitlements file's value for the com.apple.security.application-groups entitlement
   ```

   To check an existing App ID: open it, confirm **App Groups** is ticked, then click **Edit**/**Configure** beside it and confirm `group.com.mchrisgm.revox` is selected. Nothing else is required at this milestone (no push, no iCloud).
3. **Team ID.** Copy the 10-character Team ID from [Membership details](https://developer.apple.com/account#MembershipDetailsCard). It becomes the `APPLE_TEAM_ID` secret.
4. **Agreements.** In App Store Connect open **Business** (or **Agreements, Tax, and Banking**) and make sure the Apple Developer Program License Agreement is accepted by the Account Holder. Uploads fail until it is, every time Apple issues a new version of the agreement.
5. **App Store Connect API key with the Admin role.** In App Store Connect go to **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys** and generate a key with access **Admin**. Download the `AuthKey_XXXX.p8` file immediately (it can be downloaded only once) and note the **Key ID** and the **Issuer ID** shown on that page.

   **Admin, not App Manager.** App Manager can upload builds, and it is enough for [Path B](#path-b-manual-signing) where you supply the certificate yourself. It cannot create the *cloud-managed distribution certificate* that [Path A](#path-a-automatic-cloud-managed-signing) needs, and the failure comes at the export step, long after the archive has succeeded:

   ```
   error: exportArchive Cloud signing permission error
   error: exportArchive No profiles for 'com.mchrisgm.revox' were found
   ```

   An Admin key is powerful — it can manage users, agreements and app records for the whole account — and it lives in a GitHub secret. If that breadth is unacceptable, use Path B and keep the key at App Manager, used only for the upload.
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

as a notice on the run, the `upload` job is skipped, and the workflow finishes successfully. `main` stays green and nothing else changes. The moment the four secrets exist the next merge to `main` (or dispatched run, or `v*` tag) performs the real upload; no workflow edit is needed. The everyday CI workflow (`ci.yml`) never needs any secret.

## After the upload

1. **Processing.** The run's last line reports the build number. App Store Connect processes the upload for usually 5 to 15 minutes (occasionally longer) and emails you when it is done or if it was rejected. The build then appears under **TestFlight** → **iOS Builds**. Because `ITSAppUsesNonExemptEncryption` is `false` in both Info.plists, there is no "Missing Compliance" question to answer.
2. **Internal testing group.** Under **TestFlight** → **Internal Testing** create a group (for example `ReVox team`), enable **Automatic distribution** so every new build reaches it, and add testers. Internal testers must be users of your App Store Connect team (up to 100); they get an email invitation immediately and no review is needed.
3. **External testing group with a public link.** Under **External Testing** create a group, add the build, and click **Enable Public Link**; set a tester limit if you want one (up to 10,000). Fill in **Test Information** first (what to test, a description, feedback email, contact details); the build cannot be submitted without it.
4. **Beta App Review.** The first build in an external group, and any later build with a new marketing version, goes through Beta App Review before external testers can install it (usually within a day or two). Later builds with the same marketing version are normally available right away. Share the public link only after the build shows **Ready to Test**.

Hand testers [docs/testing.md](testing.md).

## App Review notes (background audio)

Paste this into **App Store Connect → TestFlight → Test Information → Review notes** (and later into the App Review notes of the App Store submission). It answers Guideline 2.5.4 for the `audio` entry in `UIBackgroundModes`.

> ReVox is a live speech-to-English translator that runs entirely on the device. It declares the `audio` background mode because its background activity *is* audio: in microphone mode the app records speech through the microphone and plays the translated English sentence aloud through its own audio engine; in the "Other apps" mode the app plays the translated English while a user-started system broadcast (ReplayKit Broadcast Upload Extension `ReVoxBroadcast`, started from the picker on the Live screen or from Control Center's Screen Recording control) supplies the audio of another app; the extension only converts that audio to 16 kHz and hands it to the app through an App Group shared file, records nothing to disk beyond a 60-second rolling buffer that is overwritten continuously while broadcasting and zeroed when the broadcast ends, and uses no microphone (the picker's microphone button is hidden). Nothing is transmitted; no server is contacted after the one-time model download from huggingface.co that the user starts from the Models screen. The microphone is used only while the user has pressed Start in microphone mode (`NSMicrophoneUsageDescription`: "ReVox listens to speech so it can translate it to English on this iPhone. Audio never leaves the device."). The audio session is `.playAndRecord` with `.mixWithOthers`, so other apps keep playing. To test: open Models, download "small", go to Live, press Start, speak a sentence in Spanish, French or German — the English text appears and is spoken. Lock the phone and keep speaking: translation continues until Stop.

To test the Other apps mode: on the Live screen choose **Other apps**, tap **Start**, tap the broadcast picker button, select **ReVox** and **Start Broadcast**; open any app with speech in another language and play it — the English text appears in ReVox and is spoken over the other app's audio, which iOS lowers while ReVox speaks. Lock the phone: translation continues. The broadcast ends from the red status-bar indicator or Control Center.

Before every upload the CI job runs `scripts/ci/check-plists.py`, which verifies `ITSAppUsesNonExemptEncryption = false` in both plists, the microphone usage description, the `audio` background mode, and the privacy-manifest reasons of the design spec (§11). After the first upload, check the processing e-mail from App Store Connect for ITMS-91053 warnings about required-reason APIs: the pinned SDKs read file sizes with `attributesOfItem`, which the app's `C617.1` entry absorbs; any other warning is recorded in `docs/measurements/m3-microphone-mode.md` row 12 and fixed in the same milestone.

## Assigning the build to the internal group

1. App Store Connect → **TestFlight** → the build appears under **iOS** after processing (5–15 minutes); the `Missing Compliance` badge does not appear because the plists carry `ITSAppUsesNonExemptEncryption = false`.
2. Open the build → **Test Information**: paste the review notes above the first time.
3. **Internal Testing** → the group created in the one-time setup → **+** → select the build. Internal testers get the TestFlight notification within minutes; no App Review is needed for internal groups.

## Enabling the public TestFlight link

The workflow uploads builds; it cannot create testing groups or links (there is no App Store Connect API endpoint for public links, and the repository holds no App Store Connect session). The owner enables the link once, in App Store Connect, after a build that carries the History, export and About features (milestone 6 or later) shows **Ready to Test**:

1. **Test Information first.** TestFlight → **Test Information**: a description of what ReVox does (the first paragraph of `docs/testing.md`), the feedback email, and a contact for Beta App Review. Under **What to Test** paste sections 4–7, 9 and 10 of `docs/testing.md`. A build cannot be submitted to an external group without this.
2. **External group.** TestFlight → **External Testing** → **+**, name it (for example `ReVox public`), leave **Automatic distribution** on so later builds with the same marketing version reach it without a new review, and add the current build.
3. **Beta App Review.** The first build in the group is reviewed (usually within one to two days). The review notes for the `audio` background mode (section "App Review notes (background audio)" above) apply here as well: paste them into the review notes field. A build that fails review is reported by email with the reason; fix, push, and add the new build to the group.
4. **Public link.** Once the build shows **Ready to Test** in the external group, open the group and click **Enable Public Link**. Set a tester limit if wanted (up to 10 000). Copy the link; it stays valid for later builds added to the same group. Share it together with `docs/testing.md`.
5. **Later builds.** Every merge to `main` uploads a new build, as does each dispatched run and `v*` tag. With automatic distribution on, builds with the same `MARKETING_VERSION` become available to the group without review; bumping `MARKETING_VERSION` in `project.yml` triggers a new Beta App Review for the first build of that version.

Disable the link from the same page (**Disable Public Link**) to stop new testers from joining; existing testers keep their builds until they expire (90 days after upload).

## Troubleshooting

- **"Missing required icon" / ITMS-90704 or similar during processing.** App Store Connect requires a 1024×1024 app icon without transparency. The repository ships one at `ReVoxMobile/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, generated by `scripts/make_icon.py`. If you replace it, keep it 1024×1024, RGB, no alpha channel, and keep the name `AppIcon` in the asset catalog (`ASSETCATALOG_COMPILER_APPICON_NAME` in `project.yml`).
- **"Missing Compliance" status or a question about encryption after every upload.** Both Info.plists set `ITSAppUsesNonExemptEncryption` to `false`, which answers the export-compliance question automatically. If a build still asks, check that the key survived in both `ReVoxMobile/Info.plist` and `ReVoxBroadcast/Info.plist`. If you ever add encryption beyond what iOS provides, this answer must change.
- **Privacy manifest warnings by email (ITMS-91053 "Missing API declaration" or ITMS-91061 "Missing privacy manifest").** Both targets include a `PrivacyInfo.xcprivacy` declaring the required-reason APIs they use: UserDefaults (`CA92.1` for the app's own defaults, plus `1C8F.1` because the app and the broadcast extension share state through `UserDefaults(suiteName:)` on the App Group), file timestamps (`C617.1`), and disk space (`E174.1`, `85F4.1`). A warning naming a different API means new code uses it: add the API category and reason to both manifests. A warning naming a third-party framework means that package ships without a manifest; check for a newer version of the package. These are warnings and do not stop the build from reaching TestFlight, but Apple treats them as errors at App Store submission.
- **Upload fails with an agreement error** ("You must accept the ... agreement", "ITMS-90xxx: agreement not accepted", or the API returning 403). The Account Holder must accept the latest Apple Developer Program License Agreement in App Store Connect (**Business** / **Agreements, Tax, and Banking**). Nothing in the repository can fix this; re-run the workflow afterwards.
- **The "Upload to TestFlight" step fails.** The workflow uploads with a second `xcodebuild -exportArchive` run (`destination = upload`); check `upload.log` in the run's artefact for the underlying `xcodebuild` error. If the export-and-upload step is broken and you need a build in TestFlight before you can fix it, upload the `.ipa` from `build/export/` by hand: put the App Store Connect API key at `~/private_keys/AuthKey_<key id>.p8` (base64-decode the `ASC_KEY_P8` secret, or use the `.p8` you downloaded), then run

  ```bash
  xcrun altool --upload-app -f <ipa> -t ios --apiKey <key id> --apiIssuer <issuer id>
  ```

  This is a manual fallback only, not what the workflow itself does: `altool` is deprecated, and it can print `ERROR:` lines yet still exit 0, so read its output carefully rather than trusting the exit code. `notarytool` is for macOS notarisation only and is not an alternative; Apple's Transporter app can also upload the `.ipa` from the run's artefact by hand.
- **"No profiles for … were found" or an error mentioning `application-groups`.** First read the exact wording. `Cloud signing permission error` alongside it means the API key cannot create the distribution certificate: use an **Admin** key (step 5 of the one-time setup). An error naming `application-groups` at the *archive* step instead means the App IDs lack the group (step 2). Only if both are right does [Path A](#path-a-automatic-cloud-managed-signing) genuinely need switching to [Path B](#path-b-manual-signing).
- **The `Check secrets` job fails in about a second, with no log to read.** This is not a secrets problem: that job's script cannot fail, because every branch exits 0 — missing secrets *skip* the upload with a notice rather than failing. A one-second failure with no retrievable log means the job never ran a step, which in practice means GitHub refused to start it — usually the **Actions spending limit**. Check **Settings** → **Billing and licensing** → **Plans and usage**, and note that macOS runners bill at 10× the minute rate, so a day of debugging on `macos-26` consumes an allowance quickly.
- **Xcode 26.6 not on the runner image.** `scripts/ci/select-xcode.sh` prints a warning and falls back to the newest Xcode 26.x on the image. Update `XCODE_VERSION` in both workflows once you have verified the build with the newer Xcode.
- **The run failed but you need the logs.** Every run keeps `test.log`, `archive.log`, `export.log` and `upload.log` (and the `.ipa` and `build/upload/DistributionSummary.plist` when the run got that far) as the artefact `revox-mobile-build-<run number>` for 14 days.

### The archive fails naming `com.apple.developer.kernel.increased-memory-limit`

The app declares the increased-memory-limit entitlement (it lets the Whisper and pocket-tts models
coexist on 4 GB devices). Automatic signing can only attach it if the capability is enabled on the
App ID: Certificates, Identifiers & Profiles → Identifiers → the app's App ID → **Additional
Capabilities** → tick **Increased Memory Limit**, save, then re-run the workflow. The extension must
never declare it — `scripts/ci/check-plists.py` fails the build if it does.
