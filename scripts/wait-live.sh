#!/bin/sh
# After publishing: waits until the repositories' address serves VERSION, ten times in a row (a
# new site reaches every copy of GitHub's network within minutes, not at once), for at most
# twenty minutes.
#
#   scripts/wait-live.sh VERSION
set -eu
[ $# -eq 1 ] || { echo "usage: $0 VERSION" >&2; exit 2; }
BASE_URL="${BASE_URL:-https://packages.marqius.com}"
right=0; tries=0
while [ "$right" -lt 10 ]; do
    tries=$((tries + 1))
    [ "$tries" -le 400 ] || { echo "after 20 minutes $BASE_URL still does not serve $1" >&2; exit 1; }
    got="$(curl -fsS -H 'Cache-Control: no-cache' "$BASE_URL/VERSION?try=$tries" 2>/dev/null || true)"
    if [ "$got" = "$1" ]; then right=$((right + 1)); else right=0; fi
    sleep 3
done
echo "$BASE_URL serves $1"
