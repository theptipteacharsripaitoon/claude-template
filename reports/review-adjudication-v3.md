# External-Review Adjudication v3

Adjudicates `external-review-v3.md` (OpenAI GPT-5.6 Thinking, reviewing merge `4df4566`)
against the independent audit in [claude-independent-audit-v3.md](claude-independent-audit-v3.md)
(committed first at `d5d2e01`) and executable evidence gathered in that audit.

Verdicts: **Confirmed** / **Partly confirmed** / **Rejected** / **Not reproducible** / **Obsolete** / **Subjective**.
A finding is not accepted because GPT-5.6 reported it, nor rejected because it criticizes Claude's work.

Convergence note: the external score (7.6) and the independent pre-change score (7.6) were
produced blind of each other and agree; the finding sets overlap almost completely.

## Adjudication table

| # | External finding | Verdict | Evidence |
|---|---|---|---|
| 1 | `((RAN++))` under `set -e` kills strict Stop verification before any checker runs (Node/Python/Rust/Go) | **Confirmed — audit D1, rated P0 here** | Independently found before opening the review. Repro: `bash -c 'set -euo pipefail; RAN=0; ((RAN++)); echo alive'` → exit 1, no output. End-to-end: Node repo with passing `test` script + `CLAUDE_VERIFY_BLOCK=1` → prints the banner then **exit 1, zero checks run** — neither documented exit 0 (pass) nor 2 (fail), so the harness sees a hook *error*, not a decision. Sites: `verify-done.sh` lines 84, 87, 90, 101, 104, 107, 111, 112, 115, 116. External rates P1; upgraded to **P0** because an advertised enforcement mode is 100 % inoperative with wrong exit semantics. |
| 1a | Test suite misses it: blocking mode tested only with no discoverable checker | **Confirmed** | `run-tests.sh` VD5 is the only `CLAUDE_VERIFY_BLOCK=1` case and uses a repo with no ecosystem files, which skips every increment. |
| 2 | `protect-files.sh` interpolates the raw filename into ask-JSON via `printf`; hostile names break it | **Confirmed — audit D3** | Line 117. Measured: basenames containing `"`, tab, or newline → **invalid JSON** (fails `jq empty`, 3/3); the ask is silently dropped. Nuance vs the external text: Thai and *some* backslash sequences still parse (a lone `\b`-style sequence is a valid JSON escape → silent corruption rather than parse failure; a trailing backslash is invalid). Same defect class either way. |
| 2a | `t_ask` validates by substring, not by parsing | **Confirmed** | `run-tests.sh:35` — `grep -qF '"permissionDecision":"ask"'`. Will be replaced with `jq -e` structural validation (event name + decision fields). |
| 2b | `block-destructive.sh` ask-JSON needs the same treatment | **Partly confirmed** | Line 108 uses the same `printf` idiom, but interpolates the matched **pattern** — a hardcoded array literal an attacker cannot author, and no current pattern contains JSON-breaking characters → no live vulnerability (verified: ask output parses). Converted anyway so a future pattern edit cannot silently break the JSON. |
| 3a | SQL matching is case-sensitive; lowercase `drop/truncate/delete` pass | **Confirmed — audit D2** | Measured: `psql -c 'drop table users'`, `truncate table events`, `delete from users;`, `Drop Table users` all **ALLOW**; uppercase forms deny. `grep -qE` at `block-destructive.sh:86` with uppercase-only patterns (lines 50–52). |
| 3b | `rm` variants `-fr`, `-r -f`, `--recursive --force` bypass | **Confirmed — audit D2** | Measured ALLOW for all three against `/`; root cause: patterns hardcode `-rf?` (lines 24–27). Audit additionally found quoted `rm -rf "$HOME"` bypasses (D6) — same fix family. `git clean -df` also bypasses (f-before-d regex, line 45). |
| 3c | Restore commands (`npm ci/install`, `pnpm/yarn/bun install`, `pip install -r`, `uv sync`, `poetry/composer/bundle install`) "potentially uncovered" | **Rejected as defect (policy reconciliation)** | Measured: all ALLOW — **by design**. Restoring an already-committed manifest/lockfile is not a new supply-chain decision; requiring approval for every `npm ci` would make the hook unbearable and push users to blanket overrides. CLAUDE.md §2 "install, upgrade, or remove dependencies" is read as *dependency-set mutation*. The deliberate `[^-]` exclusion that allows `pip install -r`/`-e` is part of this. Reconciliation recorded in audit §7. |
| 3d | Remove/uninstall and update/upgrade forms never ask | **Confirmed — audit D5** | Measured: `npm uninstall`, `pnpm/yarn/bun remove`, `pip uninstall`, `poetry/cargo/composer remove`, `npm/yarn/cargo/poetry/bundle/composer update|upgrade` all ALLOW. §2 names upgrade and remove explicitly. Also confirmed via 3c's `[^-]` rule: `pip install -U/--upgrade pkg` bypasses the ask. `go get` (mutates `go.mod`) uncovered. All become ASK (not deny), preserving the restore ALLOWs. |
| 3e | A structured command validator would beat the regex list | **Subjective — not adopted** | The regex table is small, greppable, and now pinned by a regression matrix; a parser is more code to trust in a security path. CLAUDE.md §18 already documents that hooks are pattern-specific, not semantic. |
| 4 | CI never executed; billing lock | **Confirmed (owner action)** | Latest `main` run: job completed in 3 s, `runner_name: ""`, **empty `steps` array** — rejected before scheduling. No repository change can fix it. All workflow steps pass locally from the LF export (suite 50/50, installer green, ShellCheck v0.10.0 clean, catalog 37/37). |
| 4a | Workflow non-determinism: floating `ubuntu-latest`, unpinned Python, unpinned ShellCheck, no `concurrency` | **Confirmed** | All four verified in `test.yml`. Fix: `ubuntu-24.04`, SHA-pinned `actions/setup-python` + pinned Python, pinned ShellCheck binary verified by SHA-256, `concurrency` with cancel-in-progress. Cannot be proven green remotely until billing clears — recorded, not claimed. |
| 5 | Hooks lack explicit `timeout` | **Partly confirmed** | `timeout` (seconds, per-command) is valid per current official hook docs; default is 600 s. Adopted for the four fast PreToolUse validators (10 s). **Not** applied to `verify-done.sh`: blocking mode legitimately runs full test suites — a short timeout would break the very mode this cycle fixes. The external recommendation as written would be harmful there. |
| 5a | Prefer exec-form hook commands | **Rejected (docs)** | The current official hooks schema documents `{"type":"command","command":"<string>","timeout":<seconds>}`; no argv/exec form exists in the schema consulted for the audit. Nothing to adopt. |
| 6 | Secret scanner silently allows marker-bearing secret shapes | **Rejected (design preserved; docs added)** | Not silent: every fixture skip emits `log_warn` to stderr **and** `.claude/logs/hooks.log` (`scan-secrets.sh:105`) — an auditable trail. Value-scoped markers are the documented fixture escape hatch the hook itself instructs users toward; switching to ask would prompt on every legitimate fixture write, and hard-deny would break test authoring entirely. The two real bypass classes (line-scoped marker, first-match-only) were fixed in cycle 2 and are regression-tested (SS9/SS10). Residual risk (a real secret whose value happens to contain `EXAMPLE` etc.) is documented in the hooks README along with the detection boundary (inserted content, not the reconstructed file) and the §7 recommendation to run gitleaks/detect-secrets as a second layer. |
| 7 | Routing evaluation too small; fixture not executable; `evaluated_runs` empty; binary format | **Confirmed — audit §13** | Fixture header says "not auto-executable"; `evaluated_runs: []` at `trigger-cases.yaml:82`. The audit built a live harness (seeded per-case repos, headless `claude -p` stream-json, Skill-event extraction) and validated it on a smoke run, but the account usage limit blocked the 19×3 baseline mid-audit. This cycle: land the harness in `tests/skills/`, add `allowed_companions` to the fixture (companions don't count against precision; `must_not_load` hits count as conflicts), run 19×3, store JSONL, append `evaluated_runs`. |
| 8 | `claude-init.sh` unsafe names + not failure-atomic | **Confirmed — audit D4** | Measured: `../escape` escapes the destination root; missing template `CLAUDE.md` still reports success (unchecked `cp`; only `.claude` validated); failed installer leaves a half-built project; failure paths leave the caller `cd`'d into the wreckage. Fix: validate name as one safe path component, validate all required sources, build in a temp sibling, install there, atomically `mv` into place, clean up on failure. On-success `cd` into the project is intentional UX and kept. |
| 9a | v2 report says "38 skills", repo has 37 | **Confirmed** | `claude-independent-audit-v2.md:137`. Corrected in place with a bracketed erratum note (historical finding text otherwise untouched); catalog gate confirms 37. |
| 9b | "50/50 pass" hides the untested strict-mode path | **Confirmed** | Same evidence as 1a. New real-checker tests close it. |
| 9c | Live routing results not in `evaluated_runs` | **Confirmed** | See 7. |
| 9d | v2 Testing score 8.5 too high | **Superseded** | Independent v3 rescored Testing at 7 before reading the review. |
| 10 | No LICENSE / no tag / no profiles / no update propagation / template flag unverified | **Confirmed (status), owner actions** | LICENSE choice is explicitly reserved to the owner (per instruction, not selected). Version tag = owner release step after merge. Install profiles and template-update propagation stay roadmap — adding them now is complexity in service of a score. |

## Phase 3 — Improvement decisions

**Implement (evidence-backed net improvements):**

| Change | Reason (valid-reason list) |
|---|---|
| `verify-done.sh`: strict-safe counters (`RAN=$((RAN+1))`); `command -v` guards on cargo/go so a missing toolchain reports "not verified" instead of a fake FAILED; regression tests with real passing + failing checkers, polyglot, and missing-binary | 1, 2 (reproducible P0; unexpected hook exit) |
| `protect-files.sh` + `block-destructive.sh`: emit ask-JSON via `jq -n --arg`; `t_ask` upgraded to parse with `jq` and assert event/decision fields; hostile-basename regressions (quote, trailing backslash, tab, newline, Thai, spaces) | 3 (valid structured output) |
| `block-destructive.sh`: case-insensitive destructive matching; `rm` recursive-flag matcher covering `-fr`, split `-r -f`, `--recursive`, capital `-R`, quoted `"$HOME"`; order-independent `git clean` f+d; regression matrix rows | 5 (measured false negatives) |
| `block-destructive.sh`: ASK patterns for dependency remove/uninstall and update/upgrade (incl. `pip install -U/--upgrade`, `go get`); restore forms stay ALLOW with pinning tests | 6 (align enforcement with §2) |
| `claude-init.sh`: name validation, full source validation, temp-sibling build, atomic rename, failure cleanup, caller cwd preserved on failure; regression tests for traversal/missing-file/installer-failure/atomicity | 8, 11 (generated-project safety; failure atomicity) |
| `.claude/settings.json`: `"timeout": 10` on the four PreToolUse validators (verify-done deliberately left at default) | 7 (current-docs compatibility hardening) |
| CI: `ubuntu-24.04`, `concurrency` + cancel, SHA-pinned `setup-python` + pinned Python, ShellCheck v0.10.0 pinned by SHA-256 | 10 (deterministic CI) |
| Routing: land seed+run harness in `tests/skills/`, add `allowed_companions` to fixtures, run 19×3, store machine-readable results, fill `evaluated_runs`, report measured precision/recall/conflict/no-load/stability | 9, 13 (measured routing; automated validation) |
| Docs: hooks README (new patterns, ask tiers, timeouts, secret-scanner boundary + second-layer note), CHANGELOG, v2 "38 skills" erratum, post-implementation sections in both v3 reports | 12 (docs agree with implementation) |

**Preserve (reject change; current behavior is better or claim wrong):**

- Restore-command ALLOWs (3c) — deliberate policy reading; asking on every `npm ci` degrades the hook to noise.
- Regex list vs command parser (3e) — simpler, now matrix-pinned.
- Secret-scanner marker semantics (6) — value-scoped skip + warn + log is the right fixture path; documented instead of changed.
- Exec-form hooks (5a) — not in the documented schema.
- `verify-done` timeout — deliberately not set (see 5).
- `find … -delete` project-local denies — mild FP, deny-safe, override exists (audit §17).
- Windows working-tree CRLF ShellCheck noise — a checkout artifact; committed LF content is what CI lints; not "fixed".

**Owner actions (no repository fix possible):** clear the GitHub billing lock, then re-run Actions; choose a LICENSE; tag a release after merge; optionally enable the GitHub template flag.

---

## Implementation outcome (appended after Phases 4–5)

Every accepted item above shipped and validated; details and evidence live in the
post-implementation section of [claude-independent-audit-v3.md](claude-independent-audit-v3.md).

| Accepted item | Outcome |
|---|---|
| verify-done strict-safe + toolchain guards | Fixed (`b259fd3`); VD6–VD10 green incl. real pass/fail checkers, polyglot, missing binary |
| jq-built ask JSON (both hooks) + jq-validating tests | Fixed (`d13809e`, `679ee76`); PFH1–6 hostile-basename cases green |
| rm/clean/SQL coverage + dependency remove/upgrade asks | Fixed (`d13809e`); BD20–35 + ASK4–17 + AL1–11 pin deny/ask/restore behavior |
| claude-init atomicity + name safety | Fixed (`11795d9`); BOOT4–8 green |
| settings.json validator timeouts | Added (`fc1f171`); SET3 gate |
| CI determinism | Landed (`4fa28d9`) — and the owner cleared the billing lock mid-cycle: run 29643662878 is the first real Actions execution, all steps green |
| Routing harness + repeated measurement | Landed (`0455277`, `870ee46`): 19×3 baseline (recall .902 / precision .939 / conflict .053 / stability .895); single stable misroute fixed via repository-cleanup description disambiguation with a new recall-pinning fixture case |
| Docs sync + "38 skills" erratum | Landed (`8b80f4d`) |

Rejected items remained unchanged, as adjudicated. Score movement: 7.6 → **8.8** (rubric table in
the audit report's post-implementation section).
