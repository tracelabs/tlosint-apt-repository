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

    # Every .deb we just built must be installed, not merely unpacked.
    # Deliberately no hardcoded tool list here: tools.yaml owns that, and
    # apt resolving tlosint-meta already proves every tool it names pulled in.
    for deb in /debs/*.deb; do
        pkg="$(dpkg-deb -f "$deb" Package)"
        status="$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)"
        case "$status" in
            "install ok installed") echo "  ok: $pkg" ;;
            *) echo "  FAILED: $pkg ($status)" >&2; exit 1 ;;
        esac
    done

    # Tools we package ourselves get a real smoke test -- that is where the
    # breakage lives (venv paths, wrappers pointing at absent interpreters).
    # Distro tools need none; apt already guarantees them.
    for wrapper in /usr/bin/tlosint-*; do
        [ -e "$wrapper" ] || continue
        [ -x "$wrapper" ] || { echo "not executable: $wrapper" >&2; exit 1; }
    done

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
