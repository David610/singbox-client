# Client production baseline

## Credential storage update

VERIFIED BY AUTOMATED UNIT TESTS (platform behavior remains device-unverified):
persisted profile secrets are now split out of `subscribe.json` into
Android-Keystore/iOS-Keychain-backed `flutter_secure_storage`, with verified,
atomic, idempotent plaintext migration and fail-closed handling of missing or
corrupted entries. Portable backups exclude profiles and credentials rather
than exporting them in plaintext. See `docs/CREDENTIAL_STORAGE.md` for the
exact boundary and remaining risks.

Status of the Phase 1 production-hardening pass on top of PR #6. Every claim
below is tagged VERIFIED, NOT VERIFIED, KNOWN BLOCKER, or DEFERRED — read
the tag, not just the sentence. This document does not claim App
Store/Play Store readiness; see "Known blockers" and
`docs/LICENSING_AUDIT.md` for what's actually still open.

## Product identity

VERIFIED (checked via `rg` after edits, zero remaining matches): the
Android `applicationId`/`namespace`, the Kotlin app package, the iOS
Runner + PacketTunnel bundle identifiers, the iOS/Android App Group, the
iOS Keychain access group, and the single Dart-side identity source
(`AppUtils`) no longer reference `com.nebula.karing` / `group.com.nebula.karing`.
New identity: `com.david610.singboxclient` (app),
`com.david610.singboxclient.PacketTunnel` (extension),
`group.com.david610.singboxclient` (App Group / Keychain group).

VERIFIED: the iOS `com.apple.developer.icloud-container-identifiers` /
`ubiquity-container-identifiers` entitlement was removed from
`Runner.entitlements` — no `CloudDocuments`/`CKContainer`/ubiquity API
usage was found anywhere in `lib/` or `ios/`, so it was vestigial, not a
real feature dependency.

DEFERRED, not done in this pass: the Dart package name itself
(`pubspec.yaml`'s `name: karing`, which every one of ~1,050 import lines
across 132 files in `lib/` depends on via `package:karing/...`), the
`karing://` URL scheme, in-app display strings (251 occurrences of
"Karing" across 28 locale `.i18n.json` files plus their generated
`strings_*.g.dart`), and macOS/tvOS/Windows/Linux bundle
identifiers/branding (`com.nebula.karing.*` system-extension IDs,
`com.nebula.LibVpnCore`, Windows `Runner.rc` company/product strings,
`make_config.yaml` publisher fields). These are real, but each is either
(a) a repo-wide mechanical rename too large to validate safely in this
pass without breaking something silently, or (b) a non-shipping-priority
platform for this phase (this task's scope is iOS + Android). Renaming the
Dart package specifically needs its own dedicated, fully-validated pass —
attempting it inside this change set risked leaving the repository in an
inconsistent, half-renamed state, which this task explicitly forbids.

## Permissions (Android)

Removed as **VESTIGIAL** (traced via code search; zero real usage found —
see git history for the full per-permission rationale in the manifest's
own inline comments):
`FOREGROUND_SERVICE_SYSTEM_EXEMPTED`, `RECEIVE_BOOT_COMPLETED`,
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `ACCESS_BACKGROUND_LOCATION`,
`READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`,
`REQUEST_INSTALL_PACKAGES`, `OBSERVE_GRANT_REVOKE_PERMISSIONS`,
`RECEIVE_USER_PRESENT`.

Kept, **REAL** (traced to genuine on-demand code, not removed blind):
`CAMERA` (QR import, requested only when the user opens the scanner
screen), `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` (Wi-Fi
SSID/BSSID reading for the diversion-rule editor — Android requires
location permission for this API; note no runtime permission request flow
was found, so this may already be non-functional on modern Android without
a manual grant — STILL NOT VERIFIED whether the underlying feature
actually reaches the shipped sing-box config end-to-end: the diversion
group model round-trips `wifi_ssid`/`wifi_bssid` through local settings
storage (`lib/app/modules/vpn_service_state.dart`), but no reference to
those fields was found in the Dart config-building path
(`lib/app/utils/singbox_config_builder.dart`,
`lib/app/utils/singbox_outbound.dart`) either. Resolving that would mean
inspecting/changing how the real shipping VPN config gets built, which is
out of scope for a mobile-identity/dead-surface pass per this task's own
constraints — left as a DEFERRED open question, not touched), and
`QUERY_ALL_PACKAGES`.

UPDATE (mobile identity pass): the per-app-routing screen that originally
motivated `QUERY_ALL_PACKAGES` (`lib/screens/perapp_android_screen.dart`,
"Per-App Proxy") has been deleted — it was confirmed dead, not merely
undecided: `packages/vpn_core`'s native `SingBoxVpnService.kt` does define
`includePackage`/`excludePackage` VPN-builder options, but the Dart-facing
`vpn_core` plugin API never exposed a way to set them, and no Dart code
anywhere read `SettingManager.getConfig().perapp.list` to populate them —
so toggling apps in that screen persisted a setting that could never
affect the actual tunnel. `QUERY_ALL_PACKAGES` itself is KEPT anyway:
`lib/app/utils/package_manager_android.dart`'s full package enumeration is
shared infrastructure still used by two real, wired features — the
diversion-rule per-app target picker (`group.package`, a genuine sing-box
`package_name` route-rule field) and the live network-connections screen's
per-app icon/name display (`lib/screens/net_connections_screen.dart`).
Removing the permission would break both, which this task's own guidance
says not to do just because one dead screen also used it (shared
infrastructure, not itself dead).

KNOWN BLOCKER, still not resolved: `QUERY_ALL_PACKAGES` requires an
explicit Play Console policy justification/declaration before Play Store
submission — now for the diversion-rule/net-connections use cases
specifically, since the per-app-routing screen that used to be the
simplest justification for it no longer exists.

## Exported Android components

UPDATE (mobile identity pass): `AutomationCommandReceiver` — previously
changed from `exported="true" android:permission="…normal…"` (PR #6's fix —
a false security boundary, see below) to `exported="false"` — has now been
deleted outright, along with its manifest `<receiver>` entry and the dead
`allowedSenderPackages`/"automation whitelist" settings UI that configured
it. With the receiver already `exported="false"`, no external Tasker-style
app could reach it at all, CONNECT/RECONNECT were non-functional stubs, and
grepping the whole repo turned up no internal caller that sent
`com.david610.singboxclient.action.{CONNECT,DISCONNECT,RECONNECT}` either —
so there was no real automation surface left to preserve, only dead code
and a settings screen pointing at it. `TileService`
(`BIND_QUICK_SETTINGS_TILE`, system-only permission) and
`SingBoxVpnService` (`exported="false"`, `BIND_VPN_SERVICE`) were already
correctly locked down and are unchanged.

KNOWN BLOCKER, not addressed in this pass: `MainActivity` is
`exported="true"` with no `android:permission`, and accepts external input
via a `karing://` deep link and a `SEND text/plain` share-target — both
plausible VPN-config/subscription import vectors reachable from any app,
with no permission gate. Unlike `AutomationCommandReceiver`, these are
legitimate product features (deep-link/share-based import), not
Tasker-style automation, so "close the exported surface" is not the right
fix here — the fix is validating/sandboxing what the import path does with
attacker-controlled input, which is a parsing-robustness question, not an
identity/permission one, and is out of this phase's scope per the task's
own non-goals ("do not randomly change... routing"). Flagged for the next
phase.

## Telemetry

VERIFIED (removed): `sentry_flutter` and `sentry_dart_plugin` dropped from
`pubspec.yaml`; the `sentry:` build config block removed; `SentryUtils`
and the former `SentryUtilsPrivate` DSN-init stub rewritten to route
through the existing redacted local log (`Log.e`/`Log.i`) instead of any
network call — `flutter pub get` confirms `sentry`, `sentry_dart_plugin`,
and `sentry_flutter` are "no longer being depended on." Android's
`io.sentry.android.gradle` Gradle plugin, its `sentry {}` config block, and
the `io.sentry.auto-init`/`io.sentry.proguard-uuid` manifest meta-data were
all removed. `RemoteConfig`'s `sentry`/`sentryMinVersion` fields and the
UI/logic that referenced them (`about_screen.dart`'s toggle,
`net_connections_screen.dart`'s host-classification check,
`RemoteConfigManager.rejectSentrySubmit()`) were removed or adapted so
nothing references a removed field.

VERIFIED: no replacement third-party telemetry SDK was introduced.

DEFERRED, explicitly retained pending review, not silently ignored: the
broader `RemoteConfig`/`RemoteConfigManager` system itself still contacts
first-party Karing infrastructure at runtime for notices, config,
geo-rulesets, and update metadata (`kDefaultNotice`, `kDefaultConfig`,
`kDefaultOutpost`, `kDefaultGetTranffic`, `kDefaultGeoSite`/`kDefaultGeoIp`,
all under `karing.app`/`x31415926.top`/`github.com/KaringX/*`). This is a
much larger architectural dependency than Sentry (notices, geo-ruleset
updates, and remote config overrides are real, wired-in features, not
vestigial), and removing or re-pointing it is a product/infrastructure
decision — not something to remove blind in a security/identity pass. It
is documented here, not hidden, per this task's "for every retained
third-party service, document why the app needs it."

## Self-update

VERIFIED (removed for Android only, desktop untouched): `getExtension()`
in `auto_update_manager.dart` no longer returns `.apk` for Android — it
now falls through to the same "no download candidate" empty-string
convention the existing Linux-AppImage case already used, which
`getDownloadPath()` and `_check()` both already short-circuited on before
this change (verified by reading both call sites, not assumed). This
disables the whole download+install path for Android through the module's
existing convention rather than adding a new special case.
`AppInstaller.installApk(installer)` and its `app_installer` import were
removed from `version_update_screen.dart`; the `app_installer` pub
dependency was removed after confirming (via `rg`) it had no other call
sites. `REQUEST_INSTALL_PACKAGES` was removed from the Android manifest —
no privileged capability remains without the code that used it. Windows,
macOS, and Linux update flows (`launchUrl(file://…)` + exit, or a
password-prompted installer) are unchanged; they don't use
`REQUEST_INSTALL_PACKAGES` or an Android-style privileged install
mechanism, so leaving them alone does not reintroduce the same class of
issue.

## Karing-shell decision

**KEEP AND SANITIZE for this phase; MIGRATE TO CLEAN SHELL is likely the
right medium-term call, but insufficient evidence exists in this pass to
commit to it.**

Evidence for eventually migrating: `pubspec.yaml`'s package name
(`karing`) alone touches ~1,050 import lines across 132 files; in-app
branding touches 251 strings across 28 locale files; the app carries
inherited features well outside this product's stated scope (LAN
discovery, TV/Apple TV sync, complex per-app routing UI, a whole
remote-config/notice/geo-ruleset subsystem talking to karing.app
infrastructure, desktop self-update) that a "minimal, security-conscious
VPN application foundation" arguably doesn't need. `packages/vpn_core` is
already a clean, well-isolated, well-tested boundary (verified: 81 passing
unit tests, zero direct UI coupling) that a new shell could consume
unchanged.

Evidence against migrating *now*: this phase's actual, validated changes
(identity, permissions, exported components, telemetry, self-update) were
made safely and narrowly against the existing app, with every change
covered by a passing `flutter analyze`/`flutter test` run. A full shell
extraction is an order of magnitude larger, touches the entire UI layer,
and this task explicitly forbids creating "two half-working applications."
No coherent, buildable minimal-shell skeleton was started in this pass —
starting one without finishing it would have violated that constraint.

Recommendation for the next phase: treat "extract a minimal first-party
Flutter shell around the existing `packages/vpn_core`" as its own,
dedicated task — not a rider on protocol-contract work. Minimum viable
shell scope: connect/disconnect/reconnect UI, profile import (QR + one
well-hardened URL/subscription path), a settings screen limited to VPN
operation (not the full inherited settings surface), and the existing
diagnostics screen (already redaction-tested). Everything else inherited
from Karing should be re-justified against the product scope in section 8
of this task's own prompt before being ported forward.

## Notes on scope not touched

Per this task's explicit non-goals, DNS defaults (`8.8.8.8`),
`usesCleartextTraffic="true"`, MTU, IPv6 policy, routing rules, and the
`kDefaultOutpost`/geo-ruleset network dependencies noted above were left
untouched even though several were flagged as review items in prior
audits. They are P1/P2 items for a dedicated pass, not omissions from this
one.
