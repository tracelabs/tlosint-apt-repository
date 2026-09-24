# Keys

Public keys only. **No private key material ever lands in this repository.**

Expected contents once generated:

- `tlosint-archive-keyring.asc` — ASCII-armored public primary key
- `tlosint-archive-keyring.gpg` — dearmored, the file users install

Users install with:

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
```

Never `apt-key`. It is deprecated and makes the key a trust root for every
repository on the system.

See `../../docs/signing-runbook.md` for generation and subkey import.
