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
| Flutter | `>=3.35.0` (`pubspec.yaml`) |
| Dart | `>=3.12.2 <4.0.0` (`pubspec.yaml`) |
| Android compileSdk/targetSdk | 35 (`android/app/build.gradle.kts`) |
| Android minSdk | 26 |
| Kotlin | 2.2.20 (`android/settings.gradle.kts`) |
| Gradle | 8.14.3 (`android/gradle/wrapper/gradle-wrapper.properties`) |
| JDK | 17 |
| iOS deployment target | 13.0 (`packages/vpn_core/ios/vpn_core.podspec`; verify against `ios/Runner.xcodeproj` for the app target's own setting) |
| Go (for the VPN core only) | `1.24.7`+ (`packages/vpn_core/native/singbox-go/go.mod`) |

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

Then, in Xcode:

1. Uncomment `s.vendored_frameworks` in `packages/vpn_core/ios/vpn_core.podspec`.
2. Add a Network Extension target named to match
   `VpnCorePlugin.swift`'s `tunnelBundleIdentifierSuffix` (`.PacketTunnel`
   by default — either rename the target's bundle id to match, or edit the
   suffix in `packages/vpn_core/ios/Classes/VpnCorePlugin.swift`), with
   `ios/vpnCoreService/PacketTunnelProvider.swift` as its source and
   `Libbox.xcframework` linked to it (not to the main `Runner` target).
3. `cd ios && pod install`
4. `flutter build ios --debug --no-codesign` (or open `Runner.xcworkspace`
   and build/run from Xcode for a signed build on a device).

This mirrors how Karing's own `ios/karingService` Network Extension target
was structured (see `docs/FORK_ARCHITECTURE_AUDIT.md` §5), except
`PacketTunnelProvider.swift` now contains real tunnel logic instead of an
empty subclass of a missing framework.

## What could not be verified in this environment

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
- **No macOS/Xcode.** `build_ios.sh`,
  `packages/vpn_core/ios/Classes/VpnCorePlugin.swift`, and
  `ios/vpnCoreService/PacketTunnelProvider.swift` were not compiled. In
  particular, `LibboxPlatformInterface`'s exact method names are gomobile's
  *generated* Swift binding of a Go interface that **was** read directly
  from the pinned sing-box source (real, verified) — but gomobile's exact
  naming convention for that generated code was not independently
  confirmed against a built `Libbox.xcframework` header, because none was
  built. Treat that file as "structurally correct, naming unverified" until
  a real `build_ios.sh` run + Xcode build confirms it.
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

1. **Packet-loop wiring — DONE for Android, still open for iOS**
   (`docs/ARCHITECTURE.md` §9 item 1). `SingBoxVpnService` now implements
   `PlatformInterface` directly and drives a real `CommandServer.startOrReloadService`
   lifecycle (see `docs/ARCHITECTURE.md` §6) — the concrete remaining
   step for Android is building `libbox.aar` (this document, above) and
   running `SingBoxVpnServiceInstrumentedTest` plus a manual device
   acceptance pass against a real `singbox-vpn` server, neither possible
   in this environment (no NDK, no device). iOS: connect
   `LibboxPlatformInterface.openTun`'s settings through to a real
   `NEPacketTunnelFlow` read/write loop — this remains unstarted.
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
