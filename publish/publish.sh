#!/bin/bash
#
#  LOCAL ONLY -- NEVER RUN THIS IN CI.
#
#  This script signs and uploads. If the signing key or the R2 token ever
#  lives in Actions secrets then GitHub, or anyone who lands a malicious
#  workflow change, can sign packages that users' systems will trust or
#  replace what they download. CI builds and tests; a human publishes.
#
#  Flow: CI builds -> you download the artifact into ./artifacts -> this
#  script assembles the whole repo tree, signs Release, uploads it to R2.
#
#  Prerequisites: the signing subkey imported into $GNUPGHOME, an rclone
#  remote for the R2 bucket, and docker (or apt-ftparchive on PATH).
#  See docs/signing-runbook.md and docs/repo-layout.md
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Packages are built in CI and downloaded by hand as a workflow artifact.
# Point this at wherever you unpacked them; defaults to ./artifacts.
ARTIFACTS="${ARTIFACTS:-${ROOT}/artifacts}"
KEYRING="${ROOT}/publish/keys/tlosint-archive-keyring.gpg"
R2_DEST="${R2_DEST:-r2:tlosint-tools}"
WORK="$(mktemp -d)"
REPO="$WORK/repo"
trap 'rm -rf "$WORK"' EXIT

: "${TLOSINT_APT_KEYID:?set to the signing subkey fingerprint}"
# Full fingerprint only: a short or long key id can collide, and the trailing
# '!' below only pins a subkey when gpg can identify it exactly.
KEYID="$(tr '[:lower:]' '[:upper:]' <<<"${TLOSINT_APT_KEYID#0x}")"
[[ "$KEYID" =~ ^[0-9A-F]{40}$ ]] || {
    echo "TLOSINT_APT_KEYID must be a 40-hex-digit subkey fingerprint" >&2; exit 1; }

for tool in gpg gpgv rclone; do
    command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
done
[[ -f "$KEYRING" ]] || { echo "no public keyring at $KEYRING" >&2; exit 1; }

# ---------------------------------------------------------------------------
echo "==> checking artifacts in $ARTIFACTS"
[[ -d "$ARTIFACTS" ]] || { echo "no artifacts dir: $ARTIFACTS" >&2; exit 1; }
shopt -s nullglob
DEBS=("$ARTIFACTS"/*.deb)
(( ${#DEBS[@]} )) || { echo "no .deb files in $ARTIFACTS" >&2; exit 1; }

# Publishing is stateless: whatever is in the artifacts dir *is* the repo.
# Two versions of one package means a leftover from an earlier download.
# (No associative arrays: macOS /bin/bash is 3.2.)
DUPES="$(printf '%s\n' "${DEBS[@]##*/}" | cut -d_ -f1 | sort | uniq -d)"
if [[ -n "$DUPES" ]]; then
    echo "more than one version of: $DUPES" >&2
    echo "empty $ARTIFACTS and re-download the artifact" >&2
    exit 1
fi

printf '    %s\n' "${DEBS[@]##*/}"
read -r -p "Publish these ${#DEBS[@]} packages to $R2_DEST? [y/N] " answer
[[ "$answer" == [yY] ]] || { echo "aborted"; exit 1; }

# ---------------------------------------------------------------------------
echo "==> assembling repository tree"
mkdir -p "$REPO/pool/main" "$REPO/dists/stable/main/binary-amd64" \
         "$REPO/dists/stable/main/binary-all"
cp "${DEBS[@]}" "$REPO/pool/main/"
cp "$ROOT/publish/apt-ftparchive.conf" "$REPO/"
# Landing page and the public keyring live at the root, next to dists/ and
# pool/. Publishing is stateless, so they go into the tree every time or
# the final sync deletes them.
cp "$ROOT/publish/index.html" "$KEYRING" "${KEYRING%.gpg}.asc" "$REPO/"

# Release is written to a temp name: apt-ftparchive hashes everything under
# dists/stable, and must not find a half-written Release in there.
FTPARCHIVE='apt-ftparchive generate apt-ftparchive.conf &&
    apt-ftparchive -c apt-ftparchive.conf release dists/stable > Release.tmp &&
    mv Release.tmp dists/stable/Release && rm apt-ftparchive.conf'

if command -v apt-ftparchive >/dev/null; then
    (cd "$REPO" && sh -c "$FTPARCHIVE")
else
    # No apt-ftparchive on macOS; borrow one from a throwaway Debian container.
    # chown back afterwards, or on a Linux host the tree ends up root-owned
    # and the cleanup trap cannot remove it.
    command -v docker >/dev/null || {
        echo "need apt-ftparchive on PATH, or docker to run it" >&2; exit 1; }
    docker run --rm -v "$REPO:/repo" -w /repo debian:trixie-slim sh -c "
        apt-get update -qq && apt-get install -y -qq --no-install-recommends apt-utils >/dev/null &&
        $FTPARCHIVE && chown -R $(id -u):$(id -g) /repo"
fi

# ---------------------------------------------------------------------------
echo "==> signing Release"
# Only Release is signed. apt's chain runs InRelease -> hashes -> debs, so
# one signature covers every file in the tree.
export GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg}"

# The subkey's secret must actually be here. A '#' in field 15 of the ssb
# record means gpg only has a stub (e.g. the primary-only backup keyring).
if ! gpg --batch --with-colons --list-secret-keys "${KEYID}!" 2>/dev/null | awk -F: -v fpr="$KEYID" '
        $1 == "ssb" { ok = ($15 != "#") }
        $1 == "fpr" && $10 == fpr && ok { found = 1 }
        $1 != "fpr" && $1 != "grp" && $1 != "ssb" { ok = 0 }
        END { exit !found }'; then
    echo "signing subkey $KEYID not usable in $GNUPGHOME -- see docs/signing-runbook.md" >&2
    exit 1
fi

# The trailing '!' forces this exact subkey rather than letting gpg pick
# whichever signing-capable key it prefers.
SIGN=(gpg --local-user "${KEYID}!" --digest-algo SHA512)
"${SIGN[@]}" --clearsign -o "$REPO/dists/stable/InRelease" "$REPO/dists/stable/Release"
"${SIGN[@]}" --detach-sign --armor \
    -o "$REPO/dists/stable/Release.gpg" "$REPO/dists/stable/Release"

# Check against the keyring users actually install. A signature it cannot
# verify would break every user's apt update, so never upload one.
echo "==> verifying against $KEYRING"
gpgv --keyring "$KEYRING" "$REPO/dists/stable/InRelease"
gpgv --keyring "$KEYRING" "$REPO/dists/stable/Release.gpg" "$REPO/dists/stable/Release"

# ---------------------------------------------------------------------------
# Upload order matters: a client mid-`apt update` must never read an index
# that names a file not yet in the bucket. So: payload first, then indexes,
# then the signed Release that points at them, and only then delete.
IMMUTABLE="Cache-Control: public, max-age=31536000, immutable"
SHORT="Cache-Control: public, max-age=60"
RCLONE=(rclone copy --stats-one-line --stats 0)

echo "==> uploading pool and by-hash to $R2_DEST"
"${RCLONE[@]}" --header-upload "$IMMUTABLE" "$REPO/pool" "$R2_DEST/pool"
"${RCLONE[@]}" --header-upload "$IMMUTABLE" --include "**/by-hash/**" \
    "$REPO/dists" "$R2_DEST/dists"

echo "==> uploading indexes"
"${RCLONE[@]}" --header-upload "$SHORT" \
    --exclude "**/by-hash/**" --exclude "/stable/{InRelease,Release,Release.gpg}" \
    "$REPO/dists" "$R2_DEST/dists"

echo "==> uploading Release"
"${RCLONE[@]}" --header-upload "$SHORT" \
    --include "/stable/{Release,Release.gpg,InRelease}" \
    "$REPO/dists" "$R2_DEST/dists"

echo "==> uploading index page and keyring"
"${RCLONE[@]}" --header-upload "$SHORT" --max-depth 1 \
    --include "/{index.html,tlosint-archive-keyring.gpg,tlosint-archive-keyring.asc}" \
    "$REPO" "$R2_DEST"

echo "==> removing files no longer published"
# qubes/ is published separately by publish-qubes.sh and is not in $REPO,
# so it must be excluded or this sync deletes the whole Qubes repository.
rclone sync --stats-one-line --stats 0 --exclude "/qubes/**" "$REPO" "$R2_DEST"

echo "==> done. Verify from a clean container before announcing:"
echo "    docker run --rm -it --platform linux/amd64 debian:trixie-slim"
