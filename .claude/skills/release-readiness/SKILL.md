---
name: release-readiness
description: Use when preparing a release, version tag, or handover — running the pre-release checklist (verification green, secret scan clean, changelog, version tag, rollback plan, sign-off). Trigger on phrases like "ready to release", "cut a release", "tag a version", "release checklist", "prepare v1.2", "handover checklist". Thin checklist skill composing verification, security-review, documentation, and git-hygiene. Do NOT use for deployment/CI pipeline work or for writing the changes being released.
---

# Release Readiness

Extends `CLAUDE.md`. Thin gate: it owns only the checklist and the rollback-plan requirement; every domain rule lives in the referenced skills.

## Purpose

A release is a claim that the repository is safe to ship and safe to roll back. This checklist makes that claim verifiable instead of hopeful.

## When to use

- Before tagging a version, publishing, or handing a repository to another team.

## When NOT to use

- Deployment or CI mechanics; feature work; post-release incident handling.

## Checklist (every item blocking — report failures, never round up: `CLAUDE.md` §2/§16)

1. **Git state** — clean working tree, on the intended branch, history reviewable ([git-hygiene](../git-hygiene/SKILL.md)); no direct-to-main, per `CLAUDE.md` §11.
2. **Verification green** — the full applicable command set passes ([verification](../verification/SKILL.md)); failures block the release.
3. **Secrets clean** — scan passes, nothing committed, `.env*` ignored ([security-review](../security-review/SKILL.md)); never print values (canonical: security-review).
4. **Docs current** — README, setup, `.env.example` match reality ([documentation](../documentation/SKILL.md)).
5. **Changelog updated** — user-visible changes since the last tag, dated.
6. **Version tag** — annotated tag (`git tag -a vX.Y.Z -m "..."`) matching the manifest version; tag only AFTER items 1–5 pass. Pushing the tag is the user's action.
7. **Rollback plan written BEFORE release** — last-known-good tag, exact revert steps, data/migration implications, who executes it.
8. **Sign-off** — remaining risks listed explicitly and accepted by the user; partial completion reported as partial.

## Workflow

Run the checklist top to bottom → report each item pass/fail with evidence → on any failure, stop and fix or get explicit user acceptance → only then tag.

## Cross-references

- [verification](../verification/SKILL.md) · [security-review](../security-review/SKILL.md) · [documentation](../documentation/SKILL.md) · [git-hygiene](../git-hygiene/SKILL.md)
- `CLAUDE.md` §11 — git rules; §16 — Definition of Done

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Every checklist item reported pass/fail with evidence; failures blocked or explicitly accepted by the user.
- [ ] Rollback plan exists before the tag; tag not pushed by Claude.
