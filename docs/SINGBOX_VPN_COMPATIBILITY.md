# singbox-vpn compatibility matrix

Validates this client (`packages/vpn_core`) against
[David610/singbox-vpn](https://github.com/David610/singbox-vpn) — the
target server project — at commit
`644adbf4bb87be02dce1ecb1cf6c311032e53408`. Companion to
`docs/ARCHITECTURE.md` and `docs/BUILDING.md`.

**Honesty rule, borrowed from singbox-vpn's own
`docs/CLIENT_COMPATIBILITY.md`** (this project did not invent it
independently — it's adopted deliberately, for exactly the reason
singbox-vpn states: a "PASS" must mean an automated check ran, or a
documented manual test happened, never spec conformance or code review
alone): the **Android device** and **iOS device** columns are never marked
PASS without a dated, real-hardware test recorded below. No such test has
been run yet — every row in those two columns reads **NOT TESTED**.

## Matrix

| Feature | Parser | Config | Headless protocol | Android device | iOS device |
|---|---|---|---|---|---|
| VLESS+REALITY, flow supplied (`xtls-rprx-vision`) | PASS | PASS | PASS | NOT TESTED | NOT TESTED |
| VLESS+REALITY, flow NOT supplied (`?compat=vision-off`) | PASS (regression-tested — see below) | PASS | not separately run (same handshake path as above, minus the `flow` field) | NOT TESTED | NOT TESTED |
| Hysteria2 | PASS | PASS | PASS | NOT TESTED | NOT TESTED |
| Salamander obfuscation | PASS | PASS | PASS (covered by the Hysteria2 protocol test — obfs is always enabled in it) | NOT TESTED | NOT TESTED |
| sing-box JSON subscription/profile (`format=singbox`) | PASS | PASS | N/A — not a wire protocol; its two outbounds are covered by their own rows above | NOT TESTED | NOT TESTED |
| `vless://` URI | PASS | PASS | PASS (parsed URI's params feed the same REALITY protocol test) | NOT TESTED | NOT TESTED |
| `hysteria2://` URI | PASS | PASS | PASS (parsed URI's params feed the same Hysteria2 protocol test) | NOT TESTED | NOT TESTED |
| Subscription URL import (`GET /sub/{token}`) | PASS (body-parsing only — see scope note) | N/A | N/A — this is an HTTP GET, not a tunnel protocol | NOT TESTED | NOT TESTED |
| UDP | N/A | PASS (`udp_timeout` present in generated tun config; Hysteria2 outbound imposes no UDP restriction) | PASS (SOCKS5 UDP ASSOCIATE relay verified over Hysteria2 — see interop README) | NOT TESTED | NOT TESTED |

### Column definitions

- **Parser**: `SingBoxConfigBuilder` correctly parses the input format into
  a typed model, with every field asserted present (not just "doesn't
  throw"). Tested in `packages/vpn_core/test/singbox_vpn_compat_test.dart`
  and `singbox_config_builder_test.dart`.
- **Config**: the typed model's generated sing-box outbound JSON contains
  every field, correctly named, matching singbox-vpn's own renderer output
  — verified by (a) the same test file's field-by-field assertions and (b)
  `sing-box check -c <generated config>` against the real pinned binary,
  run directly in the session that added this matrix (see
  `docs/BUILDING.md`; not yet wired into automated CI — see "CI" below).
- **Headless protocol**: a real `sing-box` binary, as both client and
  server, actually completes the handshake and carries real bytes (TCP
  and, for Hysteria2, UDP) using the generated config — see
  `packages/vpn_core/test/interop/`. **This is not a mobile-app test** —
  see that directory's README "Scope" section, restated here because it's
  the single most important caveat in this document: a green cell in this
  column means the protocol/config layer works, nothing about
  `android.net.VpnService` or `NEPacketTunnelProvider`.
- **Android device / iOS device**: a real phone, running this app's real
  APK/IPA build, actually connects through a real (or realistic) deployed
  `singbox-vpn` server. **Never marked PASS without a dated entry below.**

## Manual device acceptance log

Copy this block and fill it in after a real on-device test; update the
matrix row(s) above only once an entry exists here — same discipline as
singbox-vpn's own `docs/DEVICE_ACCEPTANCE_TESTS.md`.

```
Date:
App build (commit / version):
Device:
OS version:
Network:
singbox-vpn deployment (host, sing-box version):

VLESS+REALITY connect:       PASS/FAIL
Hysteria2 connect:            PASS/FAIL
UDP-dependent traffic works:  PASS/FAIL
Subscription import:          PASS/FAIL
Reconnect after network switch: PASS/FAIL

Notes:
```

No entries exist yet.

## What was traced (before anything was changed)

Per this task's instruction to trace current parser behavior before
changing anything: reading singbox-vpn's `crates/compat-config/src/render.rs`
against this client's pre-existing `SingBoxConfigBuilder.parseVlessRealityUri`
found a real bug — a `vless://` URI with no `flow` parameter (exactly what
`render_vless_reality_uri_vision_off` produces) was being parsed with
`flow` silently defaulted back to `xtls-rprx-vision`, re-adding Vision to
a profile specifically constructed to omit it. Fixed in the same change
that added this matrix, with a fixture (`vless_reality_uri_vision_off.txt`)
and a named regression test
(`singbox_vpn_compat_test.dart`, group "vless:// (REALITY, flow NOT
supplied)") reproducing the exact previous failure — per this project's
regression principle (see "Regression principle" below), every future
singbox-vpn compatibility bug fix must do the same.

## Fixtures and their provenance

See `packages/vpn_core/test/fixtures/singbox_vpn/README.md` for the full,
field-by-field trace of every fixture value back to singbox-vpn's own
`render.rs`/`server.rs` source, and confirmation that every credential in
them is a fake value generated fresh for this purpose (never the user's
real subscription, never committed anywhere before this).

## Regression principle

Every singbox-vpn compatibility bug fixed from this point forward must add
a fixture and/or test reproducing the exact previous failure, in
`packages/vpn_core/test/fixtures/singbox_vpn/` and
`packages/vpn_core/test/singbox_vpn_compat_test.dart` (or
`test/interop/` for a protocol-level bug) — not just a fix with no
regression coverage. The `vless_reality_uri_vision_off.txt` fixture and
its test group above are the first instance of this principle in
practice, not just a policy statement.

## Version alignment

singbox-vpn pins `sing-box 1.13.19` (`docs/COMPATIBILITY_VERSIONS.md` in
that repo) — the exact same version this client's `vpn_core` pins
(`packages/vpn_core/UPSTREAM_VERSION.md`). This was a genuine
cross-check, not a coincidence engineered for this document: both pins
were independently arrived at as "the newest stable sing-box release" at
close dates (singbox-vpn: 2026-08-17; this client: verified in the prior
architecture milestone), and finding them identical is meaningful
evidence the two projects' compatibility assumptions are currently
aligned. If either project's pin moves, re-check this alignment — a
version skew here is exactly the kind of thing that could silently break
compatibility without any single test catching it.

## CI (not yet implemented — design only, per this task's scope)

Extends `docs/BUILDING.md`'s CI design:

- `packages/vpn_core/test/singbox_vpn_compat_test.dart` should run on
  every PR (pure Dart, no external binary needed).
- `packages/vpn_core/test/interop/` should run with `SING_BOX_BIN` set to
  a binary built by `native/singbox-go/build_android.sh`'s underlying
  toolchain (or an equivalent CI step), and — matching singbox-vpn's own
  `VPN1_REQUIRE_REAL_INTEROP=1` policy — a skip in that suite should be a
  hard CI failure, not a silent pass, once wired up.
- Neither of the above exists in CI yet (this repository has no CI at
  all — see `docs/FORK_ARCHITECTURE_AUDIT.md` §9). This document records
  intent; `docs/BUILDING.md` tracks the overall CI gap.
