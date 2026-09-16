#!/bin/bash
# Build one source package under packages/ with sbuild in unshare mode.
#
# Deliberately NOT dpkg-buildpackage: building on the host picks up packages
# that aren't in Build-Depends, producing debs that fail on a clean install.
set -euo pipefail

PKG="${1:?usage: build-package.sh <package> [dist] [arch]}"
DIST="${2:-trixie}"
ARCH="${3:-amd64}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/packages/${PKG}"
ARTIFACTS="${ROOT}/artifacts"
CHROOT="${HOME}/.cache/sbuild/${DIST}-${ARCH}.tar.zst"

[[ -d "$SRC/debian" ]] || { echo "no debian/ in $SRC" >&2; exit 1; }

# Skeleton packages that are present in the tree but not yet buildable carry a
# marker, so `make build` over all of packages/ doesn't fail the pipeline on
# work that hasn't started.
if [[ -f "$SRC/debian/NOT-READY" ]]; then
    echo "skipping $PKG (debian/NOT-READY present)"
    exit 0
fi
[[ -f "$CHROOT"     ]] || { echo "no chroot; run: make chroot" >&2; exit 1; }

mkdir -p "$ARTIFACTS"

# TODO: for kind:python packages, fetch and verify the upstream tarball into
# the source tree here before building. Must be hash-pinned -- see
# requirements.txt generated with `pip-compile --generate-hashes`.

cd "$SRC"
sbuild \
    --chroot-mode=unshare \
    --chroot="$CHROOT" \
    --dist="$DIST" \
    --arch="$ARCH" \
    --no-run-lintian \
    --build-dir="$ARTIFACTS" \
    .

echo "built $PKG -> $ARTIFACTS"
