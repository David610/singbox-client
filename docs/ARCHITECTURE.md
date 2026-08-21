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
   extends android.net.VpnService,     extends NEPacketTunnelProvider
   implements VpnPlatformInterface-    (ios/vpnCoreService/...)
   Wrapper (packages/vpn_core/android/...)
          │                               │
          ▼                               ▼
   `import io.nekohasekai.libbox.*`    `import Libbox` (direct)
   (direct; libbox.aar is a MANDATORY
   Gradle build input as of §6 below
   -- no reflection, no fallback)
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

**This section describes the real, wired packet path** (as of this
milestone), not an architecture-only skeleton. Every Go type/method name
below was read directly from the pinned v1.13.19 source
(`experimental/libbox/{command_server,platform,tun,setup}.go`), not
assumed — see `packages/vpn_core/android/src/main/kotlin/app/singboxclient/vpn_core/`
for the actual Kotlin, which is also cross-checked against
SagerNet/sing-box-for-android's own integration of the same core (both
its `stable`/1.12.23 and `main`/1.14.0-rc.1 branches — `main`'s shape is
what actually matches this pin; `stable` predates a `FindConnectionOwner`
signature change).

```
Dart: VpnCore.start(config)
  -> MethodChannel('vpn_core/methods').invokeMethod('start', {tag, configJson})
  -> VpnCorePlugin.onMethodCall  (packages/vpn_core/android/.../VpnCorePlugin.kt)
       -> android.net.VpnService.prepare(context)   [system permission dialog if needed]
       -> SingBoxVpnService.start(context, tag, configJson)
            -> Libbox.setup(SetupOptions{...})   [once per process]
            -> Intent(ACTION_START) -> SingBoxVpnService.onStartCommand
                 -> startForeground(notification: "Connecting...")   [main thread, promptly]
                 -> executor.execute {   [single background thread -- see below]
                      commandServer = CommandServer(VpnCommandServerHandler(this), this)
                      commandServer.startOrReloadService(configJson, OverrideOptions())
                        -- synchronous; throws on ANY real failure (bad
                           config, listen failure, tun rejection, ...).
                           Internally, on this same call stack, sing-box's
                           tun inbound calls back into
                           SingBoxVpnService.openTun(options: TunOptions):
                             VpnService.Builder()
                               .addAddress(...)      [from options.inet4Address/inet6Address]
                               .addRoute(...)        [from options.inet{4,6}RouteAddress, or 0.0.0.0/0 :: /0 if unset]
                               .addDnsServer(...)    [from options.dnsServerAddress]
                               .setMtu(options.mtu)
                             .establish() -> ParcelFileDescriptor
                      -- only reached if startOrReloadService did NOT throw:
                      publishStatus(CONNECTED)
                    }
```

Socket protection (**"protect underlying outbound sockets from the VPN
loop"**): `SingBoxVpnService.autoDetectInterfaceControl(fd)` calls
`VpnService.protect(fd)`. This is wired into every outbound socket the
router creates when `route.auto_detect_interface: true` (which
`SingBoxConfigBuilder.buildSingleOutboundDocument` always sets) via
`route/network.go`'s dialer-control chain in the pinned source — verified
by reading that call site, not assumed from the interface shape alone.

UDP: `Builder` doesn't need explicit UDP enabling — a `VpnService` TUN
carries both TCP and UDP once established; UDP support is controlled at
the sing-box config level (`udp_timeout` on the `tun` inbound — see
`SingBoxConfigBuilder.buildSingleOutboundDocument`'s `udpEnabled` param,
tested). IPv4 and IPv6 are both applied unconditionally (`options.inet4Address`
and `options.inet6Address` are always both read and both added to the
`Builder`, matching the config's own dual-stack `172.19.0.1/28`/
`fdfe:dcba:9876::1/126` tun addresses).

**Threading**: all libbox calls (`startOrReloadService`/`closeService`/
`close`, all blocking Go calls) run on a single-thread `ExecutorService`,
never Android's main thread. `openTun`/`autoDetectInterfaceControl` are
themselves invoked BY libbox FROM that executor thread (synchronously,
within `startOrReloadService`'s call stack) — `VpnService.Builder.establish()`
and `.protect()` are documented safe to call off the main thread. State
publishing crosses back to the main thread via a `Handler(Looper.getMainLooper())`,
required by Flutter's `EventChannel.EventSink` contract.

**State machine** (`VpnLifecycleState.kt`, unit-tested in
`src/test/kotlin/.../VpnLifecycleStateTest.kt` — no Android/libbox
dependency, runs on the plain JVM): `CONNECTED` is reachable only via
`CONNECTING -> (startOrReloadService succeeds) -> CONNECTED`; any thrown
exception takes `CONNECTING -> INVALID` instead, never `CONNECTED`. A
second `start()` while one is already `CONNECTING`/a stop is
`DISCONNECTING` is rejected outright (not raced); `start()` while already
`CONNECTED` is treated as a reload (matching `VpnCorePlugin.restart`,
which is a plain `start()` — libbox's own `StartOrReloadService` closes
the prior instance internally, so the existing `CommandServer` is reused,
never leaked). `stop()` while already `DISCONNECTED`/`INVALID` is a
harmless no-op. `stop()` (`ACTION_STOP`, `onRevoke`) always runs
`closeService()` -> `close()` on the `CommandServer`, closes the TUN
`ParcelFileDescriptor`, removes the foreground notification, and publishes
`DISCONNECTED` — repeatable indefinitely (verified by
`SingBoxVpnServiceInstrumentedTest.repeatedStartStopIsIdempotentAndAlwaysSettles`,
see the caveat below on what running that test actually requires).

**Missing `libbox.aar` is now a hard Gradle build failure, not a runtime
fallback** (`packages/vpn_core/android/build.gradle`) — a deliberate
policy change from the prior milestone's reflection-based
`LibboxBridge.kt` (deleted this milestone). There is no code path left
that could compile and then silently "succeed" at connecting without a
real core.

Real, verified Android facts used above: `minSdk = 26`, `compileSdk = 35`,
Kotlin `2.2.20`, Gradle `8.14.3`, JDK 17 (all read from the existing
`android/app/build.gradle.kts` and `android/gradle/wrapper/gradle-wrapper.properties`
in this repo — unchanged by this milestone).

**Honest verification caveat**: this environment has no Android
device/emulator and no Android NDK, so `libbox.aar` was never actually
built here and none of the above was compiled or run against the real
generated Java bindings. Every method name and signature was read
directly from the pinned Go source and cross-checked against upstream's
own real, building, running Android client at the same architecture
generation — not guessed — but "read the source and a proven reference
correctly" is not the same claim as "compiled and ran it." The concrete
next step is exactly that: build `libbox.aar`
(`packages/vpn_core/native/singbox-go/build_android.sh`, needs the
Android NDK) and run `SingBoxVpnServiceInstrumentedTest` plus the manual
device acceptance checklist in `docs/DEVICE_ACCEPTANCE.md` on real
hardware against a real `singbox-vpn` server.

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

1. **Packet-loop wiring (P0 for a working tunnel) — DONE for Android,
   STILL OPEN for iOS.** Android: `SingBoxVpnService` now implements
   `PlatformInterface` directly and drives the real `CommandServer.startOrReloadService`
   lifecycle — see §6 for the full, real call chain and its honest
   verification caveat (no device/NDK in this environment to actually
   build `libbox.aar` and run it). iOS: `LibboxPlatformInterface.openTun`
   still only establishes the OS-level tunnel settings and doesn't yet
   run the `NEPacketTunnelFlow` read/write loop — this remains the
   direct next implementation task for iOS specifically. See
   `docs/BUILDING.md` "Next implementation task".

2. **`lib/app/utils/` was ALSO entirely missing (P0) — since reconstructed,
   for real, one file at a time, from call-site usage; see below for what
   remains.**
   While tracing every `package:karing/...` import to find what else was
   missing beyond `vpn_service`/`local_services`/`private` (already known
   from the prior audit), a later pass found that `lib/app/utils/` — 57
   files (`http_utils.dart`, `app_utils.dart`, `singbox_config_builder.dart`,
   `singbox_outbound.dart`, `singbox_dns.dart`, `did.dart`, `log.dart`,
   `sentry_utils.dart`, and 49 more), imported by 70 files across `lib/` —
   did not exist in this repository either.

   **Status as of this pass**: ~40 of those 57 files have been
   reconstructed with real, working implementations, each grep'd against
   every call site in `lib/` for its actual signature (not guessed) and
   backed by dependencies already declared in `pubspec.yaml` (`dio`,
   `archive`, `crypto`, `path_provider`, `webdav_client_plus`,
   `android_package_manager`, `move_to_background`,
   `flutter_local_notifications`, `sentry_flutter`, ...). `lib/app/private/`
   (2 files: `sentry_utils_private.dart`, `app_url_utils_private.dart`) is
   also reconstructed, deliberately blank — see those files' own doc
   comments for why blank is the honest answer there, not a stub.

   A deliberate minority of the 57 are Windows/UWP-only helpers
   (`windows_version_helper.dart`, `windows_tun_fix_utils.dart`,
   `uwp_utils.dart`) or optional integrations with no server-side
   counterpart in this fork (`icloud_utils.dart`, `cloudflare_warp_api.dart`,
   `cloudflare_warp_utils.dart`, `main_channel_utils.dart`'s
   Android-command-channel piece): these report a clear "not available"
   result rather than fabricating protocol/API behavior for a backend that
   doesn't exist, following the same pattern `local_services/vpn_service.dart`
   already established for desktop-only methods.

   **Still not reconstructed** (blocked on §9.3 below, not attempted this
   pass): `proxy_conf_utils.dart`, `auto_conf_utils.dart`,
   `diversion_custom_utils.dart`, `clash_api.dart`,
   `singbox_config_builder.dart`/`singbox_dns.dart`/`singbox_outbound.dart`/
   `singbox_json_utils.dart`, `qrcode_utils.dart`, `backup_and_sync_utils.dart`.
   These all take or return the app's own `ServerConfigGroupItem`/
   `ProxyConfig`/`DiversionRulesGroup` types from §9.3, so reconstructing
   them first and having to redo the work once those types exist would be
   wasted effort — they come immediately after §9.3 in priority order.
   Notably, the missing tree's own file names (`singbox_config_builder.dart`,
   `singbox_outbound.dart`, `singbox_dns.dart`, `singbox_json_utils.dart`)
   suggest upstream Karing's Dart layer *did* build sing-box config JSON
   itself in some form — consistent with, and distinct from,
   `packages/vpn_core`'s own `SingBoxConfigBuilder` (§4), which handles only
   the VLESS+REALITY/Hysteria2 outbound leaf, not the full document.

3. **`VPNService`, `ProxyConfig`, `ServerConfigGroupItem`,
   `ServerDiversionGroupItem`, `DiversionRulesGroup`, `ProxyStrategy`, and
   the `kOutboundTag*`/`SingboxOutboundType` constants are STILL NOT
   reconstructed (P0 — the single largest remaining blocker).** A later
   pass corrected an earlier assumption here: `ServerConfig` itself
   *already exists* for real, in `server_manager.dart` (~2,900 lines,
   present in this fork) — what's actually missing is narrower and more
   concentrated than "the app's own large protocol/profile data-model
   classes" implied. It's specifically the Dart facade of the deleted
   `package:vpn_service` plugin (`vpn_service/state.dart`,
   `vpn_service/vpn_service.dart`, `vpn_service/proxy_manager.dart`),
   imported directly by only 17 files
   (`grep -rn "import 'package:vpn_service" lib/`) but defining types used
   ~100-150 times each across `server_manager.dart`, `proxy_cluster.dart`,
   `setting_manager.dart`, `remote_config_manager.dart`, and the screens
   that read their state (1,003 of the 1,898 `flutter analyze` errors
   found this pass trace back to these undefined names — see the "Current
   status" note below `## 2` for the live count).

   Their real shape (field names, types) is knowable — every call site
   that reads or writes one is real, present, un-obfuscated app code — but
   extracting it means reading `server_manager.dart` end to end (not
   grep-sampling it), since e.g. `ServerConfigGroupItem` alone has ~140
   distinct call sites across `.fromJson()`/`.toJson()`/`.clone()`/
   `.getByTag()` and a dozen fields (`enable`, `groupid`, `providerId`,
   `servers: List<ProxyConfig>`, `traffic: SubscriptionTraffic?`, `type:
   SubscriptionLinkType`, ...) whose types themselves need defining first.
   This is real, substantial, single-threaded reverse-engineering work,
   not a mechanical rename — doing it from fragments would mean guessing
   field shapes with no ground truth, which the task this document exists
   for explicitly rules out. Once these types exist, wiring `VPNService`'s
   actual VPN-affecting methods (start/stop/status) to `vpn_core` is the
   direct, already-designed mapping described in §§2-3 above; the bulk of
   the remaining effort is the data model, not the `vpn_core` wiring.

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

**Bottom line, updated**: `flutter pub get` resolves cleanly (verified with
a real Flutter 3.44.9 SDK, matching `docs/CI.md`'s pin — the blocking
private path dependency is gone). A real `flutter analyze` run against a
clean checkout found 1,898 errors, not the "flutter/dart not installed,
untested" state of the original audit; a later pass brought that to 1,003
by reconstructing ~40 of the 57 missing `lib/app/utils/` files (finding
#2) and both `lib/app/private/` files, with real implementations backed by
already-declared dependencies, not stubs. The remaining ~1,003 errors are
now overwhelmingly concentrated in one place: finding #3
(`VPNService`/`ProxyConfig`/`ServerConfigGroupItem`/
`ServerDiversionGroupItem`/`DiversionRulesGroup` and friends, from the
deleted `package:vpn_service` Dart facade) plus the handful of
`lib/app/utils/` files that depend on those same types (listed under
finding #2 above). `flutter build apk --debug` still fails on a clean
clone until finding #3 is done. See `docs/BUILDING.md` for what was and
wasn't verified, and finding #3 above for the concrete next-session scope.

## 10. Why `libbox.aar`/`Libbox.xcframework` aren't committed

They are Go build output (compiled native code, hundreds of MB across
architectures), not source — committing them would mean trusting a binary
blob nobody can review or diff, exactly the "unaudited third-party binary"
risk this milestone is trying to move away from. Instead:
`native/singbox-go/build_android.sh`/`build_ios.sh` reproduce them
deterministically from the pinned, hash-verified source on demand (§5).

Unlike the prior milestone, `packages/vpn_core/android`'s Gradle build no
longer compiles without `libbox.aar` present (see §6, "Missing `libbox.aar`
is now a hard Gradle build failure") — the old reflection boundary
(`LibboxBridge.kt`, deleted) that let the module compile regardless is
gone by design: a Kotlin service that links against the real core
directly cannot also silently compile into something that claims to
connect without it. `flutter pub get`/`flutter analyze`/`flutter test` at
the Dart level are unaffected (they never invoke this module's Gradle
build); only an actual Android build/release now requires the AAR to
exist first — see `docs/BUILDING.md`.
