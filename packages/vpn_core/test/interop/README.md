# Protocol interop tests

`reality_interop_test.dart` and `hysteria2_interop_test.dart` drive a real,
pinned `sing-box` binary as both client and server over loopback, using:

- a server config in singbox-vpn's own shape (`server::render_singbox_server_config`
  — see `test/fixtures/singbox_vpn/server_config_reference.json`)
- a client outbound built by **vpn_core's own production code**
  (`VlessRealityParams`/`Hysteria2Params`/`SingBoxConfigBuilder` — the same
  functions `lib/app/local_services/vpn_service.dart` and, eventually, the
  app's profile-import UI call), not hand-written JSON

and assert real traffic flows (and, for a wrong key/password, that it
doesn't). This is exactly the same style of test as singbox-vpn's own
`crates/compat-config/tests/reality_interop.rs` /
`hysteria2_interop.rs` — a real handshake against a real pinned binary, not
a schema check — applied to the client side instead of the server side.

## Scope — read this before trusting a pass

These tests exercise the **sing-box core** and the **exact JSON this
client's config builder generates**. They run over a `mixed` (SOCKS5)
inbound, not a real Android `VpnService` TUN device or an iOS
`NEPacketTunnelProvider`. **A pass here proves the protocol/config layer is
correct. It does not prove the mobile app's platform integration works.**
See `docs/SINGBOX_VPN_COMPATIBILITY.md` — the "Headless protocol" and
"Android/iOS device" columns are tracked separately, and only real-device
testing may mark the device columns PASS.

## Running

Requires:

- A `sing-box` binary matching the pin in `../../UPSTREAM_VERSION.md`
  (`v1.13.19`), either on `PATH` or pointed to via `SING_BOX_BIN`.
- `openssl` on `PATH` (used for the local TLS 1.3 REALITY decoy and the
  Hysteria2 TLS certificate — see `common.dart`'s doc comment for exactly
  what's required of it).

```sh
export SING_BOX_BIN=/path/to/sing-box   # or have it on PATH
cd packages/vpn_core
flutter test test/interop/
```

Both files skip (not fail) individual tests when `sing-box`/`openssl`
aren't found, so a machine without them isn't blocked — CI should require
them and treat a skip as a failure, per singbox-vpn's own
`VPN1_REQUIRE_REAL_INTEROP=1` precedent (see
`docs/SINGBOX_VPN_COMPATIBILITY.md`'s CI section).

## What was actually run in the session that added these tests

`flutter test` itself could not be run (no Flutter/Dart SDK in that
session's environment — see `docs/BUILDING.md`). Instead, the exact same
protocol steps these Dart tests perform were run directly against a real
`sing-box v1.13.19` binary built from the pinned source
(`packages/vpn_core/native/singbox-go/build_android.sh`'s underlying `go
install` step, done ad hoc for this verification), via shell + a small
Python SOCKS5 client, before being encoded as these Dart tests:

- VLESS+REALITY, correct key: real TLS 1.3 decoy handshake, real REALITY
  hijack, HTTP GET through a SOCKS5-tunneled connection returned `200 OK`.
- VLESS+REALITY, malformed public key: `sing-box check` / start rejected
  it before any handshake.
- VLESS+REALITY, wrong-but-well-formed public key (a second real X25519
  keypair): config loaded, but the handshake itself failed --
  `sing-box`'s own log: `REALITY: processed invalid connection`.
- Hysteria2+Salamander, correct password: HTTP GET through the tunnel
  returned `200 OK`.
- Hysteria2+Salamander, correct password: a UDP datagram sent through a
  SOCKS5 UDP ASSOCIATE relay came back correctly echoed from a local UDP
  target — proving UDP capability specifically, not just TCP.
- Hysteria2, wrong password: SOCKS5 CONNECT was refused; no tunnel.

These Dart test files reproduce that exact sequence in the app's own test
runner so it happens automatically in CI going forward, rather than only
once by hand.
