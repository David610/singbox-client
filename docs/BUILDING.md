# Building

Companion to `docs/ARCHITECTURE.md` (design) and
`docs/FORK_ARCHITECTURE_AUDIT.md` (how the original gap was found). This
document is written to be exact about what has and hasn't actually been
verified, including in this environment (Linux container, no Flutter/Dart
SDK, no Android SDK/emulator, no macOS/Xcode — see "What could not be
verified" below).

## Quick start (once you have Flutter installed)

```sh
git clone <this repo>
cd singbox-client
flutter pub get
flutter test
flutter build apk --debug
```

No sibling repository clone, no manually-fetched private package, and no
undocumented setup step is required for `flutter pub get` or `flutter test`
to succeed — that dependency (`vpn_service: path: ../vpn-service/`) is gone;
see `docs/ARCHITECTURE.md` §2. **`flutter build apk --debug` is expected to
still fail** on a clean clone today, for reasons unrelated to the VPN
architecture — see "Known remaining build blockers" below.

## Prerequisites

| Tool | Version used by this repo |
|---|---|
| Flutter | `>=3.44.2` (`pubspec.yaml`; first stable release with Dart 3.12.2) |
| Dart | `>=3.12.2 <4.0.0` (`pubspec.yaml`) |
| Android compileSdk/targetSdk | 35 (`android/app/build.gradle.kts`) |
| Android minSdk | 26 |
| Kotlin | 2.2.20 (`android/settings.gradle.kts`) |
| Gradle | 8.14.3 (`android/gradle/wrapper/gradle-wrapper.properties`) |
| JDK | 17 |
| iOS deployment target | 13.0 (`packages/vpn_core/ios/vpn_core.podspec`; verify against `ios/Runner.xcodeproj` for the app target's own setting) |
| Go (for the VPN core only) | `1.24.7`+ (`packages/vpn_core/native/singbox-go/go.mod`) |

The Gradle wrapper launchers (`android/gradlew` and `android/gradlew.bat`)
are committed alongside the wrapper JAR and properties. A clean checkout must
not rely on a globally-installed Gradle or on Flutter regenerating these files;
the Android build invokes the checked-in wrapper directly.

None of these were changed by this milestone; they were read from the
existing repo, not upgraded.

## Building the app (Dart/Flutter layer)

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

`flutter test` includes `packages/vpn_core/test/` if you run it from that
package directory (`cd packages/vpn_core && flutter test`); the root
`flutter test` runs the app's own `test/` directory. Both should be run in
CI (see "CI/CD" below).

## Building the Android VPN core

As of this milestone, `packages/vpn_core/android`'s Gradle build
**requires** `libbox.aar` to exist (see `docs/ARCHITECTURE.md` §6/§10) --
`SingBoxVpnService.kt` links against `io.nekohasekai.libbox.*` directly,
not via reflection, so there is no "compiles without the real core"
fallback anymore. `flutter pub get`/`flutter analyze`/`flutter test` at
the Dart level are unaffected (they never invoke this module's Gradle
build); only an actual Android build/release needs the AAR to exist
first. To produce it:

```sh
cd packages/vpn_core/native/singbox-go
go mod tidy                     # verifies the pin still resolves
go build -tags "with_gvisor with_quic with_wireguard with_utls with_clash_api" .
./singbox-go                    # smoke test only, not shipped

./build_android.sh              # requires Android SDK + NDK, JDK 17
# -> writes packages/vpn_core/android/libs/libbox.aar
```

`build_android.sh` clones sing-box at the pinned tag into
`packages/vpn_core/native/singbox-go/.sing-box-checkout/` (or
`$SING_BOX_CHECKOUT` if set) and **aborts if the checked-out commit doesn't
exactly match the pin** in `packages/vpn_core/UPSTREAM_VERSION.md` — see
that file for the upgrade procedure.

Then:

```sh
flutter build apk --debug
```

## Building the iOS VPN core

**Requires macOS + Xcode.** Not available in the environment this document
was written in — see "What could not be verified" below.

```sh
cd packages/vpn_core/native/singbox-go
./build_ios.sh
# -> writes packages/vpn_core/ios/Frameworks/Libbox.xcframework
```

Then:

1. `cd ios && pod install` (`Libbox.xcframework` is deliberately **not**
   vendored via `vpn_core.podspec` — see that file's comments. It is
   already wired directly into the `PacketTunnel` Network Extension
   target's Frameworks build phase in `Runner.xcodeproj/project.pbxproj`,
   which now expects `Libbox.xcframework` to exist at the path
   `build_ios.sh` writes to before that target will build.)
2. `flutter build ios --debug --no-codesign` (or open `Runner.xcworkspace`
   in Xcode and build/run from there for a signed build on a device).

The `PacketTunnel` Network Extension target (bundle id
`com.nebula.karing.PacketTunnel`, matching `VpnCorePlugin.swift`'s
`tunnelBundleIdentifierSuffix`) is already registered in
`ios/Runner.xcodeproj/project.pbxproj`, with `ios/vpnCoreService/*.swift`
as its sources and `Libbox.xcframework` linked to it only (not to the main
`Runner` target). It replaces Karing's own `ios/karingService` target
(see `docs/FORK_ARCHITECTURE_AUDIT.md` §5), which has been removed rather
than repaired — it depended on a `LibVpnCore.framework` built from a
`../bind/apple/` path that does not exist anywhere in this repository.
**This target registration was hand-edited into `project.pbxproj` directly
(text editing, not through Xcode's UI) and has never been opened in Xcode
or built** — see "What could not be verified in this environment" below
for exactly what that means and what to check first.

## What could not be verified in this environment

**Update (CI/CD trustworthiness pass):** this section originally
described the state after the initial Dart/Kotlin/Swift reconstruction,
written with no Flutter SDK, Android SDK/NDK, or macOS available at all.
Since then, a real Flutter SDK, Android SDK/NDK, and JDK 17 were obtained
and every Android bullet below was actually re-verified, not just
re-read: `build_android.sh` was run end-to-end against the pinned
sing-box commit, produced a real `libbox.aar` (all four ABIs), and both
`flutter build apk --debug` and `flutter build apk --release` compiled
`SingBoxVpnService.kt`/`VpnPlatformInterface.kt` against the real
generated `io.nekohasekai.libbox.*` API and linked successfully -- this
surfaced and fixed several real defects (wrong output path in
`build_android.sh`, an invalid `--` inside an XML comment in
`AndroidManifest.xml`, an AGP local-AAR bundling restriction, and two
Kotlin files still referencing the pre-migration `vpn_service` API), all
now fixed (see `docs/CI.md`'s "Known current-state gaps"). The Android
bullet below is kept for its historical verification methodology (how the
Kotlin was cross-checked against real signatures before a compiler was
available) but its risk framing ("not verified by a compiler") no longer
reflects the current state. macOS/Xcode/iOS remains genuinely
unverified in any environment this repository's history has had access
to -- `ios-build.yml`'s first real run is the first actual test of it.

Stated plainly, per this task's own instructions ("never fake a build"):

- **No Flutter/Dart SDK is installed here.** `flutter pub get`,
  `dart format`, `flutter analyze`, `flutter test`, and
  `flutter build apk --debug` were **not run**. All Dart code in
  `packages/vpn_core/` and `lib/app/local_services/`, `lib/app/private/`
  was written and manually re-read for syntax/type correctness, but not
  compiler-checked.
- **No Android SDK/NDK/emulator.** `build_android.sh`, the Gradle files,
  and `SingBoxVpnService.kt`/`VpnPlatformInterface.kt`/
  `VpnCommandServerHandler.kt`/`VpnCorePlugin.kt` were not compiled or
  run against the real generated `io.nekohasekai.libbox.*` Java bindings
  (that requires `gomobile bind` with the Android NDK, neither available
  here). `VpnService`/`Builder`/`ParcelFileDescriptor`/`ConnectivityManager`
  API usage was written against documented Android APIs, not verified by
  a compiler. What WAS done to reduce that risk: every
  `io.nekohasekai.libbox.*` method name/signature used was read directly
  from the pinned v1.13.19 Go source (not guessed), and the Kotlin
  structure (which class implements `PlatformInterface` directly vs. a
  separate wrapper, which methods get real default implementations vs.
  which three only `VpnService` itself can implement) was cross-checked
  against SagerNet/sing-box-for-android's own real, building Android
  client at the matching architecture generation (`main`/1.14.0-rc.1,
  fetched via `git clone` in this session) rather than derived from the
  Go interface alone. The one part of that reference NOT followed
  verbatim: this module puts `PlatformInterface`'s TUN-independent
  default methods in a separate `VpnPlatformInterfaceWrapper` interface
  (mirroring upstream's own split) but keeps `openTun`/
  `autoDetectInterfaceControl`/`sendNotification` directly on
  `SingBoxVpnService` rather than a standalone helper class holding a
  `VpnService` reference -- constructing `android.net.VpnService.Builder`
  (a non-static Java inner class) from outside its own outer instance is
  an edge case with no reference implementation to check it against, so
  this module avoids it entirely by mixing the interface directly into
  the service class, exactly as upstream does.
  The state-machine logic that does NOT depend on Android/libbox
  (`VpnLifecycleState.kt`) IS compiler- and test-verified: see "What WAS
  actually verified" below.
- **No macOS/Xcode/iPhone.** `build_ios.sh` was not run, `Libbox.xcframework`
  was not built, none of `packages/vpn_core/ios/Classes/VpnCorePlugin.swift`
  or `ios/vpnCoreService/{PacketTunnelProvider,PlatformInterface,RunBlocking}.swift`
  were compiled, `ios/Runner.xcodeproj` was never opened in Xcode (the
  `PacketTunnel` Network Extension target registered in `project.pbxproj`
  was added by hand-editing that file's text directly, not through Xcode's
  "New Target" UI — a materially higher-risk way to register a target,
  since nothing here re-derived or validated the project graph the way
  Xcode's own target wizard would), and `xcodebuild`/a signed device
  install/any on-device test (VLESS TCP, Hysteria2 UDP, DNS, IPv4/IPv6,
  sleep/wake, Wi-Fi/cellular transition, repeated connect/disconnect) was
  not run. What WAS done to reduce that risk, in place of an actual build:
  every Go-side interface (`PlatformInterface`, `CommandServerHandler`,
  `TunOptions`, `SetupOptions`, `OverrideOptions`) that
  `PlatformInterface.swift` implements or calls was read directly from the
  pinned `github.com/sagernet/sing-box@v1.13.19` module source (real, not
  guessed), and the exact Swift method signatures, libbox call sequence,
  and TUN-fd retrieval mechanism (`packetFlow.value(forKeyPath:
  "socket.fileDescriptor")` falling back to `LibboxGetTunnelFileDescriptor()`)
  were cross-checked against `SagerNet/sing-box-for-apple`'s own real,
  production Swift source at its `main` branch — the one branch of that
  repo whose `MARKETING_VERSION` (`1.13.19`) exactly matches this
  project's pin (its `stable` branch, pinned to `1.13.0-alpha.21`, was
  fetched too and rejected: it calls a `LibboxNewService`/`LibboxBoxService`
  constructor pair that does not exist in the pinned v1.13.19 Go source,
  confirmed by grepping that module for `^func New` and finding only
  `NewCommandServer`). See `docs/ARCHITECTURE.md` §7 for the full
  verification account and exactly what was trimmed relative to that
  reference and why. Treat all of it as "cross-checked against real,
  matching-version source on both sides of the binding, never compiled or
  run" until an actual `build_ios.sh` run, Xcode build, and device test
  confirm it.
- **What WAS actually verified, with commands run and shown in this
  session:**
  - `github.com/sagernet/sing-box@v1.13.19` resolves via the public Go
    module proxy and its full transitive dependency graph installs
    cleanly (`go mod tidy` in `packages/vpn_core/native/singbox-go/`,
    producing the committed `go.sum`).
  - A Go program importing `github.com/sagernet/sing-box/experimental/libbox`
    at that pinned version **compiles and runs successfully**
    (`go build ... && ./singbox-go`), proving the pin is real and the
    package that Android/iOS gomobile-bind against is reachable and
    buildable, using the exact build tags sing-box's own
    `cmd/internal/build_libbox` uses.
  - The exact upstream commit for the pin
    (`b5ebaa1fc0f2b94256180b95468e73ef53caa27d`, tag `v1.13.19`, dated
    2026-08-17) was read directly from `git log` against a shallow clone of
    that tag, not guessed.
  - The Go struct field names used in `SingBoxConfigBuilder`'s JSON output
    (`option.VLESSOutboundOptions`, `option.OutboundRealityOptions`,
    `option.OutboundUTLSOptions`, `option.Hysteria2OutboundOptions`) were
    read directly from that same pinned source tree, not from memory or
    documentation.
  - The exact Android `-javapkg=io.nekohasekai` flag sing-box's own
    `cmd/internal/build_libbox/main.go` passes to gomobile was read
    directly from that file, confirming `io.nekohasekai.libbox.*` as the
    real generated Java package.
  - `SagerNet/sing-box-for-android` (upstream's own real, building Android
    client for this exact core) was fetched via `git clone` at both its
    `stable` (1.12.23) and `main` (1.14.0-rc.1) branches and read
    directly, not from memory -- this is what let the discrepancy between
    those two branches' `PlatformInterface`/`CommandServerHandler` shapes
    (e.g. `findConnectionOwner`'s return type, `BoxService` vs.
    `CommandServer.startOrReloadService`) be caught and resolved in favor
    of matching the pinned v1.13.19 Go source directly, rather than
    copying whichever branch was fetched first.
  - `VpnLifecycleState.kt` (the Android VPN service's start/stop/reload
    state machine -- no Android or libbox dependency) was **actually
    compiled and its unit tests actually run** in this session: the
    Kotlin 2.2.20 compiler and a JUnit 4 runtime were installed
    standalone (no Android SDK/Gradle involved), `VpnLifecycleState.kt` +
    `VpnLifecycleStateTest.kt` were compiled together, and all 11 tests
    in `VpnLifecycleStateTest.kt` passed. This is a real, executed result
    for the state-machine logic specifically -- not extended to any
    Android- or libbox-dependent file, which still requires the real SDK/
    NDK/toolchain neither available here.

## Known remaining build blockers

See `docs/ARCHITECTURE.md` §9 "Remaining incompatibilities" for the full,
ranked list. The two that will stop `flutter build apk --debug` from
succeeding on a clean clone today, neither of which this milestone's scope
(the VPN-service architecture) covers:

1. `lib/app/utils/` — 57 files, imported by 70 files across `lib/` — does
   not exist in this repository (newly identified in this pass; distinct
   from, and larger than, the `vpn_service` gap this milestone fixed).
2. `VPNService`, `ProxyConfig`, `ServerConfig` — the app's own
   protocol/profile data-model classes, ~130 combined call sites — are not
   reconstructed (their real shape needs either the original source or a
   dedicated UI-integration pass).

## Next implementation task

The single most valuable next step, in order:

1. **Packet-loop wiring — DONE for both Android and iOS, unverified on
   real hardware for either** (`docs/ARCHITECTURE.md` §9 item 1).
   Android: `SingBoxVpnService` implements `PlatformInterface` directly
   and drives a real `CommandServer.startOrReloadService` lifecycle (see
   `docs/ARCHITECTURE.md` §6) — the concrete remaining step is building
   `libbox.aar` (this document, above) and running
   `SingBoxVpnServiceInstrumentedTest` plus a manual device acceptance
   pass against a real `singbox-vpn` server, neither possible in this
   environment (no NDK, no device). iOS: `ExtensionPlatformInterface.openTun`
   applies the tunnel network settings and hands libbox the real TUN fd,
   which libbox then owns for its own packet read/write loop (see
   `docs/ARCHITECTURE.md` §7) — the concrete remaining step is building
   `Libbox.xcframework` (this document, above), opening
   `Runner.xcworkspace` in Xcode to confirm the hand-edited
   `PacketTunnel` target actually builds, and the full physical-device
   test list this milestone specified (VLESS TCP, Hysteria2 UDP, DNS,
   IPv4/IPv6, sleep/wake, Wi-Fi/cellular transition, 10 connect/disconnect
   cycles), none possible in this environment (no macOS, no Xcode, no
   iPhone).
2. Only after that: begin reconstructing `lib/app/utils/` and
   `VPNService`/`ProxyConfig`/`ServerConfig`, file by file, starting with
   whichever the fewest other files depend on — that work should get its
   own dedicated planning pass (it's UI/app-layer work, explicitly out of
   scope for this milestone) rather than being bolted onto the VPN
   architecture task.

## CI/CD (design, not implemented — per this task's scope)

Extends the pipeline design from `docs/FORK_ARCHITECTURE_AUDIT.md` §9 with
the pin-integrity check this milestone introduces:

- **PR CI**: `dart format --set-exit-if-changed`, `flutter analyze`,
  `flutter test` (root + `packages/vpn_core`), Android debug build,
  unsigned iOS build (macOS runner), dependency/license checks, secret
  scanning — plus a new check: `git -C <build_android.sh's checkout>
  rev-parse HEAD` matches `UPSTREAM_VERSION.md`'s pinned commit (this is
  exactly what `build_android.sh`/`build_ios.sh` already assert locally;
  CI should run the same assertion so a silent pin drift fails the build
  loudly instead of shipping a different core than documented).
- **Integration CI**: `packages/vpn_core/test/singbox_config_builder_test.dart`
  already covers VLESS+REALITY and Hysteria2+Salamander config generation
  and URI parsing; extend with live protocol tests against an ephemeral
  `singbox-vpn` (github.com/David610/singbox-vpn) instance once that
  project is reachable from CI.
- **Release**: unchanged from the prior audit's design — Android AAB/APK,
  iOS archive/TestFlight, GitHub Release with changelog and checksums.
