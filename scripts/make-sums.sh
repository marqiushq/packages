#!/bin/sh
# Writes a release's SHA256SUMS, listing the four downloads from marqius.com and the six packages,
# and signs it with the package key as SHA256SUMS.asc. (The workflow adds a second signature with
# cosign, as SHA256SUMS.sigstore.json.)
#
#   scripts/make-sums.sh BUILDS PACKAGES OUT
#
# BUILDS holds the four downloads as follow-release.py fetched them, PACKAGES the six packages
# of that version as build-packages.sh made them. The key is MARQIUS_GPG_PRIVATE.
set -eu
[ $# -eq 3 ] || { echo "usage: $0 BUILDS PACKAGES OUT" >&2; exit 2; }
builds="$(cd "$1" && pwd)"
packages="$(cd "$2" && pwd)"
mkdir -p "$3"
out="$(cd "$3" && pwd)"
here="$(cd "$(dirname "$0")/.." && pwd)"
[ -s "$MARQIUS_GPG_PRIVATE" ] || { echo "missing signing key: $MARQIUS_GPG_PRIVATE" >&2; exit 2; }

sum() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
n_builds="$(ls "$builds"/marqius-wkhtmltopdf-* | grep -cv '\.sha256$')"
n_packages="$(ls "$packages" | grep -cE '\.(deb|rpm|apk)$')"
[ "$n_builds" = 4 ] && [ "$n_packages" = 6 ] || { echo "expected 4 downloads and 6 packages, found $n_builds and $n_packages" >&2; exit 1; }
{
    (cd "$builds" && sum $(ls marqius-wkhtmltopdf-* | grep -v '\.sha256$' | sort))
    (cd "$packages" && sum $(ls | grep -E '\.(deb|rpm|apk)$' | sort))
} > "$out/SHA256SUMS"

"$here/scripts/tools.sh" >/dev/null
keys="$(mktemp -d "${TMPDIR:-/tmp}/marqius-keys.XXXXXX")"
trap 'rm -rf "$keys"' EXIT INT TERM
cp "$MARQIUS_GPG_PRIVATE" "$keys/gpg.asc"
chmod 600 "$keys/gpg.asc"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$here/scripts:/scripts:ro" -v "$keys:/keys:ro" -v "$out:/out" \
    marqius-packages-repo-tools sh -c '
        set -eu
        . /scripts/in/gpg-key.sh
        gpg_sign --detach-sign --armor -o /out/SHA256SUMS.asc /out/SHA256SUMS
        check="$(mktemp -d)"
        gpg --batch --armor --export "$FPR" > "$check/key.asc"
        gpg --batch --quiet --homedir "$check" --import "$check/key.asc" 2>/dev/null
        gpg --batch --quiet --homedir "$check" --verify /out/SHA256SUMS.asc /out/SHA256SUMS 2>/dev/null'
cat "$out/SHA256SUMS"
