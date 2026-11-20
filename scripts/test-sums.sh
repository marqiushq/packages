#!/bin/sh
# After publishing: runs README.md's lines that fetch and check SHA256SUMS, exactly as printed,
# in an empty folder (cosign, gpg and gh, signed in, must be installed), then checks one
# package against it:
#
#   scripts/test-sums.sh
#
# gpg gets a keyring of its own for the run, so nothing is added to the machine's.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
BASE_URL="${BASE_URL:-https://packages.marqius.com}"
work="$(mktemp -d "${TMPDIR:-/tmp}/marqius-sums.XXXXXX")"
python3 "$here/scripts/doc-blocks.py" "$here/README.md" "$work/blocks" >/dev/null
mkdir -p "$work/run" "$work/gnupg"
chmod 700 "$work/gnupg"
export GNUPGHOME="$work/gnupg"
cd "$work/run"
for block in sums-get sums-cosign sums-gpg sums-provenance; do
    bash -e "$work/blocks/$block" || { echo "FAIL README $block"; exit 1; }
    echo "ok   README's $block line"
done
# then a download, checked as the README says
deb="$(grep -o 'marqius-wkhtmltopdf_[0-9.]*-[0-9]*_amd64\.deb' SHA256SUMS | head -1)"
curl -fsSLO "$BASE_URL/apt/pool/main/m/marqius-wkhtmltopdf/$deb"
sha256sum --ignore-missing -c SHA256SUMS
echo "ok   $deb matches SHA256SUMS"
