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
#
# The temp name must keep the .tar.zst suffix: mmdebstrap infers both the
# container format and the compressor from the output extension. A bare .tmp
# suffix makes it silently choose "directory" format instead.
TMP="$(dirname "$OUT")/.tmp-$(basename "$OUT")"
trap 'rm -rf "$TMP"' EXIT

# Ubuntu's debian-archive-keyring stops at bookworm, so bootstrapping trixie
# from an Ubuntu host fails with NO_PUBKEY unless we supply Debian's keys.
# KEYRING is set by CI; unset on a Debian host, where apt already has them.
KEYRING_ARGS=()
if [[ -n "${KEYRING:-}" ]]; then
    [[ -f "$KEYRING" ]] || { echo "KEYRING set but missing: $KEYRING" >&2; exit 1; }
    KEYRING_ARGS=(--keyring="$KEYRING")
fi

mmdebstrap --variant=buildd --arch="$ARCH" \
    "${KEYRING_ARGS[@]}" \
    --include=ca-certificates,eatmydata,debian-archive-keyring \
    "$DIST" "$TMP" "$MIRROR"

mv "$TMP" "$OUT"
echo "created $OUT"
