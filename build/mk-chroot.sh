#!/bin/bash
# Build the sbuild chroot tarball. Run once; CI caches the result.
# unshare mode needs no root and no schroot config.
set -euo pipefail

DIST="${1:-trixie}"
ARCH="${2:-amd64}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
OUT="${HOME}/.cache/sbuild/${DIST}-${ARCH}.tar.zst"

mkdir -p "$(dirname "$OUT")"

if [[ -f "$OUT" ]]; then
    echo "chroot already present: $OUT"
    exit 0
fi

mmdebstrap --variant=buildd --arch="$ARCH" \
    --include=ca-certificates,eatmydata \
    "$DIST" "$OUT" "$MIRROR"

echo "created $OUT"
