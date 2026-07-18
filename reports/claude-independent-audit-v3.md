# Independent Audit v3 — claude-template

> Third-cycle independent audit. Produced **before** opening `external-review-v3.md` and
> without relying on the correctness of any prior report, score, or test claim.

## Phase 0 — Audited state

| Item | Value |
|---|---|
| Repository | https://github.com/theptipteacharsripaitoon/claude-template |
| Audited branch | `main` |
| Audited commit | `4df4566f87aaef8e433ea37206d079618b6454f4` (merge of PR #6) — confirmed identical to remote `main` via `git ls-remote` on 2026-07-18 |
| Work branch | `claude/template-third-audit-192d32` (created from `main` @ `4df4566`, clean tree) |
| Claude Code version | 2.1.214 |
| Model | claude-fable-5 |
| OS | Windows 11 Home 10.0.26200 |
| Shells | Git Bash (GNU bash 5.2.15, msys) primary for hook execution; PowerShell 5.1 available |
| jq | 1.6 |
| Git | 2.41.0.windows.3 |
| Python | 3.10.9 |
| Node | 18.16.0 |
| Docker | 29.5.3 |
| ShellCheck | no native binary; `koalaman/shellcheck:v0.10.0` via Docker (v0.10.0, image `2097951f02e7`) |
| gh CLI | not installed — GitHub state inspected via unauthenticated REST API (repo is public) |

### GitHub Actions status at audit start

- Workflow: `.github/workflows/test.yml` (`template-tests`), 7 total runs recorded.
- Latest run on `main` @ `4df4566`: [run 29638281029](https://github.com/theptipteacharsripaitoon/claude-template/actions/runs/29638281029) — `completed` / `failure`.
- Evidence that the failure is **pre-execution**: job `hooks-and-catalog` (id 88064325818) completed in 3 s with `runner_name: ""` and an **empty `steps` array**; no check-run output/annotations. GitHub never assigned a runner and never executed a single repository step.
- Conclusion: the red CI status is an **account/billing/platform condition** (job rejected before scheduling), not a repository workflow defect. **No repository change can fix it — owner action required** (resolve the GitHub account payment/billing lock, then re-run).
- Consequence for scoring: no pushed GitHub Actions run has ever *executed* the repository's steps, so "CI green" cannot be claimed by anyone; local execution of every workflow step is the substitute evidence used in this audit (§ CI assessment).

---

## 1. Overall score before changes

**7.6 / 10** (weighted rubric, measured — see §3). Ceiling is held down by two safety/correctness
defects in the hooks (a completely broken `verify-done` blocking mode and multiple destructive-command
false negatives), one structured-output defect (`protect-files` emits invalid JSON on hostile filenames),
`claude-init` failure-atomicity gaps, and the fact that routing precision/recall is **unmeasured this
cycle** (the live harness is built but the account hit its usage limit mid-run — see §13). No score above
9.0 is defensible while P0/P1 hook defects and an un-executable CI both stand.

## 2. Method / environment

Every hook was exercised against the **committed (LF) content**, exported with `git archive HEAD | tar -x`
into a scratch tree, because this Windows working copy has `core.autocrlf=true` and shows CRLF locally
(`.gitattributes` forces `*.sh eol=lf`, so the Linux CI runner and any fresh clone see LF). ShellCheck was
run from the same LF export via `koalaman/shellcheck:v0.10.0` with the exact CI flags. Hook decisions were
classified by driving each script with real hook-input JSON built by `jq -n --arg` (never string
interpolation) and reading exit code + stdout parsed with `jq`, not substring search. All scratch work
lived outside the repo tree.

## 3. Category scores (before changes)

| Category | Weight | Score | Basis |
|---|---:|---:|---|
| Technical correctness | 15% | 7 | verify-done blocking mode crashes; rm/SQL/clean false negatives |
| Skill trigger quality | 15% | 7 | descriptions are careful and disambiguated, but **routing unmeasured** this cycle |
| Hook correctness | 15% | 7 | 4 confirmed defects (1 P0, 2 P1, 1 P2) against otherwise strong coverage |
| Conflict avoidance | 10% | 8 | must_not_load fixtures exist; not yet measured live |
| Safety & permissions | 10% | 8 | deny/ask tiers correct; destructive FN gaps dock it |
| Testing & evaluation | 15% | 7 | 50-case suite is real & green, but misses the blocking-mode + FN gaps it should catch |
| Context efficiency | 5% | 9 | lean skills, on-demand load, tight hooks |
| Team usability | 5% | 9 | strong README/HOW-TO/override/logging story |
| Maintainability | 5% | 9 | shared lib.sh, table-driven tests, catalog gate |
| Public-template readiness | 5% | 6 | no LICENSE (owner), CI cannot execute (billing), routing unmeasured |

Weighted ≈ **7.6**.

## 4. Hook-by-hook assessment

**`lib.sh`** — sound. `json_get` fails open on malformed JSON (`|| true`), `require_jq` fails open,
`log_event` never lets a logging failure abort a hook (`|| return 0` / `|| true`), override path logs.
No defects.

**`block-destructive.sh`** — strong coverage with **confirmed false negatives** (see §6). Deny path exits 2
with stderr; ASK path emits valid JSON (`permissionDecision:"ask"`) built from a **hardcoded** pattern
string (not user input), so its `printf`-interpolated JSON cannot be corrupted. Verified a 5 MB-padded
`rm -rf /` still denies (no SIGPIPE/truncation bug).

**`protect-files.sh`** — deny/ask tiers and normalized-component matching are correct (25/28 path cases
pass, including traversal `..`, `//`, mixed slashes, `.env.example.secret`, `config.environment.ts`,
`infrastructure/` non-match). **Defect:** the ASK JSON is built with `printf '…%s…' "$BASE"`, so a filename
containing a `"`, tab, or newline yields **invalid JSON** (3/3 hostile-char cases failed jq parse) — the
ask is silently lost and the protected-path prompt can be bypassed. See §10/§16.

**`scan-secrets.sh`** — **no defects found** (19/19). All patterns deny; value-scoped fixture markers work;
fake-then-real and real-then-fake both deny; marker-in-comment / marker-in-varname do **not** bypass a real
value; Edit/NotebookEdit fields covered; malformed JSON fails open; block uses stderr+exit 2 (no secret in
stdout or in `.claude/logs/hooks.log`, confirmed by grep). Detection boundary = inserted content only
(a secret split across two edits is not reconstructed) — documented, acceptable.

**`check-diff-size.sh`** — correct. Arithmetic is all comparisons inside `if`/assignments (no bare
increments). Warn (stderr) / hard-block (exit 2) both fire at thresholds. NotebookEdit covered.

**`verify-done.sh`** — reminder mode (default) is correct across clean/dirty/no-git/stop_hook_active.
**Blocking mode (`CLAUDE_VERIFY_BLOCK=1`) is completely broken** — see §5/§11 (P0).

**`install.sh`** — correct; uses `FAIL=$((FAIL+1))` (strict-safe) and validates settings.json + smoke +
functional + override. No defects.

## 5. Shell strict-mode assessment

All hooks `source lib.sh` which sets `set -euo pipefail`. Findings, each with a runnable repro:

- **P0 — `((RAN++))` aborts `verify-done.sh` blocking mode.** Under `set -e`, `((expr))` returns exit 1
  when `expr` evaluates to 0. `RAN` starts at 0, so the **first** executed `((RAN++))` (line 84/90/101/111
  depending on ecosystem) returns 1 and `set -e` kills the hook. Repro:
  `bash -c 'set -euo pipefail; RAN=0; ((RAN++)); echo alive'` → prints nothing, `exit=1`.
  End-to-end: a Node repo with a passing `test` script, `CLAUDE_VERIFY_BLOCK=1`, prints only
  “🔍 Running Definition of Done verification…” then exits **1** — never runs a check, never reports
  pass/fail, and returns neither the documented 0 (pass) nor 2 (fail). The 50-case suite's VD5 only
  exercises the *no-ecosystem* path (which skips every increment), so the bug ships green.
  The `((FAILED++))` occurrences are all `|| true`-guarded and safe.
- No other bare `((x++))`/`((x--))` in any hook (grep-verified). `grep -c` no-match, `read` at EOF in
  `scan-secrets` (input is `printf '%s\n'`-terminated so no last-line drop), pipefail pipelines
  (`… | grep -oE … || true`), empty arrays (`"${ARR[@]}"` under `set -u` guarded), and `json_get` on
  invalid JSON all behave correctly — repro'd individually, all survive.

## 6. Command threat-model matrix (block-destructive.sh)

43 commands driven through the hook. **9 confirmed false negatives, 0 false positives** among the
safety-critical set. `allow`/`deny`/`ask` = observed action.

| Command | Expected | Actual | Matched rule | Risk |
|---|---|---|---|---|
| `rm -rf /` | deny | **deny** | `rm -rf?[space]/` | — |
| `rm -fr /` | deny | **allow** ❌ | none (regex only `-rf`) | FN — catastrophic |
| `rm -r -f /` | deny | **allow** ❌ | none (split flags) | FN — catastrophic |
| `rm --recursive --force /` | deny | **allow** ❌ | none (long flags) | FN — catastrophic |
| `rm -rf ~` / `rm -rf $HOME` | deny | **deny** | `~` / `\$HOME` | — |
| `rm -rf "$HOME"` | deny | **allow** ❌ | none (quote before `$HOME`) | FN — minor |
| `rm -rf build/` | allow | **allow** | — | correct (local cleanup) |
| `find /tmp/x -delete` | deny | **deny** | `find .*-delete` | (also denies local finds — mild FP, deny-safe) |
| `git reset --hard`, `git clean -fd`, `git push --force/-f/--force-with-lease`, `git update-ref -d` | deny | **deny** | resp. | — |
| `git clean -df` | deny | **allow** ❌ | none (`-[a-z]*f[a-z]*d` needs f-before-d) | FN |
| `DROP TABLE users` / `TRUNCATE TABLE events` (upper) | deny | **deny** | resp. | — |
| `drop table users` / `truncate table events` (lower) | deny | **allow** ❌ | none (case-sensitive) | FN |
| `Drop Table users` (mixed) | deny | **allow** ❌ | none | FN |
| `DELETE FROM users;` (upper) | deny | **deny** | `DELETE FROM x;` | — |
| `delete from users;` (lower) | deny | **allow** ❌ | none (case-sensitive) | FN |
| `DELETE FROM users WHERE id=1;` | allow | **allow** | — | correct (WHERE present) |
| `terraform apply/destroy`, `kubectl delete namespace`, `helm uninstall`, `aws s3 rb --force`, `gcloud … delete` | deny | **deny** | resp. | — |
| `curl … | sh`/`| bash`/`|bash`/`| sudo bash`, `wget … | sh` | deny | **deny** | curl/wget pipe | — |
| `git push origin main`, `ls -la`, `terraform plan`, `kubectl get pods`, `grep -rf …` | allow | **allow** | — | correct (no FP) |

**Confirmed FN classes:** (a) `rm` flag variants `-fr`, `-r -f`, `--recursive --force`, quoted `"$HOME"`;
(b) `git clean -df` ordering; (c) case-insensitive SQL `drop/truncate/delete`. All are safety-relevant.
Force-push policy (`deny` for every form) is correct per CLAUDE.md §2 (“suggest; do not execute”).

## 7. Dependency-command matrix (block-destructive.sh)

38 commands. Install/add → **ASK** (correct, valid JSON); restore forms → **ALLOW** (correct — restoring
already-approved deps from a lockfile/manifest is not a new supply-chain decision); every **remove** and
**update/upgrade** form → **ALLOW**.

| Class | Examples | Actual | Policy (§2 "install, upgrade, or remove") |
|---|---|---|---|
| Add / install `<pkg>` | `npm install lodash`, `pip install requests`, `cargo add`, `go install`, `composer require`, `gem install` | ASK ✓ | ASK ✓ |
| Restore | `npm install`/`ci`, `pip install -r`, `*install`, `uv sync`, `bundle install` | ALLOW ✓ | ALLOW ✓ (restore) |
| Remove | `npm uninstall`, `pnpm/yarn/bun remove`, `pip uninstall`, `uv/cargo/poetry remove`, `composer remove` | **ALLOW** | should ASK — **gap** |
| Update / upgrade | `npm update`, `yarn upgrade`, `cargo/poetry update`, `bundle/composer update` | **ALLOW** | should ASK — **gap** |

**Reconciliation:** the restore/new-dep split is correct and worth keeping. The hook under-enforces §2 for
`remove` and `upgrade`; both are ASK-worthy (upgrade pulls new code → supply-chain; remove mutates the
manifest). This is a policy-vs-enforcement gap, not a crash — P2. Closing it means adding ASK patterns
(not deny) for remove/upgrade while preserving the restore ALLOWs.

## 8. Secret-scanner assessment

No defects (see §4). 19/19 including every pattern, multi-match, both marker orderings, marker placement,
Edit/NotebookEdit, malformed-JSON fail-open, and no-stdout/no-log-leak. Silent-allow-on-fake-marker is
**value-scoped** (marker must be inside the matched value), which is the safe choice: a marker in a comment
or variable name does not suppress a real adjacent secret. Recommend **keep as-is**.

## 9. Protected-path assessment

Deny (secrets/git) vs ask (CI/infra/migrations/lockfiles/settings/hooks) vs allow (templates/similar names)
all correct; traversal/normalization cannot bypass. Only defect is the invalid-JSON-on-hostile-basename in
the ASK branch (§4/§10). NotebookEdit `notebook_path` covered.

## 10. Hook JSON validation results

Parsed every JSON-emitting branch with `jq -e`:

- `block-destructive.sh` ASK → **valid** (`hookEventName`/`permissionDecision`/`permissionDecisionReason`
  all present; reason is a string). Interpolated `%s` is a fixed regex, not user input — safe.
- `protect-files.sh` ASK → **valid for Thai/backslash basenames, INVALID for `"`, tab, newline** in the
  basename (3/3 hostile-char cases fail `jq empty`). Root cause: `printf '…%s…' "$BASE"` interpolates a
  user-controlled string into a JSON string literal without escaping. Fix: build with `jq -n --arg`.
- No hook writes secret values to `.claude/logs/hooks.log` (grep of the accumulated log = 0 hits).

## 11. Stop-hook test results

| Scenario | Expected | Actual |
|---|---|---|
| Clean tree | exit 0, no nag | ✓ |
| Dirty tree, 1 code file (reminder) | exit 0 + DoD reminder | ✓ |
| `stop_hook_active=true` | exit 0, no nag (no loop) | ✓ |
| No git repo | exit 0 | ✓ |
| Blocking, no ecosystem checker | exit 0 + "no verification" (not "passed") | ✓ |
| **Blocking, Node repo, passing test** | exit 0 + "all checks passed" | ✗ **exit 1, no checks run** (P0) |
| **Blocking, any pyproject/Cargo/go repo** | run checks, exit 0/2 | ✗ **exit 1** (P0, same root cause) |

Reminder mode (the default, and what teams run) is solid; blocking mode is unusable and, worse, exits 1 —
which the harness could misread as a hook error rather than a policy decision.

## 12. CI assessment

`.github/workflows/test.yml` is well-formed (YAML parses) and already carries `permissions: contents:read`,
`timeout-minutes: 10`, and a SHA-pinned `actions/checkout@08c6903…` (v5.0.0), pinned `pyyaml==6.0.2`, and a
ShellCheck step with the correct `-x -P .claude/hooks` flags. **Every step passes locally** against the LF
export:

- `bash tests/hooks/run-tests.sh` → `pass=50 fail=0`
- `bash .claude/hooks/install.sh` → all green
- `shellcheck -x -P .claude/hooks …` (v0.10.0 in Docker) → **clean**
- `python tests/skills/check_catalog.py` → `37 skills checked … ALL CHECKS PASS`

**But no pushed run has ever executed:** the job is rejected pre-scheduling (empty `steps`, no runner) — an
account **billing/usage** condition, not a workflow defect. **Owner action required.** Gaps that are real
but blocked by that: `runs-on: ubuntu-latest` (not digest-pinnable), `actions/setup-python` not used (Python
comes from the runner image — version is not pinned), ShellCheck version not pinned in-workflow (relies on
the runner's preinstalled version), no `concurrency:` cancellation. These are determinism improvements worth
making, but none can be proven green until the billing lock clears.

## 13. Skill-routing results (harness built; measured run blocked this cycle)

A repeatable harness was built (`scratchpad/routing/`): `seed-case.sh` creates a domain-representative git
repo per case (real DAGs, T-SQL procs, a `.dtsx`, an OpenAPI app, a tracked `node_modules`, etc.),
`run-eval.sh` runs each of the **19** `trigger-cases.yaml` prompts **×3** through headless
`claude -p --output-format stream-json --setting-sources project`, and records loaded skills (extracted
from `Skill` tool-use events), `required_ok`, `forbidden_hit`, `no_load`, latency, model, and version to
`results.jsonl`. A single smoke run worked end-to-end and correctly captured `Skill(airflow)` loading for
the "Create an Airflow DAG" prompt — so the harness and its skill-detection are validated.

**The 19×3 baseline could not be completed: the account hit its usage/session limit** ("You've hit your
session limit · resets 7:20pm Asia/Bangkok"); all 54 runs returned `is_error:true`. **Routing precision /
recall / conflict / no-load / stability are therefore UNMEASURED in this cycle** and are recorded as such —
not estimated. The harness will be executed in the post-implementation window after the limit resets, and
the numbers appended in a clearly separated section. (This is an owner/quota condition, like CI — not a
repo defect.)

## 14. Bootstrap assessment (claude-init.sh)

13 scenarios; **9 pass, 4 confirmed defects**:

| Test | Result |
|---|---|
| Normal / spaces / unicode name, spaced dest root, existing dest refused, empty name refused, missing `.claude` refused, reports & external-review not copied, `.gitignore`/`.gitattributes` inherited | ✓ (9) |
| **`../escape` name** | ✗ escapes the destination root (`mkdir -p "$DEST_ROOT/$name"` + `cd` follows `..`) — path-traversal in the project name |
| **Missing `CLAUDE.md` in template** | ✗ reports success though `cp` of CLAUDE.md failed (unchecked `cp`); only `.claude` presence is validated |
| **Failed hook installer** | ✗ leaves a **partial project** behind (`.claude`, CLAUDE.md, etc. already copied; no cleanup on failure) |
| **cwd after a failure path** | ✗ caller is left `cd`'d inside the half-built project dir (function `cd`s and never restores on the failure branches) |

Root causes: the function `mkdir/cd`s into the final destination first and copies in place, so any later
failure leaves partial state and a moved cwd; the project name is not validated against traversal; `cp`
results are unchecked. All four are fixed by the temp-sibling-then-atomic-rename pattern the brief suggests,
plus name validation and a `trap` cleanup. (The shipped `run-tests.sh` BOOT1–3 only assert the happy path.)

## 15. Public-template readiness

- Skill count: README/INDEX/README-table all say **37**, and `check_catalog.py` confirms 37 folders ==
  INDEX rows == README rows. **Accurate.**
- Test count: README says "50-case"; `run-tests.sh` reports `pass=50`. **Accurate.**
- CHANGELOG already states the billing-blocked CI and the 9-case routing limitation honestly.
- **LICENSE:** absent — README says "all rights reserved". **Owner decision; not selected here.**
- Versioning/compatibility: CHANGELOG uses tags (v1.0/v2.0/Unreleased); hooks README documents Claude Code
  compatibility and bash/jq/grep requirements. Reasonable; no formal SemVer/compat policy doc.
- Template-update propagation (Copier-style) and install profiles remain roadmap.

## 16. Confirmed defects (with reproduction)

- **D1 (P0) — `verify-done.sh` blocking mode dies with exit 1, runs no checks.** Repro §5/§11. Any repo
  with package.json/pyproject.toml/Cargo.toml/go.mod. Root cause: bare `((RAN++))` under `set -e`.
- **D2 (P1) — destructive false negatives in `block-destructive.sh`.** `rm -fr /`, `rm -r -f /`,
  `rm --recursive --force /`, `git clean -df`, and lowercase `drop/truncate/delete … ;` all ALLOW. Repro §6.
- **D3 (P1) — `protect-files.sh` emits invalid JSON** for basenames containing `"`, tab, or newline; the
  protected-path ASK is dropped. Repro §10.
- **D4 (P1) — `claude-init.sh` is not failure-atomic** and allows project-name path traversal; leaves
  partial projects and a moved cwd on failure. Repro §14.
- **D5 (P2) — dependency `remove`/`upgrade` not asked**, contrary to CLAUDE.md §2. Matrix §7.
- **D6 (P2) — `rm -rf "$HOME"` (quoted) bypasses**; unquoted `$HOME`/`~` are caught. §6.

## 17. Unconfirmed concerns / non-defects

- Local ShellCheck SC1017 (carriage return) is a **Windows working-tree artifact**, not a repo defect —
  committed content is LF and passes ShellCheck. Do **not** "fix" line endings.
- `find … -delete` denies even project-local finds (mild false positive) — deny-safe with override; leave.
- No `timeout` on the settings.json hook entries — the docs default is 600 s; a short explicit timeout is
  optional hardening, not a defect.
- verify-done attributes all dirty files to the current session (no session-start baseline) — a documented
  limitation of Stop hooks, not a bug.

## 18. Strengths to preserve

Shared `lib.sh` with fail-open-on-misconfig; deny/ask two-tier permission model with valid ASK JSON on the
Bash path; **excellent** secret scanner (value-scoped markers, both orderings, no log leakage); normalized
path-component matching that avoids `.env`/`config.environment.ts` confusion; table-driven 50-case suite;
catalog-consistency gate; careful, disambiguated skill descriptions with explicit "Do NOT use for …" and
companion pointers; honest CHANGELOG and prior reports.

## 19. Recommendations

- **P0:** D1 — make every `verify-done` counter strict-safe (`RAN=$((RAN+1))`), add a blocking-mode
  regression test that exercises a real ecosystem checker (pass **and** fail).
- **P1:** D2 — add `rm` flag-order/long-flag/quoted variants, `git clean` order-independent, and
  case-insensitive SQL matching (`grep -iE`), with regression cases; D3 — build protect-files ASK JSON with
  `jq -n --arg` (also block-destructive for consistency), add hostile-char regression; D4 — rewrite
  `claude-init` as validate → temp-sibling copy → install → atomic rename → trap-cleanup, preserving cwd,
  with traversal-name and failure-atomicity tests.
- **P2:** D5 — add ASK patterns for dependency remove/upgrade; D6 — cover quoted `"$HOME"`; add optional
  short `timeout` to settings.json validators; add `concurrency:` + pin Python/ShellCheck in CI (cannot be
  proven until billing clears).
- **P3:** run the routing harness (post-reset), append measured metrics, and land the harness in
  `tests/skills/` so it is repeatable; consider a SemVer/compat policy doc.
- **Owner actions (no repo fix):** clear the GitHub billing/usage lock so CI executes; choose a LICENSE.

---

# Post-implementation (added after Phases 3–5; Phase 1 above is unmodified)

All fixes were adjudicated in [review-adjudication-v3.md](review-adjudication-v3.md) and landed
test-first: the new regression cases were written, run, and observed failing exactly along the
predicted defect classes (37 failing / 70 passing), then each fix turned its cases green.

## What changed

| Change | Commits |
|---|---|
| D1 (P0): verify-done strict-safe counters + missing-toolchain honesty | `b259fd3` |
| D2/D5/D6: rm variants, order-independent git clean, case-insensitive SQL, dependency remove/upgrade asks, jq ask-JSON | `d13809e` |
| D3: protect-files jq ask-JSON | `679ee76` |
| D4: claude-init name-safe + failure-atomic | `11795d9` |
| Validator timeouts in settings.json | `fc1f171` |
| Regression matrix 50 → 107 cases | `c11aa8a` |
| CI determinism (runner/Python/ShellCheck pins, concurrency) | `4fa28d9` |
| Routing harness + fixture ids/allowed_companions | `0455277` |
| Docs sync + v2 "38 skills" erratum | `8b80f4d` |
| Routing baseline results | `870ee46` |
| repository-cleanup disambiguation + recall pin (measured misroute) | see below |

Work branch note: implementation happened on `claude/hook-testing-threat-audit-6f94e3` (this
worktree's branch), which supersedes the empty `claude/template-third-audit-192d32` recorded in
Phase 0 — commits exist only on the former.

## Validation evidence

- Hook suite: **107/107** — in the worktree *and* from a clean `git archive HEAD` export.
- Installer end-to-end: green (both environments).
- ShellCheck: **clean** with the exact CI invocation (v0.10.0, `-x -P .claude/hooks`, now
  including `claude-init.sh` and the routing seed script).
- Ask-JSON: every ask branch parsed with `jq -e` including quote/tab/newline/backslash/Thai/
  300-char basenames (PFH1–6) and all dependency asks (ASK1–17).
- Catalog: 37/37; workflow YAML parses; fixture grew to 20 cases.
- **CI executed remotely and passed.** The owner cleared the billing lock mid-cycle; the push of
  this branch produced the repository's **first real GitHub Actions execution** — every step
  green on a hosted runner:
  [run 29643662878](https://github.com/theptipteacharsripaitoon/claude-template/actions/runs/29643662878).
  The Phase 1 statement "no pushed run has ever executed" is therefore obsolete as of 2026-07-18.

## Measured routing (previously UNMEASURED)

Baseline, 19 cases × 3 runs, seeded domain repos, headless `claude -p`, model `claude-sonnet-5`,
57/57 runs completed with zero errors (`tests/skills/results/routing-20260718-1221.jsonl`):

| Metric | Value |
|---|---|
| Primary recall | **0.902** |
| Precision | **0.939** |
| Conflict rate | **0.053** |
| No-load rate | **0.039** |
| Run-to-run stability | **0.895** (17/19 cases identical across all 3 runs) |

Findings: 16 of 19 cases routed perfectly 3/3 — including every review-cluster case, all
git-hygiene boundaries, both security cases, and the engine-specificity case (nothing loaded for
the PostgreSQL prompt, as intended). The **only conflict source** was `layout-root-mess`
("Organize this project - the root is a mess") loading `repository-cleanup` 3/3 — a stable
misroute traced to that skill's own trigger phrase "organize the project". The two airflow
authoring cases each dropped one run to no-load (3.9%) — recorded as variance; descriptions
unchanged (evidence inconclusive).

**Fix (smallest change):** removed "organize the project" from the `repository-cleanup`
description and added an explicit ownership pointer to `project-layout`; added fixture case
`cleanup-repo-recall` so the edited skill's own recall is permanently pinned. Verification
re-runs (same harness and model, fresh session window): `layout-root-mess` now loads
`project-layout` **3/3 with zero conflicts** (`routing-20260718-1652.jsonl`; baseline was a 3/3
misroute), and `cleanup-repo-recall` loads `repository-cleanup` **3/3**
(`routing-20260718-1656.jsonl`) — the misroute is gone and the edited skill's own recall did not
degrade. With this single conflict source eliminated, the only remaining baseline misses are the
two airflow no-load runs (variance, unchanged by design).

## Environment artifacts documented (not repo defects)

- msys jq 1.6 exits **0** on empty input with `-e` (spec says 4) — the `t_ask` helper now guards
  with a non-empty check so a silent allow can never masquerade as a valid ask.
- Windows MAX_PATH: seeding/`check_catalog.py` fail under ~260-char roots (long-path `git add`,
  `os.path.exists`); short-path exports and CI are unaffected (`core.longpaths` set in seeds).

## Re-score (same rubric)

| Category | Weight | Before | After | Basis for change |
|---|---:|---:|---:|---|
| Technical correctness | 15% | 7 | 9 | all confirmed defects fixed test-first; semantic-equivalent limits documented |
| Skill trigger quality | 15% | 7 | 8.5 | measured 19×3: recall .902 / precision .939; misroute fixed + recall-pinned |
| Hook correctness | 15% | 7 | 9 | 107-case matrix, jq-valid asks, documented exits verified |
| Conflict avoidance | 10% | 8 | 9 | measured conflicts had one source; eliminated and re-verified |
| Safety & permissions | 10% | 8 | 9 | §2 fully enforced (remove/upgrade asks); restore reconciliation documented |
| Testing & evaluation | 15% | 7 | 9 | suite ×2.1, live routing harness + committed results, **CI green remotely** |
| Context efficiency | 5% | 9 | 9 | unchanged |
| Team usability | 5% | 9 | 9 | docs synced to implementation |
| Maintainability | 5% | 9 | 9 | pinned CI, table-driven matrix, shared helpers |
| Public-template readiness | 5% | 6 | 7 | CI green + accurate docs; LICENSE/tag/profiles remain owner/roadmap |

**Overall: 7.6 → 8.8.** The 9.0 gate items are met (no known P0, strict-shell clean, valid JSON,
regression coverage, repeated routing results, deterministic CI, bootstrap failure-safety,
accurate reports, no repository-caused CI failure), but trigger quality is scored at its
*measured* values and public readiness still awaits owner decisions (LICENSE, version tag) —
so the overall stays below 9. The 9.5 bar additionally requires ≥95% measured precision, a
license, and distribution readiness; not claimed.

**Remaining owner actions:** choose a LICENSE; tag a release after merge; optionally enable the
GitHub template flag. (The billing lock is resolved.)

