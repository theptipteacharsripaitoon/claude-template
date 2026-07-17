---
name: verification
description: Use when verifying a repository still works after changes during cleanup, restructuring, or any multi-commit work — choosing which verification commands apply, running them after each commit, and handling failures. Trigger on phrases like "verify the changes", "run the checks", "did that move break anything", "verification failed", "roll back the failing change". Covers per-commit verification, the blocking-failure policy, and the surgical-rollback protocol. Do NOT use for authoring new tests (see testing skill) or for designing CI pipelines.
---

# Verification

Extends `CLAUDE.md`. Owns HOW verification runs during multi-commit work and what happens on failure. WHAT a given change type must verify is defined by `CLAUDE.md` §14 — this skill does not restate that matrix.

## Purpose

Guarantee that every logical commit leaves the repository functional: run only the applicable checks, treat failures as blocking, and roll back surgically instead of improvising fixes.

## When to use

- After each logical commit in cleanup or restructuring work; when a check fails mid-sequence; when deciding which commands a given repository needs.

## When NOT to use

- Writing or improving tests → [testing](../testing/SKILL.md).
- Defining verification depth per change type → `CLAUDE.md` §14.
- CI pipeline design.

## Core rules

- Run verification after EVERY logical commit — not once at the end.
- Run ONLY the verification commands applicable to this repository. Command menu (examples — extend per stack):

| Stack present | Commands |
|---|---|
| Python | `python -m compileall`, `pytest`, `ruff check`, `mypy` |
| Node / frontend | `npm ci`, `npm run build`, `npm test` (script names per `package.json`) |
| Docker / Compose | `docker compose config`, `docker build` |
| Airflow | `airflow dags list` |

- Verification failures are BLOCKING. No exceptions, no "probably fine".
- Never weaken, skip, or disable a check to get green (canonical: `CLAUDE.md` §2).

## Failure protocol

If ANY verification fails:

1. STOP immediately.
2. Report: failed command, error output, suspected cause, related changes.
3. Roll back ONLY the failing change using Git — the smallest surgical operation (e.g. `git revert <commit>`); never a bulk reset of the whole sequence.
4. Do NOT invent additional fixes. Do NOT continue.
5. Wait for approval.

## Workflow

1. Identify the repository's stacks (manifests, Dockerfiles, `dags/`, …) → derive the applicable command set → record it up front (in cleanup runs: the verification plan inside `CLEANUP_PLAN.md`).
2. After each commit: run the set. All green → proceed to the next planned step.
3. On any failure → Failure protocol above.
4. Log every run and its result (in cleanup runs: the execution log).

## Cross-references

- `CLAUDE.md` §14 — verification matrix by change type; §16 — Definition of Done
- [testing](../testing/SKILL.md) — authoring tests, test pyramid, flakiness

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Applicable command set identified and recorded before execution began.
- [ ] Verification ran after every logical commit; results logged.
- [ ] Any failure: stopped, reported, rolled back only the failing change, waited for approval.
