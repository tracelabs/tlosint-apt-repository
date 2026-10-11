# tlosint-apt-repository

Build, test and publish tooling for the Trace Labs OSINT package repository:
a curated, signed set of OSINT tools for Debian 13 (trixie) and Qubes OS.

It is served at **<https://apt.tracelabs.org>** as:

- **An apt repository** of versioned, signed `.deb` packages. Install the whole
  toolset with one package (`tlosint-meta`), or pick individual tools.
- **A Qubes OS template repository** for `qvm-template`, with a Debian 13
  template that has the toolset preinstalled. See **[Qubes OS install](qubes/README.md)**.

## Install on Debian 13

```bash
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL -o /etc/apt/keyrings/tlosint-archive-keyring.gpg \
    https://apt.tracelabs.org/tlosint-archive-keyring.gpg
gpg --show-keys /etc/apt/keyrings/tlosint-archive-keyring.gpg   # check the fingerprint below

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

### Signing key

Everything published here (apt indexes, Qubes repo metadata and RPMs) is
signed by one key. Its primary fingerprint is:

```
34CE 4BC7 4FC3 BFFE 7AD7  7C2A E7A5 76CA 1ABD 03CD
```

A copy is in [`publish/keys/`](publish/keys/).

## Tools

`tlosint-meta` installs everything marked available. Tools marked
*Available (Debian)* come straight from Debian's own archive. The rest are
packaged here.

<!-- tools:start -->
| Tool | Description | Package | Status |
|---|---|---|---|
| [carbon14](https://github.com/Lazza/Carbon14) | OSINT dating of web content | `tlosint-carbon14` | Available |
| exiftool | Read and write image metadata | `libimage-exiftool-perl` | Available (Debian) |
| ffmpeg | Media transcoding, required by yt-dlp merging | `ffmpeg` | Available (Debian) |
| gallery-dl | Image gallery downloader | `gallery-dl` | Available (Debian) |
| [ghunt](https://github.com/mxrch/GHunt) | Google account OSINT | `tlosint-ghunt` | Available |
| httrack | Website mirroring utility | `httrack` | Available (Debian) |
| instaloader | Download Instagram media and metadata | `instaloader` | Available (Debian) |
| internetarchive | Internet Archive command line client | `internetarchive` | Available (Debian) |
| [maigret](https://github.com/soxoj/maigret) | Collect a dossier on a person by username | `tlosint-maigret` | Available |
| mat2 | Metadata anonymisation toolkit | `mat2` | Available (Debian) |
| [metagoofil](https://github.com/opsdisk/metagoofil) | Extract metadata from public documents | `tlosint-metagoofil` | Available |
| sherlock | Hunt down social media accounts by username | `sherlock` | Available (Debian) |
| shodan | Shodan CLI and API client | `python3-shodan` | Available (Debian) |
| [spiderfoot](https://github.com/smicallef/spiderfoot) | Automated OSINT reconnaissance | `tlosint-spiderfoot` | Available |
| steghide | Steganography detection and extraction | `steghide` | Available (Debian) |
| stegosuite | Graphical steganography tool | `stegosuite` | Available (Debian) |
| stegseek | Fast steghide cracker | `stegseek` | Available (Debian) |
| streamlink | Extract streams from live services | `streamlink` | Available (Debian) |
| sublist3r | Subdomain enumeration | `sublist3r` | Available (Debian) |
| tesseract | OCR engine and English language data | `tesseract-ocr`, `tesseract-ocr-eng` | Available (Debian) |
| tor | Anonymising overlay network | `tor` | Available (Debian) |
| [whatsmyname](https://github.com/C3n7ral051nt4g3ncy/WhatsMyName-Python) | Username enumeration across sites | `tlosint-whatsmyname` | Available |
| yt-dlp | Video downloader for archiving sources | `yt-dlp` | Available (Debian) |
| [auto-archiver](https://github.com/bellingcat/auto-archiver) | Automated archiving of web resources |  | In development |
| [gowitness](https://github.com/sensepost/gowitness) | Web screenshot utility |  | In development |
| [monolith](https://github.com/Y2Z/monolith) | Save a web page as a single self-contained HTML file |  | In development |
| [owlculus](https://github.com/be0vlk/owlculus) | OSINT case management platform |  | In development |
| [phoneinfoga](https://github.com/sundowndev/phoneinfoga) | Information gathering for phone numbers |  | In development |
| [sn0int](https://github.com/kpcyrd/sn0int) | Semi-automatic OSINT framework and package manager |  | In development |
| [torbrowser-launcher](https://github.com/micahflee/torbrowser-launcher) | Tor Browser downloader and launcher |  | In development |
| [translate-shell](https://github.com/soimort/translate-shell) | Command line translator |  | In development |
| [archivebox](https://github.com/ArchiveBox/ArchiveBox) | Self-hosted web archiving |  | Opt-in, not shipped |
| [twscrape](https://github.com/vladkens/twscrape) | Twitter/X scraping |  | Opt-in, not shipped |
<!-- tools:end -->

The list is generated from [`tools.yaml`](tools.yaml) by `make readme`. Edit
that file, not this table.

## Development

```bash
make chroot     # once: build the sbuild chroot
make build      # all packages, or PKG=<name> for one
make test       # install-test the built packages in a clean container
make lint
make readme     # regenerate the tool table above
```

CI builds, lints and install-tests every package on each push, and uploads the
unsigned `.deb` files as a workflow artifact.

## Publishing

Publishing is done by hand by a maintainer, never by CI. The signing key and
the storage credentials are deliberately kept out of GitHub Actions, so a
malicious workflow change can't sign or replace packages.

| Command | What it does |
|---|---|
| `make publish` | Builds the apt repository from downloaded CI artifacts, signs it and uploads it |
| `make publish-qubes` | Uploads the signed Qubes template repository to `/qubes/<release>` |
| `make qubes-repo-rpm` | Builds and signs the `qubes-repo-tlosint` package for GitHub releases |

## Layout

| Path | Contents |
|---|---|
| `tools.yaml` | The tool list: the source of truth for `tlosint-meta` and the table above |
| `packages/` | One Debian source package per tool |
| `build/` | Build, chroot and install-test scripts |
| `publish/` | Publishing scripts, repository config and the public signing key |
| `qubes/` | The `qvm-template` repo file and the `qubes-repo-tlosint` spec |
| `scripts/` | Generators that read `tools.yaml` |

## AI assistance

Check out 
[AI_USAGE.md](AI_USAGE.md) to learn about what we do (and explicitly don't do) with AI in this repository.

## License

GPL-3.0, matching upstream [tracelabs/tlosint-vm](https://github.com/tracelabs/tlosint-vm).
