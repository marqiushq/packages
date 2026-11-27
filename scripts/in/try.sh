#!/bin/sh
# Inside a fresh container of one system: installs marqius-wkhtmltopdf from the repositories with
# README.md's own lines (in /blocks, exactly as printed), then checks what they did.
#
#   FAMILY   apt, dnf or apk
#   EXPECT   the version that must be installed
#   BASE_URL the repositories' address, as the README prints it
#   PHASE    all (the default): install, check, names, names taken away, remove
#            install: install and give it the names (the first half of an update test)
#            update: README's update line, once the site holds a newer release
#            refuse: README's install lines must fail (a repository signed with another key,
#            or a package changed after it was signed)
#
# On Debian, Ubuntu and the dnf systems the lines run as an ordinary user with sudo, logged in
# with su - (so with the system's own login PATH), as on a server; on Alpine as root, as the
# README says. apt and dnf ask before they install: the
# answer is yes, as a reader would give. /test/ca.crt, when present, is the certificate
# authority of the local stand-in for the real host, trusted first.
set -u
FAMILY="${FAMILY:?}"
EXPECT="${EXPECT:?}"
BASE_URL="${BASE_URL:?}"
PHASE="${PHASE:-all}"
pass() { echo "ok   $*"; }
fail() { echo "FAIL $*"; exit 1; }

# Ubuntu's own archive, when some of it crawls: on 26 November 2026 some of its addresses sent 7-28 kB/s
# for over an hour (kernel.org's mirror of it: 900 kB/s), and the Ubuntu 24.04 test ran out of time in
# apt-get. Each address of the archive apt names, and that mirror, are asked at once for the first
# megabyte of one file, for 4 s at most. When an address sends under a quarter of what the mirror sent,
# apt is pointed at the mirror (the same packages, signed with Ubuntu's own keys, some hours behind);
# otherwise the system is left as it came. It prints what it did, and nothing when it left apt alone.
# The README's lines then run as printed. Ubuntu's ARM64 archive (ports) has no such mirror. The same
# function is in the marqius engine's tests (tools/download-tests/config.py).
ubuntu_mirror() {
    local etc src host d ips ip mip get m b n slow got all f t
    etc=${1:-/etc}
    grep -qs '^ID=ubuntu' "$etc/os-release" || return 0
    for t in bash timeout getent mktemp; do command -v $t > /dev/null || { echo "no $t here: nothing measured" >&2; return 0; }; done
    src=$(grep -lsE 'https?://([a-z0-9-]+\.)*(archive|security)\.ubuntu\.com/ubuntu' "$etc/apt/sources.list" "$etc"/apt/sources.list.d/*.list "$etc"/apt/sources.list.d/*.sources)
    [ -n "$src" ] || { echo "apt names no archive.ubuntu.com: nothing measured" >&2; return 0; }
    host=$(grep -ohE 'https?://([a-z0-9-]+\.)*archive\.ubuntu\.com/ubuntu' $src | head -1 | cut -d/ -f3)
    [ -n "$host" ] || { echo "apt names no archive.ubuntu.com: nothing measured" >&2; return 0; }
    d=$(mktemp -d)
    ips=$(getent ahostsv4 "$host" | awk '{ print $1 }' | sort -u)
    mip=$(getent ahostsv4 mirrors.edge.kernel.org | awk 'NR == 1 { print $1 }')
    get='exec 3<> "/dev/tcp/$0/80" && printf "GET /ubuntu/ls-lR.gz HTTP/1.0\r\nHost: %s\r\n\r\n" "$1" >&3 && cat <&3'
    for ip in $ips; do
        timeout 4 bash -c "$get" "$ip" "$host" 2> /dev/null | head -c 1000000 | wc -c > "$d/$ip" &
    done
    timeout 4 bash -c "$get" "${mip:-mirrors.edge.kernel.org}" mirrors.edge.kernel.org 2> /dev/null | head -c 1000000 | wc -c > "$d/mirror" &
    wait
    m=$(($(cat "$d/mirror")))
    n=0 slow=0 got="" all=""
    for ip in $ips; do
        b=$(($(cat "$d/$ip")))
        n=$((n + 1)) all="$all, $ip $((b / 1000))"
        if [ "$m" -gt $((4 * b)) ]; then slow=$((slow + 1)) got="$got, $((b / 1000))"; fi
    done
    rm -rf "$d"
    echo "kB in 4 s at most: mirrors.edge.kernel.org $((m / 1000))$all" >&2
    [ "$slow" -gt 0 ] || return 0
    for f in $src; do
        sed -E 's#https?://([a-z0-9-]+\.)*(archive|security)\.ubuntu\.com/ubuntu#http://mirrors.edge.kernel.org/ubuntu#g' "$f" > "$f.mirror" && cat "$f.mirror" > "$f" && rm -f "$f.mirror"
    done
    echo "kernel.org's mirror of Ubuntu's archive: $slow of $host's $n addresses sent under a quarter of the mirror's $((m / 1000)) kB (${got#, } kB, in 4 s at most)"
}

# ---- a system as people have one
prepare() {
    case "$FAMILY" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            said="$(ubuntu_mirror)"
            [ -z "$said" ] || echo "apt: $said"
            { apt-get update -qq && apt-get install -y -qq --no-install-recommends sudo curl ca-certificates; } >/dev/null 2>&1 \
                || fail "could not install sudo, curl and ca-certificates"
            ;;
        dnf)
            # curl is in every one of these images; sudo, useradd, su and script are not in all
            # (asked for by path: Fedora has script in a package of its own)
            dnf install -y -q sudo /usr/sbin/useradd /usr/bin/su /usr/bin/script >/dev/null 2>&1 || fail "could not install sudo"
            ;;
    esac
    if [ -f /test/ca.crt ]; then
        case "$FAMILY" in
            apt) cp /test/ca.crt /usr/local/share/ca-certificates/marqius-test.crt && update-ca-certificates >/dev/null 2>&1 ;;
            dnf) cp /test/ca.crt /etc/pki/ca-trust/source/anchors/marqius-test.crt && update-ca-trust ;;
            apk) cat /test/ca.crt >> /etc/ssl/certs/ca-certificates.crt ;;
        esac || fail "could not trust the test certificate authority"
    fi
    if [ "$FAMILY" != apk ]; then
        id admin >/dev/null 2>&1 || useradd -m -s /bin/bash admin || fail "could not add a user"
        echo 'admin ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/admin && chmod 440 /etc/sudoers.d/admin
    fi
    # a block runs as a reader runs it: in a terminal (dnf asks before it accepts a key, and
    # refuses when nobody is at one), answering yes to each question. The answer is typed once
    # a second, as a person would: apt throws away what was typed before it asked. The typing
    # stops after five minutes (an older script, util-linux 2.37, can wait for it to end after
    # the block has finished), and a block has fifteen minutes in all.
    mkdir -p /usr/local/sbin
    if [ "$FAMILY" = apk ]; then
        printf '#!/bin/sh\ncd "$HOME" && timeout 900 sh -e "$1" < /dev/null\n' > /usr/local/sbin/runblock
    else
        printf '#!/bin/sh\ncd "$HOME" && i=0 && while [ $i -lt 300 ] && sleep 1; do echo y; i=$((i + 1)); done | timeout 900 script -qe --echo never -c "bash -e $1" /dev/null\n' > /usr/local/sbin/runblock
    fi
    chmod 755 /usr/local/sbin/runblock
}

# README's block NAME, as printed (then a new line: a terminal's last line may lack one)
run() {
    if [ "$FAMILY" = apk ]; then
        HOME=/root /usr/local/sbin/runblock "/blocks/$1"
    else
        su - admin -c "/usr/local/sbin/runblock /blocks/$1"
    fi
    rc=$?
    echo
    return $rc
}
# the README's lines that it tells Alpine readers to run as root without sudo
run_as_root_without_sudo() {
    sed 's/^sudo //' "/blocks/$1" > "/tmp/$1"
    HOME=/root /usr/local/sbin/runblock "/tmp/$1"
}
run_names() {
    if [ "$FAMILY" = apk ]; then run_as_root_without_sudo "$1"; else run "$1"; fi
}
as_user() {
    if [ "$FAMILY" = apk ]; then (cd /root && sh -c "$1"); else su - admin -c "$1"; fi
}

installed_version() {
    as_user 'marqius-wkhtmltopdf --version' 2>/dev/null | sed -n 's/^marqius-wkhtmltopdf \([0-9.]*\).*/\1/p'
}

install_lines() {
    case "$FAMILY" in
        apt) run apt-repo || fail "README apt-repo"; run apt-install || fail "README apt-install" ;;
        dnf) run dnf-repo || fail "README dnf-repo"; run dnf-install || fail "README dnf-install" ;;
        apk) run apk || fail "README apk" ;;
    esac
    pass "installed with README's lines"
    at="$(as_user 'readlink -f "$(command -v marqius-wkhtmltopdf)"')"
    [ "$at" = /usr/bin/marqius-wkhtmltopdf ] || fail "found as '$at', not /usr/bin/marqius-wkhtmltopdf"
    case "$FAMILY" in
        apt) files="$(dpkg -L marqius-wkhtmltopdf)" ;;
        dnf) files="$(rpm -ql marqius-wkhtmltopdf)" ;;
        apk) files="$(apk info -qL marqius-wkhtmltopdf | sed 's|^|/|')" ;;
    esac
    onpath="$(echo "$files" | grep -E '/s?bin/' | tr '\n' ' ')"
    [ "$onpath" = "/usr/bin/marqius-wkhtmltopdf " ] || fail "the package puts on PATH: $onpath"
    v="$(installed_version)"
    [ "$v" = "$EXPECT" ] || fail "installed version is '$v', not $EXPECT"
    pass "marqius-wkhtmltopdf $v, at /usr/bin/marqius-wkhtmltopdf"
    for name in wkhtmltopdf wkhtmltoimage; do
        if as_user "command -v $name" >/dev/null 2>&1; then fail "the package took the name $name"; fi
    done
    pass "the names wkhtmltopdf and wkhtmltoimage are left free"
    case "$FAMILY" in
        apt) dpkg -s fonts-liberation2 fonts-dejavu-core >/dev/null 2>&1 || fail "fonts not installed"
             apt-cache policy marqius-wkhtmltopdf | grep -q "$BASE_URL/apt stable/main" || fail "not from the repository" ;;
        dnf) rpm -q dejavu-sans-fonts >/dev/null || fail "DejaVu fonts not installed"
             # Liberation is recommended: installed wherever the system offers it (not on UBI)
             if dnf -q repoquery liberation-sans-fonts 2>/dev/null | grep -q liberation; then
                 rpm -q liberation-sans-fonts >/dev/null || fail "Liberation fonts not installed"
             fi
             rpm -q --qf '%{SIGPGP:pgpsig}%{RSAHEADER:pgpsig}\n' marqius-wkhtmltopdf | grep -q 'Key ID' || fail "installed package has no signature"
             { rpm -q gpg-pubkey --qf '%{SUMMARY}\n' 2>/dev/null; rpmkeys --list 2>/dev/null; } | grep -qi marqius \
                 || fail "dnf did not import the marqius key" ;;
        apk) apk info -e font-liberation font-dejavu >/dev/null || fail "fonts not installed"
             apk policy marqius-wkhtmltopdf 2>/dev/null | grep -q "$BASE_URL/alpine" || fail "not from the repository" ;;
    esac
    pass "fonts installed with it; package came signed from the repository"
}

check_lines() {
    run check || fail "README check"
    pdf="$(as_user 'head -c 5 invoice.pdf')"
    [ "$pdf" = "%PDF-" ] || fail "check: invoice.pdf is not a PDF"
    size="$(as_user 'wc -c < invoice.pdf' | tr -d ' ')"
    [ "$size" -gt 1000 ] || fail "check: invoice.pdf is only $size bytes"
    pass "README's check made invoice.pdf ($size bytes)"
}

names_lines() {
    run_names names || fail "README names"
    as_user 'wkhtmltopdf -V' 2>&1 | grep -q marqius || fail "names: wkhtmltopdf -V does not answer as marqius"
    [ -L /usr/local/bin/wkhtmltoimage ] || fail "names: no wkhtmltoimage"
    pass "README's names line: wkhtmltopdf and wkhtmltoimage run it"
}

undo_lines() {
    run_names names-undo || fail "README names-undo"
    for name in wkhtmltopdf wkhtmltoimage; do
        [ ! -e "/usr/local/bin/$name" ] || fail "names-undo left /usr/local/bin/$name"
    done
    pass "README's undo line took the names away"
}

remove_lines() {
    # a wkhtmltopdf of its own first, which "install --force" keeps and removal must put back
    printf '#!/bin/sh\necho old wkhtmltopdf\n' > /usr/local/bin/wkhtmltopdf && chmod 755 /usr/local/bin/wkhtmltopdf
    if [ "$FAMILY" = apk ]; then
        marqius-wkhtmltopdf install --force >/dev/null || fail "install --force"
    else
        su - admin -c "sudo marqius-wkhtmltopdf install --force" >/dev/null || fail "install --force"
    fi
    [ -e /usr/local/bin/wkhtmltopdf.before-marqius ] || fail "install --force kept nothing"
    run "$FAMILY-remove" || fail "README $FAMILY-remove"
    [ ! -e /usr/bin/marqius-wkhtmltopdf ] || fail "remove left /usr/bin/marqius-wkhtmltopdf"
    [ "$(/usr/local/bin/wkhtmltopdf 2>/dev/null)" = "old wkhtmltopdf" ] || fail "remove did not put the old wkhtmltopdf back"
    [ ! -e /usr/local/bin/wkhtmltoimage ] || fail "remove left the name wkhtmltoimage"
    [ ! -e /usr/local/bin/wkhtmltopdf.before-marqius ] || fail "remove left wkhtmltopdf.before-marqius"
    case "$FAMILY" in
        apt) [ ! -e /etc/apt/sources.list.d/marqius.sources ] || fail "remove left the apt source" ;;
        dnf) [ ! -e /etc/yum.repos.d/marqius.repo ] || fail "remove left the dnf repository" ;;
        apk) ! grep -q "$BASE_URL" /etc/apk/repositories || fail "remove left the Alpine repository"
             [ ! -e /etc/apk/keys/marqius.rsa.pub ] || fail "remove left the Alpine key" ;;
    esac
    pass "README's remove line removed it, took the names away and put the old wkhtmltopdf back"
}

case "$PHASE" in
    all)
        prepare
        install_lines
        check_lines
        names_lines
        undo_lines
        remove_lines
        ;;
    install)
        prepare
        install_lines
        names_lines
        ;;
    update)
        run "$FAMILY-update" || fail "README $FAMILY-update"
        v="$(installed_version)"
        [ "$v" = "$EXPECT" ] || fail "after the update line the version is '$v', not $EXPECT"
        as_user 'wkhtmltopdf -V' 2>&1 | grep -q "marqius-wkhtmltopdf $EXPECT" || fail "after the update the name wkhtmltopdf does not run $EXPECT"
        pass "README's update line moved it to $EXPECT; the names still run it"
        ;;
    refuse)
        prepare
        case "$FAMILY" in
            apt) run apt-repo || fail "README apt-repo"
                 if run apt-install; then fail "README's lines installed from a repository they should refuse"; fi ;;
            dnf) run dnf-repo || fail "README dnf-repo"
                 if run dnf-install; then fail "README's lines installed from a repository they should refuse"; fi ;;
            apk) if run apk; then fail "README's lines installed from a repository they should refuse"; fi ;;
        esac
        [ ! -e /usr/bin/marqius-wkhtmltopdf ] || fail "marqius-wkhtmltopdf was installed all the same"
        pass "README's install lines refused the repository, and installed nothing"
        ;;
    *) fail "unknown PHASE $PHASE" ;;
esac
echo PASSED
