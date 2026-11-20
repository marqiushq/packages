#!/bin/sh
# Downloads the packages of every release before VERSION from this repository's GitHub releases
# into DIR, newest first, each checked against its release's SHA256SUMS. The repositories keep
# serving every version, byte for byte as first published, so pinned installs and reproducible
# builds keep working (apt install marqius-wkhtmltopdf=0.12.9-1, and so on).
#
#   scripts/previous-releases.sh VERSION DIR [BUDGET_MB]
#
# GitHub Pages holds 1 GB. BUDGET_MB (default 900) is the room for the releases before this one.
# Should the oldest no longer fit, they are left out, so that a new release always goes out, and
# named in DIR/LEFT-OUT. The workflow warns the owners long before (at 600 MB).
# Needs gh, signed in (GH_TOKEN in the workflow), and GNU sort and sha256sum.
set -eu
[ $# -ge 2 ] || { echo "usage: $0 VERSION DIR [BUDGET_MB]" >&2; exit 2; }
version="$1"; budget_mb="${3:-900}"
mkdir -p "$2"
dir="$(cd "$2" && pwd)"
: > "$dir/LEFT-OUT"
exact="$(echo "$version" | sed 's/\./\\./g')"
older="$( { gh release list --limit 1000 --json tagName --jq '.[].tagName' | sed -n 's/^v\([0-9.]*\)$/\1/p'; echo "$version"; } \
    | sort -V -u | sed "/^$exact\$/,\$d" | sort -V -r)"
used=0; kept=0
budget=$((budget_mb * 1024 * 1024))
for v in $older; do
    size="$(gh release view "v$v" --json assets --jq '[.assets[] | select(.name | test("\\.(deb|rpm|apk)$")) | .size] | add // 0')"
    if [ $((used + size)) -gt "$budget" ]; then
        echo "$v" >> "$dir/LEFT-OUT"
        continue
    fi
    work="$(mktemp -d)"
    gh release download "v$v" --dir "$work" --pattern 'marqius-wkhtmltopdf*' --pattern 'SHA256SUMS'
    (cd "$work" && sha256sum --ignore-missing --quiet -c SHA256SUMS)
    n="$(ls "$work" | grep -cE '\.(deb|rpm|apk)$')"
    [ "$n" = 6 ] || { echo "release v$v has $n packages, not 6" >&2; exit 1; }
    mv "$work"/*.deb "$work"/*.rpm "$work"/*.apk "$dir/"
    rm -rf "$work"
    used=$((used + size)); kept=$((kept + 1))
done
echo "kept the packages of $kept earlier releases, $((used / 1048576)) MB"
if [ -s "$dir/LEFT-OUT" ]; then echo "left out for room: $(tr '\n' ' ' < "$dir/LEFT-OUT")"; fi
