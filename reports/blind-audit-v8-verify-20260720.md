# v8 Implementation & Verification Report — 2026-07-20

Implementation of the approved v8 remediation plan
([reports/blind-audit-v8-plan-20260720.md](blind-audit-v8-plan-20260720.md)).
Every confirmed P1 and the high-value P2/P3 findings from both external
documents were fixed with failing-first tests where the change was behavioral.

**No git commit, push, PR, or CI/settings change was made** — all edits are in
the working tree for review. `.github/workflows/test.yml` was deliberately not
touched (protected CI; owner-gated).

## 1. Baseline

- Branch: `claude/template-blind-audit-12a506` (worktree); parent commit `8edb40b`.
- Platform: Windows 11 / MSYS2, bash 5.2.15, jq 1.6, sha256sum (coreutils 8.32),
  npm 9.5.1, node v18.16.0, ShellCheck v0.10.0 (dockerized).

## 2. Change summary (by behavior, not file count)

| Area | Behavior change |
|---|---|
| **Bootstrap (P1)** | `claude-init` now fails closed: profile transform → env-key assertion → version stamp → manifest gen (captured `sha256sum`, exit propagated) → blank-hash reject → `sha256sum --check --quiet` → atomic `mv`, all in one checked chain. Any failure cleans staging and returns non-zero with no success line. |
| **Drift report (P1)** | `claude-template-status` refuses a blank-hash manifest instead of reporting every file "unchanged". |
| **Token logging (P1)** | web-security skill no longer authorizes logging a token prefix; recommends a non-secret correlation id. |
| **Multiline rm (P2/A1)** | `block-destructive` normalizes line-continuations + CR/LF to spaces on a match-only copy; the 5 bypass shapes now deny, harmless multiline still allows. |
| **Fail-open observability (P2/A4)** | Missing-jq and malformed-JSON fail-open paths log a `FAIL_OPEN` row (payload withheld) via `lib.sh::log_fail_open`; exit semantics unchanged (still allow). |
| **Stop-hook hang (P2/A5)** | `verify-done` detects watch/serve scripts and skips them; every check bounded by `CLAUDE_VERIFY_TIMEOUT_S` (default 300 s); timeout reported as failure, not hang. |
| **Hook README (P2)** | SQL-prose bounded guarantee rewritten to match the hook's actual (deliberate) DENY of prose `DROP`/`TRUNCATE`. |
| **Action boundaries (P2)** | testing skill: quarantine requires ticket + running lane + deadline, never skip-to-green. verification skill: `npm ci` is approval-gated; failure protocol proposes (not auto-executes) rollback. |
| **Session harness (P2)** | Now asserts must_load/must_not_load/tier/artifact-path/semantic per scenario and exits non-zero on any violation; scoring factored to `score_session.py` with 12 offline unit tests; ask-tier scenario added; `.`-globs removed. |
| **Standards (P2/P3)** | NIST 800-63B rev 4 password length; RFC 8594 (`Sunset`) vs RFC 9745 (`Deprecation`); `X-RateLimit-*` = vendor convention. |
| **Universal claims (P3)** | git-mv, components-fetch, readiness deps, CPU alerting, mobile scroll, submit confirmations, Docker HEALTHCHECK — all recast as conditional with stated exceptions. |
| **Windows portability (P3/A3)** | verify-done Node fixtures use `node -e "process.exit(N)"` (shell-independent). |
| **New enforcement** | `tests/policy_consistency.py` statically gates the token-prefix, auto-revert, skip-to-green, and hook-README-SQL invariants so the conflicts cannot silently return. |

Files touched: `claude-init.sh`; `.claude/hooks/{block-destructive,lib,verify-done}.sh`,
`.claude/hooks/README.md`; `.claude/skills/{web-security,api-design,testing,
verification,git-hygiene,frontend-layout,observability,ui-review,docker}/SKILL.md`;
`tests/hooks/{corpus.jsonl,run-tests.sh}`, `tests/installer/run-tests.sh`,
`tests/sessions/run-sessions.sh`; new `tests/policy_consistency.py`,
`tests/sessions/{score_session.py,test_score_session.py}`; `CHANGELOG.md`,
`HOW-TO.md`, `SUPPORT.md`.

## 3. Tests run — exact results

| # | Check | Command | Result |
|---|---|---|---|
| 1 | Installer failure-injection + suite | `bash tests/installer/run-tests.sh` | **`RESULT: pass=45 fail=0`** (37 prior + FI1–FI8; FI1–FI7 were RED before the fix) |
| 2 | Hook regression suite | `bash tests/hooks/run-tests.sh` | **`pass=303 fail=0`** (291 prior + BD_ML1–7, FO1–3, VD13–14) |
| 3 | Hook corpus gate | `bash tests/hooks/run-corpus.sh` | **`contract_violations: 0`** over 208 scored (215 rows incl. ML-001–010); dangerous-recall 1.0, legit-allow 1.0, ask-accuracy 1.0; ideal-label fp=7 fn=6 (all documented OOS) |
| 4 | ShellCheck v0.10.0 (`-x -P .claude/hooks`) | dockerized, all `.sh` incl. new/edited tests | **exit 0**, zero findings |
| 5 | Skill catalog consistency | `python tests/skills/check_catalog.py` | **`ALL CHECKS PASS`** (37 skills) |
| 6 | Policy-consistency gate (new) | `python tests/policy_consistency.py` | **`ALL CHECKS PASS`** (token-prefix, auto-revert, skip-to-green, hook-README-SQL) |
| 7 | Session scoring unit tests (new) | `python tests/sessions/test_score_session.py` | **`12/12 passed`** |
| 8 | Routing offline scoring | `python tests/skills/routing/test_run_eval.py` | **`15/15 passed`** |
| 9 | Routing results consistency | `python tests/skills/routing/test_results_consistency.py` | **`ALL CHECKS PASS`** (unchanged; no live fixtures edited) |
| 10 | Python compile | `python -m py_compile` (all changed .py) | **OK** |
| 11 | Markdown link check | `python tests/check_links.py` | **`ALL CHECKS PASS`** (69 files) |
| 12 | install.sh embedded self-tests | `bash .claude/hooks/install.sh` | **green** (17 sub-tests) |

### Failing-first evidence (proves the fixes are real)

- **Installer FI1–FI7**: RED against the unfixed `claude-init.sh` (`pass=38 fail=7`,
  each "expected non-zero exit … got 0"); GREEN after the fail-closed rewrite.
- **Corpus ML-001–005**: 5 contract violations against the unfixed hook; 0 after
  the multiline-normalization patch.
- **policy_consistency**: 4 failures against the unfixed skills/README (token
  prefix, `git revert`, "exclude from blocking CI gate", "documentation text …
  stays allowed"); 0 after the edits.

## 4. Checks NOT run / unavailable (declared honestly)

- **Live routing evaluation (`run_eval.py`)** — needs an authenticated Claude
  Code CLI + real model calls. **Not run.** No live fixtures were edited, so the
  committed routing results and their consistency gate remain valid; the routing
  depth-expansion recommendation from the review is **not** implemented in this
  cycle (it requires a matching live run to avoid fabricated results).
- **Live realistic-session run (`run-sessions.sh`)** — needs authenticated
  `claude`. **Not run live.** The harness was rewritten to assert, and its
  scoring is fully unit-tested offline (12/12), but the committed
  `sessions-20260720.jsonl` predates the assertion schema. A fresh authenticated
  run is required to regenerate it — **pending**, recorded here rather than
  fabricated.
- **Full git-history secret scan** — not run (no history-scanning tooling
  invoked); a targeted working-tree secret grep found only the known synthetic
  fixtures.
- **Windows CI lane** — not added (protected CI, owner-gated). The fixture
  portability fix removes the npm-shell dependence that caused the 289/291 split;
  a dedicated Windows CI lane remains an owner decision.
- **macOS / WSL2** — unchanged; still "expected, not measured" per SUPPORT.md.

## 5. Finding adjudication → disposition

| Ref | Finding | Disposition in v8 |
|---|---|---|
| P1-a/b | Bootstrap false-success (jq / sha256sum) | **FIXED** + FI1–FI8 |
| P1-c | Token-prefix logging | **FIXED** + policy_consistency |
| A1 | Multiline rm bypass | **FIXED** + corpus ML + BD_ML |
| A4 | Fail-open unobservable | **FIXED** + FO tests |
| A5 | Stop-hook watch hang | **FIXED** + VD13/VD14 |
| P2-b/c/d | testing/verification action boundaries | **FIXED** (wording + policy_consistency) |
| P2-e | Session evidence shallow | **FIXED** (assertions + offline scorer); live rerun pending |
| P2-g | Hook README SQL contradiction | **FIXED** + policy_consistency |
| P2-h/i/j | NIST / RFC / X-RateLimit | **FIXED** |
| A2 | `find -delete` prose false positive | **Accepted as documented** — the hook README already frames unanchored `find … -delete` as a conservative false positive; consistent with the SQL-prose stance. Not changed (anchoring it risks a real-command miss); noted, not "fixed". |
| A3 | Windows 289/291 | **FIXED** (portable fixtures) — exact 289 not reproduced on this host; root cause (npm script-shell) removed |
| P3-1 | Universal claims | **FIXED** (calibrated) |
| P2-f routing depth | Shallow routing fixtures | **DEFERRED** — needs live run; not fabricated |
| P3-2 public readiness | template flag / release / branch protection / report index | **OWNER-GATED** — untouched |

## 6. Remaining risks & owner-gated actions

- **Session results file is stale vs the new harness schema** until an
  authenticated live run regenerates it. The harness + offline scorer are
  correct and tested; the committed evidence is not yet refreshed.
- **CI does not yet run the two new test files** (`policy_consistency.py`,
  `test_score_session.py`) — adding those steps means editing
  `.github/workflows/test.yml`, which is owner-gated. Recommend the owner add:
  `python tests/policy_consistency.py` and
  `python tests/sessions/test_score_session.py`.
- **Routing depth expansion** (≥2 paraphrases + 1 hard negative per skill) is a
  separate live-run effort.
- **Public-template controls** (template-repo flag, first release tag, branch
  protection, secret-scanning/push protection, historical-report index) remain
  owner actions.

## 7. Fixed-rubric score (v8 tree)

Same 10-category rubric the external review used. Score reflects the current
working tree, and honors the prompt's ceiling rules.

| Category | Weight | v7 (ext. review) | v8 | Basis |
|---|---:|---:|---:|---|
| Technical correctness | 15% | 7.6 | 8.8 | Bootstrap now fails closed (8 injections green); multiline bypass closed; still one accepted prose false positive |
| Skill trigger quality | 15% | 8.3 | 8.3 | Unchanged — routing depth deferred (no live run); descriptions not degraded |
| Hook correctness | 15% | 8.8 | 9.2 | Multiline closed, fail-open observable, README matches behavior; corpus 0 violations |
| Conflict avoidance | 10% | 7.4 | 8.7 | Token/quarantine/npm-ci/revert conflicts reconciled + statically gated |
| Safety & permissions | 10% | 8.0 | 8.6 | Fail-open auditable; revert now proposed not auto-run; token never logged |
| Testing & evaluation | 15% | 8.1 | 8.7 | +FI/ML/FO/VD/policy/session-scorer tests, all failing-first; live session rerun still pending |
| Context efficiency | 5% | 7.3 | 7.3 | Not addressed this cycle (deferred until after correctness, per plan) |
| Team usability | 5% | 7.7 | 8.2 | Bootstrap trustworthy; new env var documented; profiles unaffected |
| Maintainability | 5% | 7.9 | 8.3 | Shared fail-open helper + offline scorer + policy gate reduce drift |
| Public-template readiness | 5% | 7.4 | 7.6 | Docs updated (SUPPORT/HOW-TO/CHANGELOG); release/repo controls still owner-gated |
| **Total** | 100% | **7.98** | **≈8.5** | |

**Claimed: ~8.5 / 10.** Per the prompt's gates I do **not** claim 9.0: the
supported-platform live session rerun is pending and routing depth is
unexpanded. All confirmed P1s are closed and no supported suite is red. 9.5 is
explicitly out of reach this cycle (no deep per-skill routing, no live session
evidence, no full-history scan, no release/CI controls).

## 8. Reproduction

Every result above reproduces from a clean checkout of this branch:
`bash tests/installer/run-tests.sh`, `bash tests/hooks/run-tests.sh`,
`bash tests/hooks/run-corpus.sh`, `python tests/policy_consistency.py`,
`python tests/sessions/test_score_session.py`, `python tests/skills/check_catalog.py`,
`python tests/check_links.py`, and dockerized ShellCheck v0.10.0. The two P1
bootstrap injections reproduce with a PATH-shadow `jq`/`sha256sum` as described
in the plan doc §2.1.

---

*Implemented by the same session that produced the blind audit and v8 plan. No
external-review text was used as correctness evidence — each finding was
reproduced and each fix is pinned by a test that fails before it and passes
after.*
