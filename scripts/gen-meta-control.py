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


def depends_for(tool: dict) -> str | None:
    kind = tool.get("kind")
    if kind == "distro":
        return tool.get("package") or tool["name"]
    if kind in ("python", "go", "binary"):
        return f"{BINARY_PREFIX}{tool['name']}"
    print(f"warning: unknown kind {kind!r} for {tool['name']}", file=sys.stderr)
    return None


def main() -> int | str:
    ap = argparse.ArgumentParser()
    ap.add_argument("tools")
    ap.add_argument("--template", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    with open(args.tools) as fh:
        tools = yaml.safe_load(fh) or []

    deps = sorted(filter(None, (depends_for(t) for t in tools)))
    if not deps:
        return "no dependencies generated; is tools.yaml populated?"

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
