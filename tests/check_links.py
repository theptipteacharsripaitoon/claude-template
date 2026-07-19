#!/usr/bin/env python3
"""Repo-wide relative Markdown link check (exit 1 on any broken target).

Scope: every git-TRACKED *.md file. For each `[text](target)` link whose
target is not absolute (http/https/mailto), not a pure `#anchor`, resolve it
against the file's directory and require the path to exist (an `#anchor`
suffix on a real file is stripped; anchors themselves are not validated).
Fenced code blocks and inline code spans are stripped first so shell/regex
snippets containing `](` cannot false-positive.

Complements tests/skills/check_catalog.py, which owns the skills subtree and
its stricter catalog rules; this checker exists so root docs (README, HOW-TO,
CHANGELOG, reports/…) cannot ship dead relative links.

Run: python tests/check_links.py
"""
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

FENCE_RE = re.compile(r"^(```|~~~).*?^\1\s*$", re.M | re.S)
INLINE_CODE_RE = re.compile(r"`[^`\n]*`")
LINK_RE = re.compile(r"\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")

tracked = subprocess.run(
    ["git", "-C", ROOT, "ls-files", "*.md"],
    capture_output=True, text=True, check=True,
).stdout.split()

broken = 0
for rel in tracked:
    path = os.path.join(ROOT, rel)
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    text = FENCE_RE.sub("", text)
    text = INLINE_CODE_RE.sub("", text)
    base = os.path.dirname(path)
    for match in LINK_RE.finditer(text):
        target = match.group(1)
        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        target = target.split("#", 1)[0]
        if not target:
            continue
        if not os.path.exists(os.path.join(base, target)):
            broken += 1
            print(f"FAIL: {rel} -> broken link {target}")

print(f"links: {len(tracked)} tracked markdown file(s) checked")
print("links: ALL CHECKS PASS" if not broken else f"links: {broken} BROKEN LINK(S)")
sys.exit(1 if broken else 0)
