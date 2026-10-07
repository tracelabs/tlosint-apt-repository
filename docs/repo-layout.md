# Published repository layout

Served from a Cloudflare R2 bucket on the custom domain `apt.tracelabs.org`.
R2 charges nothing for egress, and Cloudflare caches in front of it.

```
/
├── index.html                      usage page (publish/index.html)
├── tlosint-archive-keyring.gpg     what users install into /etc/apt/keyrings
├── tlosint-archive-keyring.asc
├── pool/main/*.deb
└── dists/stable/
    ├── Release
    ├── Release.gpg                 detached signature
    ├── InRelease                   inline-signed; what apt prefers
    └── main/
        ├── binary-amd64/Packages{,.gz,.xz}   (+ by-hash/SHA256/<hash>)
        └── binary-all/Packages{,.gz,.xz}     (+ by-hash/SHA256/<hash>)
```

Every publish is **stateless**. `publish/publish.sh` builds this tree only from
the downloaded CI artifact, then syncs the bucket to match it. There's no
history to prune, and older versions drop off when a new one ships.

## Upload order and caching

`publish.sh` uploads in this order, so that a client halfway through
`apt update` never follows a reference to a file that isn't there yet:

1. `pool/` and `by-hash/`. Their content never changes under a given name, so
   they get `Cache-Control: immutable`, one year.
2. The plain-path `Packages` and `Contents` indexes, `max-age=60`.
3. `Release`, `Release.gpg` and `InRelease`, `max-age=60`.
4. `index.html` and the keyring files at the root, `max-age=60`.
5. `rclone sync`, which deletes whatever this publish no longer contains.

`Acquire-By-Hash: yes` is set in `publish/apt-ftparchive.conf`. A client that
read `InRelease` just before a publish fetches the exact index files it
names, not a newer file that sits at the same plain path.

## R2 setup (one time)

1. Cloudflare dashboard → R2 → create bucket `tlosint-apt`.
2. Bucket → Settings → Custom Domains → connect `apt.tracelabs.org`. The
   `tracelabs.org` zone is already on Cloudflare, so the DNS record and the
   certificate are created for you.
3. Leave the public `r2.dev` URL **disabled**. The custom domain is the only
   way in, which keeps caching and any future access rules in one place.
4. R2 → Manage API tokens → create a token with **Object Read & Write**,
   scoped to this bucket only.
5. Configure rclone on the publishing machine:
   ```
   rclone config create r2 s3 provider=Cloudflare \
       access_key_id=<id> secret_access_key=<secret> \
       endpoint=https://<account-id>.r2.cloudflarestorage.com acl=private
   ```
   `publish.sh` uploads to `r2:tlosint-apt` by default. Override it with
   `R2_DEST`.
6. Optional: a Cache Rule on `apt.tracelabs.org` that marks everything as
   eligible for cache and respects the origin's `Cache-Control`. By default
   Cloudflare doesn't cache `.deb` or extensionless files such as `InRelease`.
7. R2 has no index documents, so `/` returns 404 even though `/index.html`
   exists. Zone → Rules → URL Rewrite Rule, filter
   `(http.host eq "apt.tracelabs.org" and http.request.uri.path eq "/")`,
   rewrite the path to the static value `/index.html`.

### What the R2 token can and cannot do

The token can replace or delete any object. It **cannot** forge a signature.
apt rejects any index that doesn't hash-chain back to an `InRelease` signed by
the subkey. So a leaked token can take the repository down, but it can't
get users to install anything. It is still a publishing credential: it lives
only in the publisher's rclone config and never in Actions secrets.

## Not here: the Qubes template

The template RPM (~0.5–1.5 GB) goes on separate hosting with a separate key.
Options, in order of preference:

1. Cloudflare R2, in a separate bucket on its own subdomain. The setup above
   carries straight over, and multi-GB objects are fine.
2. Trace Labs infra (`vm-downloads.tracelabs.org` already serves multi-GB OVAs)
3. Metadata on R2, payload on GitHub Releases via
   `createrepo_c --baseurl=https://github.com/ORG/REPO/releases/download/vX/`
   which writes `xml:base` into the `<location>` elements. Needs testing against
   `qvm-template` specifically — it shells out to dnf but isn't plain dnf.
