#!/bin/sh
# Makes throwaway signing keys for a test run that publishes nothing (a pull request, a change
# to main): DIR/gpg.asc (OpenPGP) and DIR/apk.rsa (RSA, for Alpine). They live only as long as
# the run; the real keys are used only by the publishing run.
#
#   scripts/test-keys.sh DIR
set -eu
[ $# -eq 1 ] || { echo "usage: $0 DIR" >&2; exit 2; }
mkdir -p "$1"
dir="$(cd "$1" && pwd)"
here="$(cd "$(dirname "$0")/.." && pwd)"
"$here/scripts/tools.sh" >/dev/null
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$dir:/k" marqius-packages-repo-tools sh -c '
    set -eu
    export GNUPGHOME="$(mktemp -d)"
    gpg --batch --quiet --pinentry-mode loopback --passphrase "" \
        --quick-generate-key "marqius packages test key, not for publishing <test@invalid>" rsa4096 sign 1d 2>/dev/null
    gpg --batch --armor --pinentry-mode loopback --passphrase "" --export-secret-keys > /k/gpg.asc'
docker run --rm --user "$(id -u):$(id -g)" -v "$dir:/k" marqius-packages-apk-tools \
    sh -c 'openssl genrsa -out /k/apk.rsa 4096 2>/dev/null'
chmod 600 "$dir/gpg.asc" "$dir/apk.rsa"
