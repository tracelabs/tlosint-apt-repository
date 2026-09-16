# Published repository layout

Served from GitHub Pages. Sizes here are tens of megabytes, comfortably inside
the 1 GB published-site cap and the 100 GB/month soft bandwidth limit.

```
/
├── .nojekyll                       required; Jekyll otherwise mangles paths
├── CNAME                           binds apt.tracelabs.org to the Pages site
├── pool/main/*.deb
└── dists/stable/
    ├── Release
    ├── Release.gpg                 detached signature
    ├── InRelease                   inline-signed; what apt prefers
    └── main/
        ├── binary-amd64/Packages{,.gz,.xz}
        └── binary-all/Packages{,.gz,.xz}
```

Set `Acquire-By-Hash: yes` so clients fetching mid-publish don't hit a hash
mismatch against a half-updated Pages cache. (Set in
`publish/apt-ftparchive.conf`.)

Both `.nojekyll` and `CNAME` live *in the published tree*, and every publish is
a force-pushed orphan commit — so `publish.sh` must rewrite them each time or
they vanish. Losing `CNAME` silently drops the site back to the `*.github.io`
host, which is exactly the failure users cannot work around.

## DNS and Pages setup (one time)

Because the repository is served at the domain root rather than under a repo
path, the published URIs are `https://apt.tracelabs.org/dists/stable/...`.

1. Cloudflare DNS: `CNAME apt -> tracelabs.github.io`, **DNS-only (grey cloud)**.
2. Repo Settings -> Pages -> Custom domain: `apt.tracelabs.org`.
3. Wait for GitHub to provision the Let's Encrypt certificate (up to ~24h on
   first setup), then tick **Enforce HTTPS**.
4. Optionally flip the record to proxied (orange cloud) with Cloudflare SSL mode
   **Full (strict)**. This caches the pool and largely removes the 100 GB/month
   Pages soft bandwidth limit as a concern.

A proxied record *before* step 3 breaks GitHub's domain validation and can
produce redirect loops. Flexible SSL mode does the same. Grey cloud first.

## Not here: the Qubes template

The template RPM (~0.5–1.5 GB) cannot live on Pages — one release would exceed
the entire site budget, and Git blocks files over 100 MB. Options, in order of
preference:

1. Trace Labs infra (`vm-downloads.tracelabs.org` already serves multi-GB OVAs)
2. Cloudflare R2 — no egress fees, custom domain, `rclone sync` as a publish step
3. Metadata on Pages, payload on GitHub Releases via
   `createrepo_c --baseurl=https://github.com/ORG/REPO/releases/download/vX/`
   which writes `xml:base` into the `<location>` elements. Needs testing against
   `qvm-template` specifically — it shells out to dnf but isn't plain dnf.
