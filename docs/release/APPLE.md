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

- [x] **Already declared** in this repository's entitlements (verified by reading the files directly, not assumed):
  - `ios/Runner/Runner.entitlements`: `com.apple.developer.networking.networkextension` = `["packet-tunnel-provider"]`
  - `ios/karingService/karingService.entitlements` (the OLD, currently-unbuildable extension target — see `docs/FORK_ARCHITECTURE_AUDIT.md` §5): same entitlement
- [ ] **The Network Extension capability itself must still be requested from Apple** for your specific bundle ID / Team ID via the Apple Developer portal (Certificates, Identifiers & Profiles → your App ID → capabilities). This is a per-account, per-app-ID grant Apple reviews — it is not automatically available just because the entitlement is present in a project file. `TODO(you):` request it, record the approval date here.
- [ ] Once `ios/vpnCoreService/PacketTunnelProvider.swift` is wired into a real Xcode target (`docs/BUILDING.md` "iOS", `docs/ARCHITECTURE.md` §7), create `ios/vpnCoreService/vpnCoreService.entitlements` mirroring the same `packet-tunnel-provider` entitlement and App Group as the files above — don't invent a new App Group ID; reuse `group.com.nebula.karing` (or its post-rebrand replacement — see `docs/FORK_ARCHITECTURE_AUDIT.md` §10) so the app and extension can share state via the same container.

## Packet Tunnel Provider entitlement

- [x] `com.apple.developer.networking.networkextension: packet-tunnel-provider` is the correct, specific entitlement value for a `NEPacketTunnelProvider`-based VPN client (not `app-proxy-provider`, `content-filter-provider`, or others in that array) — confirmed against Apple's own NetworkExtension documentation.
- [ ] Provisioning profiles for **both** the main app target and the (once-registered) extension target must include this entitlement — a profile generated before the capability was approved on the App ID will not have it; regenerate after approval.

## Privacy policy

- [ ] `TODO(you):` publish a privacy policy at a stable, public URL. A VPN app's privacy policy is under unusually high scrutiny (App Review specifically checks this for VPN/proxy apps) — it must accurately describe:
  - What `packages/vpn_core`'s diagnostics module does and does not collect — see `docs/DEVICE_ACCEPTANCE.md` and `packages/vpn_core/lib/src/diagnostics/redaction.dart`'s doc comments for the actual, current behavior (no destination history by default, no payload capture, probes only run when a user explicitly taps "Run connectivity tests," public-IP lookup only when explicitly requested).
  - Whether Sentry (`sentry_flutter`/`sentry_dart_plugin`, present in `pubspec.yaml`) is actually enabled in this build and what it sends if so — `lib/app/private/sentry_utils_private.dart` is currently a no-op stub (`docs/FORK_ARCHITECTURE_AUDIT.md` §10); if/when a real Sentry DSN is wired in, the privacy policy must be updated to match, not the other way around.
  - Whether the app connects to any first-party backend beyond the user's configured `singbox-vpn` server (subscription fetch endpoint, update-check endpoint, etc.) — `TODO(you):` enumerate these once the app's networking layer (`lib/app/utils/`, currently missing — `docs/ARCHITECTURE.md` §9) is reconstructed and its actual behavior is known, not before.
  - The server operator's own data practices are out of this app's control and out of scope for this app's privacy policy — but the policy should say plainly that traffic is routed to a user-configured third-party server, since App Review has flagged VPN apps for privacy-policy ambiguity on this point before.
- [ ] Add the privacy policy URL in App Store Connect (App Information → Privacy Policy URL) — required for every app, mandatory (not just recommended) for VPN apps specifically.

## Pre-use VPN data disclosure

Apple requires a VPN app to disclose, **before the user grants the VPN
permission** (i.e., before the system's "Allow VPN configuration"
prompt), what the app does with their network data.

- [ ] `TODO(you):` design and implement an in-app disclosure screen shown before the first `NEVPNManager`/`NETunnelProviderManager` permission request — not yet implemented (VPN start flow itself is part of the still-unreconstructed `VPNService`/`ProxyConfig` UI layer, `docs/ARCHITECTURE.md` §9, so there is no existing flow to attach this to yet).
- [ ] The disclosure's actual content must match reality once known:
  data is routed through the user's configured `singbox-vpn` server; this
  app does not itself log destination history by default
  (`packages/vpn_core`'s diagnostics module — see above); whether/how
  telemetry (Sentry) is enabled must be stated accurately per the
  privacy-policy item above.
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
| Does the app collect data linked to the user's identity? | Depends on whether Sentry is actually enabled (`lib/app/private/sentry_utils_private.dart` — currently a no-op) and whether any account/subscription-token system is added later |
| Does the app collect the user's precise/coarse location? | **Yes, the permission is requested** — verified directly, not assumed: `ios/Runner/Info.plist` declares `NSLocationAlwaysUsageDescription`/`NSLocationUsageDescription`/`NSLocationWhenInUseUsageDescription`/`NSLocationAlwaysAndWhenInUseUsageDescription`, all with the same string: "Karing uses the Location permission to provide users with routing based on WIFI SSID and BSSID rules, without reading your location." (`android/app/src/main/AndroidManifest.xml` similarly declares `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`/`ACCESS_BACKGROUND_LOCATION` — Android requires location permission to read the current Wi-Fi SSID/BSSID, which is the same stated purpose.) The stated purpose is Wi-Fi-based routing rules, not location tracking — `TODO(you):` verify this claim is still true against the actual reconstructed networking code once `lib/app/utils/` exists (`docs/ARCHITECTURE.md` §9), since the App Store privacy answer must match real behavior, not just this string's stated intent. If the permission is unused or removable, consider dropping it — an unused sensitive permission is itself a common App Review friction point for VPN apps. |
| Does the app collect diagnostics/crash data? | Same as the identity question — depends on whether Sentry is enabled in the shipped build |
| Does the app track users across apps/websites for advertising? | No advertising SDK is present in `pubspec.yaml` as of this audit — re-verify at release time, since a dependency change could introduce one |
| Does the app collect data NOT linked to identity (e.g. anonymized diagnostics)? | `packages/vpn_core`'s diagnostics module (`docs/DEVICE_ACCEPTANCE.md`) only ever produces data the USER explicitly exports themselves (e.g. taps "Export diagnostics" to paste into a bug report) — it is not automatically transmitted anywhere by this app. State this precisely rather than a blanket "no data collected," since the export mechanism does exist. |

Re-verify every row above at each release — a dependency bump or a new
feature can silently change the correct answer, and App Store Connect's
questionnaire is a point-in-time attestation, not something that stays
correct on its own.
