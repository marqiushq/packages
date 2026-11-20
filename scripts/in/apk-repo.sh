#!/bin/sh
# In the apk tools image: writes and signs the Alpine repository in /site/alpine, whose packages
# make-repos.sh has already put in place (one folder per architecture), and the public key
# customers install as /etc/apk/keys/$APK_KEY_NAME.
#
# The index is APKINDEX.tar.gz signed as .SIGN.RSA.<key name>: the format Alpine's own
# repositories use, which apk 2 (Alpine 3.22) and apk 3 (3.23 and later) both read.
set -eu
: "${APK_KEY_NAME:?}"
cd /site/alpine
openssl rsa -in /keys/apk.rsa -pubout -out "$APK_KEY_NAME" 2>/dev/null
cp "$APK_KEY_NAME" "/etc/apk/keys/$APK_KEY_NAME"
for arch in x86_64 aarch64; do
    ls "$arch"/*.apk >/dev/null
    (
        cd "$arch"
        apk index --quiet --no-warnings --description "marqius-wkhtmltopdf" -o APKINDEX.tar.gz -- *.apk
        abuild-sign -q -k /keys/apk.rsa -p "$APK_KEY_NAME" APKINDEX.tar.gz
    )
done
echo "apk $(sha256sum "$APK_KEY_NAME" | cut -d' ' -f1)" >> /site/KEYS
# and they read back as signed, with this key alone
for arch in x86_64 aarch64; do
    tar -tzf "$arch/APKINDEX.tar.gz" | grep -qx ".SIGN.RSA.$APK_KEY_NAME"
done
