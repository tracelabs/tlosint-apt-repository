#!/bin/bash
#
#  LOCAL ONLY -- NEVER RUN THIS IN CI.
#
#  Uploads an already-built, already-signed Qubes OS template RPM repository
#  (from tracelabs/tlosint-qube) to /qubes/<release>/ in the apt bucket, e.g.
#  https://apt.tracelabs.org/qubes/r4.3
#
#  This script does not sign anything. It refuses to upload unless both the
#  RPM and repodata/repomd.xml.asc verify against the keyring we publish.
#
#  It only ever writes or deletes under qubes/<release>/. The apt tree next to
#  it is live, and a before/after listing proves this publish left it alone.
#  See docs/repo-layout.md
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUBES_REPO="${QUBES_REPO:-${ROOT}/../tlosint-qube/repo}"
RELEASE="${RELEASE:-r4.3}"
KEYRING="${ROOT}/publish/keys/tlosint-archive-keyring.gpg"
R2_DEST="${R2_DEST:-r2:tlosint-tools}"
R2_DEST="${R2_DEST%/}"
SRC="${QUBES_REPO}/${RELEASE}"
DEST="${R2_DEST}/qubes/${RELEASE}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[[ "$RELEASE" =~ ^r[0-9]+\.[0-9]+$ ]] || {
    echo "RELEASE must look like r4.3, got: $RELEASE" >&2; exit 1; }

for tool in gpgv rclone rpmkeys zstd; do
    command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
done
[[ -f "$KEYRING" ]] || { echo "no public keyring at $KEYRING" >&2; exit 1; }

# ---------------------------------------------------------------------------
echo "==> checking $SRC"
[[ -f "$SRC/repodata/repomd.xml" && -f "$SRC/repodata/repomd.xml.asc" ]] || {
    echo "no signed repodata in $SRC -- run createrepo_c and sign repomd.xml first" >&2
    exit 1; }

echo "==> verifying repomd.xml against $KEYRING"
gpgv --keyring "$KEYRING" "$SRC/repodata/repomd.xml.asc" "$SRC/repodata/repomd.xml"

# Every metadata file repomd.xml names must exist, or dnf fails after
# fetching a perfectly valid signature.
HREFS="$(grep -oE 'location href="[^"]+"' "$SRC/repodata/repomd.xml" | cut -d'"' -f2)"
for f in $HREFS; do
    [[ -f "$SRC/$f" ]] || { echo "repomd.xml names missing file: $f" >&2; exit 1; }
done

# Publishing is stateless, like the apt side: the RPMs primary.xml lists
# are exactly what gets uploaded, and the final sync prunes anything else.
PRIMARY="$(grep -oE 'repodata/[^"]*-primary\.xml\.zst' "$SRC/repodata/repomd.xml")"
RPMS="$(zstd -dc "$SRC/$PRIMARY" | grep -oE 'location href="[^"]+\.rpm"' | cut -d'"' -f2 | sort)"
LOCAL="$(cd "$SRC" && find . -name '*.rpm' | sed 's|^\./||' | sort)"
[[ -n "$RPMS" ]] || { echo "primary.xml lists no packages" >&2; exit 1; }
[[ "$RPMS" == "$LOCAL" ]] || {
    echo "RPMs on disk do not match primary.xml -- re-run createrepo_c" >&2
    diff <(echo "$RPMS") <(echo "$LOCAL") >&2 || true
    exit 1; }

echo "==> verifying RPM signatures against $KEYRING"
# Throwaway rpmdb: the keyring is imported only for this check.
rpmkeys --dbpath "$WORK/rpmdb" --import "${KEYRING%.gpg}.asc"
for f in $RPMS; do
    rpmkeys --dbpath "$WORK/rpmdb" --checksig "$SRC/$f" | grep -q 'signatures OK' || {
        echo "bad or missing signature: $f" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# Guard against a typo'd R2_DEST: the bucket must already be the live apt
# repo. Then snapshot everything outside qubes/ so we can prove it is
# untouched afterwards.
echo "==> checking $R2_DEST is the apt bucket"
rclone lsf "$R2_DEST/dists/stable/InRelease" >/dev/null 2>&1 || {
    echo "no dists/stable/InRelease in $R2_DEST -- wrong R2_DEST?" >&2; exit 1; }
# Sorted: rclone's recursive listing order is not stable between runs.
SNAPSHOT=(rclone lsf -R --files-only --format "pst" --exclude "/qubes/**" "$R2_DEST")
"${SNAPSHOT[@]}" | sort > "$WORK/before"

echo
echo "    from: $SRC"
echo "    to:   $DEST"
printf '    %s\n' $RPMS
read -r -p "Publish these to $DEST? [y/N] " answer
[[ "$answer" == [yY] ]] || { echo "aborted"; exit 1; }

# ---------------------------------------------------------------------------
# Same order as the apt publish: payload, then hash-named metadata, then the
# signed repomd.xml that points at them, and only then delete. A client
# refreshing mid-publish never follows a reference to a missing file.
IMMUTABLE="Cache-Control: public, max-age=31536000, immutable"
SHORT="Cache-Control: public, max-age=60"
RCLONE=(rclone copy --stats-one-line --stats 10s)

echo "==> uploading RPMs"
"${RCLONE[@]}" --header-upload "$IMMUTABLE" --include "*.rpm" "$SRC" "$DEST"

echo "==> uploading metadata"
"${RCLONE[@]}" --header-upload "$IMMUTABLE" --include "/repodata/*.xml.zst" "$SRC" "$DEST"

echo "==> uploading repomd.xml"
"${RCLONE[@]}" --header-upload "$SHORT" \
    --include "/repodata/{repomd.xml,repomd.xml.asc}" "$SRC" "$DEST"

echo "==> removing files no longer published under $DEST"
# Scoped to $DEST: rclone sync never looks above the path it is given.
rclone sync --stats-one-line --stats 0 \
    --include "*.rpm" --include "/repodata/**" "$SRC" "$DEST"

echo "==> checking nothing outside qubes/ changed"
"${SNAPSHOT[@]}" | sort > "$WORK/after"
if ! diff "$WORK/before" "$WORK/after"; then
    echo "WARNING: objects outside qubes/ changed during this publish" >&2
    echo "         (a concurrent apt publish?) -- investigate before announcing" >&2
    exit 1
fi

echo "==> done. https://apt.tracelabs.org/qubes/${RELEASE}/repodata/repomd.xml"
