#!/bin/sh
# After publishing: builds README.md's Dockerfile lines, exactly as printed, on each image they
# name or stand for, then makes a PDF in each image built:
#
#   scripts/test-dockerfiles.sh
#
# PLATFORM picks the architecture (default: this machine's). RESULTS holds one log per image.
# The base images come from Amazon's public mirror of Docker's official images and the makers'
# own registries, never from Docker Hub (see test-repos.sh).
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
ECR=public.ecr.aws/docker/library
# the README's block, and the images it is meant for
ALL="docker-apt=$ECR/debian:12
docker-apt=$ECR/debian:13
docker-apt=$ECR/ubuntu:22.04
docker-apt=$ECR/ubuntu:24.04
docker-apt=$ECR/ubuntu:26.04
docker-apt=$ECR/python:3.13
docker-apt=$ECR/ruby:3.4
docker-apt=$ECR/php:8.4
docker-dnf=quay.io/rockylinux/rockylinux:9
docker-dnf=quay.io/rockylinux/rockylinux:10
docker-dnf=registry.access.redhat.com/ubi9/ubi:latest
docker-dnf=quay.io/fedora/fedora:latest
docker-dnf=public.ecr.aws/amazonlinux/amazonlinux:2023
docker-apk=$ECR/alpine:3.22
docker-apk=$ECR/alpine:3.23
docker-apk=$ECR/alpine:3.24"
RESULTS="${RESULTS:-$(mktemp -d "${TMPDIR:-/tmp}/marqius-dockerfiles.XXXXXX")}"
mkdir -p "$RESULTS"
blocks="$RESULTS/blocks"
python3 "$here/scripts/doc-blocks.py" "$here/README.md" "$blocks" >/dev/null
set -- ${PLATFORM:+--platform "$PLATFORM"}
# the base images first, one at a time, again after longer and longer pauses while a registry is
# busy, and from Google's mirror of Docker's official images if Amazon's stays busy (the same
# images), so that a rate limit is never taken for a failing line
retry() {
    for pause in 0 15 30 60 120; do
        sleep "$pause"
        "$@" && return 0
    done
    return 1
}
mirror() {
    case "$1" in
        public.ecr.aws/docker/library/*) echo "mirror.gcr.io/library/${1#public.ecr.aws/docker/library/}" ;;
        public.ecr.aws/amazonlinux/amazonlinux:*) echo "mirror.gcr.io/library/amazonlinux:${1##*:}" ;;
    esac
}
for pair in $ALL; do
    image="${pair#*=}"
    if ! retry docker pull -q "$@" "$image" >/dev/null; then
        m="$(mirror "$image")"
        { [ -n "$m" ] && retry docker pull -q "$@" "$m" >/dev/null && docker tag "$m" "$image"; } \
            || { echo "cannot pull $image" >&2; exit 1; }
    fi
done
failed=0
for pair in $ALL; do
    block="${pair%%=*}"; image="${pair#*=}"
    name="$(echo "$image" | tr '/:' '__')"
    dir="$RESULTS/$name"
    mkdir -p "$dir"
    { echo "FROM $image"; cat "$blocks/$block"; } > "$dir/Dockerfile"
    log="$dir/log"
    tag="marqius-dockerfile-test-$$-$(echo "$name" | tr 'A-Z.' 'a-z-')"
    if docker build "$@" --pull=false --no-cache -t "$tag" "$dir" > "$log" 2>&1 \
        && docker run --rm "$@" "$tag" sh -c 'cd /tmp && echo "<h1>Invoice 42</h1>" > i.html && marqius-wkhtmltopdf -q i.html i.pdf && head -c 5 i.pdf' >> "$log" 2>&1 \
        && [ "$(tail -c 5 "$log")" = "%PDF-" ]; then
        printf 'PASS  %-8s %s\n' "${block#docker-}" "$image"
    else
        failed=$((failed + 1))
        printf 'FAIL  %-8s %s (see %s)\n' "${block#docker-}" "$image" "$log"
    fi
    docker rmi -f "$tag" >/dev/null 2>&1 || true
done
[ "$failed" = 0 ]
