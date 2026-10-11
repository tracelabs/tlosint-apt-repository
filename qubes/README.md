# Qubes OS install

The Trace Labs OSINT template is a Debian 13 template with the full toolset
preinstalled, served for Qubes R4.3 from <https://apt.tracelabs.org/qubes/r4.3>.

Before `qvm-template` can see it, dom0 needs two things: the repository
definition and the signing key. You can add them by hand (option 1) or
install a package that adds both (option 2).

> **dom0 has no network access, and that's on purpose.** In both options you
> download files in an ordinary qube and copy them into dom0. Only copy files
> you've verified, because dom0 has full control of the system.

The examples below use a qube named `work`. Substitute your own.

## Option 1: the `.repo` file

**In `work`**, download the repository file and the key, and check the key's
fingerprint:

```bash
curl -fsSLO https://raw.githubusercontent.com/tracelabs/tlosint-apt-repository/main/qubes/tlosint.repo
curl -fsSLO https://apt.tracelabs.org/tlosint-archive-keyring.asc
gpg --show-keys tlosint-archive-keyring.asc
```

The fingerprint must be `34CE 4BC7 4FC3 BFFE 7AD7  7C2A E7A5 76CA 1ABD 03CD`.
Also read `tlosint.repo` before you copy it. It's short.

**In dom0**, copy both files into place:

```bash
qvm-run --pass-io work 'cat tlosint.repo' | sudo tee /etc/qubes/repo-templates/tlosint.repo >/dev/null
qvm-run --pass-io work 'cat tlosint-archive-keyring.asc' | sudo tee /etc/qubes/repo-templates/keys/tlosint.asc >/dev/null
```

To remove the repository later, delete those two files.

## Option 2: the `qubes-repo-tlosint` package

The package installs the same two files. Compared with option 1 it adds a
version number, removal with `dnf remove`, and an upgrade path when the key
rotates. It doesn't update itself: install a newer release by hand when one
comes out.

**In `work`**, download `qubes-repo-tlosint-*.noarch.rpm` and `SHA256SUMS`
from the [latest release](https://github.com/tracelabs/tlosint-apt-repository/releases/latest),
then check the checksum:

```bash
sha256sum -c SHA256SUMS
```

The RPM is also signed with the key above. If `work` is Fedora-based, you can
check the signature without trusting the key system-wide:

```bash
curl -fsSLO https://apt.tracelabs.org/tlosint-archive-keyring.asc
db="$(mktemp -d)"
rpmkeys --dbpath "$db" --import tlosint-archive-keyring.asc
rpmkeys --dbpath "$db" --checksig qubes-repo-tlosint-*.noarch.rpm   # expect "signatures OK"
```

**In dom0**, copy the package over and install it:

```bash
qvm-run --pass-io work 'cat qubes-repo-tlosint-1.0-1.fc41.noarch.rpm' > /tmp/qubes-repo-tlosint.rpm
sudo dnf install /tmp/qubes-repo-tlosint.rpm
```

To remove it: `sudo dnf remove qubes-repo-tlosint`.

## Install the template

With either option in place, run this in dom0:

```bash
qvm-template list --available debian-13-tlosint
qvm-template install debian-13-tlosint
```

`qvm-template` checks the repository metadata and the template's signature
against the key you installed. To move to a newer build later:

```bash
qvm-template upgrade debian-13-tlosint
```

## For maintainers

| File | Purpose |
|---|---|
| [`tlosint.repo`](tlosint.repo) | The repository definition. `$releasever` follows the dom0 release |
| [`qubes-repo-tlosint.spec`](qubes-repo-tlosint.spec) | The package spec. The key is copied from `publish/keys/` at build time |

`make qubes-repo-rpm` builds and signs the package into `artifacts/qubes/`.
Bump `Version` or `Release` and add a `%changelog` entry for every release.
The template repository itself is built in
[tlosint-qube](https://github.com/tracelabs/tlosint-qube) and uploaded with
`make publish-qubes`.
