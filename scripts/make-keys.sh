#!/bin/sh
# Makes the repositories' real signing keys, once, into DIR (which must not exist yet):
#
#   scripts/make-keys.sh DIR
#
#   DIR/packages-gpg-private.asc   OpenPGP, RSA 4096, no expiry: apt, dnf, .rpm, SHA256SUMS.asc
#   DIR/packages-gpg-revoke.asc    its revocation certificate, for the day it must be withdrawn
#   DIR/packages-apk-private.rsa   RSA 4096: Alpine's index and .apk files
#   DIR/marqius.asc, DIR/marqius.rsa.pub   the public halves
#
# The private files go into the workflow's secrets and the owner's offline backup, and are then
# deleted from this machine. Only public facts are printed: the fingerprint and the Alpine key's
# SHA-256, for the README.
set -eu
[ $# -eq 1 ] || { echo "usage: $0 DIR" >&2; exit 2; }
[ ! -e "$1" ] || { echo "$1 exists already: keys are made once, into a new folder" >&2; exit 2; }
mkdir -p "$1"
chmod 700 "$1"
dir="$(cd "$1" && pwd)"
here="$(cd "$(dirname "$0")/.." && pwd)"
"$here/scripts/tools.sh" >/dev/null
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$dir:/k" marqius-packages-repo-tools sh -c '
    set -eu
    umask 077
    export GNUPGHOME="$(mktemp -d)"
    gpg --batch --quiet --pinentry-mode loopback --passphrase "" \
        --quick-generate-key "marqius packages (Simple AI LLC) <hello@marqius.com>" rsa4096 sign never 2>/dev/null
    fpr="$(gpg --batch --with-colons --list-secret-keys | awk -F: "/^fpr:/ { print \$10; exit }")"
    gpg --batch --armor --pinentry-mode loopback --passphrase "" --export-secret-keys "$fpr" > /k/packages-gpg-private.asc
    gpg --batch --armor --export "$fpr" > /k/marqius.asc
    cp "$GNUPGHOME/openpgp-revocs.d/$fpr.rev" /k/packages-gpg-revoke.asc
    echo "$fpr" | sed "s/..../& /g; s/ \$//" > /k/fingerprint'
docker run --rm --user "$(id -u):$(id -g)" -v "$dir:/k" marqius-packages-apk-tools sh -c '
    set -eu
    umask 077
    openssl genrsa -out /k/packages-apk-private.rsa 4096 2>/dev/null
    openssl rsa -in /k/packages-apk-private.rsa -pubout -out /k/marqius.rsa.pub 2>/dev/null
    chmod 644 /k/marqius.rsa.pub'
echo "OpenPGP fingerprint:  $(cat "$dir/fingerprint")"
echo "Alpine key SHA-256:   $(shasum -a 256 "$dir/marqius.rsa.pub" 2>/dev/null | cut -c1-64 || sha256sum "$dir/marqius.rsa.pub" | cut -c1-64)"
