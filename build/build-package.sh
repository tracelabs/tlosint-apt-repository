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

# dpkg executes debian/rules as a program, and dpkg-source runs maintainer
# scripts the same way. A non-executable one surfaces from deep inside fakeroot
# as "debian/rules: Permission denied", which does not name the real problem.
# The bit has to be committed, not fixed at build time, or it works in CI and
# breaks for everyone cloning fresh.
for f in "$SRC"/debian/rules "$SRC"/debian/{pre,post}{inst,rm}; do
    [[ -f "$f" ]] || continue
    [[ -x "$f" ]] && continue
    echo "not executable: ${f#"$ROOT"/}" >&2
    echo "  fix with:  chmod +x '${f#"$ROOT"/}' && git update-index --chmod=+x '${f#"$ROOT"/}'" >&2
    exit 1
done
[[ -f "$CHROOT"     ]] || { echo "no chroot; run: make chroot" >&2; exit 1; }

mkdir -p "$ARTIFACTS"

# Upstream source is deliberately NOT fetched here. dpkg-source only tars
# packages/<pkg>/, so anything under build/ is absent from the .dsc -- a source
# package only we could rebuild is not a publishable one. Fetching here would
# also vendor upstream into the .dsc (contradicting the native-format rationale
# in handoff section 8) and would turn the narrow, per-package network opt-in
# below into a global host-side one.
#
# Instead: tools on PyPI, and tools whose upstream ships an installable tree,
# are pinned as hashed lines in the package's own requirements.txt. Tools with
# no packaging metadata at all fetch in their debian/rules against a pinned
# commit recorded in debian/upstream.pin. See handoff section 7.

# Packages that install from a language ecosystem at build time (dh_virtualenv
# reaching PyPI, and later cargo/go) cannot build in sbuild's default offline
# chroot. Opt in per package rather than globally, so packages that genuinely
# build offline keep the stronger guarantee.
NETWORK_ARGS=()
if [[ -f "$SRC/debian/NEEDS-NETWORK" ]]; then
    echo "note: $PKG builds with network enabled (debian/NEEDS-NETWORK)"
    NETWORK_ARGS=(--enable-network)
fi

cd "$SRC"
# --no-clean-source: sbuild otherwise runs "debian/rules clean" on the HOST
# before entering the chroot, which drags every package's build tooling onto
# the host -- dh-virtualenv for python tools, and cargo/go for the kinds still
# to come. The chroot is where build tooling belongs. CI checkouts are clean by
# construction; locally, "make clean" covers it.
sbuild \
    "${NETWORK_ARGS[@]}" \
    --no-clean-source \
    --chroot-mode=unshare \
    --chroot="$CHROOT" \
    --dist="$DIST" \
    --arch="$ARCH" \
    --no-run-lintian \
    --build-dir="$ARTIFACTS" \
    .

echo "built $PKG -> $ARTIFACTS"
