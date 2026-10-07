# Signing runbook

**Status: stub. Key not yet generated.**

## Key structure

```
primary key (CERTIFY ONLY)   air-gapped machine; paper/offline backup x2; never online
  └── signing subkey         local GPG keyring on the publishing machine, passphrase-protected
```

The primary fingerprint is what users pin in `/etc/apt/keyrings/`. Keeping it
offline means a lost or compromised signing subkey costs you one revocation
and a new subkey, not a migration of every user's keyring.

The publishing machine holds **only** the subkey's secret. `gpg -K` there must
show `sec#` for the primary: the `#` means a stub with no secret material.

The apt key and the future Qubes template key are **different keys**, with
different blast radii. The template key feeds dom0.

User ID for the apt key: `Trace Labs VM Team <vm-team@tracelabs.org>`.

## Generation (air-gapped machine)

Algorithm: Ed25519. Signing speed is irrelevant at one signature per release.

```bash
# TODO: fill in and rehearse
# 1. gpg --expert --full-generate-key   -> primary, ECC (Ed25519), certify only, no expiry
#    user ID: Trace Labs VM Team <vm-team@tracelabs.org>
# 2. gpg --expert --edit-key <fpr>      -> addkey, Ed25519 sign-only subkey
# 3. gpg --gen-revoke <fpr> > revocation.asc
# 4. gpg --export <fpr> > publish/keys/tlosint-archive-keyring.gpg
#    gpg --export --armor <fpr> > publish/keys/tlosint-archive-keyring.asc
# 5. gpg --export-secret-subkeys --armor <subkey-fpr>! > signing-subkey.asc
# 6. paperkey / two offline media for the primary + revocation cert
```

The `!` in step 5 exports only that subkey's secret; without it gpg exports
every secret subkey.

## Importing the subkey on the publishing machine

```bash
# Optional: a keyring used only for publishing, kept apart from daily use.
export GNUPGHOME=~/.gnupg/tlosint && mkdir -m 700 -p "$GNUPGHOME"
gpg --import signing-subkey.asc
gpg -K    # expect "sec#" on the primary, "ssb" on the signing subkey
shred -u signing-subkey.asc
```

`publish/publish.sh` uses `$GNUPGHOME` (default `~/.gnupg`), and it signs with
`--local-user <subkey-fpr>!`. Set `TLOSINT_APT_KEYID` to the **subkey's** full
40-hex fingerprint, not the primary's.

## Publishing

1. Wait for a green `build` run from a **push to `main`**. Never publish a
   `pull_request` run's artifact: that is unreviewed code.
2. Empty `artifacts/`, then download that run's `debs-trixie-amd64` artifact
   and unzip it there. Publishing is stateless, so the folder's contents
   *are* the repository. Any leftover `.deb` gets published, and one missing
   from the folder disappears from the repo.
3. `TLOSINT_APT_KEYID=<subkey-fpr> make publish`. It lists the debs and asks
   for confirmation, then prompts for the subkey passphrase. It checks the
   signature against `publish/keys/tlosint-archive-keyring.gpg` before it
   uploads anything.
4. Verify from a clean container (below).

## Break-glass: subkey lost or compromised

**Rehearse this before you need it.** On the air-gapped machine:

```bash
# TODO: fill in and rehearse
# 1. gpg --edit-key <primary-fpr>  -> key <n>, revkey   (revoke the old subkey)
# 2.                                  addkey            (new Ed25519 sign-only subkey)
# 3. re-export the public keyring (step 4 above) and commit it
# 4. export and import the new subkey (step 5 above, then "Importing")
# 5. publish
```

**Caveat: rotation is not automatic yet.** apt checks signatures only against
the key material in the user's `/etc/apt/keyrings/` file. A subkey issued
*after* they installed that file is not in it, so `apt update` fails until
they fetch the new keyring. Keeping the primary offline still pays off: the
fingerprint users trust doesn't change, and nobody has to re-verify a new
identity. But the new keyring still has to reach them. The
`tlosint-archive-keyring` package (pulled in by `tlosint-meta`) ships it as
`/usr/share/keyrings/tlosint-archive-keyring.gpg`: add the replacement subkey,
bump the package and publish it *before* the old subkey is retired. This only
helps users whose `Signed-By` names that path rather than `/etc/apt/keyrings/`.

## Verification before announcing a release

```bash
docker run --rm -it --platform linux/amd64 debian:trixie-slim
# install keyring, add sources, apt update -- expect zero warnings
```
