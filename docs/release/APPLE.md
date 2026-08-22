# Apple / App Store compliance checklist

Every checkbox below needs a real, verified answer before submitting to
App Store Review — this document deliberately does **not** answer the
privacy/store questionnaire items for you (per this task's explicit
instruction): those answers must reflect this app's actual behavior,
decided by whoever owns the app's privacy policy and data practices, not
guessed here. Items already verifiable from the repository are marked
`[x]` with their source cited; everything else is `[ ]` with a
`TODO(you):` placeholder.

## Organization developer account

- [ ] Enroll in the [Apple Developer Program](https://developer.apple.com/programs/) as an **Organization** (not an individual account) — required for Network Extension entitlement approval, which Apple gates more strictly for individual accounts.
      `TODO(you):` record the enrolled organization's legal name, D-U-N-S number, and account holder here once enrolled.
- [ ] Confirm the Team ID matches `IOS_TEAM_ID` configured in the `ios-release` GitHub Environment (`docs/release/RELEASE_CHECKLIST.md`).
- [ ] Add any additional release engineers as Users with the "App Manager" or "Admin" role in App Store Connect (Users and Access).

## Network Extension capability

- [x] **Already declared** in this repository's entitlements (verified by reading the files directly, not assumed — re-verified against current `origin/main` during the device-readiness audit, superseding this section's earlier `com.nebula.karing`-era text):
  - `ios/Runner/Runner.entitlements`: `com.apple.developer.networking.networkextension` = `["packet-tunnel-provider"]`, `com.apple.security.application-groups` = `["group.com.david610.singboxclient"]`
  - `ios/vpnCoreService/PacketTunnel.entitlements` (the `PacketTunnel` Network Extension target, `PRODUCT_BUNDLE_IDENTIFIER = com.david610.singboxclient.PacketTunnel`, registered in `ios/Runner.xcodeproj/project.pbxproj` — see `docs/ARCHITECTURE.md` §7): same `packet-tunnel-provider` entitlement and the same `group.com.david610.singboxclient` App Group as `Runner.entitlements` above, so the app and extension share state via the same container.
  - **Bundle-ID provenance flag (unresolved, worth a human decision, not a technical blocker)**: both bundle IDs and the App Group use the `com.david610.*` reverse-domain namespace — no longer the inherited `com.nebula.karing`, but also not independently confirmed to be a domain/identifier this project's current owner controls (it reads as a prior contributor's GitHub handle). Confirm you actually control this identifier space in your own Apple Developer account before requesting the Network Extension capability against it, or change it to one you do control.
  - `ios-build.yml`'s `xcodebuild -scheme Runner` step (see `docs/CI.md`) now actually compiles both targets against the real `Libbox.xcframework` — this was an open gap in an earlier revision of this document; it is closed as of the current `origin/main`.
- [ ] **The Network Extension capability itself must still be requested from Apple** for your specific bundle ID / Team ID via the Apple Developer portal (Certificates, Identifiers & Profiles → your App ID → capabilities). This is a per-account, per-app-ID grant Apple reviews — it is not automatically available just because the entitlement is present in a project file. `TODO(you):` request it, record the approval date here.
- [ ] **CI (`ios-build.yml`, macOS runner) now compiles both targets for real** (see `docs/CI.md`), but no human has opened `Runner.xcworkspace` in a local Xcode with a real Apple Developer Team ID / provisioning profile, or installed the result on a real device. Before relying on it for a release, do that once: confirm the `PacketTunnel` target appears correctly, builds, and archives/signs cleanly, and regenerate provisioning profiles for both targets once the Network Extension capability above is approved.

## Packet Tunnel Provider entitlement

- [x] `com.apple.developer.networking.networkextension: packet-tunnel-provider` is the correct, specific entitlement value for a `NEPacketTunnelProvider`-based VPN client (not `app-proxy-provider`, `content-filter-provider`, or others in that array) — confirmed against Apple's own NetworkExtension documentation.
- [ ] Provisioning profiles for **both** the main app target and the (once-registered) extension target must include this entitlement — a profile generated before the capability was approved on the App ID will not have it; regenerate after approval.

## Privacy manifest (`PrivacyInfo.xcprivacy`)

- [ ] **MISSING — real submission blocker.** Verified directly: no
  `PrivacyInfo.xcprivacy` file exists anywhere under `ios/` (neither for
  the `Runner` target nor the `PacketTunnel` extension), confirmed by a
  repository-wide search for the filename. Apple requires this manifest
  when an app (or an SDK it embeds) uses any "required reason" API
  (e.g. `UserDefaults`, file-modification-timestamp APIs, disk-space
  APIs, active-keyboard APIs, system-boot-time APIs) — App Store Connect
  has rejected submissions missing it since Apple's 2024 privacy-manifest
  policy took effect, for apps that use those APIs. `TODO(you):`
  determine whether `Runner`/`PacketTunnel` or any embedded pod actually
  calls a required-reason API (a real code/dependency audit, not
  guessed here — CocoaPods dependencies bundling their own
  `PrivacyInfo.xcprivacy`, e.g. some Flutter plugins' iOS pods, may
  already declare their own reasons; those don't cover `Runner`'s or
  `PacketTunnel`'s own code) and add the manifest(s) with the correct
  declared reason codes before submission.

## Privacy policy

- [ ] `TODO(you):` publish a privacy policy at a stable, public URL. A VPN app's privacy policy is under unusually high scrutiny (App Review specifically checks this for VPN/proxy apps) — it must accurately describe:
  - What `packages/vpn_core`'s diagnostics module does and does not collect — see `docs/DEVICE_ACCEPTANCE.md` and `packages/vpn_core/lib/src/diagnostics/redaction.dart`'s doc comments for the actual, current behavior (no destination history by default, no payload capture, probes only run when a user explicitly taps "Run connectivity tests," public-IP lookup only when explicitly requested).
  - UPDATE (verified against current `origin/main`, superseding this bullet's earlier text): Sentry (`sentry_flutter`/`sentry_dart_plugin`) has since been **fully removed** from `pubspec.yaml`, not merely stubbed — see `docs/CLIENT_PRODUCTION_BASELINE.md` "Telemetry". No replacement third-party telemetry/crash SDK was introduced. State this plainly and accurately in the privacy policy (no third-party crash/analytics SDK) rather than the older "depends on whether Sentry is enabled" framing.
  - The still-open, real dependency to disclose: `RemoteConfigManager` contacts first-party Karing infrastructure at runtime for notices/config/geo-rulesets/update metadata (`karing.app`/`x31415926.top`/`github.com/KaringX/*` — see `docs/CLIENT_PRODUCTION_BASELINE.md` "Telemetry", DEFERRED item). This is a real, currently-wired-in network dependency beyond the user's own VPN server and belongs in the privacy policy.
  - Whether the app connects to any OTHER first-party backend beyond the above and the user's configured `singbox-vpn` server (subscription fetch endpoint, update-check endpoint, etc.) — `TODO(you):` enumerate exhaustively before publishing the policy.
  - The server operator's own data practices are out of this app's control and out of scope for this app's privacy policy — but the policy should say plainly that traffic is routed to a user-configured third-party server, since App Review has flagged VPN apps for privacy-policy ambiguity on this point before.
- [ ] Add the privacy policy URL in App Store Connect (App Information → Privacy Policy URL) — required for every app, mandatory (not just recommended) for VPN apps specifically.

## Pre-use VPN data disclosure

Apple requires a VPN app to disclose, **before the user grants the VPN
permission** (i.e., before the system's "Allow VPN configuration"
prompt), what the app does with their network data.

- [ ] `TODO(you):` design and implement an in-app disclosure screen shown before the first `NEVPNManager`/`NETunnelProviderManager` permission request. UPDATE: the VPN start flow itself (`VPNService`/`ProxyConfig`) is real and reconstructed as of current `origin/main` (`docs/ARCHITECTURE.md` §9) — a real flow now exists to attach this screen to; it still needs to be designed and added, this is not automatically satisfied by the flow existing.
- [ ] The disclosure's actual content must match reality: data is routed
  through the user's configured `singbox-vpn` server; this app does not
  itself log destination history by default (`packages/vpn_core`'s
  diagnostics module — see above); no third-party crash/analytics SDK is
  present (Sentry removed, see above); `RemoteConfigManager`'s
  notice/config/geo-ruleset network calls to Karing infrastructure (see
  above) should be disclosed.
- [ ] Reference this disclosure explicitly in App Review notes (below) so
  reviewers can find it without hunting.

## App Review notes

`TODO(you):` fill in and paste into App Store Connect's "App Review
Information → Notes" field at submission time — a template, not an
answer, since the actual content depends on decisions not yet made:

```
This app is a VPN client implementing VLESS+REALITY and Hysteria2
protocols against a self-hosted / user-configured server
(github.com/David610/singbox-vpn or compatible sing-box deployments).

- The VPN core is `sing-box` (github.com/SagerNet/sing-box), a public,
  open-source project -- see docs/ARCHITECTURE.md for this app's
  integration.
- [TODO(you): provide App Review with working test credentials against a
  real or demo singbox-vpn deployment, OR explain why none can be
  provided (e.g. "users must supply their own server") -- App Review
  routinely rejects VPN apps it cannot actually test end-to-end.]
- [TODO(you): if the app can be used without an active VPN connection --
  e.g. a demo/offline mode -- describe that path, since reviewers who
  cannot connect a real VPN server still need to be able to evaluate
  something.]
- Pre-use VPN data disclosure: [TODO(you): describe where in the app
  flow this appears, per the "Pre-use VPN data disclosure" section
  above.]
```

## App Store privacy answers ("App Privacy" / nutrition label)

**Not filled in here — per this task's explicit instruction, these must
reflect the app's actual behavior, decided and verified by whoever owns
that decision, not guessed.** What this document provides instead: a
worksheet of the actual questions App Store Connect's privacy
questionnaire asks, cross-referenced to where in this codebase the real
answer needs to come from, so filling it out is a lookup rather than a
guess.

| Question (paraphrased from App Store Connect) | Where the real answer lives |
|---|---|
| Does the app collect data linked to the user's identity? | No third-party crash/analytics SDK is present (Sentry fully removed — see "Privacy policy" above); `RemoteConfigManager`'s calls to Karing infrastructure and any future account/subscription-token system still need their own honest answer |
| Does the app collect the user's precise/coarse location? | **Yes, the permission is requested** — verified directly, not assumed: `ios/Runner/Info.plist` declares `NSLocationAlwaysUsageDescription`/`NSLocationUsageDescription`/`NSLocationWhenInUseUsageDescription`/`NSLocationAlwaysAndWhenInUseUsageDescription`, all with the same string: "Karing uses the Location permission to provide users with routing based on WIFI SSID and BSSID rules, without reading your location." Android: `android/app/src/main/AndroidManifest.xml` still declares `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` for the same stated purpose — `ACCESS_BACKGROUND_LOCATION` was since removed as vestigial (`docs/CLIENT_PRODUCTION_BASELINE.md` "Permissions (Android)"; verified absent from the current manifest), so do not describe it as requested on Android anymore. `docs/CLIENT_PRODUCTION_BASELINE.md` itself flags that no runtime permission-request flow was found for this feature, so it may not function end to end today — `TODO(you):` confirm actual behavior before answering. |
| Does the app collect diagnostics/crash data? | No (no crash/analytics SDK present); `packages/vpn_core`'s diagnostics module is user-export-only, see below |
| Does the app track users across apps/websites for advertising? | No advertising SDK is present in `pubspec.yaml` as of this audit — re-verify at release time, since a dependency change could introduce one |
| Does the app collect data NOT linked to identity (e.g. anonymized diagnostics)? | `packages/vpn_core`'s diagnostics module (`docs/DEVICE_ACCEPTANCE.md`) only ever produces data the USER explicitly exports themselves (e.g. taps "Export diagnostics" to paste into a bug report) — it is not automatically transmitted anywhere by this app. State this precisely rather than a blanket "no data collected," since the export mechanism does exist. |

Re-verify every row above at each release — a dependency bump or a new
feature can silently change the correct answer, and App Store Connect's
questionnaire is a point-in-time attestation, not something that stays
correct on its own.
