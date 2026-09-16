#!/bin/bash
# Build the sbuild chroot tarball. Run once; CI caches the result.
# unshare mode needs no root and no schroot config.
set -euo pipefail

DIST="${1:-trixie}"
ARCH="${2:-amd64}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
OUT="${HOME}/.cache/sbuild/${DIST}-${ARCH}.tar.zst"

# mmdebstrap shells out to the compressor rather than linking a library, so a
# missing zstd surfaces as a confusing "cannot exec" deep inside the bootstrap.
for cmd in mmdebstrap zstd; do
    command -v "$cmd" >/dev/null || {
        echo "missing required command: $cmd" >&2
        echo "  Debian/Ubuntu: apt-get install mmdebstrap zstd" >&2
        exit 1
    }
done

mkdir -p "$(dirname "$OUT")"

if [[ -f "$OUT" ]]; then
    echo "chroot already present: $OUT"
    exit 0
fi

# Build to a temporary path and move only on success. A failed bootstrap
# otherwise leaves a truncated tarball that the check above happily accepts as
# a valid cached chroot on every subsequent run.
TMP="${OUT}.tmp"
trap 'rm -f "$TMP"' EXIT

mmdebstrap --variant=buildd --arch="$ARCH" \
    --include=ca-certificates,eatmydata \
    "$DIST" "$TMP" "$MIRROR"

mv "$TMP" "$OUT"
echo "created $OUT"
