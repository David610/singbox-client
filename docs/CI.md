# CI

Companion to `docs/BUILDING.md`, `docs/ARCHITECTURE.md`, and
`docs/SINGBOX_VPN_COMPATIBILITY.md`. This document describes the GitHub
Actions workflows under `.github/workflows/`, why they're shaped the way
they are, and — because several of them are honestly expected to fail
today — exactly what that means and doesn't mean.

**No workflow in this repository requires a secret.** Everything runs
against public infrastructure (the Go module proxy, pub.dev, GitHub's own
Actions runners) or is entirely self-contained (a locally-run scanner
binary, a throwaway CI-only keystore generated and discarded every run).
See "Secrets required" at the end of this document.

## Pinned versions (read before touching any workflow)

Per this task's instruction not to arbitrarily upgrade anything, every
version below was read from the repository's own declared pins, not
chosen freely:

| Tool | Pinned to | Source of truth |
|---|---|---|
| Flutter | `3.44.9` | See "Flutter version: a real correction" below — the package floor is `3.44.2`, the first stable Flutter release whose bundled Dart SDK satisfies `sdk: ">=3.12.2 <4.0.0"`; CI uses the latest patch on that compatible minor. |
| Dart | `3.12.2`, bundled with the above Flutter release | `pubspec.yaml`: `sdk: ">=3.12.2 <4.0.0"` |
| JDK | 17 | `android/app/build.gradle.kts` `sourceCompatibility`/`targetCompatibility` |
| Android compileSdk/buildTools/NDK | 35 / 36.0.0 / 28.2.13676358 | `android/app/build.gradle.kts` (unchanged by CI — fetched via AGP's own SDK auto-download once licenses are pre-accepted) |
| Kotlin | 2.2.20 | `android/settings.gradle.kts` |
| AGP | 8.11.1 | `android/settings.gradle.kts` |
| Gradle | 8.14.3 | `android/gradle/wrapper/gradle-wrapper.properties` (the wrapper itself is used — CI never installs a different Gradle) |
| CocoaPods | 1.16.2 | `ios/Podfile.lock` (`COCOAPODS:` line) |
| Xcode | whatever `macos-latest` provides | **Not pinned in the repo today** — no `.xcode-version` file, no existing CI to preserve a prior pin from. This workflow does not invent one; see "iOS Xcode version" below. |
| sing-box / libbox | `v1.13.19`, commit `b5ebaa1fc0f2b94256180b95468e73ef53caa27d` | `packages/vpn_core/UPSTREAM_VERSION.md` |

### Flutter version: a real correction

The original pin here was `3.35.7` — "the latest patch of the minor
version `pubspec.yaml` formerly declared as its `flutter: ">=3.35.0"` floor,"
reasoned entirely from that one line and never actually run. The first
real CI run of these workflows (PR #2) failed on **every** Flutter-based
job with the same error:

```
The current Dart SDK version is 3.9.2.
Because karing requires SDK version >=3.12.2 <4.0.0, version solving failed.
```

Flutter 3.35.7 bundles Dart 3.9.2 — which does not satisfy `pubspec.yaml`'s
own `sdk: ">=3.12.2 <4.0.0"` constraint. The old `flutter: ">=3.35.0"`
floor and the `sdk: ">=3.12.2"` floor were inconsistent. Both the root app
and `packages/vpn_core` now declare `flutter: ">=3.44.2"`, so dependency
resolution rejects an incompatible Flutter SDK immediately and reports the
actual supported floor.

Corrected by checking Flutter's own release manifest
(`https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json`)
for the earliest stable release bundling Dart `>=3.12.2`:

| Flutter | Dart SDK |
|---|---|
| 3.41.9 | 3.11.5 (still fails) |
| 3.44.0 | 3.12.0 (still fails) |
| **3.44.2** | **3.12.2 (first release that satisfies it)** |
| 3.44.9 | 3.12.2 (latest patch on that line, released 2026-08-06) |
| 3.47.1 | 3.13.1 (current latest stable overall) |

`3.44.9` was chosen over `3.47.1` for the same "don't arbitrarily
upgrade" reasoning as the original pin — it's the latest patch of the
*earliest* Flutter minor that actually satisfies `pubspec.yaml`'s own
constraint, not the newest Flutter available. All six workflow files'
`FLUTTER_VERSION` were updated together (`pr-fast.yml`,
`android-build.yml`, `ios-build.yml`, `singbox-vpn-compat.yml`,
`supply-chain.yml`, `release.yml`).

**Lesson recorded here on purpose**: a version pin reasoned about from a
single declared floor, without cross-checking every other constraint that
floor has to coexist with, is a guess wearing the shape of a fact. This
one only got caught because the workflow actually ran — see
`docs/release/RELEASE_CHECKLIST.md`'s own note about the iOS release path
never having been run end to end, for another pin in this repo carrying
exactly the same risk until it, too, is actually exercised.

A second, independent bug surfaced in the same CI run:
`supply-chain.yml`'s `secret-scan` job installed `gitleaks v8.30.1` using
`go-version-file: packages/vpn_core/native/singbox-go/go.mod` (pinned to
Go 1.24.7, matching sing-box's own requirement) — but gitleaks v8.30.1
itself requires Go >=1.24.11. Fixed by giving that one step its own,
independently-current Go version (`1.27.0`) instead of inheriting a pin
that exists for an unrelated reason (reproducing the sing-box build, not
running gitleaks) — see that job's inline comment.

A third, same-shaped bug was in the same file's `vulnerability-scan` job:
`osv-scanner v2.5.1` requires Go >=1.26.5, also newer than the pinned
1.24.7. Fixed the same way — an explicit, independently-current
`go-version: "1.27.0"` on that job's Go setup step, not the
`go-version-file` pin against the sing-box tree.

A fourth bug, unrelated to Go versions: `lockfile-consistency`'s
"pubspec.lock matches pubspec.yaml (app)" step failed with a diff limited
to the `url:` field of one package (`zxing2`) — `pub.flutter-io.cn` (the
host actually recorded in every package entry of the committed
`pubspec.lock`) vs. `pub.dev` in what `dart pub get` produced on the
runner. First fix attempt pinned `PUB_HOSTED_URL: https://pub.dev`,
reasoning backwards — that the committed lockfile was pub.dev and the
runner had drifted to the mirror. It was the other way around: the
committed lockfile is 100% `pub.flutter-io.cn` (`grep -c pub.flutter-io.cn
pubspec.lock` → 282, `pub.dev` → 0). Forcing `pub.dev` made the check
*fail differently* on the next run: a package's host is part of its
lockfile identity to `dart pub`, so pointing at a different host than the
one already locked forces a full re-resolution against that host's
current registry state — not just a `url:` rewrite. That re-resolution
picked several genuinely different transitive versions (e.g.
`vector_graphics_compiler` 1.2.6 → 1.3.0, `vm_service` 15.2.0 → 15.3.0),
which then failed the diff for real reasons instead of a mirror-only one.
Corrected to `PUB_HOSTED_URL: https://pub.flutter-io.cn` — matching the
host the lockfile was actually generated against, verified by grepping
the committed file rather than assumed.

A fifth bug: `dart format --output=none --set-exit-if-changed .` flagged
21 files as unformatted. These were genuinely never run through a real
`dart format` in this project's development history — no Dart/Flutter SDK
was available in the environment that authored them (see "Known
current-state gaps" below). Fixed for real, not guessed: a Dart SDK
matching this repo's pin exactly (3.12.2, the same version bundled with
`FLUTTER_VERSION: 3.44.9` above) was downloaded from
`https://storage.googleapis.com/dart-archive/channels/stable/release/3.12.2/sdk/dartsdk-linux-x64-release.zip`
and used to run `dart format .`, then `dart format --output=none
--set-exit-if-changed .` was re-run to confirm the result is stable
(0 files changed on the second pass) before committing. All resulting
diffs are whitespace/line-wrapping only — reviewed file-by-file to confirm
no semantic change.

A sixth, unrelated bug surfaced by the same CI run in
`packages/vpn_core/test/interop/reality_interop_test.dart`: both REALITY
interop tests declared `const params = VlessRealityParams(...)` while
passing `serverPort: realityPort`, where `realityPort` is a `final`
variable assigned at runtime via `await _freePort()` — not a compile-time
constant, so the `const` constructor invocation is a genuine Dart compile
error (`Error: Not a constant expression.`), not a flake. Fixed by
changing both occurrences to `final params = VlessRealityParams(...)`.

A seventh and eighth bug, both in `packages/vpn_core/android/build.gradle`,
surfaced by the `Build Android` job's first real Gradle run:
`group = "..."`/`version = "..."` assignments preceded the file's
`buildscript {}`/`plugins {}` blocks, which Gradle's script-restriction
rule forbids ("only buildscript {}, pluginManagement {} and other plugins
{} script blocks are allowed before plugins {} blocks") — fixed by moving
those two assignments to after the `plugins {}` block. The `dependencies
{}` block also used `val libboxAar = file(...)`, which is Kotlin syntax
(`val`/`var`) in a plain `.gradle` (Groovy) file, not `.gradle.kts` —
Groovy has no `val` keyword, so this would have failed to compile with
`unable to resolve class val` on the very next line Gradle's parser
reached once the ordering issue above was fixed. Changed to Groovy's
`def`. Both verified locally by compiling the file with Groovy's own
`FileSystemCompiler` (no Android Gradle Plugin needed to catch either —
one is a Gradle script-restriction error, the other a plain parse error)
before pushing.

The iOS build job's failure (`Error (Xcode): There is no XCFramework
found at '.../bind/apple/Libbox.xcframework'`) is a different case: it is
the *already-documented* "iOS VPN extension target gap" above ("Known
current-state gaps" §3) surfacing for the first time in a real run, not a
new bug. `ios/vpnCoreService/PacketTunnelProvider.swift` has a hard
compile-time `import Libbox` by design (unlike Android's
file-existence-guarded optional dependency), and no step in this
repository builds or vendors a real `Libbox.xcframework` yet, nor is
`vpnCoreService` registered as an Xcode target — see §3's own reasoning
for why hand-editing `project.pbxproj` without Xcode to validate it was
judged too risky to attempt blind. No change made here; this stays
expected-red until a developer with Xcode completes that target
registration.

Once a real Flutter SDK (3.44.9, matching this project's pin exactly) was
obtained and `flutter test`/`flutter analyze` were run for real inside
`packages/vpn_core` for the first time, two more genuine logic bugs
surfaced — neither `dart format`, `dart analyze` without a full SDK, nor
any `contains`-only test assertion could have caught either:

- `DiagnosticsCollector._onStatus` incremented `reconnectCount` on the
  *first* connection too, not just genuine reconnects: it counted any
  transition into `connected` where `_lastObservedState` was non-null and
  not already `connected` — which is exactly what the normal
  `connecting` → `connected` first-connect sequence looks like. Fixed by
  tracking a `_hasConnectedOnce` flag and only counting a transition into
  `connected` as a reconnect once the tunnel has genuinely been connected
  before.
- `redactText`'s JSON key-value pattern's shared "guess the separator
  from the matched text" replacement (`_separatorFor`) silently dropped
  the surrounding quote characters for the JSON-shaped pattern,
  corrupting otherwise-valid JSON while still satisfying every existing
  `contains('[REDACTED]')`-style assertion in `redaction_test.dart`. A
  second, subtler bug in the same file compounded it:
  `_queryKeyValuePattern`'s value character class (`[^&\s#]+`) didn't
  exclude `"`, so a `pbk=...`/`sid=...`-shaped credential sitting right
  at the end of a JSON string value greedily consumed that string's
  closing quote into an unused capture group, silently discarding it.
  Only `diagnostics_exporter_test.dart`'s "is valid, parseable JSON after
  redaction" test — an actual `jsonDecode` round-trip, not a substring
  check — could catch this, and it did, the first time it ever ran
  against a real `dart:convert`. Fixed by giving each of the three
  key-value patterns (JSON/query-string/log-line) its own explicit
  replacement instead of one shared separator-guesser, and by excluding
  `"` from both the query-string and log-line value character classes.

### iOS Xcode version

Because there was no pre-existing pin to preserve, `ios-build.yml` uses
whatever Xcode version `macos-latest` currently provides rather than
inventing a specific pin unprompted. This is a deliberate reading of "do
not arbitrarily upgrade" — pinning to *some* version now would itself be
a new choice this task wasn't asked to make. If the project later commits
to a specific Xcode version (e.g. once the iOS extension target work in
"Known current-state gaps" below lands and needs a stable toolchain to
develop against), add a `maxim-lobanov/setup-xcode` step pinned by commit
SHA, following the same pinning policy as every other action here.

## Third-party Action pinning policy

Every third-party (non-`actions/`, non-`github/`) step is either:

1. **A GitHub Action, pinned by full commit SHA** (never a mutable tag,
   never `@main`/`@latest`), with the human-readable version in a trailing
   comment — e.g. `subosito/flutter-action@1508160852fb97248640997f7cfb38da241df0ba # v2.9.1`.
   A tag can be force-moved by the action's maintainer (or, in a
   compromise, by an attacker); a commit SHA cannot. To bump one, resolve
   the new tag's commit yourself (`git ls-remote --tags <repo>`, using the
   dereferenced `^{}` commit for annotated tags) and update both the SHA
   and the comment together — never edit one without the other, or the
   comment becomes actively misleading.
2. **Built from source at a pinned version**, not run as a hosted/wrapper
   Action at all — `gitleaks` and `osv-scanner` are both installed via
   `go install <module>@<pinned tag>` (see `supply-chain.yml`), the same
   approach `singbox-vpn-compat.yml` uses for the sing-box binary itself.
   This was a deliberate choice over the `gitleaks/gitleaks-action` /
   `google/osv-scanner-action` wrapper Actions: it keeps the trust
   boundary at "Go module proxy serves the exact tagged source, `go
   install` builds it locally" rather than "trust a wrapper Action's own
   compiled/bundled binary and whatever permissions it requests," and it
   means this repository's source never leaves the runner — no step in
   any workflow here uploads code to a third-party SaaS for scanning.

`actions/*` and `github/*` (first-party GitHub Actions: checkout, cache,
upload-artifact, setup-go, setup-java) are held to the same SHA-pinning
rule as everything else — "first-party" is not an exemption.

## Workflow graph

```
pull_request / push(main)
        │
        ├── pr-fast.yml                    (fast gate)
        │     format-analyze-test  (ubuntu, ~3-6 min)
        │
        ├── android-build.yml               (integration gate)
        │     android-build       (ubuntu, ~8-15 min)
        │
        ├── ios-build.yml                   (integration gate)
        │     ios-build           (macos, ~10-20 min)
        │
        ├── singbox-vpn-compat.yml          (integration gate)
        │     parser-and-config-tests       (ubuntu, ~2-4 min)  ─┐
        │     headless-protocol-interop     (ubuntu, ~5-10 min) ─┤ parallel
        │                                                        ┘
        └── supply-chain.yml                (integration gate)
              secret-scan              (ubuntu, ~2-4 min)   ─┐
              lockfile-consistency     (ubuntu, ~2-3 min)   ─┤
              license-inventory        (ubuntu, ~2-3 min)   ─┤ parallel
              vulnerability-scan       (ubuntu, ~2-4 min)    ─┘
```

**UPDATE, added after this document's original workflow-graph diagram was
written**: a sixth workflow file, `release.yml`, now exists — it does not
appear in the graph above because it is tag-triggered (`push: tags:
["v*"]`), not `pull_request`/`push: branches: [main]` like the five PR/CI
workflows the graph diagrams. It reuses every job above as a
`workflow_call` gate, then adds real signed Android (AAB+APK) and iOS
(IPA) release builds and internal-track store uploads (Play Internal
Testing, TestFlight Internal Testing) behind two GitHub Environments'
secrets. See `docs/release/RELEASE_CHECKLIST.md` for the full walkthrough
— it is a CD pipeline, not a merge gate, and it still never promotes past
internal/beta distribution automatically.

Five PR/push-triggered workflow files, twelve jobs total (plus
`release.yml`'s own release-only jobs, gated behind a version tag and
real signing secrets). All five PR/push workflows trigger on the same
events (`pull_request` targeting `main`, `push` to `main`,
`workflow_dispatch`) so they run in parallel as separate GitHub Actions
checks rather than one long sequential pipeline — a UI-only PR waits on
whichever job is slowest (`ios-build`, ~10-20 min), not on the sum of
everything. Each workflow has its own `concurrency` group keyed on the PR
number, so pushing a new commit cancels that workflow's own in-flight run
for the same PR without touching the others.

## Fast PR gate vs. integration gate

- **Fast gate** (`pr-fast.yml`): format + analyze + unit/fixture tests,
  pure Dart, no native toolchain, no external binary. This is what every
  contributor should expect to wait on for quick iteration.
- **Integration gate** (`android-build.yml`, `ios-build.yml`,
  `singbox-vpn-compat.yml`, `supply-chain.yml`): native builds, a real
  protocol interop test, and supply-chain scanning. Slower, but still
  scoped to debug/unsigned/release-*configuration* artifacts — never a
  signed, store-ready package. That's deliberately out of scope for this
  CI-only pass (see "Secrets required" below) and belongs in a future
  release workflow, not this one.

Nothing here does multi-platform *release packaging* (App Store/Play
Store bundles, TestFlight uploads, signed artifacts) — per this task's
explicit "Do not add deployment/store secrets yet," and per "do not make
every UI PR wait for unnecessary multi-platform release packaging," none
of these jobs produce anything beyond a debug or throwaway-signed
build good enough to prove the code compiles.

## What CI proves

- **Formatting and static analysis** are consistent with the repo's own
  `analysis_options.yaml`, for `packages/vpn_core` unconditionally and for
  the app tree informationally (see "Known current-state gaps").
- **`packages/vpn_core`'s unit and fixture tests pass** — the typed
  Dart↔native boundary contract (`vpn_core_test.dart`), and the
  singbox-vpn parser/config fixtures (`singbox_vpn_compat_test.dart`,
  `singbox_config_builder_test.dart`) with every field (REALITY public
  key, short_id, server_name, flow, fingerprint, Hysteria2 password,
  `obfs.type`/`obfs.password`, port, TLS, UDP) asserted present end to
  end, input → parsed model → generated core config.
- **A real, pinned `sing-box v1.13.19` binary, built from source in CI,
  actually completes a VLESS+REALITY handshake and a Hysteria2+Salamander
  handshake** (including a genuine UDP relay, not just TCP) using
  `vpn_core`'s own production config-builder output — and that a wrong
  key/wrong password is genuinely rejected, not just schema-valid.
- **The Android debug build compiles** end to end (Dart → Kotlin → APK),
  and a release-*configuration* build (shrunk/optimized, matching what a
  real release build's code paths exercise) compiles and signs with a
  disposable CI-only key.
- **The iOS Flutter/Dart layer and the `Runner` app target compile**
  without code signing.
- **No committed secret matches gitleaks' rule set** (with a narrow,
  documented allowlist for known non-secret test/example values — see
  `.gitleaks.toml`).
- **`pubspec.lock`/`go.sum` are not silently stale** relative to their
  manifests.
- **What dependency versions are actually resolved right now**, and
  **which of them have a publicly known vulnerability** per the OSV
  database, for both the Dart and the pinned Go dependency trees.

## What CI explicitly does NOT prove

- **That the app works on a real Android or iOS device.** Every build job
  here produces a debug/unsigned/throwaway-signed artifact and stops.
  Nobody installs it on hardware, grants it the VPN permission, or
  observes actual network behavior. See
  `docs/SINGBOX_VPN_COMPATIBILITY.md` — the Android/iOS device columns
  stay `NOT TESTED` until a real, dated manual test is recorded there;
  CI cannot flip them.
- **That `android.net.VpnService` or `NEPacketTunnelProvider` actually
  route traffic.** The `singbox-vpn-compat.yml` interop tests run the
  pinned core over a `mixed` (SOCKS5) inbound on loopback — see
  `packages/vpn_core/test/interop/README.md` "Scope" for why, restated
  because it's the most important caveat in that workflow too. A green
  `headless-protocol-interop` job proves the config/core layer; it proves
  nothing about the platform VPN integration layer.
- **That the iOS VPN extension target actually compiles**, as literally
  requested by this task — see "Known current-state gaps" below. This is
  the one requirement this CI setup could not make fully real, and it's
  stated here rather than silently scoped away.
- **License compliance** in the legal sense — `license-inventory` is a
  resolved-dependency-version manifest, not verified per-package license
  text. See "License inventory scope" below.
- **That every dependency is vulnerability-free** — `vulnerability-scan`
  is non-blocking for the Go tree specifically, and reports rather than
  gates on the currently-open findings there (see "Known open findings").
- **That the app is otherwise correct.** CI catches what it's built to
  catch: formatting, analysis, the tests that exist, and the specific
  protocol/build properties described above. It is not a substitute for
  code review or for the manual device testing tracked in
  `docs/SINGBOX_VPN_COMPATIBILITY.md`.

## Known current-state gaps (read before red CI surprises anyone)

CI accurately reflects a repository that went through a real
reconstruction, not a finished app. Items below are marked resolved once
a real, executed run (not just a code read) confirmed it.

1. **RESOLVED. App-level `flutter analyze`/`flutter test` are real,
   required, blocking checks.** `lib/app/utils/` and the
   `VPNService`/`ProxyConfig`/`ServerConfig` data models were
   reconstructed (`docs/ARCHITECTURE.md` §9); `flutter analyze` returns
   zero issues and `flutter test` passes on the full app suite as of this
   workflow revision. `pr-fast.yml` no longer has `continue-on-error`
   anywhere. Getting analyze fully clean (not just error-free) surfaced
   several real bugs fixed along the way -- notably
   `home_screen_widgets.dart`'s `supportedCurrentPlatfrom()` methods
   comparing a `List<bool>` against `Platform.operatingSystem` (a
   `String`), which made `.contains()` always return `false` regardless
   of platform, and `diagnostics_screen.dart` computing a redacted,
   correlatable profile identifier (`DiagnosticsSnapshot.
   profileIdentifierRedacted`) but never actually rendering it anywhere
   in the UI.

2. **RESOLVED. `android-build.yml` and `ios-build.yml` build the pinned
   native core from source before compiling.** Both jobs run
   `build_android.sh`/`build_ios.sh` against the exact pinned sing-box
   commit, verify the resulting `libbox.aar`/`Libbox.xcframework`, and
   only then run the Flutter/Gradle/Xcode build -- so a real build either
   succeeds against the real `io.nekohasekai.libbox` API or fails loudly,
   never silently on a missing-artifact error unrelated to the actual
   code. Producing the Android AAR and building the debug + release APKs
   against it (in the environment used to prepare this revision) surfaced
   three real, previously-unexercised defects, now fixed:
   - `build_android.sh`/`build_ios.sh` both computed their output path as
     `$SCRIPT_DIR/../android/libs` / `../ios/Frameworks` -- one `..` too
     few, since `SCRIPT_DIR` is `native/singbox-go`, not `native`. This
     silently wrote to `packages/vpn_core/native/android/libs/` instead
     of `packages/vpn_core/android/libs/`, the path
     `android/build.gradle`/the podspec actually check. Neither script
     had ever been run end-to-end before, so this had never surfaced.
   - `packages/vpn_core/android/src/main/AndroidManifest.xml` had a
     literal `--` inside an XML comment (`... registerDefaultNetworkCallback)\n -- without it ...`),
     which is invalid XML -- `--` is disallowed anywhere in a comment
     body except as its closing delimiter. This failed manifest merging
     for every real Android build, but had never been caught because no
     environment before this one had a real Android toolchain to parse
     it.
   - `packages/vpn_core/android/build.gradle`'s
     `implementation(files("libs/libbox.aar"))` fails AGP's "Direct local
     .aar file dependencies are not supported when building an AAR"
     check, because `vpn_core` is itself an Android library module (it
     produces `bundleDebugAar`/`bundleReleaseAar` outputs even though the
     app only consumes it as a project dependency). Fixed by making
     `vpn_core`'s own dependency `compileOnly` (enough to compile
     `SingBoxVpnService.kt` against `io.nekohasekai.libbox.*`) and adding
     the real `implementation(files(...))` dependency directly in
     `android/app/build.gradle.kts` instead (an application module has no
     such restriction), so the classes still land in the final APK.
   - `android/app/src/main/kotlin/com/nebula/karing/{TileService,
     AutomationCommandReceiver}.kt` still referenced the pre-migration
     `io.nebula.vpn_service.VpnServiceImpl` API (a class that no longer
     exists anywhere in this repo), which failed Kotlin compilation
     outright. Rewritten against the real
     `app.singboxclient.vpn_core.SingBoxVpnService`: status display and
     disconnect are real (`currentStatus()`/`ACTION_STOP`, the same API
     `VpnCorePlugin`'s own Flutter EventChannel bridge uses); starting a
     *new* connection from these entry points is honestly left
     unimplemented (logged, not faked) since it needs a `tag` +
     `configJson` only the running Flutter engine currently knows how to
     build -- fabricating a fake connect path or a fake CONNECTED state
     would have been worse than a documented gap.

   iOS's equivalent (`xcodebuild` compiling `Runner` + the `PacketTunnel`
   extension against a freshly-built `Libbox.xcframework`) could not be
   executed in the environment used to prepare this revision (no macOS
   host) -- this is the first real run of `ios-build.yml`'s full path;
   treat its first CI result as genuine new information, not a
   rubber-stamp.

3. **A real, previously-undiscovered Gradle-configuration blocker was
   found and fixed while building `android-build.yml`**:
   `android/app/build.gradle.kts` unconditionally loaded
   `../../private_for_build/karing/karing/android/sign/sentry.properties`
   at Gradle *configuration* time (not just for release builds) — a path
   that exists only inside KaringX's private signing tree, absent on
   every CI runner and every contributor's machine. This crashed **every**
   Gradle invocation, including `assembleDebug`, before this task's
   changes — meaning no Android build, CI or local, could ever have
   succeeded here previously. Fixed with a minimal existence check (empty
   `Properties` when the file is absent, so Sentry upload becomes a
   no-op instead of a crash); unchanged for anyone who does have the
   private tree. See the inline comment at that file's `sentryKeystore`
   declaration.

4. ~~`packages/vpn_core/pubspec.lock` is not committed.~~ **Resolved**: a
   real Flutter SDK (3.44.9, matching this project's own pin) was
   obtained and used to run `flutter pub get` inside `packages/vpn_core`
   for real; the resulting `pubspec.lock` is now committed and
   `supply-chain.yml`'s `lockfile-consistency` job diffs it the same way
   as the root app's. Getting a real SDK running also caught the bug in
   item 6 below, which only a real `flutter pub get`/`flutter test` run
   could have surfaced.

5. **The Android app's `GeneratedPluginRegistrant.java` still referenced
   the deleted `vpn_service` plugin, not `vpn_core`.** `pubspec.yaml` was
   switched from `vpn_service` to `vpn_core` back in the original
   `packages/vpn_core` work, but the generated plugin registrant files
   (`android/.../GeneratedPluginRegistrant.java`,
   `macos/Flutter/GeneratedPluginRegistrant.swift`,
   `windows/flutter/generated_plugin_registrant.cc`,
   `windows/flutter/generated_plugins.cmake`) are build-time output of
   `flutter pub get`, not hand-maintained — and since no environment
   before this one had a real Flutter SDK to regenerate them, they were
   still wired to instantiate `io.nebula.vpn_service.VpnServicePlugin`
   (Android) / import and register `vpn_service` (macOS, Windows), a
   class that no longer exists anywhere in this repository. Any real
   Android build that got far enough to run would have failed to
   register the actual VPN plugin. Fixed for real by running `flutter pub
   get` with a real SDK and committing the regenerated files — not a
   hand-edit, since these files must stay in sync with whatever `flutter
   pub get` produces from `pubspec.yaml`'s plugin list. Also added
   `packages/*/build/` to `.gitignore` (only the root `/build/` was
   covered before; `packages/vpn_core/build/` showed up as untracked the
   moment `flutter test` first actually ran there).

## Why a throwaway keystore, not `--no-shrink`

`android-build.yml` generates a fresh, meaningless RSA keypair
(`ci-throwaway-not-a-secret` password, 1-day validity, never persisted
past the job) and points `android/key.properties` at it before running
`flutter build apk --release`. This is not a secret and is not meant to
resemble one — it exists only so the *release* build type's real
shrink/optimize/signing-config code path in
`android/app/build.gradle.kts` (distinct from `debug`'s) actually executes
in CI, the same way it would for a real release, without needing this
repository's absent private production key. The alternative — building
`--debug` only — would never exercise R8/shrinking or the release
`signingConfig` block at all, silently leaving that code path untested.

## License inventory scope

`license-inventory` produces a resolved-dependency-version manifest
(`dart pub deps --style=compact` for both Dart packages, `go list -m all`
for the Go tree), not verified per-package license text. Fetching and
cross-checking real license text for ~150 pub packages and ~150 Go
modules would need a per-package network call on every run — heavier than
this task's "lightweight checks" instruction calls for. What this job
*does* give you: a diffable record of exactly what was resolved on every
run, so a dependency version change (and therefore a potential license
change) is visible in the job summary and artifact history even without
full text verification. Closing this gap properly (e.g. `license_checker`
for Dart, `go-licenses` for Go) is reasonable future work, not something
this pass implemented.

## Known open findings

As of this workflow being added, `vulnerability-scan`'s OSV check finds
real, currently-unresolved CVEs in the pinned sing-box v1.13.19 module's
*transitive* Go dependencies (not this project's direct choices):

| Package | Version (pinned via sing-box) | Advisory | Fixed in |
|---|---|---|---|
| `golang.org/x/crypto` | 0.48.0 | [GO-2026-5020](https://osv.dev/GO-2026-5020) / GHSA-rm3j-f69w-wqmq | 0.52.0 |
| `golang.org/x/net` | 0.50.0 | [GO-2026-4559](https://osv.dev/GO-2026-4559) | 0.51.0 |
| `google.golang.org/grpc` | 1.79.1 | [GO-2026-6061](https://osv.dev/GO-2026-6061) / GHSA-hrxh-6v49-42gf | 1.82.1 |

These come from `github.com/sagernet/sing-box`'s own `go.mod` at the
pinned tag, not from a choice this project made independently — per this
task's "do not arbitrarily upgrade dependencies" instruction,
`supply-chain.yml` does not silently bump `go.sum` to paper over them.
`vulnerability-scan`'s OSV step is therefore `continue-on-error: true`
(it does not block merges) but its findings are always published to the
job summary and uploaded as an artifact — never silently swallowed. Two
honest paths forward, neither implemented by this CI-only pass: wait for
upstream sing-box to bump these in a future release and move this
project's pin forward (`packages/vpn_core/UPSTREAM_VERSION.md` documents
that procedure), or evaluate a manual `go mod edit -replace` override as
a stopgap, which needs its own deliberate review of whether it's
compatible with the pinned sing-box version, not something to slip into a
CI-setup task.

## Branch protection recommendations for `main`

Not configured by this task (branch protection is a repository setting,
not something expressed in workflow YAML) — recommended required status
checks, to be set under Settings → Branches → Branch protection rules for
`main`, once this repository has one:

**Required (block merge if failing):**
- `Format, analyze, test` (from `pr-fast.yml`) — even though its two app
  analyze/test steps are internally `continue-on-error`, the job itself
  still fails on a `dart format` violation or a `packages/vpn_core`
  analyze/test failure, which is exactly what should block a merge.
- `Build Android (debug + release-config, unsigned-equivalent)` (from
  `android-build.yml`) — see "Known current-state gaps" #2: this WILL
  block every merge until that reconstruction lands. That is the correct,
  honest behavior for a required check on a currently-broken build, not a
  reason to make it optional.
- `Build iOS app + compile VPN extension target` (from `ios-build.yml`) —
  same reasoning; see gap #3 for the additional caveat about what it can
  and can't currently enforce.
- `Parser + config tests (fixtures, no native binary needed)` and
  `Headless protocol interop (real pinned sing-box binary)` (both from
  `singbox-vpn-compat.yml`) — the compatibility-regression gate this
  task exists to create.
- `Secret scan (gitleaks)` (from `supply-chain.yml`).
- `Lockfile consistency` (from `supply-chain.yml`).

**Recommended but not blocking** (surface in the PR checks list, don't
gate merge on them — matches their own `continue-on-error`/informational
design):
- `License / dependency inventory`
- `Known-vulnerability scan (OSV)`

**Also recommended, independent of this task's workflows:**
- Require branches to be up to date before merging.
- Require at least one review approval.
- Do not allow force-pushes or deletion of `main`.

## Secrets required: NONE for the five PR/CI workflows above; real secrets for `release.yml`

Every workflow diagrammed in the graph above (the five PR/push,
merge-gate workflows) runs with only the default, automatically provided
`GITHUB_TOKEN` (read-only `contents: read` permission, explicitly
declared in each workflow) or no token at all. This remains true and is
what makes every PR's CI result trustworthy without any repository owner
having configured anything.

UPDATE: `release.yml` (see "Workflow graph" above) is a separate,
tag-triggered pipeline that genuinely does need real secrets —
`ANDROID_KEYSTORE_BASE64` and friends, `IOS_DIST_CERTIFICATE_P12_BASE64`
and friends, a Google Play service account JSON, and an App Store Connect
API key — scoped to two GitHub Environments (`android-release`,
`ios-release`). See `docs/release/RELEASE_CHECKLIST.md` "Secrets to
configure" for the full list and how to produce each one. This document's
original "Secrets required: NONE" claim was accurate for the CI-only
scope it was written for, but is no longer accurate for the repository as
a whole now that `release.yml` exists — whether those secrets are
actually configured in this specific repository's Environments cannot be
verified by reading the repository's own files (a configured
GitHub-encrypted secret is never visible from a checkout); tagging a
release without them configured fails loudly (each secret-consuming step
has an explicit `::error::` check), not silently.
