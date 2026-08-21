# Pinned upstream: sing-box / libbox

| | |
|---|---|
| Project | [SagerNet/sing-box](https://github.com/SagerNet/sing-box) |
| Tag | `v1.13.19` |
| Commit | `b5ebaa1fc0f2b94256180b95468e73ef53caa27d` |
| Tag date | 2026-08-17 |
| Go toolchain required | `go 1.24.7`+ (per upstream `go.mod`) |
| License | GPL-3.0 (upstream project's own license; unrelated to this repo's `LICENSE.md`) |

This is a **stable release tag**, not `main`, not a branch, and not a
pseudo-version. It was selected as the newest stable (non-alpha/beta/rc)
tag at the time this architecture milestone was implemented, verified via:

```sh
git ls-remote --tags https://github.com/SagerNet/sing-box \
  | sed 's#.*refs/tags/##' | grep -Ev 'alpha|beta|rc' | sort -V | tail
```

## Where the pin lives

`packages/vpn_core/native/singbox-go/go.mod` — the single source of truth.
`build_android.sh` and `build_ios.sh` both read `PIN_TAG`/`PIN_COMMIT` from
their own header (kept in sync with `go.mod` by hand; a CI check for this
is proposed in docs/ARCHITECTURE.md's CI section) and **refuse to build**
if the sing-box checkout they clone doesn't match the pinned commit
exactly, so the produced `libbox.aar` / `Libbox.xcframework` can never
silently drift onto a newer or different commit.

## Upgrading the pin

1. Pick a new stable tag from upstream's release list.
2. Update `PIN_TAG`/`PIN_COMMIT` in both `build_android.sh` and
   `build_ios.sh`, and this file.
3. `cd packages/vpn_core/native/singbox-go && go get github.com/sagernet/sing-box@<new-tag> && go mod tidy`
4. Re-run the pin-verification build (`go build -tags "..." .` in that
   directory) before touching any mobile build.
5. Re-run `build_android.sh` / `build_ios.sh` to regenerate the AAR/xcframework.
6. Re-run the full `vpn_core` test suite and the app's `flutter test`.

Never edit `go.sum` by hand; always regenerate it via `go mod tidy`/`go get`
so its hashes stay verifiable against the Go checksum database.
