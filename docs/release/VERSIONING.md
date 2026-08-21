# Versioning policy

**Single source of truth: `pubspec.yaml`'s `version:` field**, in the
form `X.Y.Z+N` (e.g. `1.2.24+2704`).

This is not a new convention introduced for release automation — it's
already how this repository (inherited from upstream Karing) wires
versions today:

| Consumer | Derived from | How |
|---|---|---|
| Semantic app version (user-visible) | `X.Y.Z` part | Flutter's build tooling reads `pubspec.yaml` and exposes it as `flutter.versionName` (Android, `android/app/build.gradle.kts:45`) and `$(FLUTTER_BUILD_NAME)` (iOS, substituted into `MARKETING_VERSION` in `ios/Runner.xcodeproj/project.pbxproj`) |
| Android `versionCode` | `N` part | `flutter.versionCode` (`android/app/build.gradle.kts:44`) |
| iOS `CFBundleShortVersionString` | `X.Y.Z` part | `MARKETING_VERSION = "$(FLUTTER_BUILD_NAME)"` |
| iOS `CFBundleVersion` | `N` part | `CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)"` |

Nothing needed to change in `android/app/build.gradle.kts` or the Xcode
project for this — Flutter's own tooling already treats `pubspec.yaml` as
authoritative for all four values. What `.github/workflows/release.yml`
adds is **enforcement**: the release pipeline's first job,
`version-consistency`, fails the entire release before touching a signer
or an upload endpoint if the git tag doesn't exactly match
`pubspec.yaml`.

## The rule

1. `pubspec.yaml`'s `version:` is always `X.Y.Z+N`:
   - `X.Y.Z` — semantic version, bumped per your normal judgment (patch
     for a fix, minor for a feature, major for a breaking change to
     something user-visible).
   - `N` — a monotonically increasing integer build number. **Must
     increase on every release** — both Google Play (`versionCode`) and
     App Store Connect (`CFBundleVersion`) reject a re-upload that
     doesn't increase this number, so this isn't just a style preference.
2. The release tag is always `v` + that exact string — e.g. version
   `1.2.25+2705` is tagged `v1.2.25+2705`, not `v1.2.25` and not
   `1.2.25+2705`.
3. `packages/vpn_core`'s own `pubspec.yaml` version (currently `0.1.0`)
   is a **separate, independent** package version — it is not part of
   this policy and is not checked by `version-consistency`. Bump it
   according to normal semver-for-a-library judgment when its own public
   API changes; it has no required relationship to the app's version.

## Cutting a release

```sh
# 1. Bump pubspec.yaml's version: field, e.g. 1.2.24+2704 -> 1.2.25+2705
#    (edit by hand; commit it on its own, or as part of the last PR
#    going into the release).
git add pubspec.yaml
git commit -m "Bump version to 1.2.25+2705"
git push origin main

# 2. Tag the commit that has that exact version, matching it exactly.
git tag v1.2.25+2705
git push origin v1.2.25+2705
```

Pushing the tag is what triggers `.github/workflows/release.yml`. If the
tag doesn't match `pubspec.yaml` at the tagged commit, the very first job
fails with a clear error naming the mismatch — nothing downstream (no
signing, no upload) runs.

## Why not derive the build number automatically instead?

An earlier design considered auto-deriving `N` from `git rev-list --count`
or similar at build time, so nobody has to remember to bump it by hand.
Rejected in favor of the explicit, checked `pubspec.yaml` value because:

- It's what Flutter's own tooling and this repo's existing
  `build.gradle.kts`/`project.pbxproj` wiring already expect and use —
  overriding it at build time would mean two different numbers exist
  (the file's, and whatever `--build-number` the workflow injects),
  which is a worse single-source-of-truth story, not a better one.
- An explicit, git-diffable version bump is itself useful history (you
  can see exactly when and in which commit a release's version changed),
  which an automatically-computed number at build time throws away.
- The `version-consistency` gate this project's release gates explicitly
  require (see `docs/release/RELEASE_CHECKLIST.md`) is much simpler and
  more legible as "does the tag match the file" than as "recompute the
  same derivation the release job uses and hope it matches."
