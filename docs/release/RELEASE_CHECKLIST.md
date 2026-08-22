# Release checklist

The human-readable walkthrough for `.github/workflows/release.yml`.
Companion docs: `docs/release/VERSIONING.md` (version policy),
`docs/release/APPLE.md`, `docs/release/GOOGLE_PLAY.md` (store-specific
compliance), `docs/DEVICE_ACCEPTANCE.md` (the physical-device sign-off
this checklist requires before production promotion).

## What the pipeline does, and does not, do

```
git tag vX.Y.Z+N (matching pubspec.yaml exactly)
        │
        ▼
version-consistency (fails fast if tag != pubspec.yaml)
        │
        ├─────────────┬─────────────┬─────────────┬─────────────┐
        ▼             ▼             ▼             ▼             ▼
   fast-checks   compat-checks  supply-chain  android-debug  ios-debug
  (pr-fast.yml) (singbox-vpn-  -checks       -smoke         -smoke
                 compat.yml)   (supply-      (android-      (ios-
                                chain.yml)    build.yml)     build.yml)
        │             │             │             │             │
        └─────────────┴──────┬──────┴─────────────┴─────────────┘
                              ▼ (only if ALL of the above are green)
              ┌───────────────┴───────────────┐
              ▼                               ▼
  android-release-build              ios-release-build
  (real signing, AAB+APK)            (real signing, app + [extension --
              │                       see "Known gap" below], IPA)
              ▼                               ▼
  google-play-internal                testflight-upload
  (Play "internal" track ONLY)        (TestFlight internal testing ONLY)
              │                               │
              └───────────────┬───────────────┘
                               ▼
                       github-release
        (AAB, APK, IPA, checksums, changelog, GPL source
         archive, dependency manifest -- always created as
         a PRE-RELEASE)
```

**Everything above is automatic once a matching tag is pushed.**
**Nothing below this line is automatic — every one of these is a
deliberate, manual action a human takes:**

- Promoting the Google Play release beyond Internal Testing (to Closed
  Testing, then Production).
- Submitting the iOS build for App Store Review, and releasing it once
  approved.
- Removing the "pre-release" flag on the GitHub Release.
- Recording a physical-device acceptance result
  (`docs/DEVICE_ACCEPTANCE.md`) — required before either store promotion
  above, by policy, not by anything the pipeline can technically enforce.

## Release gates (all automatic, all must be green)

Per this task's requirement, a release requires all of:

| Gate | Job | What it checks |
|---|---|---|
| CI green | `fast-checks` | Format, `packages/vpn_core` analyze/test (the app-level analyze/test steps are informational within that workflow — see `docs/CI.md` — but the job as a whole still gates on `packages/vpn_core` and formatting) |
| singbox-vpn compatibility green | `compat-checks` | Fixture/parser tests AND the real headless VLESS+REALITY/Hysteria2 protocol interop tests (`docs/SINGBOX_VPN_COMPATIBILITY.md`) |
| Version consistency green | `version-consistency` | Git tag exactly matches `pubspec.yaml`'s version (`docs/release/VERSIONING.md`) |
| Dependency/license checks green | `supply-chain-checks` | Secret scan, lockfile consistency, license/dependency inventory, OSV vulnerability scan (`docs/CI.md`) |
| Android build green | `android-debug-smoke` then `android-release-build` | Debug-build smoke test, then the real signed release build |
| iOS build green | `ios-debug-smoke` then `ios-release-build` | Unsigned-build smoke test, then the real signed release build |

**Read `docs/CI.md` "Known current-state gaps" before treating any of
this as a checklist you can blindly trust once green.** UPDATE (verified
against `origin/main` as of this document's own device-readiness audit,
`docs/CI.md`'s "Known current-state gaps" items 1-2): `lib/app/utils/`,
`VPNService`/`ProxyConfig`/`ServerConfig`, and the iOS `PacketTunnel`
Xcode target registration were all reconstructed and landed in earlier
commits (PR #2, PR #3) — `android-debug-smoke`/`ios-debug-smoke` are no
longer expected to be red on that account. Every job in this pipeline
still only proves compile/package/protocol-interop correctness, never
real-device VPN behavior — see `docs/CI.md` "What CI explicitly does NOT
prove" and `docs/DEVICE_ACCEPTANCE.md`, which remain the accurate,
current caveats.

## Before public promotion: manually recorded device acceptance

Per this task's explicit instruction, **do not promote a release to
production on either store without a dated entry in
`docs/DEVICE_ACCEPTANCE.md`** covering, at minimum, the protocols and
platforms this release actually changes. This is a policy this checklist
states, not something `release.yml` can verify — no CI job can confirm "a
human actually watched a video over Hysteria2 on a real iPhone." Treat
the absence of a recent, dated entry as a hard blocker on your own
production-promotion decision, the same way you'd treat a failing test.

## Secrets to configure

All of these are **GitHub encrypted secrets**, scoped to the two
Environments below — never repository-level secrets, and never committed
anywhere (see each secret's own `git-secrets`/gitleaks-relevant note).

### `android-release` Environment

| Secret | What it is | How to produce it |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | Your release signing keystore (`.jks`/`.keystore`), base64-encoded | `base64 -i release.keystore \| pbcopy` (or `base64 -w0 release.keystore` on Linux) — paste the output as the secret value |
| `ANDROID_KEYSTORE_PASSWORD` | That keystore's store password | — |
| `ANDROID_KEY_ALIAS` | The signing key's alias inside the keystore | — |
| `ANDROID_KEY_PASSWORD` | That key's password (often the same as the store password, but not required to be) | — |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | A Google Cloud service account's JSON key, granted access to this app in Play Console | See `docs/release/GOOGLE_PLAY.md` "Service account setup" |

**Never commit** the keystore file, its passwords, or the service
account JSON — see `.gitleaks.toml` for the secret-scanning
configuration that would flag an accidental commit of credential-shaped
values, and `docs/CI.md`'s "Secret scan" section for how it runs.

### `ios-release` Environment

| Secret | What it is | How to produce it |
|---|---|---|
| `IOS_DIST_CERTIFICATE_P12_BASE64` | An Apple Distribution certificate + private key, exported as `.p12`, base64-encoded | Export from Keychain Access (or `security export`) as a `.p12` with a password, then `base64 -w0 cert.p12` |
| `IOS_DIST_CERTIFICATE_PASSWORD` | That `.p12`'s export password | — |
| `IOS_PROVISIONING_PROFILE_BASE64` | The main (Runner/host) app's App Store distribution provisioning profile, base64-encoded, for bundle ID `com.nebula.karing` | Download the `.mobileprovision` from Apple Developer, `base64 -w0 profile.mobileprovision` |
| `IOS_PROVISIONING_PROFILE_NAME` | That profile's exact `Name` (not filename) — xcodebuild needs this for manual signing | `security cms -D -i profile.mobileprovision \| plutil -extract Name raw -` |
| `IOS_EXTENSION_PROVISIONING_PROFILE_BASE64` | The PacketTunnel Network Extension target's own App Store distribution provisioning profile, base64-encoded, for bundle ID `com.nebula.karing.PacketTunnel` — a separate signable product from the host app (see `docs/ARCHITECTURE.md` §7), so it needs its own profile, not a reuse of the host app's | Same as `IOS_PROVISIONING_PROFILE_BASE64`, but requested against the `.PacketTunnel` App ID |
| `IOS_EXTENSION_PROVISIONING_PROFILE_NAME` | That profile's exact `Name` | `security cms -D -i extension-profile.mobileprovision \| plutil -extract Name raw -` |
| `IOS_TEAM_ID` | Your Apple Developer Team ID (10 characters) | Apple Developer portal → Membership |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API key ID | App Store Connect → Users and Access → Integrations → App Store Connect API |
| `APP_STORE_CONNECT_API_ISSUER_ID` | The associated issuer ID (shared across all your keys) | Same page |
| `APP_STORE_CONNECT_API_KEY_BASE64` | The downloaded `.p8` private key content, base64-encoded | `base64 -w0 AuthKey_XXXXXXXXXX.p8` -- **Apple lets you download this exactly once**; store the base64 value as the secret immediately |

## GitHub Environment configuration

Create two Environments under **Settings → Environments**:

- `android-release`
- `ios-release`

For each:

1. Add the secrets listed above, scoped to that Environment (not
   repository-level "Secrets and variables" — Environment secrets are
   only readable by jobs that declare `environment: <name>`, which is
   exactly `android-release-build`/`google-play-internal` and
   `ios-release-build`/`testflight-upload` respectively).
2. **Recommended**: add required reviewers to both Environments. This
   means a human must click "approve" in the GitHub Actions UI before
   any job that can read these secrets runs — even for the
   internal/beta-only distribution this pipeline does. Not strictly
   required by this task (which asks for internal/beta to be automatic),
   but it's a cheap extra checkpoint against a compromised/mistaken tag
   push triggering a real signed build and upload unattended. If you add
   this, note that `release.yml` will pause and wait at
   `android-release-build`/`ios-release-build` until approved.
3. Do **not** add a deployment branch/tag restriction that's narrower
   than `v*` unless you want to further restrict which tags can trigger
   a release — the workflow's own `on.push.tags: ["v*"]` is already the
   primary gate on that.

## Android release path

1. `version-consistency` passes.
2. `android-debug-smoke` (the existing CI debug build) passes.
3. `android-release-build` decodes the real keystore, builds a signed AAB
   (`flutter build appbundle --release`) and a signed APK
   (`flutter build apk --release`), computes SHA256 checksums, uploads
   both as a workflow artifact, then shreds the decoded keystore and
   restores the repo's placeholder `key.properties`.
4. `google-play-internal` downloads the AAB and runs
   `scripts/release/upload_google_play.py --track internal` — the script
   itself hard-allowlists `internal`/`alpha`/`beta`, so it structurally
   cannot push to `production`.
5. **Manual**: open Play Console, review the Internal Testing release,
   promote to Closed Testing when ready, then eventually Production —
   see `docs/release/GOOGLE_PLAY.md`.

## iOS release path

1. `version-consistency` passes.
2. `ios-debug-smoke` (the existing CI unsigned build, including the
   `xcodebuild` step that would force the VPN extension target to
   compile once it's registered — see `docs/CI.md`) passes.
3. `ios-release-build` imports the distribution certificate into a
   temporary keychain, installs the provisioning profile, runs
   `flutter build ipa --release` with a generated `ExportOptions.plist`
   (manual signing, `app-store-connect` export method), computes a
   checksum, uploads the IPA as a workflow artifact, then deletes the
   temporary keychain and imported profile.
4. `testflight-upload` downloads the IPA and runs
   `xcrun altool --upload-app` authenticated via the App Store Connect
   API key (never a username/password/app-specific-password).
5. **Manual**: open App Store Connect, wait for TestFlight processing,
   add internal testers if not already added, and when ready, submit for
   App Store Review and release once approved — see
   `docs/release/APPLE.md`.

**This iOS path was not verified end to end** — no macOS host or Apple
Developer account was available in the environment that wrote it. It
follows Apple's own documented, standard patterns (`security
import`/`security create-keychain` for CI code signing,
`flutter build ipa --export-options-plist`, `xcrun altool --upload-app`
with an API key) rather than anything invented, but the first real run
should be treated as the actual validation, watched closely, and this
document corrected against whatever it gets wrong.

## GitHub Release contents

Created by the `github-release` job, always as a **pre-release** (a human
removes that flag once production promotion has actually happened, on
both stores or whichever is relevant):

- `*.aab`, `*.apk` (Android)
- `*.ipa` (iOS)
- `CHECKSUMS.txt` — SHA256 for every binary artifact above
- A changelog generated from `git log` between the previous and current
  tag
- `singbox-client-<tag>-source.tar.gz` — `git archive` of the exact
  tagged commit: this project's GPL-3.0 corresponding source for the
  attached binaries (see `LICENSE`, and
  `docs/FORK_ARCHITECTURE_AUDIT.md` §10 for this fork's own licensing
  situation)
- `DEPENDENCY_MANIFEST.txt` — resolved Dart (app + `vpn_core`) and Go
  (pinned sing-box tree) dependency versions, plus the exact pinned
  sing-box/libbox commit (`packages/vpn_core/UPSTREAM_VERSION.md`)

## Rollback strategy

**Google Play**: Play Console supports halting a staged/internal rollout
and, for production, a "rollback" to the previous release from the
release dashboard (re-publishing the last-known-good version with a
higher `versionCode` than the bad release, since Play never lets you
re-use a `versionCode`). Concretely:
1. Halt the current release's rollout in Play Console if still in
   progress.
2. Bump `pubspec.yaml`'s build number (`docs/release/VERSIONING.md`),
   fix the issue, tag, and push a new release through the same pipeline
   — the "rollback" is really "forward-fix and ship a new build," which
   is Play's own recommended model (you cannot re-publish an old APK/AAB
   under a lower `versionCode`).
3. For a severe issue, use Play Console's "Deactivate" on the bad release
   to stop it reaching more users while the forward-fix is prepared.

**TestFlight**: remove the problematic build from testing in App Store
Connect (Builds → select build → "Expire Build" or simply stop offering
it to new testers) — testers already on it should be told to reinstall
the previous build or wait for the fix. For a build already in
Production App Store review or released, use App Store Connect's
"Remove from Sale" for a severe issue, or expedited review for a fix
(Apple's Expedited Review Request), then release the forward-fixed
version once approved. iOS has no true rollback mechanism either — same
"forward-fix and re-submit" model as Android.

**GitHub Release**: mark the release as broken in its own notes (edit
the release body — do not delete it, since deleting a release the store
badges/checksums reference is more disruptive than leaving a clearly
labeled bad release visible) and point to the fixed tag once available.

## Remaining manual steps (full list)

Collected from throughout this document, so nothing is missed:

1. Generate and configure all secrets listed above, in both
   `android-release` and `ios-release` Environments.
2. ~~Register the PacketTunnel/NetworkExtension Xcode target~~ **Done** —
   `ios-build.yml`'s `xcodebuild` step compiles both the `Runner` and
   `PacketTunnel` targets against the real `Libbox.xcframework` (see
   `docs/CI.md`). Compiling is not the same as a validated, working
   NetworkExtension on a real device — that is still an open, device-only
   gap (`docs/DEVICE_ACCEPTANCE.md`).
3. ~~Resolve `lib/app/utils/` and `VPNService`/`ProxyConfig`/`ServerConfig`~~
   **Done** (`docs/ARCHITECTURE.md` §9) — `android-debug-smoke`/
   `ios-debug-smoke` build the real app, not a stub.
4. Complete the store compliance placeholders in `docs/release/APPLE.md`
   and `docs/release/GOOGLE_PLAY.md` — every checkbox there needs a real
   answer reflecting this app's actual behavior, not a template default.
5. Bump `pubspec.yaml`'s version and tag, per `docs/release/VERSIONING.md`,
   for every release.
6. Record a dated physical-device acceptance entry
   (`docs/DEVICE_ACCEPTANCE.md`) before promoting any release beyond
   internal/beta testing.
7. Promote Google Play Internal → Closed Testing → Production manually.
8. Submit for App Store Review and release manually once approved.
9. Remove the GitHub Release's "pre-release" flag once production
   promotion has happened.
10. Watch the first real run of this pipeline closely (see the iOS
    section's caveat above) and correct this document against reality.
