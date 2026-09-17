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

# World-readable staging dir for the keyring -- see the chmod note below.
STAGE="$(mktemp -d)"
chmod 0755 "$STAGE"
trap 'rm -rf "$TMP" "$STAGE"' EXIT

# Debian's archive keys. Ubuntu's debian-archive-keyring stops at bookworm, so
# bootstrapping trixie from an Ubuntu host fails with NO_PUBKEY. On a Debian
# host apt already has them; anywhere else we must supply them.
#
# Self-contained rather than relying on CI to export KEYRING: a silently-empty
# variable reintroduces the exact NO_PUBKEY failure this exists to prevent, and
# looks identical to having no fix at all.
HOST_ID="$(. /etc/os-release 2>/dev/null && echo "${ID:-unknown}")"
KEYRING_ARGS=()
KEYRING_SRC="${KEYRING:-}"

if [[ -z "$KEYRING_SRC" && "$HOST_ID" != "debian" ]]; then
    # Lift the keys out of Debian's own image. Preferred over pinning a keyring
    # .deb by hash: Debian's pool drops superseded versions, so a pinned URL
    # 404s on its own schedule.
    command -v docker >/dev/null || {
        echo "host is '$HOST_ID', not debian, and has no docker to source" >&2
        echo "Debian's archive keys from. Either run on Debian, or set" >&2
        echo "KEYRING=/path/to/debian-archive-keyring.gpg" >&2
        exit 1
    }
    echo "host is '$HOST_ID'; extracting Debian archive keyring from debian:${DIST}"
    KEYRING_SRC="${STAGE}/extracted.gpg"
    docker run --rm "debian:${DIST}" \
        cat /usr/share/keyrings/debian-archive-keyring.gpg > "$KEYRING_SRC"
fi

if [[ -n "$KEYRING_SRC" ]]; then
    [[ -s "$KEYRING_SRC" ]] || { echo "keyring missing or empty: $KEYRING_SRC" >&2; exit 1; }
    # Stage into a world-readable location. apt drops privileges to the _apt
    # user to verify signatures, so a keyring under a 0700 home (the default
    # for root, and for some CI users) is unreadable to it -- and apt does not
    # report a permission error. It silently proceeds with no keys and fails
    # with NO_PUBKEY, which looks exactly like not passing --keyring at all.
    cp "$KEYRING_SRC" "${STAGE}/debian-archive-keyring.gpg"
    chmod 0644 "${STAGE}/debian-archive-keyring.gpg"
    KEYRING_ARGS=(--keyring="${STAGE}/debian-archive-keyring.gpg")
fi

mmdebstrap --variant=buildd --arch="$ARCH" \
    "${KEYRING_ARGS[@]}" \
    --include=ca-certificates,eatmydata,debian-archive-keyring \
    "$DIST" "$TMP" "$MIRROR"

mv "$TMP" "$OUT"
echo "created $OUT"
