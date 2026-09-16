#!/bin/bash
#
#  LOCAL ONLY -- NEVER RUN THIS IN CI.
#
#  This script signs. If the key ever lives in Actions secrets then GitHub,
#  or anyone who lands a malicious workflow change, can sign packages that
#  users' systems will trust. CI builds and tests; a human publishes.
#
#  Prerequisites: OnlyKey plugged in and unlocked, onlykey-agent running.
#  See docs/signing-runbook.md
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Packages are built in CI and downloaded as a workflow artifact. Point this at
# wherever you unpacked them; defaults to ./artifacts.
ARTIFACTS="${ARTIFACTS:-${ROOT}/artifacts}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[[ -d "$ARTIFACTS" ]] || { echo "no artifacts dir: $ARTIFACTS" >&2; exit 1; }
shopt -s nullglob
DEBS=("$ARTIFACTS"/*.deb)
(( ${#DEBS[@]} )) || { echo "no .deb files in $ARTIFACTS" >&2; exit 1; }

: "${TLOSINT_APT_KEYID:?set to the signing subkey fingerprint}"
: "${GH_PAGES_REMOTE:=origin}"
# Custom domain for the Pages site. Written into the published tree on every
# publish -- see the CNAME note below.
APT_CNAME="${APT_CNAME:-apt.tracelabs.org}"
KEEP_VERSIONS="${KEEP_VERSIONS:-3}"

# OnlyKey is not an OpenPGP smartcard -- it goes through onlykey-agent, which
# needs its own GNUPGHOME and cannot mix software keys into that keyring.
export GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg/onlykey}"
[[ -d "$GNUPGHOME" ]] || { echo "no onlykey GNUPGHOME at $GNUPGHOME" >&2; exit 1; }

REMOTE_URL="$(git -C "$ROOT" remote get-url "$GH_PAGES_REMOTE")"

echo "==> fetching currently published tree"
# On the very first publish gh-pages does not exist yet. The fallback must
# still leave a real git repository behind, or the orphan checkout below fails.
if ! git clone -q --depth 1 --branch gh-pages "$REMOTE_URL" "$WORK/pages" 2>/dev/null; then
    echo "    (no existing gh-pages; starting fresh)"
    git init -q "$WORK/pages"
fi

cd "$WORK/pages"
mkdir -p pool/main dists/stable/main/binary-amd64 dists/stable/main/binary-all
touch .nojekyll   # without this, Jekyll can mangle or drop repo paths

# Both of these live in the published tree and are wiped by every orphan
# commit unless rewritten here. CNAME is what binds the custom domain to the
# Pages site -- losing it silently reverts users to the *.github.io host.
echo "$APT_CNAME" > CNAME

echo "==> adding new packages"
cp "$ARTIFACTS"/*.deb pool/main/

# TODO: prune pool/main to the last $KEEP_VERSIONS of each package name

echo "==> generating metadata"
cp "$ROOT/publish/apt-ftparchive.conf" .
apt-ftparchive generate apt-ftparchive.conf
apt-ftparchive -c apt-ftparchive.conf release dists/stable > dists/stable/Release.tmp
mv dists/stable/Release.tmp dists/stable/Release
rm apt-ftparchive.conf

echo "==> signing (touch the OnlyKey when it asks)"
# Only Release is signed. apt's chain runs InRelease -> hashes -> debs, so
# debsigs/dpkg-sig are unnecessary and the hardware is touched once per release.
rm -f dists/stable/InRelease dists/stable/Release.gpg
gpg --default-key "$TLOSINT_APT_KEYID" --clearsign \
    -o dists/stable/InRelease dists/stable/Release
gpg --default-key "$TLOSINT_APT_KEYID" --detach-sign --armor \
    -o dists/stable/Release.gpg dists/stable/Release

echo "==> publishing as orphan commit"
# Force-pushed orphan keeps binaries out of git history. Without this the
# repo accumulates every .deb ever shipped, forever.
git checkout -q --orphan publish
git add -A
git -c user.name="tlosint release" -c user.email="jeff.g@tracelabs.org" \
    commit -q -m "apt repository $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git push -q --force "$REMOTE_URL" publish:gh-pages

echo "==> done. Verify from a clean container before announcing:"
echo "    docker run --rm -it debian:trixie-slim"
