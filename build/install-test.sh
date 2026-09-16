#!/bin/bash
# Install every built .deb into a clean Debian environment and smoke-test it.
#
# This catches what lintian will not: broken venv paths, wrappers pointing at
# nonexistent interpreters, missing runtime Depends.
#
# Two modes:
#   docker (default) -- spins up debian:<dist>-slim. For local use.
#   native (NATIVE=1) -- installs into the current system. For CI, where the
#     job already runs inside a clean debian:<dist> container and no Docker
#     daemon is reachable from within it.
set -euo pipefail

DIST="${1:-trixie}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="${ARTIFACTS:-${ROOT}/artifacts}"

shopt -s nullglob
DEBS=("$ARTIFACTS"/*.deb)
(( ${#DEBS[@]} )) || { echo "no debs in $ARTIFACTS" >&2; exit 1; }

# The smoke tests themselves, run inside whichever clean environment we got.
read -r -d '' SMOKE <<'SMOKE_EOF' || true
    apt-get update -qq
    apt-get install -y --no-install-recommends /debs/*.deb

    # tlosint-meta is pure Depends. Proving it is installed proves apt
    # resolved and pulled every tool it names.
    dpkg-query -W -f='${Status}\n' tlosint-meta | grep -q 'install ok installed'
    for cmd in exiftool tor httrack; do
        command -v "$cmd" >/dev/null || { echo "missing: $cmd" >&2; exit 1; }
    done

    # TODO: per-tool smoke tests as real tools land, e.g.
    #   sherlock --version
    #   test -x /opt/tracelabs/sherlock/bin/sherlock
    echo "install test passed"
SMOKE_EOF

if [[ "${NATIVE:-0}" == "1" ]]; then
    echo "==> install test (native, in-place)"
    # Mirror the docker layout so the smoke script is identical in both modes.
    mkdir -p /debs && cp "$ARTIFACTS"/*.deb /debs/
    bash -euo pipefail -c "$SMOKE"
else
    echo "==> install test (docker, debian:${DIST}-slim)"
    docker run --rm -v "$ARTIFACTS":/debs:ro "debian:${DIST}-slim" \
        bash -euo pipefail -c "$SMOKE"
fi
