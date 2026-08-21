#!/usr/bin/env bash
# Produces packages/vpn_core/ios/Frameworks/Libbox.xcframework from the
# pinned sing-box revision (see UPSTREAM_VERSION.md), using sing-box's own
# official build tooling (`make lib_ios`). macOS + Xcode only.
#
# Prerequisites (see docs/BUILDING.md "iOS VPN core"):
#   - macOS with Xcode + command line tools
#   - Go toolchain matching go.mod's `go 1.24.7` directive (or newer 1.24.x)
#
# Not run automatically by any CI/build step here -- this environment has
# no macOS host to verify this script end-to-end (see docs/BUILDING.md
# "What could not be verified in this environment"). The Android script
# (build_android.sh) follows the identical pin-verification pattern and WAS
# exercised for the Go-level parts (module resolution + compile) in this
# environment; this script mirrors it for the iOS target.
set -euo pipefail

PIN_TAG="v1.13.19"
PIN_COMMIT="b5ebaa1fc0f2b94256180b95468e73ef53caa27d"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/../../ios/Frameworks"
WORK_DIR="${SING_BOX_CHECKOUT:-$SCRIPT_DIR/.sing-box-checkout}"

if [ ! -d "$WORK_DIR" ]; then
  echo "Cloning sing-box @ $PIN_TAG into $WORK_DIR"
  git clone --branch "$PIN_TAG" --depth 1 https://github.com/SagerNet/sing-box "$WORK_DIR"
fi

ACTUAL_COMMIT="$(git -C "$WORK_DIR" rev-parse HEAD)"
if [ "$ACTUAL_COMMIT" != "$PIN_COMMIT" ]; then
  echo "error: checked-out commit ($ACTUAL_COMMIT) does not match the pin ($PIN_COMMIT)." >&2
  echo "Refusing to build an unpinned core. See UPSTREAM_VERSION.md." >&2
  exit 1
fi

cd "$WORK_DIR"
make lib_ios

mkdir -p "$OUT_DIR"
cp -R Libbox.xcframework "$OUT_DIR/Libbox.xcframework"
echo "Wrote $OUT_DIR/Libbox.xcframework (sing-box $PIN_TAG / $PIN_COMMIT)"
echo "Now uncomment s.vendored_frameworks in packages/vpn_core/ios/vpn_core.podspec"
echo "and add Libbox.xcframework to the vpnCoreService extension target in Xcode."
