#!/bin/sh
# In the repo tools image: writes and signs the apt and dnf repositories in /site, whose packages
# make-repos.sh has already put in place, and the files customers set them up with.
# BASE_URL is the address /site will be served at.
set -eu
. /scripts/in/gpg-key.sh
: "${BASE_URL:?}"
cd /site
gpg --batch --armor --export "$FPR" > marqius.asc
# the fingerprint, grouped as dnf shows it when it asks to accept the key
echo "openpgp $(echo "$FPR" | sed 's/..../& /g; s/ $//')" > KEYS

# ---- apt: one suite, "stable", for every Debian and Ubuntu release (the program is static)
cd /site/apt
for arch in amd64 arm64; do
    d="dists/stable/main/binary-$arch"
    mkdir -p "$d"
    apt-ftparchive -o APT::FTPArchive::MD5=false -o APT::FTPArchive::SHA1=false \
        --arch "$arch" packages pool > "$d/Packages"
    grep -q '^Package: marqius-wkhtmltopdf$' "$d/Packages" || { echo "no $arch package for apt" >&2; exit 1; }
    gzip -9nk "$d/Packages"
    xz -9k "$d/Packages"
done
# by-hash copies too, so that a client holding an older Release still finds the Packages it names
apt-ftparchive \
    -o APT::FTPArchive::DoByHash=true \
    -o APT::FTPArchive::Release::MD5=false -o APT::FTPArchive::Release::SHA1=false \
    -o APT::FTPArchive::Release::Origin=marqius \
    -o APT::FTPArchive::Release::Label=marqius \
    -o APT::FTPArchive::Release::Suite=stable \
    -o APT::FTPArchive::Release::Codename=stable \
    -o "APT::FTPArchive::Release::Architectures=amd64 arm64" \
    -o APT::FTPArchive::Release::Components=main \
    -o "APT::FTPArchive::Release::Description=marqius-wkhtmltopdf, the drop-in replacement for wkhtmltopdf" \
    release dists/stable > /tmp/Release
mv /tmp/Release dists/stable/Release
gpg_sign --clearsign -o dists/stable/InRelease dists/stable/Release
gpg_sign --detach-sign --armor -o dists/stable/Release.gpg dists/stable/Release

# apt's source, with the key inside it (apt 2.4 and later read a key given this way)
{
    printf 'Types: deb\nURIs: %s/apt\nSuites: stable\nComponents: main\nArchitectures: amd64 arm64\nSigned-By:\n' "$BASE_URL"
    sed -e 's/^$/./' -e 's/^/ /' /site/marqius.asc
} > marqius.sources

# ---- dnf: one repository for every release of Rocky, RHEL, Fedora and Amazon Linux
cd /site/rpm
createrepo_c --quiet --no-database --checksum sha256 --general-compress-type gz .
gpg_sign --detach-sign --armor -o repodata/repomd.xml.asc repodata/repomd.xml
cat > marqius.repo <<EOF
[marqius]
name=marqius-wkhtmltopdf
baseurl=$BASE_URL/rpm
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$BASE_URL/marqius.asc
metadata_expire=6h
EOF

# ---- everything signed must check against the public key alone
check="$(mktemp -d)"
gpg --batch --quiet --homedir "$check" --import /site/marqius.asc 2>/dev/null
gpg --batch --quiet --homedir "$check" --verify /site/apt/dists/stable/InRelease 2>/dev/null
gpg --batch --quiet --homedir "$check" --verify /site/apt/dists/stable/Release.gpg /site/apt/dists/stable/Release 2>/dev/null
gpg --batch --quiet --homedir "$check" --verify /site/rpm/repodata/repomd.xml.asc /site/rpm/repodata/repomd.xml 2>/dev/null
