#!/usr/bin/env python3
"""Generate tlosint-meta's debian/control from tools.yaml.

tools.yaml is the single source of truth for the tool list. This keeps the
metapackage's Depends in sync with it so the two cannot drift.
"""
# PEP 604 unions below are evaluated at runtime without this on Python < 3.10.
from __future__ import annotations

import argparse
import sys

try:
    import yaml
except ImportError:
    sys.exit("pip install pyyaml")

# kind -> how the tool appears as a dependency
BINARY_PREFIX = "tlosint-"


KINDS = {"distro", "python", "go", "rust", "binary", "docker"}
STATUSES = {"ready", "planned", "gated"}


def depends_for(tool: dict) -> list[str]:
    """Debian dependencies contributed by one tool.

    Only status:ready tools contribute. Everything else is inventory: it is
    tracked in tools.yaml so the manifest stays the single source of truth,
    but it must not land in Depends or tlosint-meta becomes uninstallable.
    """
    name = tool["name"]
    kind = tool.get("kind")
    status = tool.get("status", "ready")

    if kind not in KINDS:
        print(f"warning: unknown kind {kind!r} for {name}", file=sys.stderr)
        return []
    if status not in STATUSES:
        print(f"warning: unknown status {status!r} for {name}", file=sys.stderr)
        return []
    if status != "ready":
        return []

    if kind == "distro":
        pkg = tool.get("package") or name
        return [pkg] if isinstance(pkg, str) else list(pkg)
    return [f"{BINARY_PREFIX}{name}"]


def main() -> int | str:
    ap = argparse.ArgumentParser()
    ap.add_argument("tools")
    ap.add_argument("--template", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    with open(args.tools) as fh:
        tools = yaml.safe_load(fh) or []

    deps = sorted({d for t in tools for d in depends_for(t)})
    if not deps:
        return "no dependencies generated; is tools.yaml populated?"

    by_status: dict[str, int] = {}
    for t in tools:
        by_status[t.get("status", "ready")] = by_status.get(t.get("status", "ready"), 0) + 1
    skipped = ", ".join(f"{n} {s}" for s, n in sorted(by_status.items()) if s != "ready")
    if skipped:
        print(f"note: not in Depends -- {skipped}", file=sys.stderr)

    block = ",\n".join(f"         {d}" for d in deps)

    with open(args.template) as fh:
        text = fh.read()
    text = text.replace("@GENERATED_DEPENDS@", block)

    with open(args.out, "w") as fh:
        fh.write(text)
    print(f"wrote {args.out} with {len(deps)} dependencies")
    return 0


if __name__ == "__main__":
    sys.exit(main())
