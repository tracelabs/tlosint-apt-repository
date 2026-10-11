#!/bin/bash
#
#  LOCAL ONLY -- signs with the local GPG subkey. Never run this in CI.
#
#  Builds qubes-repo-tlosint (qubes/qubes-repo-tlosint.spec) in a Fedora
#  container matching the Qubes R4.3 dom0 base, signs it here, and verifies
#  the signature against the keyring we publish. The signed RPM goes into
#  $ARTIFACTS/qubes/ for attaching to a GitHub release.
#
#  Prerequisites: docker, rpmsign, rpmkeys, and the signing subkey in
#  $GNUPGHOME.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="${ARTIFACTS:-${ROOT}/artifacts}"
OUT="${ARTIFACTS}/qubes"
KEYRING="${ROOT}/publish/keys/tlosint-archive-keyring.gpg"
# Qubes R4.3 dom0 is Fedora 41.
FEDORA="${FEDORA:-fedora:41}"

: "${TLOSINT_APT_KEYID:?set to the signing subkey fingerprint}"
KEYID="$(tr '[:lower:]' '[:upper:]' <<<"${TLOSINT_APT_KEYID#0x}")"
[[ "$KEYID" =~ ^[0-9A-F]{40}$ ]] || {
    echo "TLOSINT_APT_KEYID must be a 40-hex-digit subkey fingerprint" >&2; exit 1; }

for tool in docker rpmsign rpmkeys; do
    command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
echo "==> staging sources"
# Under $ARTIFACTS rather than mktemp: Docker Desktop only shares some host
# paths, and the repo checkout is always one of them.
rm -rf "$OUT"
mkdir -p "$OUT/SOURCES" "$OUT/rpms"
cp "$ROOT/qubes/qubes-repo-tlosint.spec" "$ROOT/qubes/tlosint.repo" \
   "${KEYRING%.gpg}.asc" "$OUT/SOURCES/"

echo "==> building in $FEDORA"
docker run --rm -v "$OUT:/w" -w /w "$FEDORA" sh -c "
    dnf install -q -y rpm-build >/dev/null &&
    rpmbuild -bb --define '_sourcedir /w/SOURCES' --define '_rpmdir /w/rpms' \
        SOURCES/qubes-repo-tlosint.spec &&
    chown -R $(id -u):$(id -g) /w"

shopt -s nullglob
RPMS=("$OUT"/rpms/noarch/qubes-repo-tlosint-*.noarch.rpm)
(( ${#RPMS[@]} == 1 )) || { echo "expected exactly one RPM in $OUT/rpms" >&2; exit 1; }
RPM="${RPMS[0]}"

# ---------------------------------------------------------------------------
echo "==> signing ${RPM##*/}"
# Explicit key, so a stray ~/.rpmmacros cannot pick a different one. The
# trailing '!' pins this exact subkey, as in publish/publish.sh.
export GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg}"
GPG_TTY="$(tty 2>/dev/null)" && export GPG_TTY || true
rpmsign --addsign \
    --define "_openpgp_sign gpg" \
    --define "_openpgp_sign_id ${KEYID}!" \
    --define "_gpg_digest_algo sha512" \
    "$RPM"

# dom0 checks this against the key the user imports, so check it against
# the published keyring in a throwaway rpmdb before anyone downloads it.
echo "==> verifying against ${KEYRING%.gpg}.asc"
rpmkeys --dbpath "$OUT/rpmdb" --import "${KEYRING%.gpg}.asc"
rpmkeys --dbpath "$OUT/rpmdb" --checksig -v "$RPM"
rpmkeys --dbpath "$OUT/rpmdb" --checksig "$RPM" | grep -q 'signatures OK' || {
    echo "signature does not verify" >&2; exit 1; }

mv "$RPM" "$OUT/"
rm -rf "$OUT/SOURCES" "$OUT/rpms" "$OUT/rpmdb"
RPM="$OUT/${RPM##*/}"
(cd "$OUT" && shasum -a 256 "${RPM##*/}" > SHA256SUMS)

echo "==> contents"
rpm -qlp --nosignature "$RPM"
echo "==> done: $RPM"
cat "$OUT/SHA256SUMS"
