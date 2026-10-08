# tlosint-apt-repository

Debian packaging and signed apt repository for the Trace Labs OSINT toolset.

Replaces upstream's `curl | bash` installer with real, versioned, signed
packages — and provides the package set that a native Qubes OS template will
later be built from.

> **Status: skeleton.** Nothing is built or published yet. Files contain `TODO`
> markers and placeholder values. See [`handoff.md`](handoff.md) for full
> project context and the ordered task list.

## Install

```bash
sudo install -m 0644 tlosint-archive-keyring.gpg /etc/apt/keyrings/
sudo tee /etc/apt/sources.list.d/tlosint.sources <<'EOF'
Types: deb
URIs: https://apt.tracelabs.org
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/tlosint-archive-keyring.gpg
EOF
sudo apt update && sudo apt install tlosint-meta
```

## Develop

```bash
make chroot     # once
make build      # all packages, or PKG=sherlock for one
make test
```

## Publish

`make publish` is **local only** and requires the signing hardware. CI never
signs. See [`docs/signing-runbook.md`](docs/signing-runbook.md).

## Layout

| Path | Purpose |
|---|---|
| `tools.yaml` | Single source of truth for the tool list |
| `packages/*/debian/` | One source package per tool |
| `build/` | sbuild wrappers, chroot creation, install tests |
| `publish/` | Repo metadata config and the signing publish script |
| `scripts/` | `tools.yaml` codegen |
| `docs/` | Signing runbook, published repo layout |

## License

GPL-3.0, matching upstream tracelabs/tlosint-vm.
