#!/bin/sh
# Writes the signed apt, dnf and Alpine repositories for the packages in POOL into SITE, with the
# files customers set them up with:
#
#   scripts/make-repos.sh POOL SITE BASE_URL
#
# POOL holds every package to serve, of every version kept, as build-packages.sh named them.
# BASE_URL is the address SITE will be served at, for example https://packages.marqius.com
# The keys are named as for build-packages.sh: MARQIUS_GPG_PRIVATE, MARQIUS_APK_PRIVATE and
# MARQIUS_APK_KEY_NAME.
#
#   marqius.asc                                the OpenPGP public key (apt, dnf, SHA256SUMS)
#   apt/marqius.sources                        apt's source, with the key inside it
#   apt/dists/stable/                          InRelease, Release, Release.gpg, Packages
#   apt/pool/main/m/marqius-wkhtmltopdf/       the .deb files
#   rpm/marqius.repo                           dnf's repository file
#   rpm/repodata/                              repomd.xml, signed as repomd.xml.asc
#   rpm/packages/                              the .rpm files, each signed
#   alpine/<key name>                          the Alpine public key
#   alpine/x86_64/, alpine/aarch64/            APKINDEX.tar.gz, signed, and the .apk files
#   VERSION                                    the newest version served
#   KEYS                                       the keys' fingerprints, for the README and the page
set -eu

[ $# -eq 3 ] || { echo "usage: $0 POOL SITE BASE_URL" >&2; exit 2; }
pool="$(cd "$1" && pwd)"
base_url="${3%/}"
case "$base_url" in https://*) ;; *) echo "BASE_URL must start with https://" >&2; exit 2 ;; esac
if [ -e "$2" ] && [ -n "$(ls -A "$2")" ]; then echo "$2 is not empty" >&2; exit 2; fi
mkdir -p "$2"
site="$(cd "$2" && pwd)"
here="$(cd "$(dirname "$0")/.." && pwd)"
for f in "$MARQIUS_GPG_PRIVATE" "$MARQIUS_APK_PRIVATE"; do
    [ -s "$f" ] || { echo "missing signing key: $f" >&2; exit 2; }
done
case "$MARQIUS_APK_KEY_NAME" in *.rsa.pub) ;; *) echo "MARQIUS_APK_KEY_NAME must end in .rsa.pub" >&2; exit 2 ;; esac

"$here/scripts/tools.sh" >/dev/null

# ---- the packages, where each repository wants them
mkdir -p "$site/apt/pool/main/m/marqius-wkhtmltopdf" "$site/rpm/packages" "$site/alpine/x86_64" "$site/alpine/aarch64"
cp "$pool"/marqius-wkhtmltopdf_*.deb "$site/apt/pool/main/m/marqius-wkhtmltopdf/"
cp "$pool"/marqius-wkhtmltopdf-*.rpm "$site/rpm/packages/"
for apk in "$pool"/marqius-wkhtmltopdf-*.apk; do
    name="${apk##*/}"                       # marqius-wkhtmltopdf-0.12.9-r1.x86_64.apk
    arch="${name%.apk}"; arch="${arch##*.}"
    cp "$apk" "$site/alpine/$arch/${name%.$arch.apk}.apk"
done
ls "$pool"/marqius-wkhtmltopdf_*.deb | sed 's/.*_\([0-9.]*\)-[0-9]*_[a-z0-9]*\.deb$/\1/' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 > "$site/VERSION"

keys="$(mktemp -d "${TMPDIR:-/tmp}/marqius-keys.XXXXXX")"
trap 'rm -rf "$keys"' EXIT INT TERM
cp "$MARQIUS_GPG_PRIVATE" "$keys/gpg.asc"
cp "$MARQIUS_APK_PRIVATE" "$keys/apk.rsa"
chmod 600 "$keys/"*

owner="$(id -u):$(id -g)"
docker run --rm -e BASE_URL="$base_url" \
    -v "$here/scripts:/scripts:ro" -v "$keys:/keys:ro" -v "$site:/site" \
    marqius-packages-repo-tools sh -c "sh /scripts/in/apt-rpm-repos.sh && chown -R $owner /site"
docker run --rm -e APK_KEY_NAME="$MARQIUS_APK_KEY_NAME" \
    -v "$here/scripts:/scripts:ro" -v "$keys:/keys:ro" -v "$site:/site" \
    marqius-packages-apk-tools sh -c "sh /scripts/in/apk-repo.sh && chown -R $owner /site"
echo "$site: marqius-wkhtmltopdf $(cat "$site/VERSION") and $(find "$site" -name '*.deb' -o -name '*.rpm' -o -name '*.apk' | wc -l | tr -d ' ') packages, signed, for $base_url"
