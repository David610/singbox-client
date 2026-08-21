# native/singbox-go

This directory pins the exact upstream sing-box/libbox revision this app
links against, and verifies that pin actually resolves and compiles.

It is **not** the gomobile bind target itself -- gomobile binds the
upstream `github.com/sagernet/sing-box/experimental/libbox` package
directly, using upstream's own build tooling (`cmd/internal/build_libbox`),
exactly as sing-box's own `make lib_android` / `make lib_ios` do. `shim.go`
in this directory is only a pin-verification smoke test (`go build .`
proves the version in `go.mod` resolves and compiles); it is not shipped in
the app.

## What's pinned

See `../../UPSTREAM_VERSION.md` for the full record. Short version:

```
github.com/sagernet/sing-box v1.13.19
commit b5ebaa1fc0f2b94256180b95468e73ef53caa27d
```

`go.mod`/`go.sum` in this directory are the source of truth for the pin --
they were generated with `go mod tidy` against that exact tag and are
committed so the pin is verifiable and reproducible without re-resolving
anything from the network.

## Verifying the pin (no NDK/Xcode required)

```sh
cd packages/vpn_core/native/singbox-go
go build -tags "with_gvisor with_quic with_wireguard with_utls with_clash_api" .
./singbox-go   # prints the linked libbox version
```

This was run as part of producing this repository state; see
docs/BUILDING.md for the full transcript/expectations.

## Producing the real mobile binaries

Requires a full sing-box checkout at the pinned tag (the `experimental/libbox`
package alone isn't enough -- gomobile bind needs the whole module plus its
build tooling), plus platform SDKs. See `build_android.sh` and
`build_ios.sh`, and docs/BUILDING.md for prerequisites.
