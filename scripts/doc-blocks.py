#!/usr/bin/env python3
"""Writes out README.md's command blocks, exactly as printed, for the tests to run.

    scripts/doc-blocks.py README.md DIR

Each fenced block that follows a line <!-- test: NAME --> is written to DIR/NAME. The tests
run these files and nothing else, so what a reader copies from the page is what was tested.
Only the standard library is used.
"""
import re
import sys
from pathlib import Path


def blocks(text):
    found = {}
    for m in re.finditer(r"^<!-- test: ([a-z0-9-]+) -->\n```[a-z]*\n(.*?)^```$", text, re.M | re.S):
        name, body = m.group(1), m.group(2)
        if name in found:
            sys.exit(f"README.md has two blocks named {name}")
        found[name] = body
    markers = re.findall(r"^<!-- test: ([a-z0-9-]+) -->", text, re.M)
    missing = [n for n in markers if n not in found]
    if missing:
        sys.exit(f"README.md: no command block right after the marker for {', '.join(missing)}")
    return found


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    found = blocks(Path(sys.argv[1]).read_text(encoding="utf-8"))
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for name, body in found.items():
        (out / name).write_text(body, encoding="utf-8")
    print(" ".join(sorted(found)))


if __name__ == "__main__":
    main()
