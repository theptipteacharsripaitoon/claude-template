---
name: project-layout
description: >-
  Use when reviewing or proposing repository folder structure — where files
  live, root contents, library/application/monorepo layout, structure
  migration planning. Trigger: "restructure the project", "where should this
  file go", "the root is cluttered", "propose a folder structure". Do NOT use
  for executing moves (git-hygiene owns mechanics) or module
  boundaries/architecture.

---

# Project Layout

Extends `CLAUDE.md`. Owns structure RECOMMENDATIONS. Where individual new files go day-to-day is `CLAUDE.md` §8; executing approved moves is [git-hygiene](../git-hygiene/SKILL.md).

## Purpose

Recommend a directory structure that fits the project's actual type and runtime constraints — never impose a generic template. Structure changes are proposals until approved; layout work never alters module boundaries or behavior.

## When to use

- Structure review during a repository audit; root-directory cleanup; choosing a layout for a new or reorganized project; building an old→new path mapping.

## When NOT to use

- Moving or renaming files (mechanics → [git-hygiene](../git-hygiene/SKILL.md)).
- Architecture or module-boundary changes (out of scope for layout work).
- Single-file placement questions → `CLAUDE.md` §8.

## Core rules

- **Minimal root.** Every root item must justify itself: why it exists, whether it belongs, where it should move. Manifests, README, LICENSE, `.gitignore`, and entrypoint-level config stay; everything else earns its place or moves.
- **Respect the project type.** Never force generic layouts. Never force a `src/` layout on a project that doesn't use one.
- **Justify every recommendation** — with the problem it solves, not aesthetics.
- **Propose, don't apply.** Structure changes ship as an old→new mapping for approval, never as direct edits.
- **Runtime constraints win.** Paths consumed by schedulers, CI, Docker, or DAGs are frozen — moving one requires updating its references in the same approved change (canonical: repository-cleanup).
- **Naming review.** Flag unclear names (`temp.py`, `abc.py`, `new.py`, `copy.py`, `test2.py`, `final_final.py`) and suggest intent-revealing names — suggestions only during an audit; renames execute later per git-hygiene.

## Layout guides by project type

Recommendations, not mandates — match what the codebase already does first (`CLAUDE.md` §1).

- **Library** — package folder (or existing `src/<pkg>`), `tests/`, `docs/`, `examples/`; root: manifest, README, LICENSE, changelog.
- **Application** — entrypoint at a predictable path; modules grouped by domain, not by file type; `config/`, `scripts/`, `tests/` mirroring source.
- **Service** — application layout plus: `Dockerfile`/`docker-compose.yml` at root or `docker/`; deploy manifests separate from source; `.env.example` at root; health/startup scripts discoverable.
- **Monorepo** — one folder per workspace (`frontend/`, `backend/`, `airflow/`, `infra/`, `shared/`), each with its own manifest and tests; no file belongs to two workspaces; shared code only in an explicit `shared/` workspace.

**Do:** group by domain; keep tests near what they test (per repo convention); keep generated output out of the tree (ignore list: [git-hygiene](../git-hygiene/SKILL.md)); use `archive/` for retired-but-kept material.

**Don't:** scatter config across levels; nest deeper than the project needs; mix workspace concerns; create folders "to keep things tidy" (`CLAUDE.md` §8).

## Migration strategy

1. Produce the full old→new mapping using the proposed-execution-plan table format (columns owned by repository-cleanup).
2. Get explicit approval — the mapping is then immutable.
3. Execute per [git-hygiene](../git-hygiene/SKILL.md): its core rules and cleanup commit sequence govern the moves, renames, and per-commit verification.

## Cross-references

- `CLAUDE.md` §8 — file-organization defaults for day-to-day additions
- [git-hygiene](../git-hygiene/SKILL.md) — move/rename mechanics and commit sequence

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Every recommendation justified; project type respected; no forced generic or `src/` layout.
- [ ] Root inventory complete — each item kept-with-reason or mapped to a new home.
- [ ] Changes delivered as an approved mapping table, not applied directly.
