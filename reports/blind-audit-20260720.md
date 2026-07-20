# Blind Independent Audit — 2026-07-20

Independent, evidence-backed audit of `theptipteacharsripaitoon/claude-template`.
Performed **without** reading any prior audit, adjudication, external review,
score file, or the `external-review*.md` and `reports/*` documents in the tree.
Those files were listed via `git ls-files` for inventory only and never opened.

## 1. Exact commit & environment

| Item | Value |
|---|---|
| Repo | `https://github.com/theptipteacharsripaitoon/claude-template.git` |
| Merge base commit | `8edb40bbd68e6800fa2b97b9fa27ce887f392f6f` (main tip; `Merge pull request #15 …/claude/template-audit-v7`) |
| Working branch | `claude/template-blind-audit-12a506` (worktree) |
| `git describe` | `v2.0-146-g8edb40b` |
| Working tree | clean |
| Platform | Windows 11 Home 10.0.26200 (MSYS2 mingw-w64) |
| Bash | 5.2.15(1)-release |
| Git | 2.41.0.windows.3 |
| jq | 1.6 |
| Python | Anaconda 3 (3.x) |
| ShellCheck | v0.10.0 via `koalaman/shellcheck` docker image (matches CI pin) |
| Docker | Docker Desktop present (used for containerized ShellCheck only) |
| gh CLI | 2.96.0 (used read-only to inspect CI runs) |

## 2. Checks run & observed results

All commands were run against the committed tree at the merge commit above.

| # | Check | Command | Result |
|---|---|---|---|
| C1 | ShellCheck v0.10.0 (`-x -P .claude/hooks`) on every hook, `lib.sh`, `install.sh`, and `claude-init.sh` | dockerized shellcheck, CRLF-stripped copies (worktree checkout is CRLF; see limitations) | **exit 0**, zero findings |
| C2 | `bash .claude/hooks/install.sh` (functional self-tests) | run in a scratch project dir | **all 17 sub-tests pass**, override mechanism verified |
| C3 | `bash tests/hooks/run-tests.sh` (regression suite) | table-driven, 291 cases | **`RESULT: pass=291 fail=0`** |
| C4 | `bash tests/hooks/run-corpus.sh` (policy corpus replay) | 205 rows, 198 scored (7 documented out-of-scope) | **`contract_violations: 0`, recall/precision/ask-accuracy all 1.0** |
| C5 | `python tests/skills/check_catalog.py` (catalog gate) | 37 skills, 37 frontmatter, 37 INDEX rows, 37 README rows, all internal links resolve | **`ALL CHECKS PASS`** |
| C6 | `python tests/check_links.py` | 69 tracked markdown files | **`ALL CHECKS PASS`** |
| C7 | `python tests/skills/routing/test_run_eval.py` (offline scoring/parser tests) | 15 unit cases | **`15/15 passed`** |
| C8 | `python tests/skills/routing/test_results_consistency.py` | committed results ↔ trigger fixture ↔ evaluated_runs | **`5 result set(s), 5 evaluated_runs entr(ies), fixture cases=45` — pass** |
| C9 | `bash tests/installer/run-tests.sh` (bootstrapper) | 37 sub-tests: success path, failure paths, dry-run, profiles, drift status | **`RESULT: pass=37 fail=0`** |
| C10 | `.github/workflows/test.yml` last runs (main + PRs) | `gh run list` | most recent 5 runs: all **`completed success`**; main run 29730020621 in 32 s |
| C11 | Latest committed corpus result (2026-07-20 08:48 UTC) | jq | 0 contract violations; recall 1.0; precision 1.0 |
| C12 | v7 live routing run (2026-07-20 08:33 UTC) | jq | 45 unique cases × 3 runs = 135 rows; recall 0.94, precision 0.967, stability 0.733 |
| C13 | Session harness results (`tests/sessions/results/sessions-20260720.jsonl`) | jq | 9 real headless-Claude sessions ran; 8/9 changed the expected artifact; one (s4-migration) produced no artifact but skills loaded correctly |
| C14 | Baseline context load estimate | `wc -c` on top-of-mind files | `CLAUDE.md` ≈ 32 KiB (~8 kTok); skill frontmatter (37 skills) ≈ 15 KiB (~3.7 kTok mean 399 B/skill) |
| C15 | Secret-shape sweep of shipping files | grep for AWS/GH/Stripe/PEM patterns | only the deliberate fake-AWS-key fixture in `.claude/hooks/install.sh:103` (embedded in the installer's own scan-secrets self-test) — matches the scanner's fake-marker path |
| C16 | Stray `TODO`/`FIXME`/`HACK` sweep in shipping code | grep | none in `.claude/`, root, or `tests/`; only mentions in `CLAUDE.md` policy prose and `XXXX` as a scanner fake-marker |
| C17 | `.gitignore` / `.gitattributes` review | read | `.env*` ignored with template re-includes that mirror `protect-files.sh`; `*.sh eol=lf` (fixes Windows-clone-breaks-hooks) |
| C18 | Repo inventory | `git ls-files` | 114 tracked files, of which the shipping template is ~62 (docs + `.claude/` + tests + bootstrapper); the rest is evidence & `reports/` (deliberately not opened) |
| C19 | Real-world confirmation of scan-secrets | attempted to write this report with the literal fixture value | **hook BLOCKED the write** with `secret-shaped string` and the correct pattern name — proves the scanner fires on Edit/Write of a real file, not just piped self-tests |

## 3. Prioritized findings

Ranked by severity. None of these blocks the template; several are polish items
because the current state is unusually strong. File:line refs are always to the
audited commit.

### High

1. **`external-review.md` and `external-review-v2.md` ship at repo root** — 43 KB of
   content committed at the top level (`external-review.md` 27 KB;
   `external-review-v2.md` 16 KB). For a **public template**, root-level noise
   dilutes signal on the GitHub landing page and confuses first-time consumers
   (they read what looks canonical). Either move them into `reports/`
   alongside the other historical audit artifacts, or delete once integrated.
   Nothing else at the root looks out of place. *(Evidence: `ls -la` on repo
   root; only these two files break the pattern of README/LICENSE/CLAUDE.md/
   CHANGELOG/HOW-TO/CONTRIBUTING/SECURITY/SUPPORT/installer.)*

### Medium

2. **CLAUDE.md line-ending policy for shell scripts is enforced, but the
   worktree checkout can still land as CRLF and break Linux/WSL execution
   silently for the first-time user** — `.gitattributes:2` sets `*.sh text eol=lf`,
   yet on this Windows worktree every hook file was checked out with `\r\n`
   line endings (verified by `od -c`). Under GNU ShellCheck this trips **SC1017**
   on every line, and under `bash` on Linux/WSL the classic `$'\r': command not
   found` failure occurs. HOW-TO.md §Troubleshooting names the symptom, and
   `.gitattributes` is correct, but users who **clone on Linux from a Windows
   checkout hosted upstream** may still hit this. Two mitigations worth adding:
   (a) a CI step that fails on any tracked `.sh` containing `\r`, and
   (b) `.claude/hooks/install.sh` should detect + strip CRs on install (or fail
   loudly), not just verify jq/grep.
   *(Evidence: `docker … shellcheck` produced 60+ SC1017 rows against the raw
   worktree, and after `tr -d '\r'` all findings vanish and exit is 0.)*

3. **`INDEX.md` and `README.md` under `.claude/skills/` duplicate content but
   check_catalog.py enforces them independently** — both list every skill and
   the check gates on both. This is fine today (37 skills, both files match),
   but each new skill requires editing three places (folder, INDEX.md,
   README.md). A single source of truth (e.g. generate README.md's table from
   INDEX.md at check time, or drop one) would reduce drift risk.
   *(Evidence: `tests/skills/check_catalog.py:57-72` regexes both files
   separately and fails if they disagree.)*

4. **`Protected Paths` project template block is unfilled placeholder text in
   the shipped `CLAUDE.md`** — §Project Configuration remains `_e.g., …_` (lines
   389–417). This is by design ("REQUIRED — fill before first use", line 387),
   but a **first-time template consumer** who blindly bootstraps then adds a
   file will get the universal policy without any project-specific advisory
   paths. Consider a `claude-template-status`-style warning that reports "still
   contains placeholders" until the block is filled, or a lint step for
   generated projects. *(Evidence: `CLAUDE.md:389-417`; today only the
   installer's post-bootstrap message tells the user to fill it, and drift
   from that is invisible.)*

### Low

5. **`check-diff-size.sh:9` sources `lib.sh` but does not `export
   CLAUDE_HOOK_NAME` before the source**, unlike the other four hooks. The lib
   auto-derives the name from `BASH_SOURCE[1]` (lib.sh:10-14), so the log line
   still reads `check-diff-size`. Behavior is correct; the asymmetry is
   cosmetic. Adding the export line would keep all five hooks identical and
   remove one branch of lib.sh's fallback logic from the runtime path.

6. **`scan-secrets.sh` fake-markers list mixes literal case-sensitive strings
   (`'EXAMPLE'`, `'example'`) and regex fragments (`'fake[_-]'`)** — the
   `printf … | grep -qE -e "$marker"` (line 89) treats them all as regex, so
   `EXAMPLE` and `example` are both needed to cover casing but `XXXX` matches
   in any position without word boundaries. Not a defect (false-negative on a
   real key would need it to contain literally `XXXX`), but a comment noting
   "regex fragments, not literals" would prevent a future edit from writing
   `'FAKE-'` and expecting case-insensitivity. *(Evidence: `scan-secrets.sh:72-83`.)*

7. **`verify-done.sh` blocking mode has an honest "no checker found" branch
   (lines 157-166), but reminder mode always prints the `📋 Definition of Done`
   text whenever ANY code file is dirty, including files that pre-existed the
   session** — the code comments this explicitly (`verify-done.sh:49-52`) and
   HOW-TO/README are silent on it. Users on a pre-dirty tree will see the
   reminder every Stop; the fix (SessionStart baseline) is called out in the
   comment as deliberately deferred. Acceptable but under-documented outside
   the source.

8. **`.github/workflows/test.yml` uses `pip install --quiet 'pyyaml==6.0.2'`
   without a `requirements.txt` or hash pin** — SHA-pinned actions (line 25-26)
   set the security bar high; pinning the one Python dep by version alone
   (line 49) is inconsistent with that bar. Low blast radius (test-only, on
   ubuntu-24.04, single dep), but a `--require-hashes` file would close the
   loop. Nothing else in CI is unpinned.

9. **v7 routing run stability = 0.733** (`tests/skills/results/routing-20260720-083339-summary.json`)
   is below the earlier runs' 0.9 baseline. Recall/precision both rose to a
   45-case fixture, so this is likely fixture-scope-driven variance, not a
   regression — but no `evaluated_runs:` entry in `trigger-cases.yaml` explains
   the stability drop. Adding one sentence in the run's `note:` field would
   preserve the audit trail.

### Informational (not defects)

- **Zero policy corpus violations** across 198 scored rows *and* 291-case
  regression suite is exceptional for a hook-based enforcement layer. The
  bounded guarantee (`hooks/README.md:211-241`) is falsifiable and holds.
- **Least-privilege CI**: `permissions: contents: read`, SHA-pinned actions,
  10-minute job timeout, `concurrency` cancellation — CI hygiene is textbook.
- **The `evaluated_runs` provenance ledger inside `trigger-cases.yaml`** is a
  clever way to keep results and fixture in one place; the consistency test
  gates them together.
- **The scanner blocked this audit itself** when the earlier draft embedded a
  literal AWS-key-shaped fixture. That is exactly the correct behavior — proof
  that the shipping scanner catches real editor writes, not only piped tests.
  This report references the fixture indirectly (`install.sh:103`) rather than
  reproducing the value.

## 4. Fixed 10-category weighted score

Weights sum to 100. Score = weighted average on a 0-10 scale, where 10 = shipping
public-template quality with independent evidence, 5 = usable but needs work,
0 = unusable.

| # | Category | Weight | Score | Weighted | Basis |
|---|---|---:|---:|---:|---|
| 1 | Bootstrapper correctness & safety | 10 | 9.5 | 0.95 | 37/37 installer tests, atomic rename, allowlist + unknown-entry gate, dry-run, profile transforms all validated (C9); minor: no CRLF check on install |
| 2 | Hook enforcement (correctness) | 15 | 9.7 | 1.455 | 291/291 regression + 205-row corpus (198 scored, 0 violations); ShellCheck clean; documented residuals labelled OOS (C1, C3, C4) |
| 3 | Hook enforcement (security/threat model) | 10 | 9.0 | 0.9 | SECURITY.md is honest about scope; bounded guarantee published; fake-marker path scoped to value not line; override logged; no secret values leaked to stderr; scanner confirmed on real edit (C19) |
| 4 | Skills catalog quality | 10 | 9.0 | 0.9 | 37 skills, 3 dependency clusters + AI trio, INDEX + graph, description mean 349 chars (well under 1536 cap); mild duplication concern (INDEX + README) |
| 5 | Test & evaluation evidence | 15 | 9.5 | 1.425 | Hook corpus + 291-case regression + installer + link + catalog + offline routing scoring + live routing eval + 9-scenario session harness; all reproducible; provenance stamped (C3-C13) |
| 6 | Policy (CLAUDE.md / ENFORCEMENT.md) | 10 | 9.5 | 0.95 | 20 clean sections; §16 correctly separates code-produced vs review-only tasks; §14 verification matrix scaled by §13 risk; ENFORCEMENT layer table maps to hooks |
| 7 | Documentation & onboarding | 10 | 9.0 | 0.9 | README concise (43 lines), HOW-TO comprehensive (591 lines with Windows path called out), SUPPORT + SECURITY + CONTRIBUTING present; minor: root-level `external-review*.md` clutter |
| 8 | CI & platform claims | 10 | 9.5 | 0.95 | GH workflow SHA-pinned + least-priv + timeout + concurrency; last 5 runs green (32-38 s); SUPPORT.md matrix is measured, not aspirational |
| 9 | Context efficiency | 5 | 8.5 | 0.425 | Baseline ~12 kTok (CLAUDE.md 8 kTok + skill frontmatter 3.7 kTok + settings/INDEX < 300 tok); frontmatter descriptions well under the 1536-char cap; CLAUDE.md at 417 lines is heavy but justified |
| 10 | Public-template readiness | 5 | 8.0 | 0.4 | Apache-2.0, SECURITY, SUPPORT, CONTRIBUTING, `.env*` re-include mirror, secret hygiene clean, no stray secrets; blocker: root-level review files, unfilled Project Configuration is expected but silently drifts |
| **Total** | | **100** | | **9.25 / 10** |

**Grade: A (9.25/10).** The template is production-ready for internal use and
close-to-ready for public release. The one real cleanup item is the two
top-level `external-review*.md` files.

## 5. Limitations & unavailable checks

Independent audits should call out what they *didn't* verify:

- **Historical audit / adjudication / prior-score docs deliberately unread.** Per
  the audit brief, `reports/claude-independent-audit*`, `reports/review-adjudication*`,
  `reports/productization-plan-v7.md`, `reports/proposal-*.md`, `external-review.md`,
  and `external-review-v2.md` were treated as out of scope. Their content — and any
  scoring convention they may embed — did not shape this report.
- **Live `run_eval.py` was NOT re-run**: it needs an authenticated `claude` CLI
  and real model calls, and the audit brief said "safe offline verification".
  This audit relied on the committed run summaries and re-verified the offline
  scoring math + results-consistency gates.
- **`bash tests/sessions/run-sessions.sh` was NOT re-executed** for the same
  reason. This audit trusted `tests/sessions/results/sessions-20260720.jsonl`
  and cross-referenced its schema against the runner script.
- **macOS and WSL2 paths were not tested.** SUPPORT.md already marks both
  "Expected to work, not measured" — this audit confirms the claim; no evidence
  found to widen or contract it.
- **CRLF workaround was needed to run ShellCheck.** Every worktree checkout on
  this Windows machine was CRLF, contradicting `.gitattributes`. This audit
  used `tr -d '\r'` on copies to lint; the finding above (M2) proposes closing
  the gap.
- **No sandboxed adversary testing.** SECURITY.md explicitly declares semantic
  equivalents (`python -c "shutil.rmtree(...)"`) out of scope, and the
  bounded-guarantee section confirms it. This audit did not attempt to defeat
  hooks with encoded payloads or novel spellings; the corpus already covers
  the documented set.
- **No performance regression testing.** The plan §8 latency budget is claimed
  in the hook README fast-path comment (`block-destructive.sh:220-225`), but
  this audit did not benchmark on macOS/WSL.
- **`external-review-v2.md` and `external-review.md`** were listed by
  `git ls-files` for inventory only and their content was not opened.

## 6. Proposed remediation order

Do these in this order — each unblocks or de-risks the next:

1. **Move `external-review*.md` into `reports/`** (or delete). One commit,
   zero risk. Cleans up the GitHub landing page. *(High finding #1.)*
2. **Add a CI step that fails on any tracked `.sh` containing `\r`** and mirror
   the check in `.claude/hooks/install.sh` (fail loudly, or auto-strip and
   warn). *(Medium finding #2.)* Guards the most common Windows-clone
   failure mode.
3. **Single-source the skill table**: keep `INDEX.md` authoritative and either
   generate `README.md`'s table from it in `check_catalog.py`, or replace the
   README table with a "see INDEX.md" pointer. *(Medium finding #3.)*
4. **Post-bootstrap placeholder linter**: extend `claude-template-status` to
   flag when `CLAUDE.md` Project Configuration still contains `_e.g._`
   placeholders. *(Medium finding #4.)*
5. **Cosmetics + polish**: normalize `check-diff-size.sh`'s hook-name export
   (#5), add the fake-marker regex comment (#6), document the reminder-mode
   dirty-tree caveat outside the source (#7), pin PyYAML with `--require-hashes`
   (#8), add stability note to the v7 evaluated_runs entry (#9).

After 1–2 land, the template is in my judgement ready for public tagging (`v1.0.0`).

---

*Audit performed by an independent Claude Code session on
`claude/template-blind-audit-12a506`. No historical audits, adjudications, or
external reviews were read. All checks reproducible from a fresh clone.*
