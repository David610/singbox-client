// Package main is not the real gomobile bind target -- gomobile binds the
// upstream github.com/sagernet/sing-box/experimental/libbox package
// directly (see build_android.sh / build_ios.sh, which invoke sing-box's
// own `cmd/internal/build_libbox` exactly as its own Makefile does).
//
// This file exists only so `go build`/`go mod tidy` in this directory can
// verify, outside of gomobile, that the pinned version in go.mod actually
// resolves and compiles against the real libbox package -- i.e. it is a
// pin-verification smoke test, not part of the shipped app.
package main

import (
	"fmt"

	"github.com/sagernet/sing-box/experimental/libbox"
)

func main() {
	fmt.Println("pinned sing-box/libbox version:", libbox.Version())
}
