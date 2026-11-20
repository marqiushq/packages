#!/usr/bin/env python3
"""Finds out whether the repositories are behind marqius.com, and fetches the release they need.

    python3 scripts/follow-release.py --site URL --out DIR [--always] [--version X.Y.Z] [--base URL]

Reads the latest version from marqius.com and the version the repositories serve (URL/VERSION;
none before the first release). When marqius.com is ahead, it downloads that release's four
builds into DIR (linux-x86_64, linux-arm64, macos-arm64 and windows-x86_64.exe: the Linux ones
become the packages, all four are listed in SHA256SUMS), and keeps each one only if it matches
the checksum published beside it (and with the release's SHA256SUMS, should marqius.com publish
one). --always downloads the latest release even when the
repositories serve it already (for tests); --version names the version to download. It never
goes back to an older version than the one served. In GitHub Actions it sets the step outputs
`new` (true when marqius.com is ahead of the repositories), `version` (the version downloaded,
or the one served when nothing was) and `served`. Only the standard library is used.
"""
import argparse
import hashlib
import os
import re
import socket
import sys
import urllib.error
import urllib.request
from pathlib import Path

BASE = "https://marqius.com/download/marqius-wkhtmltopdf"
BUILDS = ["linux-x86_64", "linux-arm64", "macos-arm64", "windows-x86_64.exe"]
AGENT = "marqius-packages (+https://github.com/marqiushq/packages)"


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": AGENT, "Cache-Control": "no-cache"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def key(v):
    return tuple(int(x) for x in v.split("."))


def version(text, where):
    text = text.strip()
    if not re.fullmatch(r"\d+(\.\d+)+", text):
        sys.exit(f"{where} does not hold a version: {text[:40]!r}")
    return text


def output(**kw):
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as f:
            for k, v in kw.items():
                f.write(f"{k}={v}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--site", required=True, help="where the repositories are served")
    ap.add_argument("--out", required=True, help="folder for the release's builds")
    ap.add_argument("--version", help="fetch this version, whether or not it is new")
    ap.add_argument("--always", action="store_true", help="fetch the latest even when it is served already")
    ap.add_argument("--base", default=BASE)
    a = ap.parse_args()

    latest = version(fetch(f"{a.base}/latest").decode("utf-8"), f"{a.base}/latest")
    try:
        served = version(fetch(f"{a.site.rstrip('/')}/VERSION").decode("utf-8"), f"{a.site}/VERSION")
    except urllib.error.URLError as e:
        # nothing is served yet: the site has no VERSION, or its address does not exist yet
        if not (getattr(e, "code", None) == 404 or isinstance(getattr(e, "reason", None), socket.gaierror)):
            raise
        served = "none"
    want = version(a.version or latest, "--version")
    new = served == "none" or key(want) > key(served)
    if not new and not a.always and a.version is None:
        print(f"the repositories serve {served}, the latest release; nothing to do")
        output(new="false", version=served, served=served)
        return
    if served != "none" and key(want) < key(served):
        sys.exit(f"the repositories serve {served}; they never go back to {want}")

    # a SHA256SUMS published with the release, when there is one, must agree with each file's own
    sums = {}
    try:
        for line in fetch(f"{a.base}/{want}/SHA256SUMS").decode("utf-8").splitlines():
            m = re.fullmatch(r"([0-9a-f]{64})\s+\*?(\S+)", line.strip().lower())
            if m:
                sums[m.group(2)] = m.group(1)
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for build in BUILDS:
        name = f"marqius-wkhtmltopdf-{build}"
        url = f"{a.base}/{want}/{name}"
        published = fetch(f"{url}.sha256").decode("utf-8").strip()[:64].lower()
        if not re.fullmatch(r"[0-9a-f]{64}", published):
            sys.exit(f"{url}.sha256 does not hold a checksum")
        if sums and sums.get(name.lower()) != published:
            sys.exit(f"{name}: its .sha256 and the release's SHA256SUMS disagree; nothing is built")
        data = fetch(url)
        got = hashlib.sha256(data).hexdigest()
        if got != published:
            sys.exit(f"{url} does not match its published checksum; nothing is built")
        (out / name).write_bytes(data)
        print(f"{name} {want}: {published}")
    print(f"marqius.com has {latest}; the repositories serve {served}; fetched {want}")
    output(new=str(new).lower(), version=want, served=served)


if __name__ == "__main__":
    main()
