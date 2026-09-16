#!/bin/bash
# Install every built .deb in a clean container and smoke-test it.
#
# This catches what lintian will not: broken venv paths, wrappers pointing at
# nonexistent interpreters, missing runtime Depends.
set -euo pipefail

DIST="${1:-trixie}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="${ROOT}/artifacts"

shopt -s nullglob
DEBS=("$ARTIFACTS"/*.deb)
(( ${#DEBS[@]} )) || { echo "no debs in $ARTIFACTS" >&2; exit 1; }

docker run --rm -v "$ARTIFACTS":/debs:ro "debian:${DIST}-slim" bash -euo pipefail -c '
    apt-get update -qq
    apt-get install -y --no-install-recommends /debs/*.deb
    # TODO: per-tool smoke tests, e.g.
    #   sherlock --version
    #   test -x /opt/tracelabs/sherlock/bin/sherlock
    echo "install test passed"
'
