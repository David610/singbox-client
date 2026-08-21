# vpn_core

First-party, in-repo replacement for the missing KaringX `vpn_service`
package (see `docs/FORK_ARCHITECTURE_AUDIT.md` for how that gap was found).

A small typed Dart API (`initialize`, `start`, `stop`, `restart`, `status`,
`statusStream`, `coreVersion`, `getSanitizedLogs` — see `lib/src/vpn_core.dart`)
backed by:

- Android: `android.net.VpnService` (`android/.../SingBoxVpnService.kt`)
- iOS: `NEPacketTunnelProvider` (`../../ios/vpnCoreService/PacketTunnelProvider.swift`)
- Core: a pinned, immutable public `sing-box`/`libbox` revision — see
  `UPSTREAM_VERSION.md`

See `docs/ARCHITECTURE.md` at the repo root for the full design rationale,
and `docs/BUILDING.md` for how to build the native core.

## Status

The typed Dart API, the config builder (VLESS+REALITY / Hysteria2+Salamander
JSON generation and URI parsing), and the Android `VpnService` TUN
lifecycle are implemented and tested. Wiring the established TUN interface
through to the sing-box packet-processing loop (Android: `PlatformInterface.OpenTun`;
iOS: the same, plus `NEPacketTunnelFlow` read/write loop) is the next
implementation task — see docs/ARCHITECTURE.md "Remaining incompatibilities".
