# Changelog

Format: [Keep a Changelog](https://keepachangelog.com). Versions are git tags.

## [Unreleased]

### Security (third cycle)
- **block-destructive**: closed measured false negatives — `rm` now denies every
  recursive flag spelling (`-fr`, split `-r -f`, `--recursive --force`, capital
  `-R`) and a quoted `"$HOME"` target; `git clean` force+directory flags match in
  either order, clustered or split; SQL destruction (`drop table`, `truncate
  table`, `delete from …;`) matches case-insensitively. Deny-widening only.
- **block-destructive**: dependency **remove/uninstall** and **update/upgrade**
  commands (incl. `pip install -U/--upgrade`, `go get`) now emit the CLAUDE.md §2
  approval ask; lockfile/manifest restores (`npm ci`, bare installs, `pip
  install -r`, `uv sync`, …) deliberately stay allowed.

### Fixed (third cycle)
- **verify-done (P0)**: blocking mode (`CLAUDE_VERIFY_BLOCK=1`) died with exit 1
  before running any check — a bare `((RAN++))` returns status 1 at zero under
  `set -e`. Counters are now POSIX assignments; a missing toolchain (e.g.
  `Cargo.toml` without `cargo`) is skipped with a note instead of being counted
  as a failed check.
- **protect-files**: the approval ask is now jq-built JSON — a protected basename
  containing a quote, tab, or newline no longer corrupts the payload (which
  silently dropped the ask). block-destructive's ask JSON got the same treatment.
- **claude-init**: name-safe and failure-atomic — traversal names (`../x`, `a/b`)
  are rejected, all required template sources are validated up front, the project
  is assembled in a temp sibling and renamed into place only after the installer
  succeeds; failures clean up and leave the caller's cwd untouched.

### Added (third cycle)
- Executable skill-routing harness: `tests/skills/routing/seed-repo.sh` seeds a
  domain-representative repo per fixture case; `run_eval.py` runs each prompt N×
  through headless `claude -p`, scores recall/precision/conflicts/stability, and
  writes machine-readable results to `tests/skills/results/`. Fixture format
  gains stable `id`s and `allowed_companions`.
- Hook regression cases (suite 50 → 107): rm/clean/SQL variants with allow
  guards, dependency ask/restore matrix, jq-validated ask JSON on hostile
  basenames, real passing/failing Stop-hook checkers (incl. polyglot and
  missing-toolchain), bootstrap traversal/atomicity/cwd, settings timeouts.
- Explicit 10 s `timeout` on the PreToolUse validators in `.claude/settings.json`
  (Stop hook intentionally unset — blocking mode runs real test suites).
- Third-cycle audit reports (`reports/claude-independent-audit-v3.md`,
  `reports/review-adjudication-v3.md`).

### Changed (third cycle)
- **CI**: pinned runner image (`ubuntu-24.04`), SHA-pinned `actions/setup-python`
  with Python 3.12, checksum-verified ShellCheck v0.10.0, and a concurrency group
  that cancels superseded runs; ShellCheck now also lints `claude-init.sh` and
  the routing seed script. The account billing lock was cleared mid-cycle: run
  29643662878 is the repository's **first real Actions execution — all steps
  green** on a hosted runner.
- **repository-cleanup**: trigger phrase "organize the project" removed and
  ownership pointer added — the 19×3 baseline measured a stable 3/3 misroute of
  the structure-only prompt "Organize this project - the root is a mess" away
  from project-layout; the fixture gained a `cleanup-repo-recall` case so the
  skill's own recall is pinned, and the fix was re-verified live (see
  `tests/skills/results/` and `evaluated_runs`).
- hooks README synced with implementation: ask tiers incl. dependency changes,
  component-based protected-path matching (stale `PROTECTED_PATTERNS` wording
  removed), scanner detection boundary + marker-skip logging, Stop-hook exit
  semantics, validator timeouts.

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
- ~~CI blocked by the account billing lock~~ — cleared 2026-07-18; Actions
  executes and is green (first real run: 29643662878).
- Skill routing is now measured live: 19 cases × 3 runs on seeded domain repos
  (sonnet-5) — recall 0.902, precision 0.939, conflict 0.053, stability 0.895
  at baseline, with the single stable misroute fixed and re-verified (metrics
  and per-run JSONL in `tests/skills/results/`; summary in `evaluated_runs`).
- verify-done attributes all dirty files to the current session (a Stop hook has
  no reliable session-start baseline); documented rather than reworked.
- Install profiles (minimal/python/data/full) and template-update propagation
  (Copier-style) are roadmap items.
- Destructive-command matching is now case-insensitive, which can deny prose
  that merely mentions SQL keywords (e.g. a commit message containing
  "DROP TABLE …"); deny-safe by design, override documented.

## [v2.0]
- CLAUDE.md sections 0–20; 8 domain skills; 5 enforcement hooks.

## [v1.0]
- Initial template: CLAUDE.md, 8 skills, hooks.
