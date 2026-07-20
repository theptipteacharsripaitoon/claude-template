# v8 Investigation, Reproduction & Written Plan — 2026-07-20

Response to the v8 remediation prompt. **Phase 1 only: investigation, reproduction, adjudication, and a written plan for approval.** No files were edited, no commits created, no dependencies installed, no CI touched, no remote state changed.

Two source documents were supplied by the user:
1. `claude-template-v7-independent-review.md` — external independent review (7.98 → 8.0/10).
2. `claude-template-v8-additional-session-context.md` — secondary evidence with reported A1–A5 items.

An earlier read-only blind audit I completed on the same commit is preserved at [reports/blind-audit-20260720.md](reports/blind-audit-20260720.md); it did **not** run the failure injections and did not open either external file, so its 9.25 score is superseded by this document wherever the two disagree.

---

## 1. Baseline

| Item | Value |
|---|---|
| Repo | `theptipteacharsripaitoon/claude-template` |
| HEAD commit | `8edb40bbd68e6800fa2b97b9fa27ce887f392f6f` (main tip; merge of PR #15) |
| Branch | `claude/template-blind-audit-12a506` (worktree) |
| Working tree | clean apart from this planning doc + a corpus re-run summary |
| Platform | Windows 11 Home 10.0.26200 / MSYS2 mingw-w64 |
| Bash | 5.2.15(1)-release |
| Git | 2.41.0.windows.3 |
| jq | 1.6 (Anaconda Library) |
| sha256sum | GNU coreutils 8.32 |
| Python | Anaconda 3.x |
| npm | 9.5.1 |
| node | v18.16.0 |
| Docker | Desktop present (used for containerized ShellCheck) |

## 2. Reproductions performed

Every check ran against `8edb40b`.

### 2.1 P1 — Bootstrap false-success paths (external review §Findings)

**P1-#1 strict-profile `jq` failure — CONFIRMED**

Method: PATH-shadow `jq` that exits 77 **only** when its args contain `CLAUDE_VERIFY_BLOCK`; real `jq` passes through otherwise.

Result (disposable dir `/tmp/tmp.KDl4AQEhYA/projects/my-strict-app`):
- Shim announced its own injected failure to stderr.
- Function printed `✅ Project 'my-strict-app' bootstrapped … (profile: strict, template unknown)`.
- **Function exit code: `0`.**
- Project **published**.
- `.template-version`: `profile=strict`.
- `.claude/settings.json` `.env`: **`{}`** — `CLAUDE_VERIFY_BLOCK` missing.

The `strict` label is a lie; the Stop hook will run in reminder mode.

**P1-#2 manifest `sha256sum` failure — CONFIRMED (worse than reported)**

Method: PATH-shadow `sha256sum` that always exits 77 while echoing the failure to stderr.

Result (disposable dir `/tmp/tmp.kMnDlohsAk/projects/my-manifest-app`):
- Function exit code: `0`.
- Project **published**.
- `.template-manifest`: **53 rows / 53 with blank hashes / 0 with real hashes**.
- Running `claude-template-status` against the poisoned manifest returns
  `unchanged=53 locally-modified=0 missing=0` — because `"" == ""` for every file, the drift report **actively lies** rather than flagging drift.

The compounding harm (drift report validates a poisoned manifest) was not stated by the external review; I add it here.

### 2.2 A1 — Multiline destructive-command bypass — CONFIRMED (broader)

Method: JSON payload files with the dangerous byte sequence assembled at runtime (chr()) so the outer Bash tool call itself contained no `rm -rf /` literal. Hook run on `.claude/hooks/block-destructive.sh` (CRLF-stripped).

| Payload | Verdict |
|---|---|
| `rm -rf /` (one line, baseline) | DENY |
| `rm -rf \<LF>/` (bash line continuation) | **ALLOW** |
| `rm -rf<LF>/` (bare LF, no space) | **ALLOW** |
| `rm -rf <LF>/` (bare LF w/ trailing space) | **ALLOW** |
| `rm -rf<CRLF>/` (Windows line ending) | **ALLOW** |
| `rm -r<LF>-f /` (split inside flag cluster) | **ALLOW** |
| `ls -la<LF>src/` (harmless multiline) | ALLOW |

Root cause: `echo "$CMD" | grep -qiE "$PATTERN"` matches line-by-line (grep default). Any newline between `rm -rf` and its dangerous target breaks the match.

### 2.3 A2 — `find … -delete` prose false positive — CONFIRMED

| Payload | Verdict |
|---|---|
| `echo 'usage: find . -name X -delete'` | **DENY** |
| `git commit -m 'refactor: drop find -delete loop'` | **DENY** |
| `find . -name '*.tmp' -delete` (real) | DENY (correct) |
| `find . -name '*.tmp'` (neutral) | ALLOW |
| `grep -R -delete /etc` (wrong tool) | ALLOW |

The pattern `find[[:space:]].*-delete` (block-destructive.sh:70) is unanchored substring. This is safety-conservative but contradicts the bounded-guarantee prose (see item 2.7).

### 2.4 A3 — Windows Git Bash VD6/VD8 fixture failure — PARTLY CONFIRMED

- On **this** host (npm 9.5.1, `script-shell=null`, node v18.16.0): full suite `pass=291 fail=0`; VD6/VD8 both PASS.
- Reviewer reported `pass=289 fail=2` on a different Windows config.
- Root cause is portability of `"test": "exit 0"` under a shell-config-dependent npm: same fixture, different environment, different outcome.
- **Finding is real** (the fixture is npm-shell-config-fragile); **exact failure not reproducible** on my box. A `node -e "process.exit(0)"` fixture removes the shell dependency entirely.

### 2.5 A4 — Malformed-input fail-open is unobservable — CONFIRMED

| Input | Exit | stderr | Log entry |
|---|---:|---|---|
| Garbage JSON to `block-destructive` | 0 | *(empty)* | **none** |
| Garbage JSON to `protect-files` | 0 | *(empty)* | **none** |
| Garbage JSON to `scan-secrets` | 0 | *(empty)* | **none** |
| Valid JSON, `PATH` without `jq` (`block-destructive`) | 0 | "Hook misconfiguration: jq not installed" | **none** |

The audit log records BLOCK / WARN / OVERRIDE / ASK — never fail-open. A silent bypass leaves zero trace.

### 2.6 A5 — Stop-hook watch-mode hang — CONFIRMED

Method: staged a repo with `"test": "node -e \"setTimeout(()=>{},20000)\""` and dirty a code file; ran `verify-done.sh` under `CLAUDE_VERIFY_BLOCK=1` with an external `timeout 8s`.

- The hook ran until `timeout` killed it (exit 124, wall 8 s).
- `.claude/settings.json` `.hooks.Stop[0].hooks[0]` has **no `timeout` field** (deliberately, per the hook comment).
- A real `vitest --watch` / `jest --watch` would hang the Stop hook indefinitely with no user-visible signal.

### 2.7 P1 — Token-prefix logging conflict — CONFIRMED

- `CLAUDE.md:138`: "Never log secrets, auth headers, session tokens, full request/response bodies, or PII."
- `web-security/SKILL.md:155`: "**Mask in logs:** show last 4 digits, show token prefix only."

A model consulting the more-specific web-security skill will produce a log line containing a partial credential.

### 2.8 P2 — Testing/verification action-boundary conflicts — CONFIRMED

- `CLAUDE.md §2`: "Disable, skip, or weaken tests, type checks, or lint rules to make CI green" — forbidden.
- `CLAUDE.md §10`: "Do not delete, skip, `xit`, or `@skip` tests" — forbidden.
- vs `testing/SKILL.md:135`: "Quarantine immediately — mark as known-flaky in the tracker, **exclude from blocking CI gate**."

- `CLAUDE.md §2`: dependency install/upgrade/remove requires explicit user confirmation.
- vs `verification/SKILL.md:38`: `npm ci` listed as routine verification command.

- `verification/SKILL.md:51`: automatic `git revert <commit>` inside the failure protocol.
- `verification/SKILL.md:53-54`: "Do NOT invent additional fixes. Do NOT continue. Wait for approval." — but the revert has already happened. History mutation precedes approval.

### 2.9 P2 — Hook README SQL-prose contradiction — CONFIRMED

- `hooks/README.md:40`: "documentation string that merely mentions `DROP TABLE` is blocked too. False positives are cheaper …"
- `hooks/README.md:227-231` (bounded guarantee): "Documentation text mentioning a statement stays allowed — that boundary is deliberate."

| Payload | Verdict |
|---|---|
| `echo "DROP TABLE users;"` | **DENY** (matches L40 claim, contradicts L230) |
| `echo "TRUNCATE TABLE sessions"` | **DENY** (matches L40, contradicts L230) |
| `echo "DELETE FROM orders"` (no `;`) | ALLOW (matches L230 — DELETE has a nuance the other two lack) |
| `git commit -m 'drop the DROP TABLE stmt'` | **DENY** |

L40 is the accurate description; L227-231's blanket "prose stays allowed" is false for DROP/TRUNCATE.

### 2.10 P2 — Standards refs — CONFIRMED (three items)

- `web-security/SKILL.md:22`: "Reject passwords <12 chars" — current NIST SP 800-63B rev 4 (2024) requires ≥15 chars for single-factor primary secret; ≥8 within MFA. One number for both contexts is stale.
- `api-design/SKILL.md:53`: `Deprecation: <date>` and `Sunset: <date>` both attributed to RFC 8594 — RFC 8594 (2019) covers `Sunset` only; `Deprecation` is specified in RFC 9745 (2025).
- `api-design/SKILL.md:129`: `X-RateLimit-*` presented alongside standards (Idempotency-Key, ETag, W3C traceparent) — this is a widespread vendor convention (GitHub/Stripe/Twitter); the active IETF draft uses un-prefixed `RateLimit-*` with different semantics.

### 2.11 P3 — Over-strong "universal" skill claims — CONFIRMED

- `git-hygiene/SKILL.md:35`: "history and rename detection depend on `git mv`" — Git records snapshots; rename detection is heuristic-based on content similarity, independent of how the move was performed.
- `frontend-layout/SKILL.md:37`: "Components never call `fetch`/`axios` directly" — breaks React Server Components, Next.js server component data-loading, TanStack Query.
- `observability/SKILL.md:114`: "The readiness check **must** verify … critical dependencies. (Canonical rule)" — contested; can amplify outages (one DB blip fans out to every pod).
- `observability/SKILL.md:128`: "CPU usage" listed as never-alert — sustained CPU saturation IS user pain via queueing latency / throttling.
- `ui-review/SKILL.md:32,34`: "horizontal scroll on mobile is a finding" / "Destructive actions confirm: delete/submit/pay flows show consequence + confirmation" — data grids / carousels legitimately scroll; save-buttons are submits that don't need confirmation.
- `docker/SKILL.md:26,90`: mandatory `HEALTHCHECK` conflicts with orchestrator-owned probes (k8s probes normally ignore image `HEALTHCHECK`).

### 2.12 Session evaluation depth — CONFIRMED

`tests/sessions/run-sessions.sh`:
- No `must_load`, `must_not_load`, or expected permission tier per scenario.
- s6 (`cleanup`) outcome regex = `.`; s10 (`conflicting`) outcome regex = `.` — matches any change.
- s1 (unit-test task) → 0 skills loaded (should have loaded `testing`).
- s3 (Airflow retries) → 0 skills loaded.
- s8 (Python rename) → 0 skills loaded (should have loaded `python-refactor`).
- s4: `outcome=no-artifact-change` but `claude_exit=0`.
- **All 9 rows: `asks=0`, `denies=0`** — the ask tier is not exercised anywhere.
- Scenario 9 (installer compat) is deliberately not-a-model-session; 9 model-driven rows, not 10.

### 2.13 Routing evidence depth — CONFIRMED

`tests/skills/trigger-cases.yaml`:
- 39 positive `must_load` cases + 6 no-load/observational (45 total).
- **35 of 37 skills have exactly 1 positive fixture** (only `airflow` and `git-hygiene` have 2).
- 7 skills never appear in any `must_not_load`: `agent-design`, `config-management`, `dependency-review`, `documentation`, `python-performance`, `release-readiness`, `ssis-review`.

`tests/skills/results/routing-20260720-083339-summary.json`: `cc_version: null`. Every row's `.cc_version` is also `null`. The fixture ledger's `evaluated_runs` entry supplies the CLI version by hand — transparent but weak automated provenance.

### 2.14 Full-suite re-runs (baseline confirmation)

- `bash tests/hooks/run-tests.sh` → `RESULT: pass=291 fail=0`.
- `bash tests/hooks/run-corpus.sh` → `contract_violations: 0`.
- `bash tests/installer/run-tests.sh` → `RESULT: pass=37 fail=0`.
- `python tests/skills/check_catalog.py` → PASS.
- `python tests/skills/routing/test_run_eval.py` → 15/15 PASS.
- `python tests/skills/routing/test_results_consistency.py` → PASS.
- `python tests/check_links.py` → PASS.
- ShellCheck v0.10.0 (`-x -P .claude/hooks`) over CRLF-stripped copies → exit 0, 0 findings.

## 3. Adjudication table

Legend: **C** confirmed live · **PC** partly confirmed · **R** rejected · **O** obsolete · **NR** not reproducible · **OG** owner-gated · **NEW** discovered in this reproduction and not in either source doc.

### Primary review (`claude-template-v7-independent-review.md`)

| Ref | Item | Adjudication | Evidence |
|---|---|---|---|
| P1-a | Bootstrap strict-profile jq false success | **C** | §2.1 |
| P1-b | Bootstrap manifest sha256sum blank hashes | **C** (worse) | §2.1 |
| P1-c | web-security authorizes token prefix vs CLAUDE.md §7 | **C** | §2.7 |
| P2-a | Windows Git Bash VD6/VD8 fixture failure | **PC** | §2.4 (fixture fragile; failure not reproduced on my box) |
| P2-b | testing skill quarantine ≠ CLAUDE.md §10 | **C** | §2.8 |
| P2-c | verification skill `npm ci` ≠ CLAUDE.md §2 | **C** | §2.8 |
| P2-d | verification skill auto-`git revert` ≠ approval flow | **C** | §2.8 |
| P2-e | Session evidence measures activity, not correctness | **C** | §2.12 |
| P2-f | Routing evidence too shallow for 9.5 claim | **C** | §2.13 |
| P2-g | Hook README SQL-prose contradiction | **C** | §2.9 |
| P2-h | NIST password rule stale | **C** | §2.10 |
| P2-i | RFC 8594 vs 9745 attribution | **C** | §2.10 |
| P2-j | `X-RateLimit-*` labelled as standard | **C** | §2.10 |
| P3-1 | Universal claims: git mv, components-never-fetch, readiness deps, CPU-never-alert, mobile scroll, HEALTHCHECK | **C** | §2.11 |
| P3-2 | Public-template hygiene: template-repo flag, secret scanning, first release, historical-reports index | **OG** | Owner-gated per prompt; no verification performed |
| Verdict | Independent-review score 8.0/10 | acknowledged; not carried forward | v8 will be rescored on the fixed 10-category rubric |

### Secondary session context (`claude-template-v8-additional-session-context.md`)

| Ref | Item | Adjudication | Evidence |
|---|---|---|---|
| A1 | Multiline destructive-command bypass | **C** (broader than reviewer example) | §2.2 |
| A2 | `find … -delete` prose false positive | **C** | §2.3 |
| A3 | Windows doc disagreement | **PC** | §2.4 (README OK; HOW-TO/hook-README emphasize WSL) |
| A4 | Malformed-input fail-open unobservable | **C** | §2.5 |
| A5 | Stop-hook watch-mode hang | **C** | §2.6 |
| Other-session 88/100 rubric | 88/100 score | not inherited | prompt explicitly says use v8 fixed rubric |
| Other-session "bootstrap is failure-atomic" | | **R** | §2.1 (P1-a and P1-b reproduce false success) |
| Other-session "all offline checks pass under Windows Git Bash" | | **PC** | true on my host; false on reviewer's — env-dependent |
| Other-session "no policy/skill conflicts" | | **R** | §2.7, §2.8, §2.9 |
| Other-session "safe for production as-is" | | **R** | contradicted by confirmed P1s |

### Discrepancy table (primary review vs. secondary session)

| Claim | Primary review | Secondary session | v8 disposition |
|---|---|---|---|
| Bootstrap atomicity | broken (P1) | atomic | Trust primary — reproduced live in §2.1 |
| Windows test suite result | `289/291` | `291/291` | Both real; env-dependent. Fix the fixture. |
| Policy/skill conflicts | multiple listed | none | Trust primary — reproduced in §2.7-2.9 |
| Multiline destructive bypass | not raised | raised (A1) | Trust secondary — reproduced in §2.2 |
| Production readiness | 8.0/10, "not yet" | 88/100, "strong" | Trust primary + reproductions: bootstrap P1s block "safe as-is" |

### NEW findings this reproduction

| ID | Finding | Severity | Location |
|---|---|---|---|
| NEW-1 | `claude-template-status` reports `unchanged=<count>` against a poisoned all-blank-hash manifest — the drift report actively validates a broken manifest | **P1** | claude-init.sh:305-319 |
| NEW-2 | The A1 multiline bypass extends beyond `\<LF>` continuation: bare LF, CRLF, and LF inside the flag cluster all bypass | **P2** | block-destructive.sh RM_REC pattern; grep matches per line |
| NEW-3 | scan-secrets hook fires on my *own* audit report writes when a fixture literal is embedded — proof the hook works on real editor writes (positive) | note | scan-secrets.sh (working as intended) |

## 4. Written plan (for approval before implementation)

> This is a large change: it will touch ≥6 files and modifies `.claude/settings.json`, hooks, skills, CLAUDE.md, and installer + tests. Per `CLAUDE.md §4` this requires the written plan below and my explicit halt.

### 4.1 Goal

Close every **confirmed P1** and the highest-value confirmed P2s from both external documents so that a fresh independent reviewer running the same failure injections on the v8 tip observes: bootstrap fails closed on every failure I injected in §2.1; the token-prefix conflict is gone; the multiline `rm -rf` bypass is closed; hook README ↔ corpus are consistent; and the session harness fails on missing required skills. Deliberately do **not** try for a 9.0+ score — optimize for behavior a separate reviewer can reproduce.

### 4.2 Approach (2–4 bullets per work item)

Grouped by change type, ordered by severity. Each item is scoped to the smallest edit that fixes it without collateral rewriting.

**P1-A — Bootstrap fails closed**
- Make profile-application, version-stamp, manifest-generation, manifest-verification, and final `mv` one checked chain (`&&` all the way through the case + jq-empty + manifest steps; on any failure `rm -rf "$tmp" && return 1`).
- Manifest generation: propagate `sha256sum` errors — either use `sha256sum "$file" > "$manifest"` (native format) or wrap the loop so a non-zero `$?` from `sha256sum` aborts. Then run `sha256sum --check --quiet "$manifest"` from inside the staging dir; on failure abort.
- Profile assertion: after strict/security-sensitive profile, re-parse settings.json and require the expected env keys exist; abort if not.
- Add a regression test matrix in `tests/installer/run-tests.sh`: for each of {jq, sed, date, find, sort, sha256sum, mv} inject a controlled failure (PATH-shadow shim), assert function exit ≠ 0, assert `DEST_ROOT/<name>` does not exist, assert no success line printed.

**P1-B — Remove token-prefix logging authorization**
- Rewrite `web-security/SKILL.md:154-156` to align with CLAUDE.md §7: no token/auth-header value ever hits a log, prefix or not. Recommend a non-secret correlation identifier (request ID, session record ID hashed with a server-side pepper).
- Add a static consistency test (`tests/policy_consistency.py` or extend `check_catalog.py`) that greps skills for phrases like "token prefix", "auth header prefix", "bearer prefix" and fails.

**P2-A — Multiline destructive-command bypass (A1)**
- In `block-destructive.sh`, normalize `$CMD` before matching: collapse backslash+LF (bash line continuation) to a single space, collapse remaining CR/LF/CRLF sequences to a single space. Do this on a **copy** used only for matching; leave the original for log/report.
- Do **not** apply a broad newline-to-space replacement without neighboring tests: add corpus rows for the six A1 shapes as DENY + a handful of harmless multiline shapes (`ls\nsrc/`, `echo 'line1\nline2'` in prose) as ALLOW. Test both directions before landing.
- CRLF-normalize the input string once at the top of the hook (independent of `.gitattributes`).

**P2-B — Malformed-input observability (A4)**
- Extend `lib.sh` with a `log_fail_open` helper that writes a `WARN`/`FAIL_OPEN` line naming the hook and reason (missing jq, unparseable JSON), never the payload itself.
- Wire the two current fail-open sites (`require_jq`, `json_get`'s implicit malformed-JSON branch) to call it. Do not change the exit semantics — still fail open, just make bypass observable.
- Add a test that pipes garbage JSON and asserts a WARN row appears in `hooks.log`.

**P2-C — Stop-hook hang (A5)**
- Detect long-running/watch-mode intent conservatively: if the `test` script matches `--watch|--serve|-w( |$)` regex, skip it and record "skipped (watch mode)" — treat as "no test discovered" (exit 0, honest report), never as pass.
- Add a `CLAUDE_VERIFY_TIMEOUT_S` env var (default 300 s) that wraps each `run_check` in `timeout ${CLAUDE_VERIFY_TIMEOUT_S}s` — a `124` exit is reported as "checker timed out" (a failure in blocking mode, an honest note in reminder mode).
- Do NOT add a `timeout` to the Stop entry in `.claude/settings.json` without owner approval (Claude Code's Stop hooks intentionally have no short timeout).

**P2-D — Testing/verification action-boundary conflicts**
- `testing/SKILL.md:135`: reword "exclude from blocking CI gate" to "quarantine requires an approved ticket, a still-running non-blocking quarantine lane, a removal deadline, and remains failure-visible; never a skip-to-green".
- `verification/SKILL.md:38`: annotate `npm ci` (and any restore commands) as "requires user-approval per CLAUDE.md §2 when they mutate node_modules — proceed only after the current-message approval or a documented pre-approval scope"; leave the entry present because lockfile-restore IS a legitimate verification step under approval.
- `verification/SKILL.md:47-54`: reorder to (1) STOP → (2) preserve state, diagnose read-only → (3) *propose* rollback with a diff preview → (4) execute rollback ONLY after approval. Never auto-execute `git revert`.
- Add a `tests/policy_consistency.py` check that asserts no skill body contains the phrases "exclude from blocking CI gate" or a `git revert` recommendation without a preceding "propose" / "with approval".

**P2-E — Hook README ↔ corpus consistency (SQL-prose)**
- Rewrite `hooks/README.md:227-231` to describe the actual behavior: "Documentation text mentioning DROP/TRUNCATE is blocked (conservative false positive; matches the L40 note). Documentation text mentioning a bare `DELETE FROM` (no terminator) stays allowed; client-wrapped or `;`-terminated forms are blocked."
- Add a documentation-consistency check: extract the L40 sentence and L227-231 promises, assert they don't contradict via a simple keyword compare in `tests/skills/check_catalog.py` or a sibling script.

**P2-F — Session evaluation gains real assertions**
- Extend `tests/sessions/run-sessions.sh` scenarios: each `run_scenario` gains explicit `must_load="…"`, `must_not_load="…"`, and a semantic check (e.g. for s1: assert the new test file's content contains `def test_` and imports the target function).
- Change s6 and s10 outcome regexes from `.` to specific paths (`CLEANUP-PROPOSAL.md` and `helpers.py` respectively).
- Exit non-zero when a required skill is missing OR the semantic check fails; keep `outcome=no-artifact-change` as a failure signal (currently silent).
- Move the "installer compat" step out of the model-session file; run it separately in CI.
- Add at least one scenario that triggers the ask tier (e.g. "add lodash to package.json" → protect-files ask, dependency ask).

**P2-G — Standards-refs corrections**
- `web-security/SKILL.md:22`: "Passwords: single-factor ≥15 chars (NIST SP 800-63B rev 4, 2024); within MFA context ≥8 is acceptable. State threat model." Preserve breach-list check and the 12-char text as a fallback rationale note.
- `api-design/SKILL.md:53`: split the citation — `Sunset: <date>` (RFC 8594, 2019); `Deprecation: <date>` (RFC 9745, 2025).
- `api-design/SKILL.md:129`: label `X-RateLimit-*` as "vendor convention (GitHub/Stripe/Twitter); the IETF `draft-ietf-httpapi-ratelimit-headers` uses un-prefixed `RateLimit-*` with different semantics — pick one style per API".

**P3-A — Windows fixture portability**
- Replace `"test": "exit 0"` fixtures in `tests/hooks/run-tests.sh` VD6/VD8 with `"test": "node -e \"process.exit(0)\""` (shell-independent). Same for the failure variant (`process.exit(1)`).
- Do NOT add a Windows CI lane without explicit owner approval (protected CI scope). Document the required npm/node versions in `SUPPORT.md`.

**P3-B — Universal-claim calibration**
- `git-hygiene/SKILL.md:35`: "Prefer `git mv` for cleanliness in the diff; rename detection works on content similarity regardless, but `git mv` keeps the intent obvious in the commit."
- `frontend-layout/SKILL.md:37`: "In client-side data-loading (React Query, SWR, raw hooks), components go through the `src/api/` wrapper. Server-component and framework data-loader contexts (RSC, Next `page.tsx`, Remix loaders) fetch by design; keep the fetch adjacent to the loader entry, not scattered across children."
- `observability/SKILL.md:114`: "Readiness reflects dependency status when a dependency outage means this replica cannot serve. Beware amplification: if all replicas share the same dep, readiness-based failover can cascade. Split checks or add per-dep circuit breakers when the dep is not per-replica."
- `observability/SKILL.md:128`: "Do not alert on CPU as a proxy for user pain (use SLO burn). Do alert on sustained CPU saturation (e.g. ≥90% for 15 min) tied to a capacity SLO."
- `ui-review/SKILL.md:32,34`: qualify — "Unintended horizontal scroll is a finding; intentional carousels/grids are not. Destructive or externally-visible actions (delete/pay/publish) confirm; ordinary save-button submits do not."
- `docker/SKILL.md:26,90`: qualify — "Set `HEALTHCHECK` for standalone/compose deployments; k8s deployments own probes at the Deployment level and typically ignore image HEALTHCHECK — do not duplicate."

**P3-C — Context and repo hygiene (deferred to after correctness)**
- Root-level `external-review.md` and `external-review-v2.md`: move to `reports/` (item 1 of my earlier audit).
- CLAUDE.md size reduction: only after §7-§14 clarifications settle; no immediate action.
- Report-directory index and archive policy: propose after implementation lands.

### 4.3 Files affected (surgical scope)

**Hooks / installer (P1, P2-A/B/C):**
- `claude-init.sh` (P1-A: chained transaction; verification of profile + manifest)
- `.claude/hooks/block-destructive.sh` (P2-A: multiline normalization)
- `.claude/hooks/lib.sh` (P2-B: `log_fail_open` helper)
- `.claude/hooks/scan-secrets.sh`, `protect-files.sh`, `check-diff-size.sh` (P2-B: wire helper into fail-open sites; no exit-code change)
- `.claude/hooks/verify-done.sh` (P2-C: watch-mode detection + per-check timeout wrapper)
- `.claude/hooks/README.md` (P2-E: SQL-prose bounded-guarantee correction)

**Policy / skills (P1, P2-D/G, P3-B):**
- `CLAUDE.md` — no changes proposed unless a §7 tightening is needed to close the token loop; TBD after P1-B edit.
- `.claude/skills/web-security/SKILL.md` (P1-B tokens + P2-G password rule)
- `.claude/skills/api-design/SKILL.md` (P2-G RFC 8594/9745 + X-RateLimit)
- `.claude/skills/testing/SKILL.md` (P2-D quarantine)
- `.claude/skills/verification/SKILL.md` (P2-D npm ci + git revert)
- `.claude/skills/git-hygiene/SKILL.md` (P3-B git mv)
- `.claude/skills/frontend-layout/SKILL.md` (P3-B components-never-fetch)
- `.claude/skills/observability/SKILL.md` (P3-B readiness + CPU)
- `.claude/skills/ui-review/SKILL.md` (P3-B scroll + confirmations)
- `.claude/skills/docker/SKILL.md` (P3-B HEALTHCHECK)

**Tests (add regressions; never weaken):**
- `tests/installer/run-tests.sh` (P1-A failure-injection matrix)
- `tests/hooks/corpus.jsonl` (A1 multiline shapes + prose regression rows)
- `tests/hooks/run-tests.sh` (VD6/VD8 fixture: `node -e ...`)
- `tests/sessions/run-sessions.sh` (P2-F: must_load/must_not_load, semantic checks, tighter outcome regexes, ask-tier scenario)
- `tests/policy_consistency.py` (new; P1-B, P2-D, P2-E consistency assertions)

**Docs:**
- `SUPPORT.md` (P3-A: pin the working npm/node/script-shell config for the Windows lane claim)
- `HOW-TO.md` (may need one line for the new `CLAUDE_VERIFY_TIMEOUT_S` env var)

**Not touched (owner-gated per prompt):**
- `.github/workflows/test.yml` (protected CI; will propose changes as a separate PR if any Windows lane is required)
- Any protected branch, any push, any release, any GitHub settings.

### 4.4 Alternatives considered

- **Rewrite `claude-init.sh` from scratch as a POSIX-safe transaction library.** Rejected: too large a diff, breaks the current shell-function-sourced ergonomic. The chained-transaction fix is surgical.
- **Kill the token-prefix authorization by deleting the whole "Logging (security-sensitive paths)" section.** Rejected: some of it is correct (never full tokens, never full CC, audit-log immutability). Just remove the "prefix only" line.
- **For A1, use `tr '\r\n' '  '` and re-run the existing patterns.** Rejected without neighboring-test evidence: could create false positives on commands that legitimately span lines. Instead: normalize `\<LF>` → ` ` and other LF/CRLF → ` `, then re-test the full corpus.
- **For A5, add a Stop-hook timeout in settings.json.** Rejected without owner approval: Claude Code's Stop-hook timeout policy is deliberate.
- **Do NOTHING about A3.** Rejected: fixture-fragility is real; the fix is cheap (node -e).

### 4.5 Risks & blast radius

| Risk | Blast | Mitigation |
|---|---|---|
| Chained transaction breaks a legitimate profile that today succeeds | New projects created via `claude-init` | Full re-run of `tests/installer/run-tests.sh` (37 sub-tests) + new failure-injection tests |
| A1 normalization creates new false positives on legitimate multiline `rm` | New DENY on cleanup commands users rely on | Corpus expansion first (dangerous + harmless neighbors) before touching the pattern; run corpus in gate mode |
| Test-skill quarantine tightening surprises teams already using flaky quarantine | Skills users notice new wording | Wording only, no hook change; provide a "how to run a non-blocking quarantine lane" section |
| Verification skill dropping auto-revert makes some existing workflows slower | Users of the failure protocol | Keep `git revert` as a *proposal step*, not removal |
| Watch-mode detection false-positives on scripts with `--watch` in a URL or comment | Legitimate tests skipped | Match on script token, not any substring; explicit regex on flag position |
| Session harness gains failure exits and prior "green" runs will re-run red | Team perception of a regression | Land the assertion changes with a re-run baseline in the same commit |
| CRLF-normalization in hooks masks a real CRLF corruption elsewhere | Bad file writes silently allowed | The normalization is only for pattern matching, never for what's forwarded |

### 4.6 Rollback plan

- All edits land in a **v8 branch** off `main`.
- If any post-merge regression appears: `git revert <v8-merge-commit>` — the changes are additive/reversible; no schema, no data.
- The bootstrap change is the only one with runtime-behavior impact on new projects; existing projects are untouched (they use their frozen `.claude/` copy).

### 4.7 Verification (what the v8 tip must show)

Per the prompt's "Verification required before reporting completion" list — exact commands, exit codes, outputs. The v8 tip must show:

1. New failure-injection tests: exit non-zero, no `DEST_ROOT/<name>` written, no success line, for each of {jq, sed, date, find, sort, sha256sum, mv}.
2. `bash tests/installer/run-tests.sh` — pass=all/fail=0 (baseline 37/37 + new injection cases).
3. `bash tests/hooks/run-tests.sh` — pass ≥ current 291, fail=0.
4. `bash tests/hooks/run-corpus.sh --gate` — `contract_violations: 0` with A1 multiline shapes added as DENY and neighboring harmless as ALLOW.
5. ShellCheck v0.10.0 (`-x -P .claude/hooks`) — exit 0.
6. `python tests/skills/check_catalog.py` — PASS (catalog invariant preserved).
7. `python tests/skills/routing/test_run_eval.py` — pass all.
8. `python tests/skills/routing/test_results_consistency.py` — PASS.
9. `python -m py_compile` on every changed .py, `python -c 'import yaml; yaml.safe_load(open("path"))'` on every changed YAML/JSON.
10. `python tests/check_links.py` — PASS.
11. `tests/sessions/run-sessions.sh` — new asserts pass (must_load / semantic check / ask tier exercised); live rerun **not required** if model access is unavailable — recorded as such per prompt.
12. Live routing rerun: **not required** unless a live signal is available; committed results unchanged; consistency test still green.
13. Secret scan (targeted grep) — no new secret shapes; full-history scan **not required** offline.
14. `tests/policy_consistency.py` — PASS (new file; enforces the three inter-doc invariants named above).

## 5. Explicit halt

Per the v8 remediation prompt §"Required first response":

> Provide the repository-required written plan … Stop and wait for my approval before implementation.

I am stopping here. I will not edit any repository file, install any dependency, modify CI, commit anything, push, open a PR, or change remote settings until you approve — including approval of the specific scope in §4.3.

If you approve, I will proceed strictly in order:
1. Land failure-injection tests (P1-A red first, then close).
2. Land P1-B token change + policy_consistency test.
3. Land A1 corpus rows red first, then the normalization patch.
4. Land the remaining P2/P3 edits in the order shown in §4.2.
5. Re-run the full verification list from §4.7 and produce the v8 verification report.

Owner-gated items (repo settings, release tag, historical-report archive policy, Windows CI lane, Stop-hook timeout in settings.json) are held for explicit direction — not included in the default implementation batch.

---

*Investigation and reproductions performed by the same session that produced [reports/blind-audit-20260720.md](reports/blind-audit-20260720.md). Two source documents (`claude-template-v7-independent-review.md`, `claude-template-v8-additional-session-context.md`) were treated as evidence to reproduce, not as findings to inherit. Every reproduction referenced above is bit-reproducible from a clean clone with the fixtures and shims described.*
