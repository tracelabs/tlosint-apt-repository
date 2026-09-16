# Signing runbook

**Status: stub. Key not yet generated.**

## Key structure

```
primary key (CERTIFY ONLY)   air-gapped machine; paper/offline backup x2; never online
  └── signing subkey         loaded into an OnlyKey slot (stored-key mode)
```

The primary fingerprint is what users pin in `/etc/apt/keyrings/`. Keeping it
offline means a lost or bricked OnlyKey costs you one revocation and a new
subkey, not a migration of every user's keyring.

The apt key and the future Qubes template key are **different keys**. One
OnlyKey holds up to 16 ECC and 4 RSA keys, so both fit in separate slots.

## Generation (air-gapped machine)

```bash
# TODO: fill in and rehearse
# 1. gpg --expert --full-generate-key   -> primary, certify only, no expiry
# 2. gpg --expert --edit-key <fpr>      -> addkey, signing subkey
# 3. gpg --gen-revoke <fpr> > revocation.asc
# 4. gpg --export <fpr> > publish/keys/tlosint-archive-keyring.gpg
# 5. gpg --export-secret-subkeys <subkey>! > signing-subkey.asc   (to load)
# 6. paperkey / two offline media for the primary + revocation cert
```

## Loading onto the OnlyKey

OnlyKey is **not** an OpenPGP smartcard — no `gpg --card-edit`, no `keytocard`,
no scdaemon. It goes through `onlykey-agent` (a trezor-agent fork).

```bash
# TODO: fill in and rehearse
# - Load the signing subkey into a slot via the OnlyKey App (stored-key mode)
# - onlykey-gpg init "Trace Labs <...>" --import-pub <pubkey> -sk ECC2
# - export GNUPGHOME=~/.gnupg/onlykey
```

Algorithm: try Ed25519 first. There are reports of a `TypeError` when loading an
ed25519 *signing* subkey into an ECC slot while cv25519 encryption subkeys load
fine. Old report, may be fixed. Fall back to RSA-4096 if it bites — signing
speed is irrelevant at one signature per release.

## Break-glass: signing without the OnlyKey

`lib-agent` is a small fork of a lightly maintained upstream and has broken on
Python version bumps before. **Rehearse this before you need it.**

```bash
# TODO: procedure for signing a Release from the air-gapped machine using the
# offline primary to issue a fresh signing subkey.
```

## Verification before announcing a release

```bash
docker run --rm -it debian:trixie-slim
# install keyring, add sources, apt update -- expect zero warnings
```
