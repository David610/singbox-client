# Fork Architecture Audit — singbox-client (Karing fork)

Audit date: 2026-08-21
Scope: audit and planning only. No code, branding, or dependency changes were made.
Environment note: this audit was performed in a Linux container with no Flutter/Dart SDK
installed (`flutter`/`dart` not on PATH) and no macOS/Xcode available. All build-related
findings below are static analysis of the repository, not verified compiler/build output,
except where explicitly marked as "attempted".

---

## 1. Executive summary

**This repository, as it stands, cannot build a working Karing/singbox-client app for
Android or iOS.** It is a partial export of the KaringX/karing source tree with the
single most important component — the actual VPN/tunnel engine — removed.

The Flutter app (`lib/`) is a UI and orchestration layer. Every piece of protocol logic
(VLESS, REALITY, XTLS-Vision, Hysteria2, Salamander, sing-box/libbox bindings, TUN setup,
platform `VpnService`/`NetworkExtension` integration) lives in a separate package called
`vpn_service`, declared in `pubspec.yaml` as:

```yaml
vpn_service:
  path: ../vpn-service/
```

That path does not exist in this repository, is not a git submodule, and is not fetched
from any public git remote (it's commented out as a `git:` alternative pointing at
`https://github.com/KaringX/vpn-service.git`, which is not publicly accessible). In
addition, two more local-only source trees are imported by the Dart code but are absent
from the repo entirely:

- `lib/app/local_services/` — imported by 21 files (wraps/re-exports `vpn_service`)
- `lib/app/private/` — imported by 3 files, including `lib/main.dart` (Sentry init, and
  likely other private/telemetry wiring)

Net effect: `flutter pub get` will fail (unresolvable path dependency), and even if that
path were faked locally, the app would still fail to compile because ~24 Dart files
reference packages/modules with zero source present in this repo.

No CI/CD exists (`.github/` contains only issue templates, no workflows). No secrets were
found committed, but `android/key.properties` references an external, non-repo keystore
path (`../../private_for_build/...`) with placeholder-looking passwords — this file should
not ship as-is in a public fork.

**Bottom line:** this is currently a UI shell, not a shippable VPN client. Making it
independently buildable requires either (a) obtaining the private `vpn-service` source
(unlikely to be available, since KaringX keeps it closed), or (b) writing a new
platform-integration layer against public `sing-box`/`libbox` from scratch. Given the
target server project (`singbox-vpn`) and target protocol set (VLESS+REALITY, XTLS-Vision,
Hysteria2, Salamander), option (b) is the only realistic path to an independently
maintained, open-source client.

---

## 2. Is the repo actually buildable?

**No**, for both platforms, for the same root cause.

Evidence:

- `pubspec.yaml:150-152`:
  ```yaml
  vpn_service:
    path: ../vpn-service/
    #git:
      #url: https://github.com/KaringX/vpn-service.git
      #ref: main
  ```
  `../vpn-service/` relative to the repo root does not exist anywhere in this container's
  filesystem (`find / -iname "vpn-service"` / `vpn_service` outside this repo → no
  results). `pubspec.lock` confirms the resolved dependency is `source: path`, `version
  "0.12.15"`, `relative: true` — i.e. the lockfile was generated on a machine that *did*
  have a sibling `vpn-service` checkout, and that checkout was never included when this
  fork was created.

- `lib/app/local_services/` — referenced via `import 'package:karing/app/local_services/vpn_service.dart';`
  in 21 files (`lib/main.dart`, `lib/app/modules/server_manager.dart`,
  `lib/app/modules/remote_config_manager.dart`, `lib/app/modules/setting_manager.dart`,
  `lib/app/modules/proxy_cluster.dart`, `lib/app/modules/auto_update_manager.dart`,
  `lib/app/modules/notice_manager.dart`, `lib/app/modules/biz.dart`,
  `lib/app/modules/board_provider_notice_manager.dart`, most of `lib/screens/*.dart`).
  The directory `lib/app/local_services/` does not exist in the repo at all.

- `lib/app/private/` — referenced by `lib/main.dart` (`sentry_utils_private.dart`),
  `lib/app/modules/board_provider_manager.dart`, `lib/app/modules/board_provider_notice_manager.dart`.
  Directory does not exist.

- Native side confirms the same gap. Android:
  `android/app/src/main/kotlin/com/nebula/karing/TileService.kt` and
  `AutomationCommandReceiver.kt` call `io.nebula.vpn_service.VpnServiceImpl`,
  `VpnServicePlugin`, `VpnState` — all Kotlin classes that live inside the missing
  `vpn_service` plugin's Android sources, not in `android/app/src/main/kotlin/` of this
  repo. `GeneratedPluginRegistrant.java` registers `io.nebula.vpn_service.VpnServicePlugin`
  but that class is not present.

- iOS: `ios/karingService/PacketTunnelProvider.swift` is a **4-line file**:
  ```swift
  import Foundation
  import LibVpnCore

  class PacketTunnelProvider: ExtensionProvider {}
  ```
  `LibVpnCore` and `ExtensionProvider` — i.e. 100% of the Network Extension / packet
  tunnel implementation — come from the same missing external package (its iOS pod, per
  `ios/Podfile.lock`: `vpn_service (0.1.0)` pinned by a checksum, `.symlinks/plugins/vpn_service/ios`,
  not present in this repo either).

- No Flutter/Dart SDK is available in this audit environment, so `flutter pub get` was not
  actually executed against the real pub registry; the conclusion above is derived from
  static inspection of `pubspec.yaml`/`pubspec.lock`/filesystem contents, which is
  sufficient to be certain the resolution would fail (a `path:` dependency to a
  non-existent directory fails deterministically, independent of network access).

### 2.1 What `vpn_service` provides

Based on every call site referencing it, `vpn_service` is a Flutter federated plugin
(Dart API + native Android/iOS/macOS/Windows/Linux implementations) that owns:

- The sing-box/libbox Go core bindings (compiled into native libs, invoked from Kotlin/Swift).
- Outbound/config generation for all supported protocols (VLESS, REALITY, XTLS-Vision,
  Hysteria2, Salamander, and whatever else Karing supports upstream).
- The platform VPN integration: Android `android.net.VpnService` subclass
  (`VpnServiceImpl`), iOS `NEPacketTunnelProvider` subclass (`ExtensionProvider`, exposed
  via `LibVpnCore`), plus macOS/Windows/Linux equivalents (TUN/WinTun handling).
- Proxy/connection state (`vpn_service/state.dart`), the proxy manager
  (`vpn_service/proxy_manager.dart`), and the top-level `vpn_service/vpn_service.dart`
  facade the Dart UI calls into.
- Traffic stats, per-app routing, DNS, and low-level networking glue.

None of this is present in this repository, in any language, for any platform.

### 2.2 Which code paths rely on it

Effectively the entire "does something with the VPN" surface of the app:
- App startup (`lib/main.dart`) — initializes vpn_service state before UI renders.
- Server/profile management (`server_manager.dart`, `remote_config_manager.dart`,
  `setting_manager.dart`, `proxy_cluster.dart`).
- Home screen, server select screen, settings, DNS screens, diversion rules, net
  connections/check screens, in-app webview, backup/sync (LAN + WebDAV) screens.
- Android `TileService` (Quick Settings tile) and `AutomationCommandReceiver` (Tasker/
  automation intents) — both call into `VpnServiceImpl` directly.
- iOS Network Extension target (`karingService`) — is *entirely* `vpn_service`.

In short: remove `vpn_service` and there is no VPN client left, only a settings/profile UI.

### 2.3 Functionality present upstream but absent here

Everything protocol- and tunnel-related. Confirmed by direct search: the strings
`REALITY`, `Salamander`, and `libbox`/`Libbox` do **not appear anywhere in `lib/`**. Only
one hit for `hysteria` (in `lib/screens/my_profiles_screen.dart`, almost certainly just a
profile-type label/enum value, not protocol logic). This strongly indicates the Dart layer
never constructs protocol configs itself — it hands opaque profile data to `vpn_service`,
which does all protocol-specific work internally. That work is 100% absent from this repo.

### 2.4 Can the missing dependency be reconstructed from public sing-box/libbox?

Partially, with real engineering effort, not a drop-in swap:

- `sing-box` (public, GPL-3.0, SagerNet) already implements VLESS, VLESS+REALITY,
  XTLS-Vision, Hysteria2, and (via `sing-box`'s `hysteria2`/plugin ecosystem or a
  Salamander-capable fork) obfuscation. `libbox` is sing-box's mobile-bindable Go library
  (used by the official SFA — SingBox For Android — and SFI — SingBox For iOS — reference
  apps), which is the natural public replacement API surface.
- However, `vpn_service` is not just "a thin wrapper around libbox" — it also owns the
  platform `VpnService`/`NEPacketTunnelProvider` lifecycle, IPC between the Flutter UI
  isolate and the tunnel process/extension, state synchronization, and Karing-specific
  config translation (profile format → sing-box JSON). None of that plumbing exists in
  this repo either, so it must be written new, informed by the public SFA/SFI reference
  apps' architecture (`github.com/SagerNet/sing-box`, `SFI`/`SFA` open-source apps) rather
  than recovered.
- Realistic conclusion: **rebuildable, not recoverable.** Treat it as "build a new
  `vpn_service`-equivalent plugin against public `libbox`", not "find the missing file."

### 2.5 Other local-path / private / unavailable dependencies

From `pubspec.yaml`, all pinned to **specific commits on `github.com/KaringX/...`** (public
repos, but forked/patched by KaringX, not upstream originals):

| Dependency | Source | Risk |
|---|---|---|
| `vpn_service` | `../vpn-service/` (local path) — **not resolvable, not public** | **Blocking** |
| `flutter_inappwebview` | `KaringX/flutter_inappwebview.git` @ pinned commit | Patched fork of a public plugin |
| `webdav_client_plus` | `KaringX/webdav_client.git` @ pinned commit | Patched fork |
| `android_package_manager` | `KaringX/android_package_manager.git` @ pinned commit | Patched fork |
| `move_to_background` | `KaringX/move_to_background.git` @ pinned commit | Patched fork |
| `window_manager` (override) | `KaringX/window_manager.git` @ pinned commit | Patched fork |

These git-sourced forks *are* publicly fetchable (unlike `vpn_service`), so they don't
block a build by themselves — but see §2.6.

Two more locally-missing Dart source trees (not declared in `pubspec.yaml` as
dependencies, just missing folders under `lib/`):
- `lib/app/local_services/` (21 importers)
- `lib/app/private/` (3 importers, includes Sentry init)

Also present but not a build blocker: `android/key.properties` points at
`../../private_for_build/karing/karing/android/sign/karing.release.keystore`, a path
outside the repo. Building a signed release APK/AAB is not possible without that keystore
(expected/normal for a fork — you'll generate your own).

### 2.6 Supply-chain risk of modified KaringX dependencies

Real, and worth ranking (see §14). Concretely:
- Each `KaringX/*` git dependency is pinned to a commit hash, which is good practice, but
  the *repos themselves* are controlled by a third party (KaringX) with no attached
  license/audit trail visible in this pass — anyone deriving a "trusted VPN client" from
  this tree is trusting KaringX's forks of `flutter_inappwebview`, `window_manager`, etc.,
  not the upstream maintainers.
- `flutter_inappwebview` and `window_manager` are meaningful attack surface (in-app browser
  rendering arbitrary remote content; native window/process control on desktop). A patched
  fork of either is a plausible place to hide something, though nothing malicious was
  found or specifically looked for in this pass (out of scope — static structural audit
  only, not a security code review of third-party fork contents).
- Longer-term recommendation (not executed in this phase): pin to forks only where a real
  patch is needed and documented, mirror the deltas against upstream in an internal repo,
  and prefer upstream + a small patch-set over an opaque third-party fork.

---

## 3. Current architecture (as much as is present)

```
┌─────────────────────────────────────────────────────────────────┐
│                         Flutter app (lib/)                       │
│  screens/  ─────────────────────────────────────────────────┐   │
│    home_screen, server_select_screen, settings_screen,       │   │
│    dns_settings_screen, diversion_rules_screen, ...           │   │
│                          │ calls                               │   │
│  app/modules/  ─────────▼─────────────────────────────────────┤   │
│    server_manager        (profile/subscription state)          │   │
│    remote_config_manager (subscription fetch + parse)           │   │
│    setting_manager        (app + proxy settings)                │   │
│    proxy_cluster          (server group / selection logic)      │   │
│    auto_update_manager, notice_manager, biz, ...                │   │
│                          │ imports                              │   │
│  app/local_services/vpn_service.dart   ← ★ MISSING FROM REPO    │   │
└──────────────────────────┼───────────────────────────────────────┘
                            │  package:vpn_service (Dart API)
                            ▼
        ┌───────────────────────────────────────────┐
        │   vpn_service plugin  ← ★ ENTIRELY MISSING  │
        │   (path: ../vpn-service/, not in this repo) │
        │                                              │
        │  Dart facade: vpn_service.dart, state.dart,  │
        │               proxy_manager.dart             │
        │  Android: io.nebula.vpn_service.*            │
        │           (VpnServiceImpl, VpnServicePlugin) │
        │  iOS/macOS: LibVpnCore (ExtensionProvider)    │
        │  Presumed internals: sing-box/libbox core,    │
        │  protocol config generation (VLESS, REALITY,  │
        │  XTLS-Vision, Hysteria2, Salamander), TUN,    │
        │  DNS, routing rules                            │
        └───────────────────┬───────────────────────────┘
                             │ (would call, if present)
                 ┌───────────┴────────────┐
                 ▼                        ▼
      Android android.net.VpnService   iOS NEPacketTunnelProvider
      (native TUN fd)                  (Network Extension)
                 │                        │
                 └──────────┬─────────────┘
                             ▼
                    sing-box / libbox core
                    (Go, compiled native lib)
                             │
                             ▼
                      Network tunnel / server
                   (e.g. singbox-vpn target server)
```

Everything below the "★ MISSING" boundary is not present in this repository in any form
(Dart, Kotlin, Swift, or Go). The Flutter app only ever talks to `package:vpn_service`'s
public API surface (`vpn_service.dart`, `state.dart`, `proxy_manager.dart`); it never
touches libbox or platform VPN APIs directly.

---

## 4. Android VPN path (as designed — cannot be traced further, code absent)

```
User imports subscription (screens/*_screen.dart, remote_config_manager.dart)
  → profile parsed (presumed inside vpn_service; no parser found in lib/)
  → stored via server_manager.dart / local_storage
  → user selects server (proxy_cluster.dart, server_select_screen.dart)
  → setting_manager.dart builds "start" request
  → package:vpn_service (Dart facade) — MISSING
  → MethodChannel to io.nebula.vpn_service.VpnServicePlugin — MISSING
  → VpnServiceImpl extends android.net.VpnService — MISSING
  → libbox/sing-box native invocation — MISSING
  → TUN fd established, packets routed to sing-box core — MISSING
```

Android-native call sites that *are* present but only reach into the missing plugin:
- `TileService.kt` — Quick Settings tile toggles VPN via
  `io.nebula.vpn_service.VpnServiceImpl.ACTION_START` / `ACTION_STOP`, reads
  `VpnState` (`CONNECTED`/`DISCONNECTED`) — implementation absent.
- `AutomationCommandReceiver.kt` — broadcast receiver for automation (e.g. Tasker) that
  fires the same start/stop actions and reads `VpnServiceImpl.service_file_name` —
  implementation absent.
- `GeneratedPluginRegistrant.java` — registers `VpnServicePlugin`, class absent, so this
  registration would throw/no-op at runtime even if the rest of the app somehow compiled.

**Where protocol-specific parameters would be created:** cannot be determined from this
repo. No REALITY/Salamander/Hysteria2 config-construction code exists in `lib/` or
`android/`. It must live inside `vpn_service`'s Dart or native layer (unknown which,
without the source).

## 5. iOS VPN path (as designed — cannot be traced further, code absent)

```
User imports subscription → profile parsed → stored → server selected
  → package:vpn_service (Dart facade) — MISSING
  → platform channel to iOS-side vpn_service pod — MISSING
  → NEVPNManager / NETunnelProviderManager configuration — MISSING (not in Runner/ either)
  → karingService extension target starts:
      PacketTunnelProvider: ExtensionProvider (from LibVpnCore) — MISSING
  → NEPacketTunnelProvider packet flow → sing-box/libbox — MISSING
```

`ios/karingService/PacketTunnelProvider.swift` is the entire visible iOS tunnel-extension
source in this repo — 4 lines, a bare subclass. `karingService.entitlements` and
`Info.plist` exist (defining the Network Extension target's capabilities/App Group), but
all actual behavior is inherited from `LibVpnCore`, an external framework not vendored
here (arrives via the same missing `vpn_service` pod, per `ios/Podfile.lock`).

**Where REALITY public key/short_id, VLESS flow, Hysteria2 password, and Salamander
obfuscation are configured:** cannot be located. No Swift/Dart source in this repo
constructs or stores these values. They are either generated inside the missing
`vpn_service`/`LibVpnCore` code, or read from parsed profile data whose parser is also
inside that missing package.

**UDP support, DNS config, routing rules, TUN settings:** same conclusion — no evidence in
this repo; entirely inside the missing dependency.

---

## 6. sing-box/core dependency chain

Cannot be traced directly — no `go.mod`, no vendored Go sources, no compiled `.aar`/
`.xcframework`/`.so`/`.a` binaries for a sing-box/libbox core were found in this repository
tree (`bind/windows/` contains only MSVC runtime DLLs — `vcruntime140d.dll`,
`ucrtbased.dll`, `msvcp140d.dll` — i.e. C++ runtime redistributables, not a VPN core).
The dependency chain is presumed to be:

```
this app → package:vpn_service (missing) → libbox (Go, SagerNet/sing-box bindings, missing)
```

No version pin for sing-box/libbox is visible anywhere in this repo (it would live in the
missing package's own `go.mod`/build scripts).

---

## 7. Build environment

Pinned/declared versions found in the repo:

| Tool | Constraint (from repo) | Source |
|---|---|---|
| Dart SDK | `>=3.12.2 <4.0.0` | `pubspec.yaml` |
| Flutter | `>=3.35.0` | `pubspec.yaml` |
| Android Gradle Plugin / Gradle / Kotlin | not fully verified this pass — `android/build.gradle.kts`, `android/gradle/wrapper/gradle-wrapper.properties` exist and were not deeply parsed for exact versions in this pass | `android/` |
| Android `applicationId` | `com.nebula.karing` | `android/app/build.gradle.kts:40` |
| iOS bundle IDs | `com.nebula.karing`, `com.nebula.karing.karingWidget`, `com.nebula.karing.karingService` | `ios/Runner.xcodeproj/project.pbxproj` |
| Xcode / iOS deployment target | not verified this pass (no macOS host available) | — |
| CocoaPods lockfile present | yes, `ios/Podfile.lock`, `macos/Podfile.lock` | — |
| sing-box/libbox version | **not visible anywhere in this repo** | — |

### Commands attempted

`flutter`/`dart` are **not installed** in this audit container (`which flutter dart` →
not found). No build or test command from the requested list
(`flutter --version`, `flutter doctor -v`, `flutter pub get`, `dart format`,
`flutter analyze`, `flutter test`) could be executed. This is stated plainly rather than
faked, per instructions. No Android SDK/emulator and no macOS/Xcode host are available
either, so Android and iOS builds were not attempted.

**To actually validate buildability**, the next session needs either a container image
with the Flutter SDK preinstalled, or network access to install one, plus — separately and
more importantly — a resolution for the missing `vpn_service`/`local_services`/`private`
source trees, since `pub get` will fail before any compiler is even relevant.

---

## 8. Testing gaps

- `test/` contains exactly one file: `widget_test.dart` (the default Flutter template
  smoke test, not inspected in depth this pass but very unlikely to cover VPN/protocol
  logic given the file count).
- No protocol/parser unit tests (VLESS URI parsing, REALITY params, Hysteria2 URI parsing,
  subscription format parsing) exist in this repo, consistent with that logic living
  entirely inside the missing `vpn_service` package.
- No integration tests, no golden tests, no CI-run test suite of any kind.

---

## 9. CI/CD gaps

`.github/` contains only `ISSUE_TEMPLATE/bug_report.yml` and `feature_request.yml`. **No
`.github/workflows/` directory exists — there is no CI/CD pipeline at all today**: no lint,
no analyze, no test run, no build, no release automation.

Everything under "Primary question 4" in the task (PR CI, integration CI, release
pipeline) is **100% greenfield** — nothing to migrate or extend, just design. Per
instructions this phase only designs, does not implement, the pipeline. Recommended shape
(for a later phase):

- **PR CI**: `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`,
  Android debug build, unsigned iOS build (macOS runner only), `flutter pub outdated`/
  license-checker step, secret-scanning (e.g. gitleaks/trufflehog) on the diff.
- **Integration CI**: once a public `vpn_service` replacement exists — subscription
  parser tests, VLESS+REALITY config-generation tests, Hysteria2 config-generation tests,
  and (stretch) live protocol tests against an ephemeral `singbox-vpn` instance spun up in
  the CI job.
- **Release**: tag-triggered, Android AAB+APK build and sign, iOS archive + TestFlight
  upload, GitHub Release with changelog and SHA256 checksums for all artifacts.

This is a design note only — no workflow YAML has been added in this phase.

---

## 10. Licensing / rebranding inventory

- **Upstream license**: `LICENSE` (GPL-3.0) and `LICENSE.md` both present. `LICENSE.md`
  text: "Copyright (C) 2024 by nebula ... GNU General Public License ... **In addition, no
  derivative work may use the name or imply association with this application without
  prior consent.**" — i.e. GPL-3.0 plus an additional non-endorsement/naming restriction.
  This is a licensing nuance to flag, not to advise on (no legal advice given, per
  instructions) — it directly affects the rebranding plan.
- **App/package identity to replace before publishing under a new brand**:
  - Android `applicationId`: `com.nebula.karing` (`android/app/build.gradle.kts`)
  - iOS bundle IDs: `com.nebula.karing`, `com.nebula.karing.karingWidget`,
    `com.nebula.karing.karingService` (`ios/Runner.xcodeproj/project.pbxproj`)
  - Android package/namespace: `com.nebula.karing` (Kotlin sources under
    `android/app/src/main/kotlin/com/nebula/karing/`)
  - App name: `karing` (`pubspec.yaml` `name:`/`description:`)
  - Logos: `logo.png`, `logo-round.png`, `logo-round-macos.png`, `logo-round_grey.png` at
    repo root, plus `ios/Runner/Assets.xcassets/AppIcon.appiconset`
  - README files in ~25 languages, all Karing-branded (`README.md` + `README_*.md`)
- **Hardcoded Karing domains found** (grep over `lib/`):
  - `https://harry.karing.app/assets/bind.js`
  - `https://tools.karing.app/`
  - (search was not exhaustive of every screen/module; a full grep for `karing.app`,
    `.karing.`, and any additional first-party API hosts should be done before rebrand,
    including inside the still-missing `vpn_service`/`private` trees once recovered/rebuilt)
- **Telemetry**: `sentry_flutter`/`sentry_dart_plugin` are dependencies; actual Sentry
  DSN/org/project values are **not** in `pubspec.yaml`'s `sentry:` block (all fields blank)
  and are not in this repo's visible source — they likely live in the missing
  `lib/app/private/sentry_utils_private.dart`, which is exactly the kind of file that
  should never be committed as-is and must be replaced with the new brand's own Sentry
  project (or removed) later.
- **Build signing**: `android/key.properties` references a keystore outside the repo
  (`../../private_for_build/...`) — expected to not be present; a new signing identity
  will be needed regardless.
- **Update/auto-update endpoints**: `auto_update_manager.dart` exists but no hardcoded
  update URL was found in this pass within `lib/`; likely constructed from the same
  `karing.app` domains or from the missing private module — needs a follow-up targeted
  search once more time/budget is available.
- **Firebase**: no `google-services.json`/`GoogleService-Info.plist` found; only unrelated
  `assets/datas/geosite/firebase*.srs` (sing-box geosite rule-set data for routing rules
  named "firebase", not an SDK config file).

Everything in this list must be replaced (identifiers, icons, domains, telemetry) before
publishing a derivative under an independent brand, and the GPL-3.0 "no derivative may use
the name / imply association" clause needs the user's own legal/licensing judgment before
publishing.

---

## 11. Recommended target architecture

High-level direction only (not a redesign of the current app, per phase scope):

1. Keep the existing Flutter UI/app layer (`lib/`) as the starting point — it's a
   reasonably complete profile/settings/subscription UI shell once its missing imports are
   satisfied.
2. Build a **new, first-party, open-source platform plugin** (name TBD, e.g.
   `sb_vpn_service`) that:
   - Wraps public `sing-box`/`libbox` (SagerNet) directly — same approach as the official
     SFA (SingBox for Android) / SFI (SingBox for iOS) reference apps.
   - Implements Android `VpnService` and iOS `NEPacketTunnelProvider` from scratch,
     informed by those public reference implementations.
   - Implements config generation for VLESS, VLESS+REALITY, XTLS-Vision, Hysteria2, and
     Salamander obfuscation, targeting compatibility with the `singbox-vpn` server project.
   - Implements `vless://` and `hysteria2://` URI parsing and sing-box-compatible
     subscription parsing as testable, pure-Dart (or pure-Go, exposed via FFI) modules —
     not opaque native code — so they're auditable and unit-testable, unlike the current
     black-box `vpn_service`.
3. Replace `lib/app/local_services/vpn_service.dart` and `lib/app/private/` with real,
   first-party, committed source (no more phantom local paths).
4. Re-evaluate each `KaringX/*` forked git dependency: upstream where possible, or fork
   under your own org with a documented patch rationale.

## 12. Migration phases (proposed, not started)

1. **Phase 0 (this audit)** — done.
2. **Phase 1 — Unblock the build**: stub out `local_services`/`private`/`vpn_service` with
   minimal, clearly-marked placeholder implementations so `flutter pub get` /
   `flutter analyze` / `flutter test` can actually run and give a real read on the rest of
   the codebase's health.
3. **Phase 2 — New VPN engine**: build the sing-box/libbox-backed replacement plugin
   (Android first, since it's the more tractable platform without macOS hardware
   constraints; iOS second).
4. **Phase 3 — Protocol/subscription correctness**: `vless://`/`hysteria2://` parsing,
   sing-box-compatible subscription import, REALITY/XTLS-Vision/Hysteria2/Salamander
   config generation, validated against `singbox-vpn`.
5. **Phase 4 — CI/CD**: stand up the PR/integration/release pipelines designed in §9.
6. **Phase 5 — Rebrand**: replace all identifiers/icons/domains/telemetry inventoried in
   §10, resolve the GPL naming-restriction question, publish under the new brand.

## 13. Risks, ranked

- **P0 — Blocking**: `vpn_service` (and thus all VPN functionality) is entirely absent
  from the repo and not publicly obtainable. The app does not build. Nothing else matters
  until this is addressed.
- **P0 — Blocking**: `lib/app/local_services/` and `lib/app/private/` are also missing
  local source, independent of the `vpn_service` pub dependency — even a working
  `vpn_service` package would not make `flutter pub get`/compile succeed without these.
- **P1 — High**: No CI/CD exists at all — every future change is unverified until this is
  built.
- **P1 — High**: No tests exist for protocol/parsing logic (because that logic doesn't
  exist in this repo yet) — this is a testing gap that will follow directly from Phase 3.
- **P2 — Medium**: Supply-chain exposure to unaudited `KaringX/*` forked dependencies
  (`flutter_inappwebview`, `window_manager`, `webdav_client_plus`,
  `android_package_manager`, `move_to_background`) — functional today, but third-party
  trust risk for a security-sensitive VPN app.
- **P2 — Medium**: GPL-3.0 + "no derivative may use the name / imply association" clause
  needs resolution before any public rebrand/publish.
- **P3 — Low**: Hardcoded `karing.app` domains, Karing branding/icons/READMEs throughout —
  cosmetic/identity work, mechanical once the engine (P0s) is solved.
- **P3 — Low**: `android/key.properties` points at a non-repo keystore path — expected for
  a fork, just needs a fresh signing identity, not a structural problem.

## 14. Exact next implementation task

**Do not start building UI or protocol features yet.** The single next concrete task,
scoped tightly, is:

> Stub `lib/app/local_services/vpn_service.dart`, `lib/app/private/` (the ~4 files it's
> expected to contain, inferred from import sites), and a minimal `vpn_service` local
> package (pure Dart, no native implementation yet — just enough class/method signatures
> matching every call site found in `lib/`) so that `flutter pub get`, `dart format
> --set-exit-if-changed`, and `flutter analyze` can run to completion and produce a real,
> actionable list of remaining compile errors. This turns "the repo doesn't build" from an
> unverified claim into a fully diagnosed, file-by-file punch list, and is a prerequisite
> for every phase in §12. This should be done in its own follow-up session/PR, not as part
> of this audit-only phase.

---

*This document reflects a static, read-only audit performed without a Flutter/Dart SDK,
without Android SDK/emulator, and without macOS/Xcode. No build was actually executed; all
"cannot build" conclusions are derived from missing files/directories that any toolchain
would also fail on. No code, dependencies, or branding were changed. No commits were made.*
