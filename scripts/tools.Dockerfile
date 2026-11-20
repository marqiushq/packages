# The tools that sign the packages and write the repositories' indexes, from pinned images, so
# a laptop and the workflow use the same ones. (Docker's official images, from Amazon's public
# mirror of them: Docker Hub limits how often a machine may pull.)
#
#   repo   gpg, rpmsign, apt-ftparchive, createrepo_c (Debian 13)
#   apk    apk index and abuild-sign (Alpine 3.24)

FROM public.ecr.aws/docker/library/debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2 AS repo
RUN apt-get update \
 && apt-get install -y --no-install-recommends gnupg apt-utils createrepo-c rpm xz-utils \
 && rm -rf /var/lib/apt/lists/*

FROM public.ecr.aws/docker/library/alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS apk
RUN apk add --no-cache abuild
