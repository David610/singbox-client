#!/usr/bin/env bash
# Produces packages/vpn_core/android/libs/libbox.aar from the pinned
# sing-box revision (see UPSTREAM_VERSION.md), using sing-box's own
# official build tooling -- this script is a thin, documented wrapper
# around `make lib_android` in a checkout of the pinned tag, not a
# reimplementation of it.
#
# Prerequisites (see docs/BUILDING.md "Android VPN core"):
#   - Go toolchain matching go.mod's `go 1.24.7` directive (or newer 1.24.x)
#   - Android SDK + NDK (ANDROID_HOME / ANDROID_NDK_HOME set)
#   - JDK 17
#
# This script is NOT run automatically by `flutter pub get` or CI's default
# build -- producing the real core is a deliberate, explicit step, because
# it requires the Android NDK and takes several minutes. Until it has been
# run once, the app still builds (see docs/ARCHITECTURE.md "Why libbox.aar
# isn't committed") but the VPN tunnel will not carry traffic.
set -euo pipefail

PIN_TAG="v1.13.19"
PIN_COMMIT="b5ebaa1fc0f2b94256180b95468e73ef53caa27d"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/../../android/libs"
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
make lib_android

mkdir -p "$OUT_DIR"
cp libbox.aar "$OUT_DIR/libbox.aar"
echo "Wrote $OUT_DIR/libbox.aar (sing-box $PIN_TAG / $PIN_COMMIT)"
