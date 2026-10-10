# tlosint-apt-repository

Debian packaging and signed apt repository for the Trace Labs OSINT toolset.

Replaces upstream's `curl | bash` installer with real, versioned, signed
packages — and provides the package set that a native Qubes OS template will
later be built from.

## Root Signing Key

Our signing key fingerprint is: `34CE 4BC7 4FC3 BFFE 7AD7  7C2A E7A5 76CA 1ABD 03CD`

A copy of our keys can be found in this repository [here](/publish/keys/tlosint-archive-keyring.gpg) or at [https://apt.tracelabs.org](https://apt.tracelabs.org/index.html)

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

`make publish-qubes` uploads the signed Qubes template repo from
`../tlosint-qube/repo/r4.3` to <https://apt.tracelabs.org/qubes/r4.3>,
leaving the apt tree untouched. See [`docs/repo-layout.md`](docs/repo-layout.md).

`make qubes-repo-rpm` builds and signs `qubes-repo-tlosint`, the dom0 package
that adds that repository to `qvm-template`, into `artifacts/qubes/` for
attaching to a GitHub release.

## Layout

| Path | Purpose |
|---|---|
| `tools.yaml` | Single source of truth for the tool list |
| `packages/*/debian/` | One source package per tool |
| `build/` | sbuild wrappers, chroot creation, install tests |
| `publish/` | Repo metadata config and the signing publish script |
| `qubes/` | `qvm-template` repo file and the `qubes-repo-tlosint` spec |
| `scripts/` | `tools.yaml` codegen |
| `docs/` | Signing runbook, published repo layout |

## License

GPL-3.0, matching upstream tracelabs/tlosint-vm.
