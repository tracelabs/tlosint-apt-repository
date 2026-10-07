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

    # Entry points shipped by our own packages get a real smoke test -- that is
    # where breakage lives: venv paths, shebangs left pointing into the build
    # directory, hand-written wrappers naming an interpreter that is not there.
    #
    # Derived from "dpkg -L" rather than a hardcoded list or a /usr/bin/tlosint-*
    # glob. The binaries are named after the TOOL (maigret, ghunt), not after the
    # package (tlosint-maigret), so that glob matched nothing and this check
    # silently passed for as long as it existed. Asking dpkg keeps tools.yaml as
    # the only place the tool list lives.
    for deb in /debs/*.deb; do
        pkg="$(dpkg-deb -f "$deb" Package)"
        # Pure-Depends, config and keyring packages ship no entry point by design.
        case "$pkg" in tlosint-meta|tlosint-config|tlosint-archive-keyring) continue ;; esac

        found=0
        while IFS= read -r f; do
            [ -e "$f" ] || continue
            found=1
            [ -x "$f" ] || { echo "  not executable: $f" >&2; exit 1; }

            target="$(readlink -f "$f")"
            [ -e "$target" ] || { echo "  dangling: $f -> $target" >&2; exit 1; }
            case "$target" in
                /opt/tracelabs/*) : ;;
                *) echo "  $f resolves outside /opt/tracelabs: $target" >&2; exit 1 ;;
            esac

            # The check that actually proves the venv works end to end.
            if "$f" --help >/dev/null 2>&1; then
                echo "  entrypoint ok: $f -> $target"
            else
                echo "  FAILED: $f --help exited non-zero" >&2
                exit 1
            fi
        done <<EOF
$(dpkg -L "$pkg" | grep '^/usr/bin/' || true)
EOF

        [ "$found" = 1 ] || { echo "  no /usr/bin entry point in $pkg" >&2; exit 1; }
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
