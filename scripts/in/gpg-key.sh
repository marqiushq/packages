# Sourced by the scripts that sign: loads the OpenPGP private key from /keys/gpg.asc into a
# keyring of its own, which disappears with the container, and sets FPR to its fingerprint.
GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
chmod 700 "$GNUPGHOME"
gpg --batch --quiet --import /keys/gpg.asc 2>/dev/null
FPR="$(gpg --batch --with-colons --list-secret-keys | awk -F: '/^fpr:/ { print $10; exit }')"
[ -n "$FPR" ] || { echo "no OpenPGP private key in /keys/gpg.asc" >&2; exit 1; }
gpg_sign() {
    gpg --batch --yes --quiet --pinentry-mode loopback --passphrase '' \
        --local-user "$FPR" --digest-algo SHA512 "$@"
}
