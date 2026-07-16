---
name: documentation
description: Use when proposing or writing repository documentation — README, .env.example, CONTRIBUTING — or assembling the final report of a cleanup/restructuring. Trigger on phrases like "write the README", "document the setup", "create .env.example", "contributing guide", "final cleanup report", "handover documentation". Covers doc structure standards and the cleanup final-report format. Do NOT use for code comments/docstrings, API reference docs (see api-design), or architecture docs.
---

# Repository Documentation

Extends `CLAUDE.md`. Owns repo-level documentation PROPOSALS and the cleanup final report.

## Purpose

Give a repository the minimum documentation a new engineer needs to run, change, and trust it — proposed first, written only after approval — and define the final report that closes a cleanup.

## When to use

- README, `.env.example`, or CONTRIBUTING creation or overhaul; documentation proposals inside an audit; writing the cleanup final report.

## When NOT to use

- Docstrings and inline comments → `CLAUDE.md` §6.
- API reference documentation → [api-design](../api-design/SKILL.md).
- Domain runbooks and architecture docs.

## Core rules

- **Proposal-only during audits.** In read-only phases, documentation is PROPOSED in the plan, never written to the repo. Files are created only in the documentation commit after approval.
- **README** must let a newcomer succeed alone: what the project is, prerequisites, install, run, test, project structure overview, where config lives, maintenance notes and gotchas.
- **`.env.example`** — every required env var, fake-but-formatted placeholder, comments for units and accepted values, grouped by prefix. Canonical rules: `CLAUDE.md` §7 Environment Variables. Never real values (canonical: [security-review](../security-review/SKILL.md)).
- **CONTRIBUTING** — how to branch and commit (point to `CLAUDE.md` §11), how to run checks locally, what a PR needs. Keep it one page.
- **Docs tell the truth.** A doc that contradicts reality is worse than none; update docs in the same change that invalidates them (`CLAUDE.md` §16).

## Cleanup final report structure

Deliver at the end of a cleanup (workflow: repository-cleanup):

- Repository summary and statistics
- Files inspected / moved / renamed / archived / deleted
- Duplicate files and unused files
- Generated files removed
- Config consolidations performed (if the opt-in phase ran)
- Reference updates
- Verification results
- Remaining risks
- Manual follow-up items
- Updated directory tree
- Final `.gitignore`
- README recommendations
- `.env.example` recommendations
- Future maintenance recommendations

## Cross-references

- `CLAUDE.md` §7 — environment variables; §11 — conventions CONTRIBUTING points to; §16 — docs-updated gate
- [api-design](../api-design/SKILL.md) — API reference documentation
- [security-review](../security-review/SKILL.md) — never real values in examples

## Done criteria (in addition to CLAUDE.md §14)

- [ ] No doc file written before its proposal was approved (audit contexts).
- [ ] `.env.example` covers every required var with fake placeholders; zero real values.
- [ ] Final report includes every section above (cleanup contexts).
