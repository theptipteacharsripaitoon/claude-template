#!/usr/bin/env python3
"""Catalog consistency gate for .claude/skills/.

Checks (exit 1 on any failure):
  1. Every skill folder has a SKILL.md with parseable YAML frontmatter.
  2. frontmatter name == folder name; description present and <= 1536 chars
     (documented combined cap for description + when_to_use).
  3. Folder count == INDEX.md built-table rows == README.md table rows.
  4. Every relative markdown link in .claude/skills/**/*.md resolves.

Requires: pyyaml.  Run: python tests/skills/check_catalog.py
"""
import glob
import io
import os
import re
import sys

import yaml

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SKILLS = os.path.join(ROOT, ".claude", "skills")
DESC_CAP = 1536
ok = True


def fail(msg):
    global ok
    ok = False
    print("FAIL:", msg)


folders = sorted(
    os.path.basename(os.path.dirname(p))
    for p in glob.glob(os.path.join(SKILLS, "*", "SKILL.md"))
)

for name in folders:
    path = os.path.join(SKILLS, name, "SKILL.md")
    text = io.open(path, encoding="utf-8").read()
    if not text.startswith("---"):
        fail("%s: no frontmatter" % name)
        continue
    try:
        meta = yaml.safe_load(text.split("---", 2)[1])
    except yaml.YAMLError as exc:
        fail("%s: frontmatter does not parse: %s" % (name, exc))
        continue
    if meta.get("name") != name:
        fail("%s: frontmatter name %r != folder" % (name, meta.get("name")))
    desc = meta.get("description") or ""
    if not isinstance(desc, str) or len(desc) < 50:
        fail("%s: missing/short description" % name)
    if len(desc) > DESC_CAP:
        fail("%s: description %d chars exceeds %d cap" % (name, len(desc), DESC_CAP))

index_rows = re.findall(
    r"^\| \[([a-z0-9-]+)\]\(", io.open(os.path.join(SKILLS, "INDEX.md"), encoding="utf-8").read(), re.M
)
readme_rows = re.findall(
    r"^\| `([a-z0-9-]+)/`", io.open(os.path.join(SKILLS, "README.md"), encoding="utf-8").read(), re.M
)
if sorted(index_rows) != folders:
    fail(
        "INDEX built-table mismatch: folders=%d index=%d; delta=%s"
        % (len(folders), len(index_rows), sorted(set(folders) ^ set(index_rows)))
    )
if sorted(readme_rows) != folders:
    fail(
        "README table mismatch: folders=%d readme=%d; delta=%s"
        % (len(folders), len(readme_rows), sorted(set(folders) ^ set(readme_rows)))
    )

for path in glob.glob(os.path.join(SKILLS, "**", "*.md"), recursive=True):
    base = os.path.dirname(path)
    for match in re.finditer(r"\]\(([^)]+)\)", io.open(path, encoding="utf-8").read()):
        link = match.group(1)
        if link.startswith(("http", "#")):
            continue
        if not os.path.exists(os.path.join(base, link)):
            fail("%s -> broken link %s" % (os.path.relpath(path, ROOT), link))

print("catalog: %d skills checked" % len(folders))
print("catalog: ALL CHECKS PASS" if ok else "catalog: FAILURES ABOVE")
sys.exit(0 if ok else 1)
