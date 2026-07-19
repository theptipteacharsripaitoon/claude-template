# Changelog

Format: [Keep a Changelog](https://keepachangelog.com). Versions are git tags.

## [Unreleased]

### Fixed (fifth cycle)
- **claude-init (P1)**: a failed copy of `CLAUDE.md`, `.gitignore`, or
  `.gitattributes` was MASKED — the subshell is the operand of `if !`, a
  context where bash ignores `set -e` (even one issued inside it), so the
  installer's exit 0 published an incomplete project with a success message.
  Steps are now `&&`-chained (short-circuits in any context) and the staged
  tree is validated for every required artifact before the atomic rename;
  four one-failure-at-a-time PATH-stub regressions (BOOT10–13). The header
  now also states the interrupt limitation honestly (a killed process can
  leave a `.claude-init.*` temp dir; no trap — the function is sourced).
- **verify-done**: `run_check` executes argument vectors directly — `eval`
  removed (CLAUDE.md §7 consistency); VD6–VD10 semantics unchanged.
- **.gitignore**: re-include all five supported env templates
  (`.env.sample`, `.env.template`, `.env.dist`, `.env.test.example` joined
  `.env.example`) so the file hook's "committed env templates" allowlist and
  Git tracking policy agree; generated projects inherit the fix.

### Security (fifth cycle)
- **block-destructive**: closed measured v5 bypasses — quoted `rm` command
  words (`"/bin/rm" -rf /`, `'rm' -rf /`), brace-expanded `${HOME}` targets,
  quoted force-refspecs (`git push origin "+main"`), option-first installs
  (`npm install --save-dev/-D/-g`, `pip install --user`), and semicolon-less
  unguarded `DELETE FROM …` ending the command. Safe controls measured
  unchanged: quoted prose (`echo 'rm -rf /'`, `echo "DELETE FROM users"`,
  commit messages), `rm -rf build/`, WHERE-guarded DELETE, and every
  lockfile/manifest restore stay allowed.
- **block-destructive**: `git commit` while on `main`/`master`/`production`/
  `release/*` now emits the CLAUDE.md §2 approval ask (plain feature-branch
  commits and `git push` keep their existing flows).
- **protect-files**: ALL sensitive-basename comparisons are case-folded
  (`ID_RSA`, `Secrets.yaml`, `Credentials.json`, `.NPMRC`, … gate exactly
  like their lowercase forms — same file on Windows/macOS); the whole
  `.github/actions/` subtree now asks (composite-action scripts run with
  workflow trust, not just `action.yml`); `.claude/settings.local.json` asks
  like `settings.json` (per the settings docs, local allow rules skip
  workspace trust and `disableAllHooks` is accepted there); generic `*.pem`
  moved deny→ask (public cert chains; private-key content stays hard-blocked
  by scan-secrets, key containers `*.key`/`*.p12`/`*.pfx`/… stay deny).

### Added (fifth cycle)
- Stream-JSON extraction hardened and testable: pure `parse_stream()` +
  `stream_anomaly()` in `run_eval.py` — malformed lines and a missing
  terminal `result` event now mark the run ERRORED (visible, excluded from
  metrics) instead of silently scoring as a valid no-load; new
  `--fail-on-error` gate; 9 offline parser fixtures.
- `tests/skills/routing/test_results_consistency.py`: every committed
  summary must recompute exactly from its JSONL, every `evaluated_runs`
  entry must match the summary it cites, and the newest full-fixture run
  must be recorded.
- `tests/check_links.py`: repo-wide relative Markdown link check over
  tracked files (code fences stripped).
- CI now runs the offline routing tests, results consistency, `py_compile`,
  workflow+fixture YAML validation, generated-file cleanliness, and the
  link check (live model routing stays local-only).
- Hook regression suite 143 → 187: quoted/braced/option-first/semicolon-less
  command variants with prose safe-controls, protected-branch commit ask,
  case-folded basenames, both settings layers × Edit/Write/NotebookEdit,
  `.github/actions/` subtree, PEM ask tier, bootstrap masked-copy failures,
  gitignore/template agreement.
- `evaluated_runs` records the final authoritative 20×3 run
  (`routing-20260718-195349`: recall 0.963, precision 1.0, conflict 0.0);
  older entries annotated where their hand-entered `cc_version` is not
  backed by the summary file.
- Fifth-cycle audit + adjudication reports; repository-level secret-scanner
  proposal for owner sign-off (`reports/proposal-secret-scanner.md` — not
  installed, owner decision).

### Changed (fifth cycle)
- README: guardrail-not-sandbox warning near the intro; brittle hook-count
  replaced with the runner-authoritative phrasing.
- hooks README synced with implementation: secret values are withheld
  everywhere (not "stderr only"), DELETE end-of-command coverage + the
  quote-boundary residual documented, new ask tiers listed.

### Fixed (fourth cycle — recorded retroactively; details in reports/*-v4.md)
- Stop-hook verification now works in linked git worktrees (`.git` is a
  file there); untracked code in new directories is counted.
- scan-secrets never prints matched-secret material (no prefix/preview);
  audit-log fields escape control characters (no forged records).
- Destructive-command matching hardened: `/bin/rm`, `\rm`, `rm -rf -- /`,
  schema-qualified/bracketed SQL, `DROP VIEW/PROC/INDEX`, force-push via
  `+refspec`; key/cert/credential files, `action.yml`, `.gitmodules`,
  `*.tf` gated; `.env` case variants denied.
- claude-init excludes machine-local `.claude` state from generated
  projects; routing harness gained duplicate-id rejection, result-file
  collision guards, `--min-recall`/`--max-conflict`/`--fail-on-miss` gates,
  auto-captured `cc_version`, and scoring-math unit tests; CI runs on a
  pinned image with checksum-verified ShellCheck.

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
