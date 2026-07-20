# Changelog

Format: [Keep a Changelog](https://keepachangelog.com). Versions are git tags.

## [Unreleased]

### Fixed (eighth cycle)
- **claude-init bootstrap (P1): now fails closed.** Profile application, version
  stamp, manifest generation, manifest verification, and the final publish are
  one checked transaction (`if ! ( … )` with explicit `|| exit 1` at every
  step). Reproduced defects, now fixed: a broken `jq` during the strict/
  security-sensitive transform previously published a project labelled `strict`
  whose `settings.json` had **no** `CLAUDE_VERIFY_BLOCK` (exit 0 + success
  line); a broken `sha256sum` published a manifest of **blank hashes** that then
  validated against itself. The transform now asserts the intended env keys
  actually landed, the manifest is generated via captured `sha256sum` (exit code
  propagated), any blank-hash row aborts, and `sha256sum --check --quiet` must
  pass before the atomic `mv`. New failure-injection tests (FI1–FI8) cover jq/
  sed/find/sha256sum/mv failures + the drift-report guard.
- **claude-template-status (P1 follow-on)**: refuses to validate a manifest that
  contains blank-hash rows instead of reporting every file "unchanged"
  (`"" == ""`) — the compounding harm of the sha256sum defect.
- **web-security (P1): removed partial-token logging authorization.** "show
  token prefix only" contradicted CLAUDE.md §7 ("never log … session tokens").
  Now: never log any part of a token/auth header — use a non-secret correlation
  id. Enforced by a new static gate, `tests/policy_consistency.py`.
- **block-destructive (P2, A1): multiline recursive-`rm` bypass closed.** grep
  matched line-by-line, so `rm -rf \<LF>/`, a bare `LF`/`CRLF` split, or
  `rm -r<LF>-f /` all slipped through. The command is normalized (line
  continuations + CR/LF → space) on a match-only copy before matching; corpus
  rows ML-001–010 and hook cases BD_ML1–7 pin both the dangerous and the
  harmless-multiline neighbors.
- **hooks (P2, A4): fail-open is now observable.** When `jq` is missing or the
  input is unparseable the hooks still allow (fail open) but now log a
  `FAIL_OPEN` row (payload withheld) via `lib.sh::log_fail_open`, so a silent
  guardrail bypass is auditable. Tests FO1–FO3.
- **verify-done (P2, A5): watch-mode no longer hangs the Stop hook.** Watch/serve
  test scripts (`--watch`, `next dev`, nodemon, `vite`, …) are detected and
  skipped with an honest "no verification" note; every check is additionally
  bounded by `CLAUDE_VERIFY_TIMEOUT_S` (default 300 s) so a non-obvious
  long-runner is reported as a timeout failure, not a hang. Tests VD13/VD14.
- **hooks README (P2): SQL-prose bounded guarantee corrected.** The guarantee
  claimed "documentation text mentioning a statement stays allowed"; the hook
  actually (deliberately) blocks prose containing `DROP`/`TRUNCATE`. The README
  now matches the executable behavior; `policy_consistency.py` gates the phrase.

### Changed (eighth cycle)
- **testing skill (P2): flaky-test quarantine reworded** — an approved ticket, a
  still-running non-blocking quarantine lane, and a removal deadline are
  required; it is never a skip-to-green (CLAUDE.md §2/§10).
- **verification skill (P2): action boundaries reconciled** — `npm ci`/install
  annotated as an approval-gated dependency operation; the failure protocol now
  *proposes* a rollback (preserve state, diagnose read-only) instead of running
  `git revert` before approval.
- **session harness (P2): now asserts, not just records.** Each scenario declares
  `must_load`/`must_not_load`, an expected permission tier, a specific artifact
  path (no more `.`), and a semantic check; the run exits non-zero on any
  violation. Scoring is factored into `tests/sessions/score_session.py`,
  unit-tested offline by `test_score_session.py` (12 cases); an ask-tier
  scenario (s11) was added.
- **standards refs (P2/P3)**: NIST SP 800-63B rev 4 password length (≥15
  single-factor / ≥8 within MFA); `Sunset` = RFC 8594, `Deprecation` = RFC 9745;
  `X-RateLimit-*` labelled a vendor convention vs the IETF `RateLimit` draft.
- **universal-claim calibration (P3)**: `git mv` (rename detection is heuristic,
  not dependent on it), components-fetch (RSC/loaders excepted), readiness
  dependency checks (amplification caveat), CPU alerting (saturation is valid),
  mobile horizontal scroll and submit confirmations (intentional cases
  excepted), Docker `HEALTHCHECK` (orchestrator-owned probes excepted).
- **test fixtures (P3, A3): Windows portability.** `verify-done` Node fixtures
  use `node -e "process.exit(N)"` instead of a bare `exit N` npm script, so the
  suite no longer depends on npm's `script-shell` (the v7 289/291 vs 291/291
  split). SUPPORT.md records the measured config.

### Fixed (seventh cycle)
- **protect-files (P1)**: the `.env.example`/`.sample`/`.template`/`.dist`
  allowlist suppresses only the `.env*` filename deny — previously it exited
  the whole hook, so ANY protected path (`.git/`, `.secrets/`, workflows,
  actions, hooks, migrations) could be reached by giving the file a template
  basename. Root/nested templates stay editable (V7-01).
- **block-destructive (P1, SQL)**: long client flags now covered —
  `psql --command=`/`--command `, `mysql --execute=`, `sqlcmd --query `, with
  `=` or space before the quoted statement; short `-c`/`-e`/`-Q` unchanged and
  the quote boundary keeping prose (`echo "DELETE FROM users"`) allowed is
  preserved (V7-03).
- **block-destructive (P1, deps)**: pip installs are decided by explicit
  restore-vs-install logic instead of one regex — `pip install -q requests`,
  `-c`/`--constraint` spellings now ask; `-r`/`--requirement` restores stay
  allowed whatever other options are present. npm asks with global options
  before the subcommand (`npm --prefix /tmp install lodash`) and for
  local-path installs (`npm install ./pkg`); bare option-redirected restores
  (`npm install --prefix ./out`) stay allowed (V7-02).
- **block-destructive (P2, git)**: the protected-branch ask survives global
  options between `git` and `commit` (`-C .`, `-c k=v`, `--no-pager`,
  `--git-dir/--work-tree`) and path/env invocations (`/usr/bin/git`,
  `env git`); command-position class now matches RM_WORD. `git -C <other>`
  target branches remain unresolved by design — documented in the bounded
  guarantee (V7-08).
- **block-destructive (P2, anchoring)**: every dependency ask pattern is
  anchored at a command position — `cargo install` no longer matches through
  the *go* pattern by accident, and `mongo install`/`django get`/prose can
  no longer trigger asks (V7-09).

### Security (seventh cycle)
- **block-destructive**: recursive-deletion coverage extended to the measured
  destroyers — quoted absolute targets (`rm -rf '/srv/data'`),
  `$PWD`/`${PWD}`/`$(pwd)` (destroyed the whole tree in sandbox), dot-glob
  character classes `.[!.]*`/`.[^.]*` (deleted `.git/`), and brace sweeps
  `{*,.[!.]*,..?*}` (deleted everything). Named relative cleanup
  (`rm -rf ./build`, `node_modules`, `dist/assets`) stays allowed (V7-04/05/06/07).
- **block-destructive (policy)**: global tool installs now ask deliberately —
  `cargo install`, `pipx install`, `uv tool install` — matching the existing
  `gem install`/`go install` behavior; previously `pipx`/`uv tool` were
  allowed outright and `cargo` asked only by accident (V7-13; reversible
  one-line policy choice).

### Performance (seventh cycle)
- **block-destructive**: one combined-alternation grep decides match/no-match;
  the per-pattern loop runs only on a hit to name the pattern in the message.
  Measured on Windows Git Bash: ordinary-command p50 2179 ms → 275 ms,
  p95 2409 ms → 303 ms (~8×; ~170 process spawns → ~4). Behavior unchanged —
  291/291 regressions and the 205-row corpus verify the restructure (V7-10).

### Added (seventh cycle)
- **tests/hooks/corpus.jsonl + run-corpus.sh**: 205-row labeled policy corpus
  replayed through the real hooks; separates contract (`expected`) from
  semantic ideal and out-of-scope rows; emits a confusion matrix. Baseline at
  the audited commit: 27 contract violations, dangerous-action recall 0.821.
  After the v7 fixes: 0 violations, recall 1.000, false-deny rate 0.000.
- **hooks README**: "Bounded guarantee" section — five falsifiable statements
  covering recursive deletion, protected-branch commits, SQL, strict Stop
  (best-effort, not a hard DoD gate), and the universal regex limit.
- **LICENSE**: Apache-2.0, verbatim official text (owner-authorized); README
  license section; CONTRIBUTING.md, SECURITY.md, SUPPORT.md added.
- **claude-init profiles + dry-run**: `--profile minimal|standard|strict|team|
  security-sensitive` as jq transforms of the staged settings.json; `--dry-run`
  reports the full plan and writes nothing; allowlist copy replaces
  copy-everything-then-prune (95% of previously copied bytes were machine-local
  worktrees) and fails loudly on unknown `.claude/` entries.
- **Update propagation (detect-and-report tier)**: `.claude/.template-version`
  + `.claude/.template-manifest` (sha256 per managed file) stamped into every
  generated project; `claude-template-status` classifies unchanged / locally
  modified / missing and never writes. `tests/installer/run-tests.sh`: 37 cases.
- **Routing evaluation at full coverage**: fixture extended 20 → 45 cases so
  all 37 skills have positive evidence plus ambiguous-observation rows; skill
  descriptions compressed to routing signals (listing 20,229 → 13,415 chars)
  with the six missing Do-NOT boundaries added; results carry provenance
  (repo commit, fixture digest, descriptions digest, model, CC version).
- **tests/sessions/run-sessions.sh**: ten-scenario realistic-session harness
  recording skills loaded, hook ask/deny counts, replayed Stop decision,
  wall-clock, and artifact outcome — sanitized to names and counts.
- **Authoritative full-fixture routing run** (`results/routing-20260720-083339`,
  claude-sonnet-5, repo `05bfb3d`): 45 cases × 3 reps = 135 runs, 0 errored —
  recall 0.940, precision 0.967, conflict rate 0.007, no-load 0.060, stability
  0.733 (0.805 over the 41 asserting cases); skill-averaged macro recall
  0.9505 / precision 0.9788 across all 37 skills. Sole conflict:
  `review-api-breaking` run 1 co-loaded `api-design`; 7 isolated no-loads,
  never a mis-load.
- **Realistic-session evidence** (`tests/sessions/results/sessions-20260720.jsonl`):
  9 model-driven scenarios — 0 asks, 0 denials, 0 unrequested skill loads,
  8/9 produced the expected artifact (s4: alembic binary absent in the seed;
  the session reported inability), Stop replay correct in every row. The
  harness's evidence capture was corrected on first live contact (hooks.log
  is tab-separated; bracketed-marker greps counted 0) and now also records
  per-session tool-call counts so hook overhead is estimable.
- 66 new hook regressions (V7-01…09 families plus intended-allow controls).

### Fixed (sixth cycle)
- **verify-done (P1)**: Bun's modern text lockfile `bun.lock` (default since
  Bun 1.2) now selects bun — previously only `bun.lockb` did, so new Bun
  projects were verified with npm or not at all. The Node test check runs
  `$PM run test` instead of `$PM test`: identical for npm/pnpm/yarn, and the
  only correct form for Bun (`bun test` invokes the native runner, which
  ignores the package.json script the check is gated on — real Bun 1.3.14
  exits 1 "No tests found" on a healthy script-only project).
- **protect-files (P1)**: directory-segment comparisons are case-folded like
  basenames — `.GIT/config`, `.Secrets/`, `.CLAUDE/settings.local.json`,
  `MIGRATIONS/`, `.GITHUB/actions/` variants address the SAME files on
  Windows/macOS (proven via NTFS same-file writes) and previously bypassed
  the deny/ask tiers. Original casing kept in messages; on case-sensitive
  Linux a distinct `.GIT/` now errs toward ask/deny (over-caution by design).
- **check-diff-size**: honors `CLAUDE_HOOK_OVERRIDE` in the hard-block branch
  (logged), as the hooks README always documented; previously the only
  blocking hook that ignored the override mechanism.

### Security (sixth cycle)
- **block-destructive**: current-directory destruction denied — `rm -rf ./*`,
  `-- ./*`, `./.??*`, `"./"*`, bare `.??*` (which really delete; measured in
  disposable sandboxes) plus the inert-but-intent-destructive `.`, `./`, `..`
  (GNU rm refuses those — reproduced, not assumed). Named relative cleanup
  (`rm -rf ./build`, `../temporary-build`) stays allowed.
- **block-destructive**: client-wrapped unguarded DELETE without `;` denied —
  `psql -c` / `mysql -e` / `sqlcmd -Q` with either quote style and
  intervening options. WHERE-guarded statements and prose
  (`echo "DELETE FROM users"`, commit messages) stay allowed; clients taking
  SQL as a positional argument (sqlite3) remain a documented residual.
- **block-destructive**: env-redirected installs now ask —
  `npm install --prefix DIR pkg`, `pip install --target DIR pkg`,
  `pip install --no-deps pkg`, and any `pip install --index-url …`
  (non-default index = supply-chain decision, deliberately including
  restores). Bare `npm install --prefix DIR` and all other restores stay
  allowed.

### Added (sixth cycle)
- Hook regression suite 187 → 228: bun lockfile/command matrix driven by a
  stub bun on a **restricted PATH** (VD9 is now host-independent — bun absent
  by construction, present via stub; exact `bun run test` argv asserted),
  current-directory rm globs with named-cleanup allows, client-wrapped SQL
  with WHERE/prose controls, env-redirected installs with restore control,
  protected-path case variants across Write/Edit/NotebookEdit, and diff-size
  override in both directions.
- Sixth-cycle blind audit + adjudication reports with measured evidence
  (real-Bun Docker semantics, NTFS case-equivalence, disposable-directory rm
  behavior, 251 MB bootstrap-copy timing, live false-positive profile);
  consolidated owner-decision proposals
  (`reports/proposal-owner-decisions-v6.md` — license, release/version
  policy, community/security docs; nothing activated, owner decisions).

### Changed (sixth cycle)
- hooks README: tier table reflects the new coverage; the four confirmation
  levels (hook deny/ask → permission prompt → user pre-allowlist → CLAUDE.md
  §2 in-chat norm) are documented as distinct — a pre-allowlisted mutating
  command is NOT re-prompted, and the old "never silently executed" claim is
  corrected; new-hook guidance now says secret values go to *neither* stderr
  nor the log (context to stderr, pattern names to the log).
- claude-init header: success-path `cd` documented precisely (the subshell
  claim now scopes to assembly); unknown future `.claude/` local-state files
  are named as a copy residual — keep the template checkout clean.

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
