# Built and signed by build/build-qubes-repo-rpm.sh (make qubes-repo-rpm).
# Source1 is copied from publish/keys/ at build time; it is not duplicated here.

Name:      qubes-repo-tlosint
Version:   1.0
Release:   1%{?dist}
Summary:   Trace Labs OSINT template repository for qvm-template
License:   GPL-3.0-or-later
URL:       https://github.com/tracelabs/tlosint-apt-repository
BuildArch: noarch
Requires:  qubes-repo-templates
Source0:   tlosint.repo
Source1:   tlosint-archive-keyring.asc

%description
Repository definition and signing key for installing Trace Labs OSINT
templates with qvm-template.

%install
install -D -m 0644 %{SOURCE0} %{buildroot}/etc/qubes/repo-templates/tlosint.repo
install -D -m 0644 %{SOURCE1} %{buildroot}/etc/qubes/repo-templates/keys/tlosint.asc

# The key is deliberately not noreplace: a newer package must replace it when
# the signing subkey rotates. Local edits to the .repo file survive upgrades.
%files
%config(noreplace) /etc/qubes/repo-templates/tlosint.repo
/etc/qubes/repo-templates/keys/tlosint.asc

%changelog
* Sat Oct 10 2026 Trace Labs VM Team <vm-team@tracelabs.org> - 1.0-1
- Initial package: tlosint-templates repo for Qubes R4.3
