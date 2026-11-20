#!/usr/bin/env python3
"""Writes the repositories' home page from README.md, so that the address customers configure
shows the same instructions in a browser:

    scripts/make-index.py README.md SITE [--repo marqiushq/packages] [--strict]

The key fingerprints come from SITE/KEYS (written with the repositories), in place of the
README's {{FINGERPRINT}} and {{APK_KEY_SHA256}}. With --strict, the README itself must already
print those same fingerprints: the publishing run uses it, so the page and the README can never
name a key other than the one that signed the repositories. Only the standard library is used.
"""
import argparse
import html
import re
import sys
from pathlib import Path

STYLE = """
:root { --bg: #ffffff; --fg: #1d1d1f; --muted: #5b5b66; --line: #e3e3e8; --code: #f5f5f7;
        --accent: #8a5a00; --button: #ffffff; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #111114; --fg: #ececf1; --muted: #a2a2ad; --line: #2c2c33; --code: #1b1b20;
          --accent: #e0b25c; --button: #22222a; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg);
       font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
main { max-width: 860px; margin: 0 auto; padding: 40px 16px 64px; }
h1 { font-size: 30px; line-height: 1.25; margin: 0 0 16px; }
h2 { font-size: 21px; margin: 40px 0 12px; padding-top: 16px; border-top: 1px solid var(--line); }
a { color: var(--accent); }
p, li { color: var(--fg); }
code { font: 14px/1.5 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; background: var(--code);
       padding: 1px 5px; border-radius: 4px; overflow-wrap: anywhere; }
.block { position: relative; margin: 12px 0 20px; }
pre { margin: 0; background: var(--code); border: 1px solid var(--line); border-radius: 8px;
      padding: 14px 76px 14px 16px; overflow-x: auto; }
pre code { background: none; padding: 0; white-space: pre; overflow-wrap: normal; }
.copy { position: absolute; top: 8px; right: 8px; font: 13px/1 inherit; padding: 7px 10px; cursor: pointer;
        color: var(--fg); background: var(--button); border: 1px solid var(--line); border-radius: 6px; }
.copy:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
"""

SCRIPT = """
document.querySelectorAll('.copy').forEach(function (b) {
  b.addEventListener('click', function () {
    var text = b.parentNode.querySelector('code').innerText;
    navigator.clipboard.writeText(text).then(function () {
      b.textContent = 'Copied';
      setTimeout(function () { b.textContent = 'Copy'; }, 1500);
    });
  });
});
"""


def slug(text):
    s = re.sub(r"<[^>]+>", "", text).lower()
    s = re.sub(r"[^a-z0-9 -]", "", s)
    return s.strip().replace(" ", "-")


def inline(text, repo):
    parts = re.split(r"(`[^`]+`)", text)
    out = []
    for p in parts:
        if p.startswith("`") and p.endswith("`") and len(p) > 1:
            out.append(f"<code>{html.escape(p[1:-1])}</code>")
            continue
        p = html.escape(p, quote=False)
        p = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", p)

        def link(m):
            label, url = m.group(1), m.group(2)
            if not re.match(r"^(https?:|#|mailto:)", url):
                url = f"https://github.com/{repo}/blob/main/{url}"
            return f'<a href="{html.escape(url)}">{label}</a>'

        p = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", link, p)
        out.append(p)
    return "".join(out)


def render(md, repo):
    lines = md.splitlines()
    body, para, items, i = [], [], [], 0

    def flush():
        if para:
            body.append(f"<p>{inline(' '.join(para), repo)}</p>")
            para.clear()
        if items:
            body.append("<ul>" + "".join(f"<li>{inline(x, repo)}</li>" for x in items) + "</ul>")
            items.clear()

    title = ""
    while i < len(lines):
        line = lines[i]
        if line.startswith("<!--"):
            i += 1
            continue
        if line.startswith("```"):
            flush()
            code = []
            i += 1
            while not lines[i].startswith("```"):
                code.append(lines[i])
                i += 1
            body.append('<div class="block"><pre><code>' + html.escape("\n".join(code))
                        + '</code></pre><button class="copy" type="button">Copy</button></div>')
        elif line.startswith("# "):
            flush()
            title = line[2:].strip()
            body.append(f"<h1>{inline(title, repo)}</h1>")
        elif line.startswith("## "):
            flush()
            text = line[3:].strip()
            body.append(f'<h2 id="{slug(text)}">{inline(text, repo)}</h2>')
        elif line.startswith("- "):
            if para:
                flush()
            items.append(line[2:].strip())
        elif not line.strip():
            flush()
        else:
            if items and line.startswith("  "):
                items[-1] += " " + line.strip()
            else:
                para.append(line.strip())
        i += 1
    flush()
    return title, "\n".join(body)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("readme")
    ap.add_argument("site")
    ap.add_argument("--repo", default="marqiushq/packages")
    ap.add_argument("--strict", action="store_true")
    a = ap.parse_args()
    md = Path(a.readme).read_text(encoding="utf-8")
    keys = dict(line.split(" ", 1) for line in Path(a.site, "KEYS").read_text().splitlines() if " " in line)
    facts = {"{{FINGERPRINT}}": keys["openpgp"], "{{APK_KEY_SHA256}}": keys["apk"]}
    if a.strict:
        for placeholder, value in facts.items():
            if value not in md:
                sys.exit(f"README.md does not print the key that signed the repositories: {value}")
    for placeholder, value in facts.items():
        md = md.replace(placeholder, value)
    title, body = render(md, a.repo)
    page = f"""<!doctype html>
<html lang="en-GB">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="Install marqius-wkhtmltopdf, the drop-in replacement for wkhtmltopdf, with apt, dnf and apk.">
<style>{STYLE}</style>
</head>
<body>
<main>
{body}
</main>
<script>{SCRIPT}</script>
</body>
</html>
"""
    Path(a.site, "index.html").write_text(page, encoding="utf-8")


if __name__ == "__main__":
    main()
