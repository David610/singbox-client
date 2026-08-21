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

The Dart/Kotlin/Manifest side of `vpn_core` compiles without the real
sing-box core (see `docs/ARCHITECTURE.md` §10, "Why libbox.aar isn't
committed" and `LibboxBridge.kt`'s reflection boundary). To get an actually
functional tunnel:

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
  and `SingBoxVpnService.kt`/`VpnCorePlugin.kt`/`LibboxBridge.kt` were not
  compiled or run. `VpnService`/`Builder`/`ParcelFileDescriptor` API usage
  was written against documented Android APIs, not verified by a compiler.
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
    real generated Java package (used in `LibboxBridge.kt`).

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

1. **Packet-loop wiring** (`docs/ARCHITECTURE.md` §9 item 1): connect
   `SingBoxVpnService`'s established `ParcelFileDescriptor` (Android) and
   `LibboxPlatformInterface.openTun`'s settings (iOS) through to a real
   `libbox.NewCommandServer`/`BoxService` instance, so a config actually
   starts moving packets. This is scoped, testable in isolation (once
   `libbox.aar`/`Libbox.xcframework` are built per this document), and
   does not require touching `lib/`.
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
