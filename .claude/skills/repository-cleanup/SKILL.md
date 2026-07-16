---
name: repository-cleanup
description: Use when auditing, cleaning up, reorganizing, or professionalizing an existing repository — finding unused files, restructuring folders, removing generated artifacts, preparing a repo for team handover. Trigger on phrases like "clean up this repo", "organize the project", "find unused files", "repository audit", "declutter", "professionalize the repo", "prepare for handover". Orchestrates the full audit → approval → execute → verify workflow. Do NOT use for architecture refactoring, rewriting business logic, modernizing code, or performance work — behavior preservation is mandatory.
---

# Repository Cleanup & Professionalization

Extends `CLAUDE.md`. Orchestrator skill: it owns the cleanup workflow spine and delegates domain rules to the skills under Cross-references.

## Purpose

Prepare a repository for long-term professional maintenance while preserving 100% of existing behavior. Optimize for maintainability, readability, discoverability, consistency, predictable structure, easy onboarding, and professional Git history. Repository organization is the goal; behavior preservation is mandatory. Priorities: correctness, safety, maintainability, minimal changes, professional Git history — never aesthetics over functionality.

## When to use

- Auditing or restructuring an existing repository; hunting unused or duplicate files; root cleanup; pre-handover professionalization.

## When NOT to use

- Architecture refactoring, business-logic rewrites, code modernization, performance optimization, package redesign (see Architecture boundary).
- Building new features, or one-off file moves outside an audited, approved plan.

## Absolute rules (override everything below)

- Never change runtime behavior. Never sacrifice functionality for organization.
- Never assume a file is unused. Never delete anything without evidence.
- Never rename or move files without justification. Never introduce new dependencies unless required.
- Never rewrite architecture. Never perform hidden changes.
- Every action must have written justification. Every destructive action requires explicit approval.
- Archive is always preferred over deletion. Smaller diffs are preferred over large refactors.
- If uncertain, KEEP the file.

## Decision principles

Preserve behavior > cleaner structure · Evidence > assumptions · Archive > delete · Move > rename · Small commits > large commits · Professional maintainability > personal preference.

## Architecture boundary

Unless explicitly requested, NEVER: introduce Repository Pattern or Dependency Injection, split or merge business modules, rewrite APIs or business logic, force a `src/` layout, replace frameworks or libraries, change startup behavior or runtime configuration. Only organize the repository. The ONLY exception is the optional config-consolidation module ([references/config-consolidation.md](references/config-consolidation.md)).

## Workflow (phases are mandatory — never skip, never merge)

### Phase 0 — Safety checks

Verify: git repository exists, current branch, git status, working tree, existing `.gitignore` and ignored files. Not a git repo → STOP; ask the user to `git init` and create an initial commit. Dirty working tree → STOP; create no branches (canonical: [git-hygiene](../git-hygiene/SKILL.md)); ask the user to commit or stash; wait. Clean tree → create branch `cleanup/restructure` and start Phase 1.

### Phase 1 — Read-only audit

Strictly read-only: no moves, renames, deletes, edits, import updates, or commits. Sole exception: create exactly TWO untracked planning artifacts — `.claude/CLEANUP_PLAN.md` and `.claude/CLEANUP_EXECUTION.md`. Do not create any other files.

`CLEANUP_PLAN.md` must contain: repository summary; file classifications; dependency analysis; duplicate analysis (incl. duplicated constants/config values — feeds config consolidation); risk assessment; proposed directory structure; old→new path mapping; confidence scores; proposed `.gitignore` (proposal only); documentation proposals (proposal only — [documentation](../documentation/SKILL.md)); execution plan; verification plan. `CLEANUP_EXECUTION.md` starts with: repository state, pending work, execution-log placeholder.

Audit items (evidence required for every conclusion; domain rules delegated):

- **File classification** — every relevant file: Production / Development / Testing / Temporary / Generated / Experimental / Archived / Unknown. Explain every classification.
- **Dependency analysis** — is each source file referenced by: imports (relative/absolute), Docker, Docker Compose, Airflow DAGs, FastAPI, Flask, SQL, Batch, Bash, PowerShell, cron, SQL Agent, Windows Task Scheduler, UiPath, GitHub Actions, GitLab CI, Azure Pipelines, startup scripts, config files, environment variables, documentation.
- **Unused file detection** — never assume. "Unused" requires zero references across ALL of the above plus a ripgrep sweep. Confidence: 95–100 = safe to delete AFTER approval; 80–94 = archive recommended; below 80 = keep.
- **Duplicate detection** — utilities, SQL, configs, constants, helpers, scripts, docs, assets → recommend Keep / Merge / Archive with reasons.
- **Root directory review** — every root item: why it exists, whether it belongs, whether it should move (standards: [project-layout](../project-layout/SKILL.md)).
- **Repository noise** — detect generated artifacts (target list: [git-hygiene](../git-hygiene/SKILL.md)). Recommend removal only if generated.
- **Secret scan** — per [security-review](../security-review/SKILL.md). Never print secret values (canonical: security-review).
- **Dependency review** — per [dependency-review](../dependency-review/SKILL.md).
- **Runtime-critical paths — FROZEN** — Airflow DAG folders, Docker bind mounts, docker-compose volumes, SQL Agent job paths, Windows Task Scheduler paths, UiPath project paths, GitHub Actions, GitLab CI, Azure Pipelines, git hooks, startup scripts, production config paths. Never move them independently; any move MUST update its references in the SAME approved change.
- **Folder structure review** — recommend a better structure; do NOT apply it ([project-layout](../project-layout/SKILL.md)).
- **Naming review** — suggest better names for unclear files; do NOT rename in Phase 1 ([project-layout](../project-layout/SKILL.md)).
- **Risk analysis** — hardcoded/absolute paths, circular or fragile imports, platform/runtime assumptions, large binaries, duplicate configs.

Proposed execution plan — table with columns: `Old Path | New Path | Reason | Evidence | Risk | Confidence | Approval Required`.

END OF PHASE 1: STOP. Wait for explicit approval. Do not perform any repository changes.

### Approval state & plan integrity

After explicit user approval, prepend to the top of `CLEANUP_PLAN.md`:

```
Status: APPROVED
Approved At: <ISO-8601 timestamp>
Approved By: User
Approved Scope: Phase 2 [and Phase 3 if explicitly approved]
```

Phase 2 MUST refuse to execute if this marker is absent. If `CLEANUP_PLAN.md` changes after approval, approval becomes INVALID — STOP and request approval again. Phase 2 executes ONLY from the approved plan: reload it first, verify the marker, never silently update it.

### Phase 2 — Execution

The approved plan is immutable; any action outside it requires NEW approval. Never improvise. Move/rename mechanics and the commit sequence: [git-hygiene](../git-hygiene/SKILL.md). Delete ONLY when evidence exists AND confidence ≥ 95 AND the user approved — otherwise archive. Whenever files move, update every affected reference (imports, Dockerfile, docker-compose, Airflow DAGs, configs, README, scripts, CI/CD, SQL Agent, Task Scheduler, UiPath, examples, documentation) — everything must remain functional. After every logical commit, run [verification](../verification/SKILL.md); failures are BLOCKING (canonical: verification).

### Recovery mode

If execution is interrupted: reload both planning artifacts, verify the approval marker is still valid, determine the last completed commit, resume from the next pending step. Never restart Phase 2 from scratch unless requested.

### Execution log

Maintain `.claude/CLEANUP_EXECUTION.md` (untracked) recording: timestamp, commit, files moved / renamed / archived / deleted, verification commands and results, rollbacks, remaining work.

### Final report

Close the cleanup with the final report defined by [documentation](../documentation/SKILL.md).

## Scale & monorepo rules

- Directories full of generated files (`logs/`, `exports/`, `archive/`, `datasets/`, `generated/`, `node_modules/`, `dist/`, `build/`): do NOT inspect every file — summarize the directory, sample representative files, prioritize source code, never waste context on generated artifacts.
- Multiple independent workspaces (`frontend/`, `backend/`, `airflow/`, `infra/`, `shared/`): audit each workspace independently, then produce one overall summary. Never mix unrelated workspaces.

## Success criteria

Runtime behavior preserved; Git history preserved where possible; minimal root; no tracked generated artifacts; no exposed secrets; clear structure; easy onboarding; every change justified; every destructive action approved. Safety, correctness, maintainability, and minimal disruption are the measures of success — not the number of files moved.

## Cross-references

- [project-layout](../project-layout/SKILL.md) — structure standards, naming review, migration proposals
- [git-hygiene](../git-hygiene/SKILL.md) — clean-tree gate, `git mv`, commit sequence, `.gitignore`
- [verification](../verification/SKILL.md) — per-commit verification and failure protocol
- [dependency-review](../dependency-review/SKILL.md) — manifest/lockfile audit
- [security-review](../security-review/SKILL.md) — secret scan and response
- [documentation](../documentation/SKILL.md) — README/.env.example/CONTRIBUTING proposals, final report
- [references/config-consolidation.md](references/config-consolidation.md) — optional Phase 3 module

## Done criteria (in addition to CLAUDE.md §16)

- [ ] Approval marker present before any Phase 2 change; plan unchanged since approval.
- [ ] Every delete backed by evidence + confidence ≥ 95 + approval; everything else archived.
- [ ] Every move shipped its reference updates in the same approved change.
- [ ] Verification ran after every logical commit; final report delivered.
