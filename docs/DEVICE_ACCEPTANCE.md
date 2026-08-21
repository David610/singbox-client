# Device acceptance protocol

Companion to `docs/SINGBOX_VPN_COMPATIBILITY.md` (parser/config/headless
protocol validation — automated, CI-run, proves the config/core layer is
correct) and the in-app Diagnostics screen
(`lib/screens/diagnostics_screen.dart`, backed by
`packages/vpn_core/lib/src/diagnostics/`). **This document is the other
half**: nothing here can be automated away, because the question it
answers is not "does the generated config parse correctly" but

> Is real device traffic correctly traversing the intended tunnel,
> including TCP, UDP/QUIC, and native apps?

No CI job, headless interop test, or diagnostics-screen probe can answer
that — only a real phone, on a real network, running a real app build,
against a real (or realistic) `singbox-vpn` deployment can. Per
`docs/SINGBOX_VPN_COMPATIBILITY.md`'s own honesty rule (borrowed from
singbox-vpn's `docs/CLIENT_COMPATIBILITY.md`, and repeated here
deliberately): **a row in the matrix below is only ever "yes"/PASS after
a completed, dated entry exists in the log — never from code review, a
green CI run, or a diagnostics-screen probe passing.**

## What this protocol does NOT do

- **It does not implement surveillance.** Nothing here runs unattended,
  nothing here builds a history of what a device visited. Every test is a
  human performing an action once and recording the result.
- **It does not capture application payloads.** The Diagnostics screen's
  probes (see below) prove *reachability* (a TCP connect succeeded, a DNS
  query got a response) and never log or export what was sent/received.
  This protocol's tests ask "does the real app work," which a tester
  observes directly (does the video play, does the page load) — nothing
  here needs or wants packet capture.
- **It does not log destination history by default.** The Diagnostics
  screen only runs probes when a human taps "Run connectivity tests," and
  the results are not persisted beyond that session unless the human
  explicitly exports them.

## Before you start: the Diagnostics screen

Open the app's Diagnostics screen (once wired into navigation — see
`lib/screens/diagnostics_screen.dart`'s bottom comment for current
integration status) before and after each test run in the matrix below.
It gives you, sanitized and safe to include in a bug report:

app version/build, platform + OS version, VPN state, selected
profile/transport, VPN core version, server hostname, public IP
before/after (only when you tap "check public IP" — see the in-app
notice), IPv4/IPv6/DNS/TCP/UDP status, a QUIC/HTTP3 reachability
*heuristic* (explicitly labeled as such — it is not a confirmed QUIC
handshake), approximate latency, tunnel uptime, reconnect count, and the
most recent sanitized engine error. Tap "Export diagnostics" to get a
paste-into-GitHub-issue bundle. **It never shows or exports the REALITY
private key, a raw subscription token, the Hysteria2 password, or the
VLESS UUID** (the UUID appears only in a redacted, last-4-characters form,
e.g. `****88d9`, for correlating "which profile was this" without
exposing the credential) — see
`packages/vpn_core/lib/src/diagnostics/redaction.dart` and its test suite
for the enforcement mechanism.

Attach the exported bundle to every logged test run below — it is not a
replacement for the manual matrix (it can't observe "did the video play"),
it's supporting evidence alongside it.

## Matrix

**Platforms:** iPhone, Android
**Networks:** Wi-Fi, cellular
**Protocols:** VLESS+REALITY, Hysteria2

That's 2 × 2 × 2 = 8 independent test *runs*, each running all 20 tests
below. Not every combination needs a fresh run for every app change —
see "How much of the matrix to re-run" at the end — but the full matrix
should exist at least once before a release is called acceptance-tested.

### The 20 tests

| # | Test | What "pass" means | Automatable? |
|---|---|---|---|
| 1 | VPN connects | App reports connected within a reasonable time (note actual seconds) | Diagnostics screen shows VPN state |
| 2 | Public IP changes to VPN server | Diagnostics screen's public-IP-before vs. public-IP-after differs, and "after" matches the server's known public IP | Diagnostics screen (explicit "check public IP" tap) |
| 3 | DNS works | A real page in a real browser resolves and loads | Diagnostics screen's DNS probe is a supporting signal, not a substitute |
| 4 | Normal HTTPS works | A real HTTPS site loads fully (not just a bare TCP connect) | Diagnostics screen's TCP probe is supporting only |
| 5 | UDP works | Diagnostics screen's UDP probe passes, AND a real UDP-dependent action (a video call, or test #5's own generic request) succeeds | Diagnostics screen probe + one manual confirmation |
| 6 | HTTP/3 (QUIC) behavior recorded | Record what happened (worked / fell back to HTTP/2 / failed) — see "HTTP/3 note" below | Diagnostics screen's heuristic is a hint, not proof |
| 7 | Browser YouTube works | A YouTube video, opened in the device's normal mobile browser, plays without excessive buffering | No — real browser, real playback |
| 8 | **Native YouTube works** | The real, installed YouTube app plays a video | **No — see "Do not automate native app tests" below** |
| 9 | Telegram works | The real, installed Telegram app sends/receives a message and loads media | No — real app |
| 10 | TikTok behavior recorded | Record what happened (works / degraded / blocked) — TikTok is a known-sensitive target for some deployments; this is a recording task, not a pass/fail gate | No — real app |
| 11 | App Store / Play Store network works | The store app can search and view a listing (does not require an actual purchase/install) | No — real store app |
| 12 | Device lock 5 min → unlock | After 5 minutes locked, VPN is still connected (or reconnects promptly) on unlock | Diagnostics screen confirms state after |
| 13 | Background app | Backgrounding the app (home button, switch apps) for a few minutes doesn't drop the tunnel | Diagnostics screen confirms state after |
| 14 | Wi-Fi → cellular | Toggling off Wi-Fi mid-connection: VPN reconnects (note how long) rather than silently staying disconnected | Diagnostics screen confirms reconnect count increased and state |
| 15 | Cellular → Wi-Fi | Same, reversed | Diagnostics screen |
| 16 | Reconnect after temporary network loss | Airplane mode on for 30s, then off: VPN recovers without a manual reconnect | Diagnostics screen |
| 17 | 30-minute idle connection | Leave connected, phone idle/locked, for 30 minutes; still connected at the end | Diagnostics screen's tunnel uptime field |
| 18 | 30-minute active streaming | 30 minutes of continuous video/audio streaming without the tunnel dropping | Manual observation; diagnostics screen for uptime/reconnect count after |
| 19 | Throughput measurement | Run a real speed test (e.g. a well-known speed-test app/site) with and without the VPN; record both numbers | Manual, or a speed-test app's own result screen |
| 20 | Battery/thermal observations | Subjective but recorded: does the device feel noticeably warmer, does battery drop noticeably faster, over the test session | Manual observation only |

### HTTP/3 note (test 6)

REALITY is TCP-only (it disguises a TLS 1.3 handshake); Hysteria2 is
QUIC/UDP-based. A site that prefers HTTP/3 may behave differently over
each transport, and some networks throttle/block UDP/443 outright
independent of this app. Record what you actually observed (which sites,
which transport, what happened) rather than a single "works/doesn't" —
the Diagnostics screen's `quicHeuristic` field is a hint for where to
look, not a substitute for observing real HTTP/3 behavior (e.g. via a
browser's dev tools "protocol" column, where available).

### Do not automate native app tests

**Test 8 (native YouTube) — and by the same reasoning, tests 9-11 — must
be performed by a human actually opening the real, installed app and
observing real behavior.** A generic HTTP request to a YouTube-adjacent
endpoint is a *supporting diagnostic* (does basic HTTPS reach that domain
at all) — it is explicitly **not equivalent to native YouTube playback**,
which involves the app's own DNS/CDN selection logic, its own connection
pooling and protocol negotiation, DRM/token exchange, adaptive bitrate
streaming behavior, and whatever anti-automation/anti-proxy detection the
service applies to its native clients specifically (which can differ from
what a browser or a bare HTTP client sees). A green "generic request"
result and a real native-app failure are both possible at the same time,
and only one of them is what a real user experiences. If you want a
scripted pre-check before the manual test, run it and record it
separately, clearly labeled as a supporting diagnostic — never substitute
it for the actual manual pass/fail on test 8.

## Recording a run

Copy this block per test run (one run = one platform × network × protocol
combination, all 20 tests) and paste the filled-in result into this file
or into the tracking issue/PR for the change being validated. Follow
`docs/SINGBOX_VPN_COMPATIBILITY.md`'s own discipline: **a matrix cell only
changes to PASS once a block like this exists**, dated, for that exact
combination — not from "it probably still works."

```
## Device acceptance run

Date/time (with timezone):
Device: (exact model, e.g. "iPhone 15 Pro", "Pixel 8")
OS: (exact version, e.g. "iOS 18.1", "Android 14")
App build SHA: (short git SHA -- see the Diagnostics screen's "Build" field)
App version: (e.g. "1.2.24+2704")
VPN server: (hostname or label -- NOT the full credential-bearing URI)
singbox-vpn / sing-box version on the server: (from the server operator, or
  the Diagnostics screen's "Core version" field for the client side)
Protocol under test: VLESS+REALITY | Hysteria2
Network: Wi-Fi | Cellular (carrier, if relevant)
Tester:

Diagnostics export attached: YES/NO (paste the exported bundle, or link
  to where it's attached)

1. VPN connects:                          PASS/FAIL   (time to connect: ___s)
2. Public IP changes to VPN server:        PASS/FAIL
3. DNS works:                              PASS/FAIL
4. Normal HTTPS works:                     PASS/FAIL
5. UDP works:                              PASS/FAIL
6. HTTP/3/QUIC behavior:                   (describe what happened)
7. Browser YouTube works:                  PASS/FAIL
8. Native YouTube works:                   PASS/FAIL   (NOT a generic request -- see above)
9. Telegram works:                         PASS/FAIL
10. TikTok behavior:                       (describe what happened)
11. App Store / Play Store network works:  PASS/FAIL
12. Device lock 5 min -> unlock:           PASS/FAIL
13. Background app:                        PASS/FAIL
14. Wi-Fi -> cellular:                     PASS/FAIL   (reconnect time: ___s)
15. Cellular -> Wi-Fi:                     PASS/FAIL   (reconnect time: ___s)
16. Reconnect after temporary network loss: PASS/FAIL  (reconnect time: ___s)
17. 30-minute idle connection:             PASS/FAIL
18. 30-minute active streaming:            PASS/FAIL
19. Throughput: without VPN ___ Mbps / with VPN ___ Mbps
20. Battery/thermal observations:          (describe)

Notes / anomalies:
```

No entries exist yet — this section documents the *procedure*, matching
`docs/SINGBOX_VPN_COMPATIBILITY.md`'s own manual-acceptance-log pattern
(and singbox-vpn's own `docs/DEVICE_ACCEPTANCE_TESTS.md`, which this
structure deliberately mirrors, for the reason given there: an owner
using multiple related repos benefits from one consistent template rather
than a different one per project).

### How much of the matrix to re-run

Not every code change needs all 8 runs re-executed:

- A change to `packages/vpn_core`'s config generation, URI parsing, or
  the Android/iOS VPN core integration: re-run the full matrix before the
  next release.
- A UI-only change with no touch on `vpn_core`, native VPN code, or the
  Diagnostics screen: no re-run required, but don't claim the matrix is
  still "passing" for that release without a recent dated entry — surface
  the actual last-tested date.
- A single protocol/config bug fix: re-run at minimum the specific
  platform × protocol combination the fix targets, on both networks.

## A/B client comparison

When something fails and it's unclear whether the problem is this app,
this app's generated config, or the server/network itself, compare the
**exact same server and user credentials** across multiple clients. A
failure that reproduces in every client points at the server or network;
a failure unique to this app points at this app.

### Clients to compare against

| Client | Platform | Where to get it | Notes |
|---|---|---|---|
| **This app** | Android, iOS | This repo's own build | The thing under test |
| **Upstream Karing** | Android, iOS, desktop | [KaringX/karing](https://github.com/KaringX/karing) releases | The fork's origin — useful because it shares this project's UI/profile conventions but (per `docs/FORK_ARCHITECTURE_AUDIT.md`) a different, private VPN engine. A failure that reproduces here but not in upstream Karing narrows the problem toward this project's `vpn_core`/native integration specifically. |
| **Hiddify** | Android, iOS, Linux, Windows, macOS | [hiddify/hiddify-app](https://github.com/hiddify/hiddify-app) releases | Already singbox-vpn's own primary reference client (see that repo's `docs/CLIENT_COMPATIBILITY.md` and `docs/clients/`) — the most directly comparable third-party baseline, and the one singbox-vpn's own maintainers already test against. |
| **Official sing-box Apple client** | iOS, macOS, tvOS | App Store ("sing-box", SagerNet) | Where practical (App Store availability varies by region) — useful specifically because it's the *reference* sing-box client: if the official client fails against a server this app also fails against, the problem is almost certainly server/network/protocol-config, not this app's `vpn_core` integration. |

### How to run an A/B comparison

1. Generate (or reuse) one `singbox-vpn` user/token whose credentials you
   are comfortable pasting into multiple apps for testing purposes —
   never reuse your own personal daily-driver credentials for this, and
   rotate/revoke the test token afterward (`docs/SINGBOX_VPN_COMPATIBILITY.md`'s
   fixtures already establish the pattern of using disposable test
   credentials, never real ones).
2. Import the same subscription URL (or the same `vless://`/`hysteria2://`
   share link) into each client being compared.
3. Run the SAME test from the matrix above (start with test 1, 2, 4, and
   5 — connect, public IP, HTTPS, UDP — before going deeper) on the SAME
   device, SAME network, back to back, as close in time as practical (network
   conditions and server load can shift between runs).
4. Record each client's result side by side:

```
## A/B comparison

Date/time:
Device / network (held constant across all clients tested):
VPN server / test token (label only, not the credential itself):
Protocol: VLESS+REALITY | Hysteria2

| Test              | This app | Upstream Karing | Hiddify | sing-box (Apple) |
|-------------------|----------|------------------|---------|-------------------|
| Connects          |          |                  |         |                   |
| Public IP changes |          |                  |         |                   |
| HTTPS works       |          |                  |         |                   |
| UDP works         |          |                  |         |                   |

Conclusion (server/network issue vs. this-app-specific):
```

5. **Interpretation**: if every client fails identically, treat it as a
   server/network/protocol-config problem and take it to
   `docs/SINGBOX_VPN_COMPATIBILITY.md` / the singbox-vpn project's own
   `docs/CLIENT_COMPATIBILITY.md` and interop tests, not this app's issue
   tracker. If only this app fails, that's a real, actionable bug here —
   attach the Diagnostics export from the failing run.
