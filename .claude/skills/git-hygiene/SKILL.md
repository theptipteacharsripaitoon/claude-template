---
name: git-hygiene
description: >-
  Use when preparing git state for a RESTRUCTURING or cleanup — work branch,
  batches of file moves, commit sequencing, fixing what git tracks. Trigger:
  "set up the cleanup branch", "git mv this batch", "stop tracking generated
  files", "untrack node_modules". Do NOT use for a simple one-off move the
  user asked for (just do it), commit-message format (CLAUDE.md §11), or
  automated end-of-task commits.

---

# Git Hygiene for Restructuring

Extends `CLAUDE.md`. Owns the git mechanics that keep history professional while files move. Commit-message format, branch-naming conventions, and forbidden operations (force-push, direct commits to main) are owned by `CLAUDE.md` §11 — not restated here.

## Purpose

File moves and cleanup churn destroy history and reviewability when done carelessly. These rules keep every step traceable, reversible, and reviewable.

## When to use

- Any batch of file moves or renames; starting cleanup/restructuring work; untracking generated artifacts; writing or extending `.gitignore`.

## When NOT to use

- A single move or rename the user directly asked for — perform it and commit per `CLAUDE.md` §11; no branch or sequence ceremony required.
- Choosing commit types/format or branch names → `CLAUDE.md` §11.
- Automated end-of-task commits; history rewrites of shared branches (forbidden, `CLAUDE.md` §11).

## Core rules

- **Clean-tree gate.** Never start restructuring on a dirty tree: STOP, create no branches, ask the user to commit or stash, wait.
- **Dedicated branch.** All restructuring happens on a work branch created from a clean tree — never on main. The branch name comes from the governing workflow (a cleanup run names it in its Phase 0) or from `CLAUDE.md` §11.
- **`git mv` whenever possible.** Never move tracked files with plain filesystem operations when `git mv` is available — history and rename detection depend on it.
- **Move first. Rename later.** Never combine a move and a rename in one step; each is its own reviewable change.
- **One logical change per commit.** A reviewer must be able to state each commit's purpose in one sentence.
- **Verify after every commit** per [verification](../verification/SKILL.md).

## Cleanup commit sequence

One logical change per commit, in this order:

1. **Hygiene (must be FIRST)** — add/extend `.gitignore` (including ignoring the `.claude/CLEANUP_*.md` planning artifacts); `git rm --cached` generated artifacts; remove tracked cache and generated files; remove tracked secrets ONLY if approved (reporting, rotation, history cleanup: [security-review](../security-review/SKILL.md)).
2. **Folder restructuring** — approved moves only, via `git mv`.
3. **Reference updates** — imports, configs, scripts, docs updated for the moves.
4. **Documentation.**
5. **Archive** — files archived instead of deleted.
6. **Approved renames only** — update references for each rename, verify, commit separately from moves.

## .gitignore standards

Generated artifacts are never tracked. Ignore-target list (this is also the "repository noise" audit target list):

`__pycache__/`, `*.pyc`, `.pytest_cache/`, `.mypy_cache/`, `.ruff_cache/`, `.cache/`, `coverage/`, `htmlcov/`, `dist/`, `build/`, `*.egg-info/`, `node_modules/`, `.venv/`, `venv/`, `logs/`, `tmp/`, `temp/`, `exports/`, `generated/`, debug outputs, backup files (`*.bak`, `*~`), OS junk (`.DS_Store`, `Thumbs.db`).

- During an audit, the `.gitignore` is a PROPOSAL; it is written to the repo only in the hygiene commit after approval.
- `.env*` and other secret files must be ignored before any commit lands (canonical: `CLAUDE.md` §7).

## Cross-references

- `CLAUDE.md` §11 — commit format, branch naming, forbidden git operations
- [security-review](../security-review/SKILL.md) — tracked secrets: report, rotate, clean history
- [verification](../verification/SKILL.md) — post-commit verification and failure protocol

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Work happened on a dedicated branch created from a clean tree.
- [ ] All moves used `git mv`; no move+rename combined in one step.
- [ ] Hygiene commit landed first; commits follow the sequence, one logical change each.
- [ ] No generated artifacts or planning files tracked after the hygiene commit.
