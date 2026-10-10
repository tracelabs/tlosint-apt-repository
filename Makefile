# tlosint-apt-repository
#
# Build and test are safe to run anywhere, including CI.
# `publish` is LOCAL ONLY -- it signs and uploads to R2. See docs/signing-runbook.md

SHELL      := /bin/bash
DIST       ?= trixie
ARCH       ?= amd64
ARTIFACTS  ?= artifacts
PACKAGES   := $(notdir $(wildcard packages/*))

.PHONY: help chroot control keyring build test lint clean publish publish-qubes qubes-repo-rpm

help:
	@echo "chroot   - build the sbuild chroot tarball (once, then cached)"
	@echo "control  - regenerate tlosint-meta/debian/control from tools.yaml"
	@echo "keyring  - copy publish/keys keyring into tlosint-archive-keyring"
	@echo "build    - build all packages       (PKG=<name> for one)"
	@echo "test     - install-test built debs in a clean container"
	@echo "lint     - shellcheck + lintian"
	@echo "publish  - LOCAL ONLY. Signs with the local GPG subkey, uploads to R2."
	@echo "publish-qubes - LOCAL ONLY. Uploads the signed Qubes RPM repo to /qubes/<release>."
	@echo "qubes-repo-rpm - LOCAL ONLY. Builds and signs qubes-repo-tlosint into artifacts/qubes/."

chroot:
	build/mk-chroot.sh "$(DIST)" "$(ARCH)"

control:
	scripts/gen-meta-control.py tools.yaml \
	  --template packages/tlosint-meta/debian/control.in \
	  --out packages/tlosint-meta/debian/control

# publish/keys/ is the source of truth; the package carries a committed copy
# because dpkg-source only tars packages/<pkg>/.
keyring:
	cp publish/keys/tlosint-archive-keyring.gpg packages/tlosint-archive-keyring/

build: control keyring
ifdef PKG
	build/build-package.sh "$(PKG)" "$(DIST)" "$(ARCH)"
else
	@for p in $(PACKAGES); do build/build-package.sh "$$p" "$(DIST)" "$(ARCH)" || exit 1; done
endif

# NATIVE=1 installs into the current system instead of spinning up a
# container -- used in CI, where the job already runs inside a clean Debian.
test:
	build/install-test.sh "$(DIST)"

lint:
	shellcheck build/*.sh publish/*.sh
	@for f in $(ARTIFACTS)/*.changes; do lintian -I --pedantic "$$f" || true; done

clean:
	rm -rf $(ARTIFACTS)

publish:
	publish/publish.sh

# Uploads ../tlosint-qube/repo/<release> to /qubes/<release>. Signs nothing;
# QUBES_REPO and RELEASE override the source.
publish-qubes:
	publish/publish-qubes.sh

# The dom0 bootstrap package, attached to GitHub releases by hand.
qubes-repo-rpm:
	build/build-qubes-repo-rpm.sh
