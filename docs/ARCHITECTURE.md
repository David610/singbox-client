# Architecture

This document describes the target architecture for the VPN engine boundary
in this fork, replacing KaringX's missing/private `vpn_service` package with
a first-party package (`packages/vpn_core`) built on a pinned public
`sing-box`/`libbox` core. It assumes you've read
`docs/FORK_ARCHITECTURE_AUDIT.md` (the prior audit-only pass that found the
gap this document addresses).

Companion document: `docs/BUILDING.md` (how to actually build each piece).

## 1. What `vpn_service` previously provided

See `docs/FORK_ARCHITECTURE_AUDIT.md` §2.1 for the full account. In short:
100% of the protocol/tunnel engine — sing-box/libbox bindings, VLESS/REALITY/
XTLS-Vision/Hysteria2/Salamander config handling, TUN setup, and the Android
`VpnService` / iOS `NEPacketTunnelProvider` implementations — lived in that
package, and none of it was present in this repository, in any language,
for any platform.

## 2. What replaced it: `packages/vpn_core`

```
Flutter app (lib/)
      │
      │  package:vpn_core  (packages/vpn_core/lib/vpn_core.dart)
      ▼
┌─────────────────────────────────────────────────────────────┐
│ VpnCore (7 methods: initialize, start, stop, restart,        │
│          status, statusStream, coreVersion, getSanitizedLogs)│
│                         │                                     │
│              VpnCorePlatform (plugin_platform_interface)      │
│                         │                                     │
│              MethodChannelVpnCore                              │
│         MethodChannel('vpn_core/methods')                      │
│         EventChannel('vpn_core/status')                        │
└───────────────────────┬────────────────────────────────────────┘
                         │
          ┌──────────────┴───────────────┐
          ▼                               ▼
   Android                            iOS
   VpnCorePlugin.kt                   VpnCorePlugin.swift
   (MethodChannel handler,            (NETunnelProviderManager
    VPN permission flow)               config + start/stop)
          │                               │
          ▼                               ▼
   SingBoxVpnService.kt                PacketTunnelProvider.swift
   extends android.net.VpnService      extends NEPacketTunnelProvider
   (packages/vpn_core/android/...)     (ios/vpnCoreService/...)
          │                               │
          ▼                               ▼
   LibboxBridge.kt (reflection)        `import Libbox` (direct)
          │                               │
          └───────────────┬───────────────┘
                           ▼
              io.nekohasekai.libbox.* (Android)  /  Libbox.xcframework (iOS)
              gomobile bindings of experimental/libbox
                           │
                           ▼
              github.com/sagernet/sing-box v1.13.19 (PINNED)
              commit b5ebaa1fc0f2b94256180b95468e73ef53caa27d
              (packages/vpn_core/native/singbox-go/go.mod, verified
               to resolve and compile in this environment -- see
               docs/BUILDING.md)
```

`packages/vpn_core` lives **in this repository**, under version control,
with its own tests (`packages/vpn_core/test/`). It is not a private path
dependency and not tracked to a moving branch — see §5.

## 3. Why the Dart↔native boundary is 7 methods, not a plugin surface

`VpnCorePlatform` (`packages/vpn_core/lib/src/vpn_core_platform_interface.dart`)
exposes exactly:

```
initialize()
start(VpnCoreConfig)
stop()
restart(VpnCoreConfig)
status() / statusStream()
coreVersion()
getSanitizedLogs({maxLines})
```

Nothing else crosses the Dart↔native boundary. In particular:

- **No per-protocol methods.** `VpnCoreConfig.singBoxConfigJson` is a
  complete, pre-built sing-box configuration document. Protocol logic
  (VLESS+REALITY, Hysteria2+Salamander) is Dart-side, in
  `SingBoxConfigBuilder` (`packages/vpn_core/lib/src/config/singbox_config_builder.dart`),
  producing JSON matching sing-box's own documented `option.*` schema —
  never native code, never a wire-protocol reimplementation.
- **No raw file descriptors, no platform-specific types.** The native side
  owns TUN lifecycle entirely; Dart never sees a fd or a `VpnService`/
  `NEPacketTunnelProvider` instance.
- **No settings/preferences surface.** Where the app used to reach into
  `vpn_service`'s state/proxy-manager objects directly (`VPNService`,
  `ProxyConfig`, `ServerConfig` — see §7), those are app-level concerns and
  do not belong on this boundary even once reconstructed.

Rationale: every method added here is a method every platform must
implement correctly and every future core swap must preserve. A small,
stable surface is what makes "swap sing-box for something else later" or
"add Windows/Linux/macOS support" tractable; a large ad hoc surface (the
shape `vpn_service` apparently had, given `VPNService`'s ~65 call sites)
is exactly what made the original package unrecoverable when its source
was lost.

## 4. Config generation: preserving VLESS+REALITY and Hysteria2

`SingBoxConfigBuilder` (tested in
`packages/vpn_core/test/singbox_config_builder_test.dart`) provides:

- `parseVlessRealityUri(String)` — parses `vless://uuid@host:port?security=reality&flow=...&sni=...&pbk=...&sid=...&fp=...#tag`.
- `parseHysteria2Uri(String)` — parses `hysteria2://` and `hy2://` share
  links, including `?obfs=salamander&obfs-password=...`.
- `VlessRealityParams.toOutboundJson()` / `Hysteria2Params.toOutboundJson()`
  — produce sing-box outbound JSON. Field names (`uuid`, `flow`,
  `tls.reality.public_key`, `tls.reality.short_id`, `tls.utls.fingerprint`,
  `obfs.type`/`obfs.password`, `password`) were taken directly from sing-box
  `option.VLESSOutboundOptions`, `option.OutboundRealityOptions`,
  `option.OutboundUTLSOptions`, and `option.Hysteria2OutboundOptions`
  (verified by reading that source at the pinned v1.13.19 tag — see
  `packages/vpn_core/UPSTREAM_VERSION.md`), not guessed or copied from
  memory.
- `buildSingleOutboundDocument(...)` — wraps one outbound in a minimal
  `tun` inbound + routing document, with `udp_timeout` present (UDP
  enabled) unless explicitly disabled — see §6.

No cryptography, TLS, REALITY handshake, or Hysteria2/QUIC wire logic is
implemented anywhere in `vpn_core` or the app. All of that runs inside the
pinned sing-box core, as required.

## 5. Pinning the core

`packages/vpn_core/native/singbox-go/go.mod` requires
`github.com/sagernet/sing-box v1.13.19` — a specific stable release tag,
not `main`, not a branch, not a floating pseudo-version. `go.sum` (also
committed) locks every transitive dependency's hash. `build_android.sh` /
`build_ios.sh` additionally hard-code the exact commit
(`b5ebaa1fc0f2b94256180b95468e73ef53caa27d`) and **refuse to build** if a
freshly cloned checkout of the pinned tag doesn't match that commit
exactly — see `packages/vpn_core/UPSTREAM_VERSION.md` "Where the pin
lives" for the full mechanism and the upgrade procedure.

This was verified to actually resolve and compile in this environment
(no NDK/Xcode required for this level of verification):

```
$ cd packages/vpn_core/native/singbox-go && go mod tidy && \
  go build -tags "with_gvisor with_quic with_wireguard with_utls with_clash_api" .
$ ./singbox-go
pinned sing-box/libbox version: unknown   # ldflags unset outside the real build_libbox tooling; see below
```

("unknown" is expected here — the real version string is injected via
`-ldflags -X .../constant.Version=...` by sing-box's own build tooling,
which `build_android.sh`/`build_ios.sh` invoke; this smoke test only proves
the module resolves and the package compiles against the pin, which is
what it's for.)

## 6. Android path

```
Dart: VpnCore.start(config)
  -> MethodChannel('vpn_core/methods').invokeMethod('start', {tag, configJson})
  -> VpnCorePlugin.onMethodCall  (packages/vpn_core/android/.../VpnCorePlugin.kt)
       -> android.net.VpnService.prepare(context)   [system permission dialog if needed]
       -> SingBoxVpnService.start(context, tag, configJson)
            -> Intent(ACTION_START) -> SingBoxVpnService.onStartCommand
                 -> LibboxBridge.checkConfig(configJson)   [libbox.CheckConfig, reflection]
                 -> VpnService.Builder()
                      .addAddress(...) .addRoute(0.0.0.0/0, ::/0)
                      .addDisallowedApplication(packageName)
                      .setMtu(9000) .setBlocking(false)
                    .establish()  -> ParcelFileDescriptor
                 -> startForeground(notification)   [required by Android for a long-running VpnService]
                 -> publishStatus(CONNECTED)
```

UDP: `Builder` doesn't need explicit UDP enabling — a `VpnService` TUN
carries both TCP and UDP once established; UDP support is controlled at
the sing-box config level (`udp_timeout` on the `tun` inbound — see
`SingBoxConfigBuilder.buildSingleOutboundDocument`'s `udpEnabled` param,
tested).

**Not yet wired**: the established `ParcelFileDescriptor` is not yet handed
to libbox's `PlatformInterface.OpenTun` / `CommandServer` — see §7.

Real, verified Android facts used above: `minSdk = 26`, `compileSdk = 35`,
Kotlin `2.2.20`, Gradle `8.14.3`, JDK 17 (all read from the existing
`android/app/build.gradle.kts` and `android/gradle/wrapper/gradle-wrapper.properties`
in this repo — unchanged by this milestone).

## 7. iOS path

```
Dart: VpnCore.start(config)
  -> MethodChannel('vpn_core/methods').invokeMethod('start', {tag, configJson})
  -> VpnCorePlugin.handle(...)  (packages/vpn_core/ios/Classes/VpnCorePlugin.swift)
       -> NETunnelProviderManager.loadAllFromPreferences / create + save
       -> manager.connection.startVPNTunnel(options: ["configJson": ...])
            [configJson crosses via NEVPNConnection's private options
             dictionary -- Apple's documented mechanism for exactly this,
             never a launch argument, never logged]
  -> (new process) PacketTunnelProvider.startTunnel(options:)
       (ios/vpnCoreService/PacketTunnelProvider.swift)
         -> LibboxCheckConfig(configJson)
         -> LibboxNewBoxService(configJson, LibboxPlatformInterface(self))
         -> service.start()
```

`LibboxPlatformInterface` implements the Go-side `PlatformInterface`
contract (`experimental/libbox/platform.go` in the pinned sing-box source —
`OpenTun`, `UseProcFS`, `UsePlatformAutoDetectInterfaceControl`,
`FindConnectionOwner`, `GetInterfaces`, `UnderNetworkExtension`,
`ReadWIFIState`, `SystemCertificates`, `ClearDNSCache`,
`SendNotification`, ...). `openTun` calls
`NEPacketTunnelProvider.setTunnelNetworkSettings(_:completionHandler:)` —
the documented, App Store-safe way to establish the tunnel interface on
iOS (there is no raw fd handoff like Android's `ParcelFileDescriptor`;
NetworkExtension instead exposes `packetFlow` for reading/writing packets).

**Important caveat, stated plainly**: this repository has no macOS/Xcode
host, so `Libbox.xcframework` was never actually built or linked in this
environment, and `LibboxPlatformInterface`'s exact Swift method names/types
are gomobile's *generated* binding of the Go interface above — the Go
interface itself was read directly from the pinned source (real), but the
precise Swift spelling gomobile emits should be checked against the
generated header the first time `Libbox.xcframework` is actually built
(`packages/vpn_core/native/singbox-go/build_ios.sh`). See
`docs/BUILDING.md` "What could not be verified in this environment".

**Not yet wired**: the `NEPacketTunnelFlow` read/write loop that actually
moves packets between the OS and libbox once `openTun` returns — see §9.

## 8. Security implications

- **Credentials never logged.** `VlessRealityParams`/`Hysteria2Params`
  override `toString()` to redact `uuid`/`publicKey`/`password`/
  `salamanderPassword`; this is unit-tested
  (`singbox_config_builder_test.dart`, "toString never leaks..." cases).
  `VpnCorePlatform.getSanitizedLogs` is documented to never return raw
  config JSON or a field named `uuid`/`password`/`public_key`/`short_id`
  once real log streaming is wired (§9) — enforced today by
  `SingBoxVpnService.sanitizedLogs()` returning a fixed placeholder rather
  than anything derived from config.
- **Config crosses the boundary as an opaque JSON string**, not as
  discrete typed fields — this means neither `VpnCorePlugin.kt` nor
  `VpnCorePlugin.swift` ever need to know a credential's field name to
  route it correctly, shrinking the surface that could accidentally log or
  mishandle one.
- **iOS**: `configJson` is passed through `NEVPNConnection`'s `options`
  dictionary at `startVPNTunnel(options:)`, which is the platform's
  intended private channel for provider configuration — not a
  `UserDefaults`/App Group file (which would be readable by any process in
  the same App Group) and not a process launch argument (visible via
  `ps`/crash logs).
- **Android**: `SingBoxVpnService.checkConfig`/config handling never
  writes `configJson` to `Log.*`; only the resolved `tag` (a
  non-credential display label) appears in the foreground notification and
  logs.
- **REALITY's public key and short ID** are technically public-by-protocol
  values (not secret), but are still treated as credential-adjacent and
  redacted for consistency and to avoid setting a precedent of "some
  server-identifying values are fine to log."
- **`libbox.aar`/`Libbox.xcframework` are build outputs, never committed**
  (see §10) — this also means no prebuilt native binary from a third party
  is trusted blindly; every developer (and CI, once built per
  `docs/BUILDING.md` §CI) produces it from the pinned, hash-verified source
  themselves.

## 9. Remaining incompatibilities (honest accounting)

This milestone delivers the **architecture**: a real, tested, pinned,
in-repo `vpn_core` package with a correct `VpnService`/
`NEPacketTunnelProvider` skeleton on both platforms. It does **not** yet
deliver a fully working tunnel, and does **not** yet make the whole `lib/`
tree compile. Specifically, in priority order:

1. **Packet-loop wiring (P0 for a working tunnel).** Android:
   `SingBoxVpnService`'s `ParcelFileDescriptor` is not yet handed to
   libbox's `CommandServer`/`PlatformInterface.OpenTun`. iOS:
   `LibboxPlatformInterface.openTun` establishes the OS-level tunnel
   settings but doesn't yet run the `NEPacketTunnelFlow` read/write loop.
   Until this lands, the VPN permission flow, TUN establishment, and
   config validation are real and working, but no traffic flows. This is
   the direct next implementation task — see `docs/BUILDING.md` "Next
   implementation task".

2. **`lib/app/utils/` is ALSO entirely missing — a newly identified gap,
   larger than the `vpn_service` gap this milestone addresses (P0).**
   While tracing every `package:karing/...` import to find what else was
   missing beyond `vpn_service`/`local_services`/`private` (already known
   from the prior audit), this pass found that **`lib/app/utils/` — 57
   files (`http_utils.dart`, `app_utils.dart`, `singbox_config_builder.dart`,
   `singbox_outbound.dart`, `singbox_dns.dart`, `did.dart`, `log.dart`,
   `sentry_utils.dart`, and 49 more), imported by 70 files across `lib/` —
   does not exist in this repository either.** This was not caught by the
   prior audit pass (which only checked `local_services` and `private`)
   and is **not fixed by this milestone**: reconstructing 57 unknown files
   from grep'd call sites is a separate, much larger effort than the VPN
   architecture work requested here, and doing it by guessing would mean
   fabricating app-wide utility code with no ground truth. Notably, the
   missing tree's own file names (`singbox_config_builder.dart`,
   `singbox_outbound.dart`, `singbox_dns.dart`, `singbox_json_utils.dart`)
   suggest upstream Karing's Dart layer *did* build sing-box config JSON
   itself in some form — consistent with, and now superseded by,
   `packages/vpn_core`'s `SingBoxConfigBuilder` (§4), but the other ~53
   files (HTTP client, device/app utils, logging, backup/sync, QR codes,
   ...) have no equivalent yet.

3. **`VPNService`, `ProxyConfig`, `ServerConfig` are NOT reconstructed
   (P1).** These are the app's own large protocol/profile data-model
   classes (grep found ~65, ~59, and ~7 call sites respectively across
   `server_manager.dart`, `proxy_cluster.dart`, `home_screen.dart`, and
   others) that the pre-existing UI code manipulates directly. Their real
   shape (field names, types) is unknown without either the original
   `vpn_service` source or a dedicated reverse-engineering/UI-integration
   pass — explicitly out of scope here ("do not redesign the UI"). Wiring
   them to `vpn_core` is real, substantial follow-up work, not a
   mechanical rename.

4. **`FlutterVpnService`'s desktop-only methods are stubs (P2).**
   `authorizeService`, `firewallAddPorts`, `getProcessIcon`/
   `getProcessList`, `getAppGroupDirectory`, `hideDockIcon`,
   `setExcludeFromRecents` (Windows/macOS service-elevation and
   per-app-routing helpers) throw `UnimplementedError` or return inert
   defaults in `lib/app/local_services/vpn_service.dart` — out of scope for
   the Android/iOS target this task specified.

5. **iOS Swift binding names are unverified against a real build (P2)** —
   see §7's caveat.

6. **No CI yet** to enforce the pin-mismatch check or run
   `packages/vpn_core/test/` automatically — see `docs/BUILDING.md`'s CI
   section (design only, per the prior audit's scope).

**Bottom line**: `flutter pub get` will now resolve (the blocking private
path dependency is gone, replaced by an in-repo package — requirement 1/13
of this milestone). `flutter build apk --debug` will very likely **still
fail** on a clean clone, because of finding #2 above (`lib/app/utils/`)
and #3 (`VPNService`/`ProxyConfig`/`ServerConfig`) — neither of which is
part of the VPN-service-layer architecture this milestone was scoped to
fix. See `docs/BUILDING.md` for exactly what was and wasn't verified.

## 10. Why `libbox.aar`/`Libbox.xcframework` aren't committed

They are Go build output (compiled native code, hundreds of MB across
architectures), not source — committing them would mean trusting a binary
blob nobody can review or diff, exactly the "unaudited third-party binary"
risk this milestone is trying to move away from. Instead:
`native/singbox-go/build_android.sh`/`build_ios.sh` reproduce them
deterministically from the pinned, hash-verified source on demand (§5),
and `SingBoxVpnService`'s reflection boundary (`LibboxBridge.kt`) lets the
rest of the Android module compile and its tests pass even before a
developer has run that step — see `docs/BUILDING.md`.
