#!/bin/sh
# In the repo tools image: signs each .rpm in /out with rpmsign, then checks every signature
# against the public key alone, in an empty rpm database.
set -eu
. /scripts/in/gpg-key.sh
export GPG_TTY=/dev/null   # no terminal here, and none is needed: the key has no passphrase
for rpm in /out/*.rpm; do
    rpmsign --addsign \
        --define "_gpg_name $FPR" \
        --define "_gpg_digest_algo sha256" \
        --define "_gpg_sign_cmd_extra_args --batch --pinentry-mode loopback --passphrase ''" \
        "$rpm" >/dev/null
done
db="$(mktemp -d)"
gpg --batch --armor --export "$FPR" > "$db/key.asc"
rpmkeys --dbpath "$db" --import "$db/key.asc"
for rpm in /out/*.rpm; do
    rpmkeys --dbpath "$db" --checksig "$rpm" | grep -q ': digests signatures OK$' \
        || { rpmkeys --dbpath "$db" -Kv "$rpm" >&2; echo "signature check failed: $rpm" >&2; exit 1; }
done
