# Changelog

Format: [Keep a Changelog](https://keepachangelog.com). Versions are git tags.

## [Unreleased]

### Added
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

### Changed
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

### Fixed
- verify-done Stop hook exited 1 on every clean stop (pipefail + empty grep).
- All jq hooks exited 4 on malformed JSON; now fail open per hook policy.
- install.sh test counter died under `set -e` on the first failing test.
- verify-done now honors `stop_hook_active` (no re-entry loops in blocking mode).
- HOW-TO: `claude` invocation (was `claude code`), Phase 4 no longer recreates
  the shipped claude-init.sh, macOS zsh note, hook-count correction.

### Known limitations / roadmap
- No LICENSE yet (owner decision) — blocks public reuse.
- Trigger-case fixtures (`tests/skills/trigger-cases.yaml`) require live
  sessions to evaluate; no large-scale routing eval has been run.
- Install profiles (minimal/python/data/full) and template-update propagation
  (Copier-style) are roadmap items.

## [v2.0]
- CLAUDE.md sections 0–20; 8 domain skills; 5 enforcement hooks.

## [v1.0]
- Initial template: CLAUDE.md, 8 skills, hooks.
