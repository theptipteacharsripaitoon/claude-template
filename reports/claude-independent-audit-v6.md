# Independent Audit v6 — Blind Phase (pre-external-review)

Sixth staged audit of the Claude Code governance template. This report was
written **before opening `external-review-v6.md`** (existence confirmed, content
untouched — verified by method: the file was never read, grepped, or previewed
in this session before this report was committed). Findings below were
reproduced from scratch; nothing was carried forward from v1–v5 reports without
re-execution.

---

## 1. Exact state

| Item | Value |
|---|---|
| Repository | `https://github.com/theptipteacharsripaitoon/claude-template.git` |
| Audited commit | `2c3520125fb6f86b9848f8e84b98684e33f9c9f8` — merge of PR #12 (v5 cycle) |
| Relation to prompt's commit | `2c35201…` **is the current head** of `origin/main` (not merely an ancestor, not obsolete) |
| Fast-forward | no-op: local HEAD already equals `origin/main` after `git fetch origin` |
| Work branch | `claude/template-audit-v6` (session worktree branch `claude/template-audit-v6-4fdca5` renamed via `git branch -m`; worktree directory name keeps its suffix) |
| Working tree | clean at audit start (`git status --porcelain` empty) |
| Latest successful CI run at audit start | run `29681254044` (template-tests), 2026-07-19T09:15:24Z, **head_sha exactly `2c3520125fb6…`**, conclusion `success` |

## 2. Environment

| Tool | Version |
|---|---|
| OS | Windows 11 Home 10.0.26200 (MINGW64_NT-10.0-26200) |
| Shell | GNU bash 5.2.15(1)-release (x86_64-pc-msys, Git Bash); PowerShell 5.1 for Docker calls |
| Claude Code | 2.1.215 |
| Model | claude-fable-5 |
| Git | 2.41.0.windows.3 (`core.autocrlf=true` locally) |
| jq | 1.6 |
| Python | 3.10.9 (PyYAML 6.0.1 locally; CI pins 6.0.2) |
| ShellCheck | **absent locally**; run via Docker `koalaman/shellcheck:v0.10.0` (same pinned version as CI) |
| Bun | **absent locally**; real-Bun evidence via Docker `oven/bun:1` → **bun 1.3.14** |
| Node / npm | v18.16.0 / 9.5.1 |
| Docker | client+server 29.5.3 (Desktop) |
| gh CLI | absent (CI inspected read-only via GitHub REST API) |

**Line-ending note (environment artifact, not a repo defect).** In this
app-provisioned worktree the seven `.claude/hooks/*.sh` files are CRLF on disk
despite `.gitattributes` pinning `*.sh text eol=lf` (index is LF; `git ls-files
--eol` shows `i/lf w/crlf` for exactly those seven files; `tests/hooks/run-tests.sh`
and `claude-init.sh` are LF). A **fresh clone produces LF working files** for all
`.sh` (verified in scratch: `w/lf`), so template consumers are unaffected; Git
Bash executes the CRLF copies fine (the full suite passed on them). Authoritative
ShellCheck was therefore run against a clean `git archive HEAD` export.

## 3. Independent score (blind, fixed rubric)

| Category | Weight | Score | Notes |
|---|---|---|---|
| Technical correctness | 15% | 8.3 | all checks green, but three P1s found (Bun ×2, protected-path case) |
| Skill trigger quality | 15% | 8.8 | precision 1.0 / recall 0.963 / conflict 0.0 (20 cases × 3 runs), but only 16/37 skills have positive fixture coverage |
| Hook correctness | 15% | 8.2 | strong tested coverage; current-dir rm globs, diff-size override, SQL-client no-`;` gaps |
| Conflict avoidance | 10% | 9.0 | deny-before-ask tested; conflict_rate 0.0; disciplined "Do NOT use" boundaries |
| Safety & permissions | 10% | 8.7 | tier model implemented+documented; override contract broken for one hook |
| Testing & evaluation | 15% | 8.5 | 187 hook cases, offline routing tests, live-eval evidence; missing bun-present, case-variant, rm-glob regressions |
| Context efficiency | 5% | 8.5 | CLAUDE.md 32.8 KB; descriptions mean 534 chars; 0 manual-only skills |
| Team usability | 5% | 9.0 | ops README, one-command install, log tuning guidance |
| Maintainability | 5% | 9.0 | shared lib, table-driven suite, ShellCheck-clean, honest comments |
| Public-template readiness | 5% | 7.0 | no license, no release/version policy (secret-scanner proposal exists) |
| **Weighted total** | | **8.5** | |

## 4. Complete test evidence (authoritative checks, §A)

All run from the worktree root at commit `2c35201`.

| # | Check | Command | Exit | Result |
|---|---|---|---|---|
| 1 | Complete hook suite | `bash tests/hooks/run-tests.sh` | 0 | `RESULT: pass=187 fail=0`; duration **real 3m49.0s** (user 1m20.9s, sys 1m39.4s) on Windows/MSYS |
| 2 | Hook installer | `bash .claude/hooks/install.sh` | 0 | "Hooks installed and functional", override self-test passes |
| 3 | ShellCheck (pinned v0.10.0, Docker, LF export) | `docker run --rm -v <lf-export>:/mnt -w /mnt koalaman/shellcheck:v0.10.0 -x -P .claude/hooks <7 hooks> tests/hooks/run-tests.sh claude-init.sh tests/skills/routing/seed-repo.sh` | 0 | clean (run against `git archive HEAD` export; the CRLF working copies produced SC1017 noise — see §2 note) |
| 4 | Skill catalog | `python tests/skills/check_catalog.py` | 0 | `37 skills checked … ALL CHECKS PASS` |
| 5 | Routing scoring/parser tests | `python tests/skills/routing/test_run_eval.py` | 0 | `15/15 passed` |
| 6 | Routing-result consistency | `python tests/skills/routing/test_results_consistency.py` | 0 | `4 result set(s), 4 evaluated_runs entr(ies), fixture cases=20 … ALL CHECKS PASS` |
| 7 | Python compilation | `python -m py_compile <5 files>` | 0 | clean |
| 8 | Settings JSON | `jq empty .claude/settings.json` | 0 | valid |
| 9 | Workflow + routing YAML | `python -c "yaml.safe_load(...)"` both files | 0 | valid |
| 10 | Generated-file cleanliness | `git ls-files '*.pyc'` + `__pycache__` grep | — | none tracked |
| 11 | Markdown links | `python tests/check_links.py` | 0 | `59 tracked markdown file(s) … ALL CHECKS PASS` |

## 5. Bun verification matrix (§B)

Fixtures: git repos each with `package.json` containing a passing `test`
script (`echo RAN_PACKAGE_JSON_TEST_SCRIPT`), one dirty code file, and lockfile
per case. "Bun present" is a stub `bun` on a prepended PATH dir that records
argv; "Bun absent" is the unmodified PATH (bun genuinely absent here — for
host-independence see D-BUN-3). `verify-done.sh` run with `CLAUDE_VERIFY_BLOCK=1`
(blocking) and default (reminder).

| Project | bun absent | bun present (stub) |
|---|---|---|
| `bun.lock` only | **PM=npm (misdetected)**; ran `npm test` → "All 1 … passed", exit 0 | **PM=npm (misdetected)** — bun never invoked even though installed |
| `bun.lockb` only | PM=bun; "'bun' is not installed — Node checks skipped" → "No verification…", exit 0 (honest) | PM=bun; **invoked `bun test`** (stub argv log: `bun test`), exit 0 |
| both lockfiles | same as `bun.lockb` only | same as `bun.lockb` only (`bun test`) |
| neither | PM=npm (default); `npm test` ran the script, exit 0 | identical (stub not consulted) |
| `package-lock.json` (control) | PM=npm; `npm test` passed | identical |

Reminder mode (default) prints the §16 checklist and exits 0 regardless of PM —
verified on the `bun.lockb` fixture.

**Real-Bun ground truth (Docker `oven/bun:1` = bun 1.3.14):**

| Scenario | Command | Exit | Output |
|---|---|---|---|
| script only, no native test files | `bun test` | **1** | `No tests found!` (native runner ignores the package.json script) |
| script only, no native test files | `bun run test` | 0 | `RAN_PACKAGE_JSON_TEST_SCRIPT` |
| one native `*.test.ts` present | `bun test` | 0 | `1 pass` |
| `bun install` with a real dependency | — | 0 | writes **text `bun.lock`** (modern default), not `bun.lockb` |

Conclusions: (1) `bun.lock` — the file modern Bun writes by default — is not
detected (`verify-done.sh:87` checks only `bun.lockb`), so new Bun projects are
verified with npm, or not at all if npm is missing; (2) for the script-gated
test check (only run when `.scripts.test` exists), `bun test` is provably the
wrong command — blocking mode reports **failure on a healthy project**
(`bun test` exit 1 "No tests found") where `bun run test` exits 0; (3) the
existing suite's bun case relies on bun being absent from the host, i.e.
host-dependent.

## 6. Recursive-rm matrix (§C)

Hook decision = `block-destructive.sh` fed `{"tool_name":"Bash",…}`. Real
behavior = executed in disposable nested sandboxes (GNU coreutils **8.32**,
Git Bash), fixture: `a.txt`, `build/o.txt`, `sub/f.txt`, dotfiles `.a` (2 ch),
`.ab` (3 ch), `.hidden`.

| Command | Hook | Real behavior (exit; what remained) | Expected policy |
|---|---|---|---|
| `rm -rf .` | ALLOW | exit 1, `refusing to remove '.' or '..'` — **nothing deleted** | deny (defense-in-depth; intent is destructive) |
| `rm -rf ./` | ALLOW | exit 1, same refusal, nothing deleted | deny |
| `rm -rf ..` | ALLOW | exit 1, same refusal, nothing deleted; parent intact | deny |
| `rm -rf ./*` | **ALLOW** | exit 0; **all visible entries deleted** (dotfiles survive) | **deny** |
| `rm -rf -- ./*` | **ALLOW** | exit 0; same deletion | **deny** |
| `rm -rf ./.??*` | **ALLOW** | exit 0; dotfiles ≥3 chars deleted (`.ab`, `.hidden`) | **deny** |
| `rm -rf ./* ./.??*` | **ALLOW** | exit 0; everything but `.a` deleted | **deny** |
| `rm -rf "./"*` | **ALLOW** | exit 0; all visible entries deleted (quote does not stop glob) | **deny** |
| `rm -rf ./build` | ALLOW | exit 0; only `build/` deleted | allow (named relative cleanup) |
| `rm -rf ../temporary-build` | ALLOW | exit 0; only the named sibling deleted; cwd intact | allow (named relative cleanup) |

Safe controls (hook): `rm -rf /`, `rm -rf *`, `rm -rf ~`, `rm -rf $HOME` all
DENY; `rm -rf build/`, `rm file.txt`, `rm -rf node_modules` all ALLOW.

Findings: the prompt's caution is confirmed — `rm -rf .` does **not** delete the
current directory (POSIX/GNU refusal, exit 1). The genuinely destructive forms
are the **current-directory globs**, and the hook allows every one of them while
denying the equivalent bare `*` — an inconsistent posture (D-RM-1). Dot-target
forms (`.`, `./`, `..`) are inert under GNU rm but still signal destructive
intent; policy is to deny them too (cheap, no legitimate use).

## 7. Protected-path segment case matrix (§D)

Hook decisions identical across **Write, Edit, and NotebookEdit** (36 runs; the
hook reads `file_path // notebook_path`):

| Path | Decision | Expected on a case-insensitive FS |
|---|---|---|
| `.claude/settings.local.json` | ASK | ASK ✓ |
| `.CLAUDE/settings.local.json` | **ALLOW** | ASK — same file on NTFS |
| `.Claude/settings.json` | **ALLOW** | ASK |
| `.github/actions/example/script.sh` | ASK | ASK ✓ |
| `.GITHUB/actions/example/script.sh` | **ALLOW** | ASK |
| `.github/ACTIONS/example/script.sh` | **ALLOW** | ASK |
| `.git/config` | DENY | DENY ✓ |
| `.GIT/config` | **ALLOW** | DENY — same file on NTFS |
| `.secrets/token.txt` | DENY | DENY ✓ |
| `.Secrets/token.txt` | **ALLOW** | DENY |
| `migrations/0001.sql` | ASK | ASK ✓ |
| `MIGRATIONS/0001.sql` | **ALLOW** | ASK |

Controls: `.claude/settings.json` ASK; `.github/workflows/ci.yml` ASK;
`.GITHUB/WORKFLOWS/ci.yml` ALLOW (bypass); `Migrations/0001.sql` ALLOW (bypass);
`src/app.py` ALLOW ✓; `C:\repo\.GIT\config` ALLOW (bypass, backslash form).

**Filesystem evidence (this platform, NTFS):** writing through
`.CLAUDE/settings.local.json` modified the file read back via
`.claude/settings.local.json` (one directory entry, content `changed`), and
appending `[test] injected = true` through `.GIT/config` was **read back by git
itself** (`git config --get test.injected` → `true`). So on Windows/macOS
default filesystems the case variants address the **same protected files** and
the deny/ask tiers are bypassable (D-CASE-1). On case-sensitive Linux these are
genuinely different paths, so folding segments errs toward ASK/DENY of a
distinct directory — the hook's own stated philosophy ("over-cautious, never a
dangerous allow", protect-files.sh:16-17) endorses that trade. Policy: fold
directory-segment comparisons; keep original casing in messages (already the
rule for basenames, protect-files.sh:34-39).

## 8. SQL client matrix (§E)

| Command | Hook | Classification |
|---|---|---|
| `psql -c "DELETE FROM users"` | **ALLOW** | false negative — executes a full-table delete |
| `psql -c 'DELETE FROM users'` | **ALLOW** | false negative (documented residual, hooks README:38) |
| `mysql -e "DELETE FROM users"` | **ALLOW** | false negative |
| `sqlcmd -Q "DELETE FROM dbo.Users"` | **ALLOW** | false negative |
| `psql -c "DELETE FROM users;"` | DENY | covered (`;`-terminated pattern) |
| `mysql -e "DELETE FROM users;"` | DENY | covered |
| `sqlcmd -Q "DELETE FROM dbo.Users;"` | DENY | covered |
| `psql -c "DELETE FROM users WHERE id = 1"` | ALLOW | correct (WHERE-guarded) |
| `psql -c "DROP TABLE users"` | DENY | covered (DROP needs no anchor) |
| `mysql -e "TRUNCATE TABLE logs"` | DENY | covered |
| `echo "DELETE FROM users"` | ALLOW | correct control |
| `git commit -m "document DELETE FROM users"` | ALLOW | correct control |
| `printf '%s\n' 'DELETE FROM users'` | ALLOW | correct control |

The no-`;` client forms slip because the DELETE anchors require `;` or
end-of-command immediately after the table name and a closing quote defeats
both (block-destructive.sh:78-84, deliberately, to keep prose allowed). A
**client-aware** pattern (`psql -c` / `mysql -e` / `sqlcmd -Q` followed by a
quoted destructive statement) closes the gap without touching the prose
controls, which is the preferred shape per this cycle's mandate (D-SQL-1).

## 9. Dependency option matrix (§F)

| Command | Hook | Classification | Verdict |
|---|---|---|---|
| `npm install lodash` | ASK | dependency decision | ✓ |
| `npm install --save-dev lodash` | ASK | dependency decision | ✓ |
| `npm install --prefix /tmp lodash` | **ALLOW** | new-package install (into another prefix) | **gap** — value-taking option (`--prefix /tmp`) breaks the option-skip pattern |
| `npm install --workspace app lodash` | ASK | dependency decision | ✓ |
| `npm ci` | ALLOW | restore | ✓ |
| `npm install` (bare) / `--legacy-peer-deps` | ALLOW | restore | ✓ |
| `pip install requests` | ASK | dependency decision | ✓ |
| `pip install --user requests` | ASK | user-site mutation | ✓ |
| `pip install --target /tmp requests` | **ALLOW** | environment-only install (still fetches+installs new code) | **gap** |
| `pip install --no-deps requests` | **ALLOW** | new-package install into the environment | **gap** |
| `pip install -r requirements.txt` / `-e .` | ALLOW | restore | ✓ |
| `pip install -U requests` / `--upgrade` | ASK | upgrade | ✓ |
| `pnpm add` / `yarn add` / `bun add` / `poetry add` / `uv add` / `cargo add` / `gem install` / `composer require` / `go get` / `go install` | ASK | dependency decision | ✓ |
| `npm uninstall` / `pip uninstall` / `npm update` / `yarn upgrade` | ASK | remove/upgrade | ✓ |
| `uv sync` / `poetry install` / `bundle install` / `composer install` | ALLOW | restore | ✓ |

Three gaps, all of one shape: an option **taking a value** (or starting the
package position with `-`) defeats the "skip options then require a package
token" idiom (D-DEP-1). Everything else matches the documented policy
(hooks README tier table + block-destructive.sh:96-148 comments).

## 10. False-positive matrix (§G)

| Harmless command | Hook | Note |
|---|---|---|
| `echo "/bin/rm" -rf /` | **DENY** | FP; quoted-path form is an intentional catch (`"/bin/rm" -rf` is a real invocation shape, block-destructive.sh:26-28) |
| `printf '%s\n' '"/bin/rm" -rf /'` | **DENY** | FP, same trade-off |
| `git commit -m 'document "/bin/rm" -rf /'` | **DENY** | FP, same trade-off |
| `echo "run rm -rf / to destroy everything"` | **DENY** | FP; unquoted `rm -rf /` inside prose is indistinguishable from a command |
| `echo 'rm -rf /'` | ALLOW | quote-boundary design working as documented |
| `git log --grep "rm -rf"` | ALLOW | ✓ |
| `echo "DELETE FROM users"` / commit / printf | ALLOW ×3 | ✓ |
| `echo "DROP TABLE users"` | **DENY** | FP; README:40 documents exactly this ("mention … blocked too") |
| `git commit -m "document DROP TABLE users"` | **DENY** | FP, documented |
| `echo "TRUNCATE TABLE logs"` | **DENY** | FP, documented |

Measured FP profile over this 13-command harmless set: 7 denied (54% of this
deliberately adversarial prose set — not a rate over normal traffic). The
trade-offs are explicit in code comments and README:40; the DELETE quote-anchor
design shows a zero-FP path exists for that family, while DROP/TRUNCATE/rm
favor recall. **Live incident during this audit:** the session's own hook denied
the auditor's Bash call because the command string contained `echo "DROP TABLE
users"` — the measured trade-off, experienced first-hand. Retained as designed;
documented, not "fixed", per "measure trade-offs rather than claiming zero
false positives".

## 11. Documentation / policy consistency (§H)

| Claim | Where | Verdict |
|---|---|---|
| Bootstrap failure leaves cwd untouched; "all cd's happen in a subshell" | claude-init.sh:8-15 | **Accurate as scoped** — the sentence scopes to *failed* bootstrap; the copy-phase `cd` is in the `if ! ( … )` subshell; the success-path `cd "$dest"` (line 118) is a deliberate feature, printed as `Currently at:` |
| Diff-size unblock: "raise `CLAUDE_DIFF_BLOCK_LINES` / set `CLAUDE_HOOK_OVERRIDE`" | hooks README:44 | **Contradicted by implementation** — `check-diff-size.sh` never calls `check_override`; empirically exit 2 with `CLAUDE_HOOK_OVERRIDE=check-diff-size` **and** `=all` (D-OVR-1). The `CLAUDE_DIFF_BLOCK_LINES` path works |
| Secret output: only pattern name, never value/prefix | hooks README:87-97 | Accurate — scan-secrets.sh:114-127; suite case SS11 probes for leakage |
| Hook-suite count wording | README:22 ("the runner's final `RESULT:` line is the authoritative case count") | Accurate; `RESULT: pass=187 fail=0` matches CHANGELOG.md:61 ("143 → 187") |
| Exact CI commit | this audit §1 | Latest successful run tested head_sha `2c35201…` exactly |
| Normal permission flow vs §2 explicit confirmation | hooks README:31-38 four-tier table vs CLAUDE.md §2 | Consistent — plain `git push` intentionally left to Claude Code's own prompt (tier 3), documented as such |
| Changelog current cycle | CHANGELOG.md:5-7 | `[Unreleased]` covers the **fifth** cycle; v6 entry required at implementation time |
| Routing evidence links | CHANGELOG.md:67,125,148,233; README:22 | All four result sets exist under `tests/skills/results/`; link check passes |
| "documentation string that merely mentions DROP TABLE … is blocked too" | hooks README:40 | Accurate (measured, §10); CHANGELOG:30-31's "quoted prose stays allowed" is also accurate — it speaks of `rm`/`DELETE` examples, which do have quote boundaries |
| SQL residual disclosure | hooks README:38 | Accurate and honest — matches §8 exactly |

## 12. Routing and context architecture (§I)

Measurements at `2c35201`:

- `CLAUDE.md`: **417 lines, 4,884 words, 32,791 chars**.
- 37 `SKILL.md` files; total body size **181,647 chars**; descriptions: min 58 /
  max 100 words (mean 72.5), min 440 / max 727 chars (**mean 533.8**).
- Manual-only skills (`disable-model-invocation: true`): **0** anywhere.
- Candidate measurements: repository-cleanup 727 chars desc / 10,539 body;
  git-hygiene 615 / 4,488; release-readiness 497 / 2,886; verification 548 / 3,255.
- Routing fixture: 6 clusters, **20 cases**, 16 distinct `must_load` skills
  (21 of 37 skills have no positive fixture coverage).
- Latest committed live run `routing-20260718-195349` (cc 2.1.214,
  claude-sonnet-5, 20 cases × 3 runs = 60, 0 errored): **recall 0.963,
  precision 1.0, conflict_rate 0.0, no_load_rate 0.037, stability 0.9**.

`disable-model-invocation: true` evaluation for the four candidates:
- **repository-cleanup** and **git-hygiene** are `must_load` targets in the live
  eval (1 and 2 cases; repository-cleanup also appears in 3 `must_not_load`
  lists and currently produces zero conflicts). Making them manual-only would
  mechanically fail those fixture cases and regress measured recall →
  **rejected on routing evidence**.
- **release-readiness** and **verification** have zero eval coverage either
  way; with measured precision 1.0 / conflict 0.0 there is no over-trigger
  evidence to justify removing auto-invocation, and the possible context saving
  is ~1,045 chars of description between them. Per the mandate ("do not change
  invocation behavior without routing/usability evidence") → **no change**;
  candidate for a future eval extension instead.
- `verify-done.sh` **does not use `eval`** — `run_check` executes an argument
  vector (verify-done.sh:65-77, comment states the §7 rationale). Verified by
  reading the current file, not prior reports.

## 13. Bootstrap copy policy assessment (§J)

v5 atomicity re-tested: BOOT1–BOOT13 pass inside the 187-case suite; plus fresh
scratch experiments (`claude-init` sourced from the audited commit):

| Experiment | Result |
|---|---|
| Baseline (template `.claude` ≈ 1 MB) | 13.12 s wall (install.sh self-test dominates on MSYS) |
| Inflated template: `.claude` = **251 MB** (200 MB worktree blob + 400 files + 50 MB log + local settings) | **13.15 s** — copy-then-prune overhead is noise (<0.1 s delta) |
| Prune list on success path | `worktrees/`, `logs/`, `settings.local.json` all pruned from output ✓ |
| Unknown future local state (`.claude/future-cache.bin`, `.claude/future-state/`) | **leaks into the bootstrapped project** (fixed prune list cannot know future names) |
| SIGKILL mid-bootstrap | destination **never published**; leftover `.claude-init.XXXXXX` temp dir remains — exactly the documented limitation (claude-init.sh:12-13); on Windows the leftover was transiently un-deletable ("Device or resource busy") while installer children lingered, then removable |

Assessment: the copy-everything-then-prune model is **retained**. The measured
copy cost is negligible even at 251 MB of local state, failure atomicity holds,
and the only real residual — unknown future `.claude/` files leaking — is
low-severity (a template checkout is normally a clean clone) and is exactly the
class of thing an allowlist would trade for permanent maintenance risk (every
new legitimate template file would need allowlisting or would silently vanish
from bootstrapped projects). Benefit does not outweigh complexity; documenting
the residual is the right move.

## 14. Confirmed defects (independent, all reproduced this session)

| ID | Sev | Defect | Evidence |
|---|---|---|---|
| D-BUN-1 | P1 | `verify-done.sh:87` detects only `bun.lockb`; modern Bun (1.3.14) writes **text `bun.lock`** by default → Bun projects misdetected as npm (masked when npm present, "no verification" when absent) | §5 matrix + Docker lockfile probe |
| D-BUN-2 | P1 | `verify-done.sh:112` runs `"$PM" test` → `bun test` invokes Bun's native runner, which ignores the package.json `test` script the check is gated on; healthy script-only projects **fail verification** (exit 1 "No tests found") | §5 Docker + stub argv |
| D-BUN-3 | P2 | The suite's Bun case depends on bun being absent from the host (breaks on bun-equipped machines); no bun-present coverage | §5; run-tests.sh VD9 design |
| D-CASE-1 | P1 | protect-files directory-segment matching is case-sensitive; on the template's own primary platforms (Windows/macOS) `.GIT/config`, `.Secrets/`, `.CLAUDE/settings.local.json`, `MIGRATIONS/`, `.GITHUB/actions/` case variants address the real protected files and bypass DENY/ASK | §7 matrix + NTFS same-file proof |
| D-RM-1 | P2 | Destructive current-directory globs (`rm -rf ./*`, `-- ./*`, `./.??*`, `"./"*`, combinations) are allowed while equivalent bare `*` is denied; dot-targets (`.`, `./`, `..`) also uncaught (inert under GNU rm but intent is destructive) | §6 hook + real-deletion evidence |
| D-OVR-1 | P2 | `check-diff-size.sh` ignores `CLAUDE_HOOK_OVERRIDE` though hooks README:44 documents it as the unblock path; empirically blocked under `=check-diff-size` and `=all` | §11 |
| D-SQL-1 | P2 | `psql -c` / `mysql -e` / `sqlcmd -Q` with quoted no-`;` `DELETE FROM` execute unguarded deletes but are allowed (documented residual; client-aware matching closes it without harming prose controls) | §8 |
| D-DEP-1 | P3 | `npm install --prefix DIR pkg`, `pip install --target DIR pkg`, `pip install --no-deps pkg` slip the dependency ASK tier (value-taking/dash-leading options defeat the patterns) | §9 |
| D-BOOT-1 | P3 | Unknown future `.claude/` local-state files leak into bootstrapped projects (fixed prune list) — to be documented as a limitation, not code-fixed (see §13) | §13 |

## 15. Rejected claims (checked and disproven this session)

| Claim | Verdict |
|---|---|
| "`rm -rf .` deletes the current directory" | **False** on GNU coreutils 8.32: POSIX refusal, exit 1, nothing deleted (§6). The dangerous forms are the globs |
| "`verify-done.sh` still uses `eval`" | False — argument-vector execution since v5 (verify-done.sh:65-77) |
| "Copy-everything-then-prune makes bootstrap slow with big local state" | False — 251 MB of extra state added <0.1 s (§13) |
| "Repo ships CRLF shell scripts / breaks on Linux" | False — index is LF, `.gitattributes` pins `*.sh eol=lf`, fresh clone checks out LF; the CRLF seen locally is a machine-local provisioning artifact (§2) |
| "claude-init cd-claim is wrong" | False — the "cwd untouched" claim scopes to failed bootstraps and holds; success-path `cd` is an intended, printed feature (§11) |
| "`npm install` restore / `pip install -r` are wrongly asked" | False — restores correctly allowed (§9) |
| "NotebookEdit bypasses protect-files" | False — `notebook_path` handled and verified across all 36 matrix runs (§7) |

## 16. Strengths

- 187/187 hook regression cases pass; the suite is table-driven, dependency-light
  (bash+jq+git), and covers allow/ask/deny directions plus installer, settings
  hygiene (SET1-3), bootstrap (BOOT1-13), and secret-output leakage (SS11).
- ShellCheck-clean at CI's pinned v0.10.0 across all ten shell scripts.
- Honest documentation: the SQL residual, prose-FP trade-off, log-security
  rules, blocking-mode semantics, and bootstrap kill-limitation are all
  disclosed where they live — every §11 claim except one verified accurate.
- Live routing evidence committed (4 result sets, consistency-checked), with
  precision 1.0 / conflict 0.0 at 60 runs.
- Deny-before-ask ordering, jq-built ask JSON (injection-safe), fail-open on
  missing jq/malformed input, worktree-aware git detection, and case-folded
  basename gating are all deliberate, tested decisions.
- `.gitattributes` LF pinning demonstrably protects fresh clones on Windows.

## 17. Priorities

- **P1**: D-BUN-1 + D-BUN-2 (verify-done Bun correctness: detect `bun.lock`,
  run the intended script), D-CASE-1 (fold directory segments in protect-files).
- **P2**: D-RM-1 (deny current-directory destructive globs, keep named cleanup),
  D-OVR-1 (honor the documented override in check-diff-size — or fix the doc;
  code fix preferred for contract consistency), D-SQL-1 (client-aware SQL
  matching), D-BUN-3 (host-independent bun tests).
- **P3**: D-DEP-1 (close value-taking-option dependency gaps + document the
  policy), D-BOOT-1 (document unknown-file residual), CHANGELOG v6 entry,
  owner-only proposals (license, release/version policy) prepared inactive.

---

# Post-implementation validation (appended after Phase 3)

Sections 1–17 above are the unmodified blind-audit record. Everything below
was measured after the v6 fixes landed.

## 18. Implementation record

| Commit | Change |
|---|---|
| `711c871` | test: 41 new regression cases (failing-first) |
| `6791547` | fix: verify-done detects `bun.lock`, runs `$PM run test` |
| `5366e92` | fix: protect-files case-folds directory segments |
| `46edf42` | fix: block-destructive — current-dir rm targets, client-wrapped DELETE, env-redirected installs |
| `b40acec` | fix: check-diff-size honors `CLAUDE_HOOK_OVERRIDE` |
| `bddaeaf` | docs: hooks README / claude-init / CHANGELOG sync + owner proposals |

**Failing-first evidence:** with only `711c871` applied the suite reported
`RESULT: pass=197 fail=31` — the 31 failures were exactly the new
deny/ask/bun/override cases (VD9b's argv log captured the wrong `bun test`
command verbatim; VD12 captured the npm misdetection), and all 187 legacy
cases plus the 10 new behavior-locking controls stayed green.

## 19. Final battery (all on final code)

| Check | Result |
|---|---|
| Complete hook suite | **228/228 pass**, exit 0 — real 4m07s (Windows/MSYS) |
| Hook installer | exit 0 |
| ShellCheck v0.10.0 (Docker, LF) | exit 0, all 10 scripts |
| Skill catalog | 37 skills, pass |
| Routing scoring/parser | 15/15 |
| Routing-result consistency | pass (4 sets, fixture=20) |
| `py_compile` (5 files) | exit 0 |
| settings JSON / workflow+fixture YAML | valid |
| Generated-file cleanliness | clean |
| Markdown links | 62 files, pass |
| Live routing eval | **not run — not required** (no skill description or invocation behavior changed) |

Matrix re-runs on the fixed hooks: recursive-rm — all 9 destructive
current-dir forms DENY while `./build`, `../temporary-build`, `build/`,
`node_modules` stay ALLOW; protected paths — **0 allows across all 36
variant×tool runs** (deny for `.GIT`/`.Secrets` variants incl. backslash form,
ask for the rest; `SRC/App.py` control still allows); SQL — all 4 no-`;`
client forms + options variant DENY, WHERE-guarded and all prose controls
ALLOW; dependencies — 24 ask / 9 restore-allow (every restore preserved); Bun —
`bun.lock`, `bun.lockb`, and both-lockfile projects all select bun and invoke
exactly `bun run test` (stub argv), absent-bun runs stay honestly "no
verification" on a restricted PATH; diff-size override allows+logs with the
env var set and still blocks without it. False-positive profile unchanged:
the documented prose denials (`"/bin/rm"`, DROP/TRUNCATE mentions) and prose
allows (`echo 'rm -rf /'`, all DELETE prose) are identical to §10.

## 20. Post-implementation score (same rubric)

| Category | Weight | Blind | Final | Basis for change |
|---|---|---|---|---|
| Technical correctness | 15% | 8.3 | 9.2 | three P1s fixed with failing-first regressions; residuals documented honestly |
| Skill trigger quality | 15% | 8.8 | 8.8 | unchanged — no routing work this cycle (16/37 positive coverage stands) |
| Hook correctness | 15% | 8.2 | 9.3 | all confirmed gaps closed; controls prove no over-widening |
| Conflict avoidance | 10% | 9.0 | 9.0 | unchanged |
| Safety & permissions | 10% | 8.7 | 9.2 | override contract consistent everywhere; four confirmation levels documented |
| Testing & evaluation | 15% | 8.5 | 9.2 | 228 cases; host-independent bun; both-direction override; case variants |
| Context efficiency | 5% | 8.5 | 8.5 | unchanged |
| Team usability | 5% | 9.0 | 9.0 | unchanged |
| Maintainability | 5% | 9.0 | 9.0 | unchanged |
| Public-template readiness | 5% | 7.0 | 7.5 | owner decisions consolidated into actionable proposals; still no license/tag |
| **Weighted total** | | **8.5** | **9.0** | |

**9.0 gate check:** no unresolved P0/P1 ✓ · Bun correct and deterministic ✓ ·
destructive current-directory globs covered ✓ · protected directory case
variants addressed ✓ · false-positive controls pass ✓ · documentation matches
implementation ✓ · final CI green on the exact final commit — verified at push
time and recorded in the pull request (the report cannot contain its own
commit's CI result).

**9.5 is explicitly NOT claimed:** routing coverage is 20 cases / 16 of 37
skills (gate requires broad repeated coverage of all 37), recall 0.963 vs the
>0.90 gate ✓ but precision/conflict evidence spans only those cases;
license/release/public-packaging remain owner decisions (prepared, inactive).
