#!/bin/sh
# Builds the two pinned tool images (scripts/tools.Dockerfile) when they are missing or changed:
# marqius-packages-repo-tools and marqius-packages-apk-tools.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
# from Amazon's mirror of Docker's official images, again after pauses while it is busy, and
# from Google's mirror if it stays busy
build() {
    docker build -q -f "$here/tools.Dockerfile" --target "$1" --build-arg "LIBRARY=$2" -t "marqius-packages-$1-tools" "$here"
}
for target in repo apk; do
    ok=""
    for pause in 0 15 30 60; do
        sleep "$pause"
        if build "$target" public.ecr.aws/docker/library; then ok=yes; break; fi
    done
    [ -n "$ok" ] || build "$target" mirror.gcr.io/library
done
