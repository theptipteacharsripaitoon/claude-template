---
name: release-readiness
description: >-
  Use when preparing a release, version tag, or handover — pre-release
  checklist: verification green, secret scan clean, changelog, rollback plan,
  sign-off. Trigger: "ready to release", "cut a release", "tag a version",
  "release checklist". Thin checklist composing verification, security-review,
  documentation, git-hygiene. Do NOT use for deploy/CI pipeline work or
  writing the changes being released.

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
2. **Verification green** — the full applicable command set passes ([verification](../verification/SKILL.md)). **Non-waivable:** a release with failing verification is never acceptable; sign-off cannot override it.
3. **Secrets clean** — scan passes, nothing committed, `.env*` ignored ([security-review](../security-review/SKILL.md)); never print values (canonical: security-review). **Non-waivable:** a release is never cut with a secret exposure, regardless of sign-off.
4. **Docs current** — README, setup, `.env.example` match reality ([documentation](../documentation/SKILL.md)).
5. **Changelog updated** — user-visible changes since the last tag, dated.
6. **Version tag** — annotated tag (`git tag -a vX.Y.Z -m "..."`) matching the manifest version; tag only AFTER items 1–5 pass. Pushing the tag is the user's action.
7. **Rollback plan written BEFORE release** — last-known-good tag, exact revert steps, data/migration implications, who executes it.
8. **Sign-off** — remaining risks listed explicitly and accepted by the user; partial completion reported as partial.

## Workflow

Run the checklist top to bottom → report each item pass/fail with evidence → on any failure, stop and fix. The **secret (3) and verification (2) gates are non-waivable** — no sign-off can accept them; the remaining items may be accepted only with an explicit, documented user waiver → only then tag.

## Cross-references

- [verification](../verification/SKILL.md) · [security-review](../security-review/SKILL.md) · [documentation](../documentation/SKILL.md) · [git-hygiene](../git-hygiene/SKILL.md)
- `CLAUDE.md` §11 — git rules; §16 — Definition of Done

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Every checklist item reported pass/fail with evidence; failures blocked or explicitly accepted by the user.
- [ ] Rollback plan exists before the tag; tag not pushed by Claude.
