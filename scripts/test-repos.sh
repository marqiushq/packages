#!/bin/sh
# Installs marqius-wkhtmltopdf from the repositories on each system, with README.md's lines run
# exactly as printed (scripts/in/try.sh), in a fresh container per system and architecture:
#
#   scripts/test-repos.sh SITE [SYSTEM...]              before publishing: SITE, served by a local
#                                                       stand-in that answers for the real host
#   scripts/test-repos.sh --upgrade OLD NEW [SYSTEM...] install from site OLD, then run README's
#                                                       update line once the stand-in serves NEW
#   scripts/test-repos.sh --live [SYSTEM...]            after publishing: the real repositories
#
# The stand-in answers as BASE_URL's host (default https://packages.marqius.com) with a
# certificate from a throwaway authority that only the test containers trust.
#
# PHASE=refuse expects README's install lines to fail (a tampered site; see scripts/in/try.sh).
# PLATFORMS picks the architectures (default: linux/amd64 linux/arm64), JOBS how many containers
# run at once (default 4), EXPECT the version that must be installed (default: the site's
# VERSION file). One log per system and architecture goes to RESULTS (default: a new folder).
# The exit status is 0 only when every system passed.
#
# The images come from their makers' own registries, or from Amazon's public mirror of Docker's
# official images (else Google's: the same images, the same digests), never from Docker Hub, whose
# pull limit is shared by everything on a machine. Each is pinned by the digest of its build for
# the architecture, looked up once and pulled one at a time before the containers start.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
BASE_URL="${BASE_URL:-https://packages.marqius.com}"
BASE_URL="${BASE_URL%/}"
ALL="debian12 debian13 ubuntu2204 ubuntu2404 ubuntu2604 rocky9 rocky10 ubi9 fedora al2023 alpine322 alpine323 alpine324"
SERVER_IMAGE="public.ecr.aws/docker/library/python:3.13-alpine@sha256:9ef1a599f863231c3d91e941389bfdc4a2d6070557243d54df1a4e57015b960e"
ECR=public.ecr.aws/docker/library

# system -> image and package family
system() {
    case "$1" in
        debian12)   echo "$ECR/debian:12 apt" ;;
        debian13)   echo "$ECR/debian:13 apt" ;;
        ubuntu2204) echo "$ECR/ubuntu:22.04 apt" ;;
        ubuntu2404) echo "$ECR/ubuntu:24.04 apt" ;;
        ubuntu2604) echo "$ECR/ubuntu:26.04 apt" ;;
        rocky9)     echo "quay.io/rockylinux/rockylinux:9 dnf" ;;
        rocky10)    echo "quay.io/rockylinux/rockylinux:10 dnf" ;;
        ubi9)       echo "registry.access.redhat.com/ubi9/ubi:latest dnf" ;;
        fedora)     echo "quay.io/fedora/fedora:latest dnf" ;;
        al2023)     echo "public.ecr.aws/amazonlinux/amazonlinux:2023 dnf" ;;
        alpine322)  echo "$ECR/alpine:3.22 apk" ;;
        alpine323)  echo "$ECR/alpine:3.23 apk" ;;
        alpine324)  echo "$ECR/alpine:3.24 apk" ;;
        *) echo "unknown system $1 (one of: $ALL)" >&2; return 1 ;;
    esac
}

# a registry call, again after longer and longer pauses while the registry answers "too many
# requests" (registries limit how often an address may ask, and CI machines share addresses)
retry() {
    for pause in 0 15 30 60 120; do
        sleep "$pause"
        "$@" && return 0
    done
    return 1
}

# the same image in Google's mirror of Docker's official images, for an image of Amazon's mirror
mirror() {
    case "$1" in
        public.ecr.aws/docker/library/*) echo "mirror.gcr.io/library/${1#public.ecr.aws/docker/library/}" ;;
        public.ecr.aws/amazonlinux/amazonlinux[:@]*) echo "mirror.gcr.io/library/amazonlinux${1#public.ecr.aws/amazonlinux/amazonlinux}" ;;
    esac
}

# pull REF (one architecture of an image, by digest), from its mirror if its registry stays busy
fetch_image() {
    retry docker pull -q --platform "$2" "$1" >/dev/null && return 0
    m="$(mirror "$1")"
    [ -n "$m" ] && retry docker pull -q --platform "$2" "$m" >/dev/null && docker tag "$m" "$1"
}

# image -> the digests of its linux/amd64 and linux/arm64 builds, as "amd64 REF" and "arm64 REF",
# read from the image's index with one request
digests() {
    docker manifest inspect "$1" > "$RESULTS/manifest.json" 2>/dev/null || return 1
    python3 - "$1" "$RESULTS/manifest.json" <<'EOF'
import json, sys
image, path = sys.argv[1:3]
name = image.rsplit(":", 1)[0]
for m in json.load(open(path)).get("manifests", []):
    p = m.get("platform", {})
    if p.get("os") == "linux" and p.get("architecture") in ("amd64", "arm64") and p.get("variant", "v8") == "v8":
        print(p["architecture"], f"{name}@{m['digest']}")
EOF
}

# ---- one system and architecture (called back through xargs)
if [ "${1:-}" = --one ]; then
    sys="$2"; platform="$3"
    arch="${platform#linux/}"
    family="$(system "$sys" | cut -d' ' -f2)"
    ref="$(awk -v s="$sys" -v a="$arch" '$1 == s && $2 == a { print $3 }' "$RESULTS/images")"
    log="$RESULTS/$sys-$arch.log"
    [ -n "$ref" ] || { echo "FAIL no image for $sys on $arch" > "$log"; exit 0; }
    set -- --platform "$platform" -v "$BLOCKS:/blocks:ro" -v "$here/scripts/in:/s:ro"
    [ -n "${NET:-}" ] && set -- "$@" --network "$NET" -v "$CA_DIR:/test:ro"
    start="$(date +%s)"
    if [ -n "${UPGRADE_FROM:-}" ]; then
        name="marqius-pkgtest-$RUN_ID-$sys-$arch"
        docker run -d --name "$name" "$@" "$ref" sleep 3600 >/dev/null
        echo "$name" >> "$RESULTS/containers"
        docker exec -e FAMILY="$family" -e EXPECT="$UPGRADE_FROM" -e PHASE=install -e BASE_URL="$BASE_URL" "$name" sh /s/try.sh > "$log" 2>&1 || true
        exit 0
    fi
    docker run --rm "$@" -e FAMILY="$family" -e EXPECT="$EXPECT" -e PHASE="${PHASE:-all}" -e BASE_URL="$BASE_URL" "$ref" sh /s/try.sh > "$log" 2>&1 || true
    echo "seconds $(( $(date +%s) - start ))" >> "$log"
    exit 0
fi

# ---- the run
mode=local; old=""; site=""
case "${1:-}" in
    --live) mode=live; shift ;;
    --upgrade) mode=upgrade; old="$(cd "$2" && pwd)"; site="$(cd "$3" && pwd)"; shift 3 ;;
    ''|-*) echo "usage: $0 SITE [SYSTEM...] | --upgrade OLD NEW [SYSTEM...] | --live [SYSTEM...]" >&2; exit 2 ;;
    *) site="$(cd "$1" && pwd)"; shift ;;
esac
systems="${*:-$ALL}"
for s in $systems; do system "$s" >/dev/null; done
PLATFORMS="${PLATFORMS:-linux/amd64 linux/arm64}"
JOBS="${JOBS:-4}"
RESULTS="${RESULTS:-$(mktemp -d "${TMPDIR:-/tmp}/marqius-pkgtest.XXXXXX")}"
mkdir -p "$RESULTS"
RESULTS="$(cd "$RESULTS" && pwd)"
case "$RESULTS" in *" "*) echo "RESULTS must be a folder without spaces in its path" >&2; exit 2 ;; esac
RUN_ID="$$"
export RESULTS RUN_ID

BLOCKS="$RESULTS/blocks"
python3 "$here/scripts/doc-blocks.py" "$here/README.md" "$BLOCKS" >/dev/null
export BLOCKS

if [ "$mode" = live ]; then
    EXPECT="${EXPECT:-$(curl -fsSL "$BASE_URL/VERSION")}"
else
    EXPECT="${EXPECT:-$(cat "$site/VERSION")}"
fi
export EXPECT

# ---- the images: looked up once each, then pulled one at a time
: > "$RESULTS/images"
for s in $systems; do
    image="$(system "$s" | cut -d' ' -f1)"
    found="$(retry digests "$image")" || found="$(retry digests "$(mirror "$image")" | sed "s|$(mirror "$image" | sed 's/:[^:]*$//')@|${image%:*}@|")" \
        || { echo "cannot look up $image" >&2; exit 1; }
    [ -n "$found" ] || { echo "cannot look up $image" >&2; exit 1; }
    for p in $PLATFORMS; do
        ref="$(echo "$found" | awk -v a="${p#linux/}" '$1 == a { print $2 }')"
        [ -n "$ref" ] || { echo "$image has no build for $p" >&2; exit 1; }
        echo "$s ${p#linux/} $ref" >> "$RESULTS/images"
        if ! docker image inspect "$ref" >/dev/null 2>&1; then
            fetch_image "$ref" "$p" || { echo "cannot pull $ref" >&2; exit 1; }
        fi
    done
done

host="${BASE_URL#https://}"; host="${host%%/*}"
case "${BASE_URL#https://}" in */*) prefix="/${BASE_URL#https://*/}" ;; *) prefix=/ ;; esac
NET=""; CA_DIR=""
cleanup() {
    [ -f "$RESULTS/containers" ] && xargs docker rm -f < "$RESULTS/containers" >/dev/null 2>&1 || true
    [ -n "$NET" ] && { docker rm -f "$NET-server" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
    rm -f "$RESULTS/containers"
}
trap cleanup EXIT INT TERM

if [ "$mode" != live ]; then
    # the stand-in host: a throwaway certificate authority and a certificate for the real name
    CA_DIR="$RESULTS/ca"
    mkdir -p "$CA_DIR" "$RESULTS/server"
    "$here/scripts/tools.sh" >/dev/null
    docker run --rm -v "$RESULTS/server:/c" -v "$CA_DIR:/ca" marqius-packages-apk-tools sh -c "
        openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj '/CN=marqius packages test authority' \
            -keyout /c/ca.key -out /ca/ca.crt 2>/dev/null &&
        openssl req -newkey rsa:2048 -nodes -subj '/CN=$host' -keyout /c/server.key -out /c/server.csr 2>/dev/null &&
        printf 'subjectAltName=DNS:$host\n' > /c/ext &&
        openssl x509 -req -in /c/server.csr -CA /ca/ca.crt -CAkey /c/ca.key -CAcreateserial -days 2 \
            -extfile /c/ext -out /c/server.crt 2>/dev/null &&
        chmod 644 /c/server.key"
    NET="marqius-pkgtest-$RUN_ID"
    docker network create "$NET" >/dev/null
    mkdir -p "$RESULTS/link"
    if [ "$mode" = upgrade ]; then
        ln -sfn /srv/old "$RESULTS/link/current"
    else
        ln -sfn /srv/new "$RESULTS/link/current"
    fi
    oldsite="$site"
    [ -n "$old" ] && oldsite="$old"
    docker image inspect "$SERVER_IMAGE" >/dev/null 2>&1 || fetch_image "$SERVER_IMAGE" "linux/$(docker version --format '{{.Server.Arch}}')"
    docker run -d --name "$NET-server" --network "$NET" --network-alias "$host" \
        -v "$site:/srv/new:ro" -v "$oldsite:/srv/old:ro" -v "$RESULTS/link:/srv/link" \
        -v "$RESULTS/server:/c:ro" -v "$here/scripts/in:/s:ro" \
        "$SERVER_IMAGE" python3 /s/serve.py /srv/link/current "$prefix" /c/server.crt /c/server.key >/dev/null
    # no system starts before the stand-in answers
    n=0
    until docker exec "$NET-server" python3 -c 'import socket; socket.create_connection(("127.0.0.1", 443), 1)' 2>/dev/null; do
        n=$((n + 1))
        [ "$n" -lt 60 ] || { echo "the stand-in server did not start" >&2; docker logs "$NET-server" >&2; exit 1; }
        sleep 1
    done
    export NET CA_DIR
fi

pairs="$RESULTS/pairs"
: > "$pairs"
for s in $systems; do for p in $PLATFORMS; do echo "$s $p" >> "$pairs"; done; done
echo "testing $(wc -l < "$pairs" | tr -d ' ') system and architecture pairs ($mode, marqius-wkhtmltopdf $EXPECT${old:+ after $(cat "$old/VERSION")}), logs in $RESULTS"

if [ "$mode" = upgrade ]; then
    UPGRADE_FROM="$(cat "$old/VERSION")"; export UPGRADE_FROM
    xargs -P "$JOBS" -n 2 sh "$0" --one < "$pairs"
    docker exec "$NET-server" ln -sfn /srv/new /srv/link/current
    while read -r s p; do
        family="$(system "$s" | cut -d' ' -f2)"
        log="$RESULTS/$s-${p#linux/}.log"
        echo "--- the site now holds $EXPECT" >> "$log"
        grep -q '^FAIL' "$log" && continue
        docker exec -e FAMILY="$family" -e EXPECT="$EXPECT" -e PHASE=update -e BASE_URL="$BASE_URL" "marqius-pkgtest-$RUN_ID-$s-${p#linux/}" \
            sh /s/try.sh >> "$log" 2>&1 || true
    done < "$pairs"
else
    xargs -P "$JOBS" -n 2 sh "$0" --one < "$pairs"
fi

failed=0
need=1
[ "$mode" = upgrade ] && need=2
while read -r s p; do
    arch="${p#linux/}"
    log="$RESULTS/$s-$arch.log"
    if ! grep -q '^FAIL' "$log" && [ "$(grep -c '^PASSED' "$log")" -ge "$need" ]; then
        printf 'PASS  %-11s %-6s %s\n' "$s" "$arch" "$(grep -c '^ok ' "$log") checks"
    else
        failed=$((failed + 1))
        printf 'FAIL  %-11s %-6s %s\n' "$s" "$arch" "$(grep -m1 '^FAIL' "$log" || tail -n 1 "$log")"
    fi
done < "$pairs"
[ "$failed" = 0 ]
