#!/bin/sh
# Builds the six packages of one marqius-wkhtmltopdf version from its published static builds:
#
#   .deb  amd64, arm64      .rpm  x86_64, aarch64      .apk  x86_64, aarch64
#
#   scripts/build-packages.sh VERSION BUILDS OUT
#
# BUILDS is a folder holding marqius-wkhtmltopdf-linux-x86_64 and marqius-wkhtmltopdf-linux-arm64,
# already checked against their published checksums (scripts/follow-release.py does that).
# The packages are signed with the keys in these files:
#
#   MARQIUS_GPG_PRIVATE    OpenPGP private key, armored: signs each .rpm
#   MARQIUS_APK_PRIVATE    RSA private key: signs each .apk
#   MARQIUS_APK_KEY_NAME   the file name of its public key in /etc/apk/keys
#
# nfpm and the signing tools run in pinned Docker images, so the packages are made the same way
# on a laptop and in the workflow. The package revision is REVISION (default 1).
set -eu

NFPM_IMAGE="ghcr.io/goreleaser/nfpm:v2.49.0@sha256:9ea46a59c4d055ef7071b22f3520b53e8dad98e18043b2f881b53bd7ffec634e"

[ $# -eq 3 ] || { echo "usage: $0 VERSION BUILDS OUT" >&2; exit 2; }
version="$1"
builds="$(cd "$2" && pwd)"
mkdir -p "$3"
out="$(cd "$3" && pwd)"
here="$(cd "$(dirname "$0")/.." && pwd)"
revision="${REVISION:-1}"
case "$version" in ''|*[!0-9.]*) echo "not a version: $version" >&2; exit 2 ;; esac
case "$revision" in ''|*[!0-9]*) echo "not a revision: $revision" >&2; exit 2 ;; esac

for f in "$MARQIUS_GPG_PRIVATE" "$MARQIUS_APK_PRIVATE"; do
    [ -s "$f" ] || { echo "missing signing key: $f" >&2; exit 2; }
done
case "$MARQIUS_APK_KEY_NAME" in *.rsa.pub) ;; *) echo "MARQIUS_APK_KEY_NAME must end in .rsa.pub" >&2; exit 2 ;; esac

"$here/scripts/tools.sh" >/dev/null

work="$(mktemp -d "${TMPDIR:-/tmp}/marqius-packages.XXXXXX")"
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/keys"
cp "$MARQIUS_GPG_PRIVATE" "$work/keys/gpg.asc"
cp "$MARQIUS_APK_PRIVATE" "$work/keys/apk.rsa"
chmod 600 "$work/keys/"*

# Debian wants the packaging's own changelog beside the copyright file
{
    printf 'marqius-wkhtmltopdf (%s-%s) stable; urgency=medium\n\n' "$version" "$revision"
    printf '  * marqius-wkhtmltopdf %s, packaged from the published Linux build.\n' "$version"
    printf '    https://marqius.com/wkhtmltopdf/\n\n'
    printf ' -- Simple AI LLC <hello@marqius.com>  %s\n' "$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
} | gzip -9n > "$work/changelog.Debian.gz"

for arch in amd64 arm64; do
    case "$arch" in
        amd64) build=marqius-wkhtmltopdf-linux-x86_64 ;;
        arm64) build=marqius-wkhtmltopdf-linux-arm64 ;;
    esac
    [ -s "$builds/$build" ] || { echo "missing $builds/$build" >&2; exit 2; }
    sed -e "s|\${ARCH}|$arch|g" -e "s|\${VERSION}|$version|g" -e "s|\${REVISION}|$revision|g" \
        -e "s|\${BUILD}|/builds/$build|g" -e "s|\${CHANGELOG}|/work/changelog.Debian.gz|g" \
        -e "s|\${APK_KEY_FILE}|/work/keys/apk.rsa|g" -e "s|\${APK_KEY_NAME}|${MARQIUS_APK_KEY_NAME%.rsa.pub}|g" \
        "$here/package/nfpm.yaml" > "$work/nfpm-$arch.yaml"
    if grep -n '^[^#]*\${' "$work/nfpm-$arch.yaml" >&2; then echo "a value above was not filled in" >&2; exit 1; fi
    # apk keeps one "key = value" a line in .PKGINFO, so its description is the first line only
    awk '/^description: [|]-$/ { getline; sub(/^ +/, ""); print "description: \"" $0 "\""; skip = 1; next }
         skip && /^[^ ]/ { skip = 0 }
         !skip' "$work/nfpm-$arch.yaml" > "$work/nfpm-$arch-apk.yaml"
    for format in deb rpm apk; do
        config="/work/nfpm-$arch.yaml"
        [ "$format" = apk ] && config="/work/nfpm-$arch-apk.yaml"
        docker run --rm --user "$(id -u):$(id -g)" \
            -v "$here:/src:ro" -v "$builds:/builds:ro" -v "$work:/work:ro" -v "$out:/out" -w /src \
            "$NFPM_IMAGE" package --config "$config" --packager "$format" --target /out/ >/dev/null
    done
done

# Alpine finds a package in its repository by <name>-<version>.apk, in a folder per architecture
# (nfpm names it marqius-wkhtmltopdf_<version>_<arch>.apk; the version has no underscore)
for apk in "$out"/marqius-wkhtmltopdf_*.apk; do
    rest="${apk##*/marqius-wkhtmltopdf_}"; rest="${rest%.apk}"
    mv "$apk" "$out/marqius-wkhtmltopdf-${rest%%_*}.${rest#*_}.apk"
done

docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$here/scripts:/scripts:ro" -v "$work/keys:/keys:ro" -v "$out:/out" \
    marqius-packages-repo-tools sh /scripts/in/sign-rpms.sh
ls -1 "$out"
