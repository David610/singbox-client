#!/usr/bin/env bash
# The pinned sing-box tag + commit (see UPSTREAM_VERSION.md) is recorded
# independently in four places that have no mechanical link to each
# other: go.mod (tag only -- go.sum has content hashes, not a git commit
# SHA), build_android.sh, build_ios.sh, and
# .github/workflows/singbox-vpn-compat.yml. A hand-edit to only one of
# them would silently build/verify a different revision than the others
# claim. This script is the "CI check for this is proposed" follow-up
# UPSTREAM_VERSION.md's "Where the pin lives" section refers to -- it
# fails loudly on any mismatch instead of leaving that drift to be
# discovered by whichever build happens to break first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

UPSTREAM_MD="$REPO_ROOT/packages/vpn_core/UPSTREAM_VERSION.md"
GO_MOD="$SCRIPT_DIR/go.mod"
BUILD_ANDROID="$SCRIPT_DIR/build_android.sh"
BUILD_IOS="$SCRIPT_DIR/build_ios.sh"
COMPAT_WORKFLOW="$REPO_ROOT/.github/workflows/singbox-vpn-compat.yml"

extract() {
  # extract <pattern> <file>: prints the first regex capture group match.
  grep -oE "$1" "$2" | head -1
}

MD_TAG="$(extract '\| Tag \| `v[0-9][0-9.]*`' "$UPSTREAM_MD" | grep -oE 'v[0-9][0-9.]*')"
MD_COMMIT="$(extract '\| Commit \| `[0-9a-f]{40}`' "$UPSTREAM_MD" | grep -oE '[0-9a-f]{40}')"

GOMOD_TAG="$(extract 'github.com/sagernet/sing-box v[0-9][0-9.]*' "$GO_MOD" | grep -oE 'v[0-9][0-9.]*$')"

ANDROID_TAG="$(extract 'PIN_TAG="v[0-9][0-9.]*"' "$BUILD_ANDROID" | grep -oE 'v[0-9][0-9.]*')"
ANDROID_COMMIT="$(extract 'PIN_COMMIT="[0-9a-f]{40}"' "$BUILD_ANDROID" | grep -oE '[0-9a-f]{40}')"

IOS_TAG="$(extract 'PIN_TAG="v[0-9][0-9.]*"' "$BUILD_IOS" | grep -oE 'v[0-9][0-9.]*')"
IOS_COMMIT="$(extract 'PIN_COMMIT="[0-9a-f]{40}"' "$BUILD_IOS" | grep -oE '[0-9a-f]{40}')"

COMPAT_TAG="$(extract 'SING_BOX_PIN_TAG: "v[0-9][0-9.]*"' "$COMPAT_WORKFLOW" | grep -oE 'v[0-9][0-9.]*')"
COMPAT_COMMIT="$(extract 'SING_BOX_PIN_COMMIT: "[0-9a-f]{40}"' "$COMPAT_WORKFLOW" | grep -oE '[0-9a-f]{40}')"

fail=0
check() {
  local name="$1" value="$2"
  if [ "$value" != "$MD_TAG" ] && [ "$value" != "$MD_COMMIT" ]; then
    echo "::error::pin mismatch: $name is '$value', UPSTREAM_VERSION.md says '$MD_TAG'/'$MD_COMMIT'" >&2
    fail=1
  fi
}

check "go.mod tag" "$GOMOD_TAG"
check "build_android.sh PIN_TAG" "$ANDROID_TAG"
check "build_android.sh PIN_COMMIT" "$ANDROID_COMMIT"
check "build_ios.sh PIN_TAG" "$IOS_TAG"
check "build_ios.sh PIN_COMMIT" "$IOS_COMMIT"
check "singbox-vpn-compat.yml SING_BOX_PIN_TAG" "$COMPAT_TAG"
check "singbox-vpn-compat.yml SING_BOX_PIN_COMMIT" "$COMPAT_COMMIT"

if [ "$fail" -ne 0 ]; then
  echo "One or more sing-box pin references have drifted apart -- see UPSTREAM_VERSION.md 'Upgrading the pin'." >&2
  exit 1
fi

echo "sing-box pin consistent everywhere: $MD_TAG / $MD_COMMIT"
