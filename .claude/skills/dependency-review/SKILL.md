---
name: dependency-review
description: Use when auditing a project's declared dependencies — requirements.txt, pyproject.toml, package.json, poetry.lock, uv.lock, Pipfile — for unused, missing, duplicate, or obsolete packages. Trigger on phrases like "audit the dependencies", "unused packages", "clean up requirements", "do we still need this package", "review the lockfile", "duplicate dependencies". Covers evidence-based classification and safe removal proposals. Do NOT use for adding or upgrading dependencies (CLAUDE.md §7 Supply Chain — installs need user approval) or for CVE triage depth.
---

# Dependency Review

Extends `CLAUDE.md`. Owns the manifest/lockfile AUDIT. Rules for adding new dependencies (license, CVEs, typosquatting, pinning) are `CLAUDE.md` §7 Supply Chain; installing or removing is user-approved only (`CLAUDE.md` §2).

## Purpose

Classify every declared dependency with evidence so removals are safe and omissions are caught — without touching the environment.

## When to use

- Dependency audit during a cleanup; "why is this package here" questions; drift between manifest and lockfile; multiple manifests in one repository.

## When NOT to use

- Adding, choosing, or upgrading a dependency → `CLAUDE.md` §7 + user approval.
- Vulnerability triage depth → dedicated tooling (`pip-audit`, `npm audit`) per `CLAUDE.md` §7.

## Core rules

- **Review targets:** `requirements.txt`, `pyproject.toml`, `package.json`, `poetry.lock`, `uv.lock`, `Pipfile` — plus the lockfile of the package manager the project actually uses (a foreign lockfile is itself a finding, `CLAUDE.md` §8).
- **Classify each package:**
  - *Missing* — imported/used but not declared.
  - *Unused* — declared, with zero imports or usages found.
  - *Duplicate* — declared in multiple manifests, or two packages serving the same purpose.
  - *Obsolete* — deprecated, renamed, unmaintained, or superseded upstream.
- **Evidence per finding.** Search imports AND dynamic/indirect usage: plugin entry points, CLI invocations in scripts/CI, config-file references, framework autoloads. No evidence → not a finding. Uncertain → keep (evidence > assumptions).
- **Propose, never execute.** The output is a recommendation table; the USER runs installs and removals.
- **Removals are verified** like any change — after an approved removal lands, run [verification](../verification/SKILL.md).

## Workflow

1. Enumerate manifests and lockfiles; note which package manager is canonical.
2. Build the declared-set vs used-set (imports, scripts, configs, CI).
3. Classify each package with evidence.
4. Report: `Package | Declared in | Finding | Evidence | Recommendation`.

## Cross-references

- `CLAUDE.md` §7 Supply Chain — adding deps, pinning, audit tooling; §2 — installs need approval
- [verification](../verification/SKILL.md) — verifying approved removals

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Every declared package classified with evidence; dynamic usage checked before calling anything unused.
- [ ] No package installed or removed by Claude; recommendation table delivered.
