#!/usr/bin/env python3
"""Regenerate the tool table in README.md from tools.yaml.

Rewrites everything between the <!-- tools:start --> and <!-- tools:end -->
markers, so the README's tool list cannot drift from the manifest.
"""
# PEP 604 unions below are evaluated at runtime without this on Python < 3.10.
from __future__ import annotations

import argparse
import re
import sys

try:
    import yaml
except ImportError:
    sys.exit("pip install pyyaml")

START, END = "<!-- tools:start -->", "<!-- tools:end -->"


def status_for(tool: dict) -> str:
    status = tool.get("status", "ready")
    if status == "ready":
        return "Available (Debian)" if tool.get("kind") == "distro" else "Available"
    if status == "gated":
        return "Opt-in, not shipped"
    return "In development"


def package_for(tool: dict) -> str:
    if tool.get("status", "ready") != "ready":
        return ""
    if tool.get("kind") == "distro":
        pkg = tool.get("package") or tool["name"]
        pkgs = [pkg] if isinstance(pkg, str) else pkg
        return ", ".join(f"`{p}`" for p in pkgs)
    return f"`tlosint-{tool['name']}`"


def name_for(tool: dict) -> str:
    src = tool.get("source")
    return f"[{tool['name']}]({src})" if src else tool["name"]


def table(tools: list[dict]) -> str:
    # Available first, then in development, then opt-in; alphabetical within.
    order = {"ready": 0, "planned": 1, "gated": 2}
    rows = sorted(tools, key=lambda t: (order.get(t.get("status", "ready"), 1), t["name"]))
    lines = ["| Tool | Description | Package | Status |", "|---|---|---|---|"]
    lines += [
        f"| {name_for(t)} | {t.get('summary', '')} | {package_for(t)} | {status_for(t)} |"
        for t in rows
    ]
    return "\n".join(lines)


def main() -> int | str:
    ap = argparse.ArgumentParser()
    ap.add_argument("tools")
    ap.add_argument("--readme", required=True)
    args = ap.parse_args()

    with open(args.tools) as fh:
        tools = yaml.safe_load(fh) or []
    with open(args.readme) as fh:
        text = fh.read()

    pattern = re.compile(re.escape(START) + r".*?" + re.escape(END), re.S)
    if not pattern.search(text):
        return f"{args.readme} has no {START} ... {END} block"
    text = pattern.sub(lambda _: f"{START}\n{table(tools)}\n{END}", text)

    with open(args.readme, "w") as fh:
        fh.write(text)
    print(f"wrote {len(tools)} tools to {args.readme}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
