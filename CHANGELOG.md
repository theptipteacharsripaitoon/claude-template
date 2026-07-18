# Changelog

Format: [Keep a Changelog](https://keepachangelog.com). Versions are git tags.

## [Unreleased]

### Security
- **scan-secrets**: closed two same-pattern bypasses — a real secret no longer
  slips through behind a fixture on an earlier line, nor when its own line
  contains an incidental word like "example". Fake-marker detection is now scoped
  to the matched value (matching the hook's own guidance), not the whole line.

### Added
- Second-cycle audit reports (`reports/claude-independent-audit-v2.md`,
  `reports/review-adjudication-v2.md`) with measured live skill-routing results.
- Hook regression cases: SS9/SS10 (secret bypasses), PF10/PF11/PF13 + PFA1–4
  (protect-files matching + ask flow), VD5 (no-checks-ran), BOOT1–3 (bootstrap).
  Suite is now 50 cases.

### Changed
- **protect-files**: matches normalized path components / exact basenames instead
  of raw substrings (fixes `config.environment.ts` false positive); secrets stay a
  hard deny, while CI/infra/migrations/lockfiles/settings/hooks now emit a
  structured `ask` so in-chat approval works.
- **verify-done**: runs every ecosystem present (polyglot) and distinguishes
  "no checks discovered" from "checks passed".
- **CLAUDE.md §16 Definition of Done**: now task-type conditional — no mandatory
  tests/commit/execution for review/investigation/docs tasks; commit required only
  for requested Git operations; type-check only where a checker exists.
- **CI**: explicit `permissions: contents: read`, `timeout-minutes`, pinned pyyaml.
- **docker skill**: description scoped to authoring (points to docker-review);
  multi-stage Done criterion honors the single-stage exception.
- **database-migrations**: reversibility wording aligned with its conditional Done.

### Fixed
- **claude-init**: generated projects now inherit `.gitignore` and `.gitattributes`
  (previously `git add -A` could stage `.env`; `.sh` hooks risked CRLF on Windows).
- ShellCheck findings SC2155 (install.sh) and SC2016 (block-destructive.sh); stale
  `MultiEdit` matcher headers corrected to `NotebookEdit`.
- Hook README drift: `claude` invocation, NotebookEdit coverage, deny/ask tiers,
  value-scoped fixture markers.

### Added (prior cycle)
- 29 new skills (phases A–D): repository-cleanup orchestration, verification,
  git-hygiene, security-review, project-layout, dependency-review,
  documentation, release-readiness; data engineering (sql-layout,
  database-review, airflow-layout, airflow-review, etl-review, ssis-review);
  Python/backend (python-layout/review/refactor/performance,
  config-management, api-review, docker-review, fastapi-review); AI/DevOps/
  frontend (agent-design, prompt-engineering, llm-evaluation, ci-review,
  frontend-layout, ui-review, design-system). Catalog: `.claude/skills/INDEX.md`.
- Hook regression suite (`tests/hooks/run-tests.sh`, 39 cases) and skill
  catalog checks (`tests/skills/check_catalog.py`); CI workflow.
- Root README, .gitignore, .gitattributes (LF-normalized shell scripts).
- `CLAUDE_TEMPLATE_DIR` override for `claude-init`.
- Audit reports: `reports/claude-independent-audit.md`,
  `reports/review-adjudication.md`.

### Changed (prior cycle)
- Dependency installs (npm/pip/cargo/…) now prompt for approval
  (`permissionDecision: ask`) instead of hard-denying.
- Hook matcher covers `NotebookEdit`; stale `MultiEdit` removed.
- Engine specificity labeled: database-review + sql-layout (SQL Server/T-SQL),
  database-migrations (PostgreSQL lock-safety).
- Trigger scopes narrowed: git-hygiene (restructuring efforts only),
  python-refactor, airflow (authoring only), repository-cleanup (deliberate).
- Production-tier conditionality: docker multi-stage, kubernetes
  PDB/NetworkPolicy, observability per-endpoint instrumentation.
- Readiness-check rule canonicalized in observability; docker/kubernetes point.

### Fixed (prior cycle)
- verify-done Stop hook exited 1 on every clean stop (pipefail + empty grep).
- All jq hooks exited 4 on malformed JSON; now fail open per hook policy.
- install.sh test counter died under `set -e` on the first failing test.
- verify-done now honors `stop_hook_active` (no re-entry loops in blocking mode).
- HOW-TO: `claude` invocation (was `claude code`), Phase 4 no longer recreates
  the shipped claude-init.sh, macOS zsh note, hook-count correction.

### Known limitations / roadmap
- No LICENSE yet (owner decision) — blocks public reuse.
- CI cannot run until the GitHub account billing lock is cleared (owner action);
  the workflow itself is green locally.
- Skill routing was measured on a 9-case live sample (see the v2 audit report);
  a full 19-case precision/recall run needs per-domain seed projects.
- verify-done attributes all dirty files to the current session (a Stop hook has
  no reliable session-start baseline); documented rather than reworked.
- Install profiles (minimal/python/data/full) and template-update propagation
  (Copier-style) are roadmap items.

## [v2.0]
- CLAUDE.md sections 0–20; 8 domain skills; 5 enforcement hooks.

## [v1.0]
- Initial template: CLAUDE.md, 8 skills, hooks.
