#!/bin/sh
# Builds the two pinned tool images (scripts/tools.Dockerfile) when they are missing or changed:
# marqius-packages-repo-tools and marqius-packages-apk-tools.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
for target in repo apk; do
    docker build -q -f "$here/tools.Dockerfile" --target "$target" -t "marqius-packages-$target-tools" "$here"
done
