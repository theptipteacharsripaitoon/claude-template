# Independent Audit — Cycle 5 (blind phase)

Fifth staged review. Phase 1 was performed **without** opening
`external-review-v5.md`; every claim below was reproduced in this session.
No prior cycle's conclusion was carried forward unverified.

## 1. Audited state

| Item | Value |
|---|---|
| Repository | https://github.com/theptipteacharsripaitoon/claude-template.git |
| Audited commit | `21cc3d5ae985f3080cae62b866a74b35b8269379` |
| Relation to `21cc3d5ae…` | **is the current head of `main`** (== `origin/main` after `git fetch`; not merely an ancestor, not obsolete) |
| Work branch | `claude/template-audit-v5-2b6bd3` (linked worktree, created at `21cc3d5`) |
| Working tree at start | clean (`git status --short` empty) |
| Latest CI run | `29675660200` — `completed/success` on **`21cc3d5`** (branch `main`, 2026-07-19T05:58:04Z) |
| CI-tested commit vs audited commit | identical — the audited head itself is CI-green, not just an earlier branch commit (branch-head runs `29675656944`/`29675646660` on `f546f6f` also green) |

## 2. Environment

| Tool | Version |
|---|---|
| Claude Code | 2.1.215 |
| Model | claude-fable-5 |
| OS | Windows 11 Home 10.0.26200 |
| Shell | GNU bash 5.2.15 (x86_64-pc-msys, Git Bash) |
| Git | 2.41.0.windows.3 (`core.autocrlf=true` locally) |
| jq | 1.6 |
| Python | 3.10.9 (PyYAML 6.0.1) |
| ShellCheck | v0.10.0 via Docker 29.5.3 (`koalaman/shellcheck:v0.10.0` — same pin as CI) |
| gh CLI | not installed (GitHub API queried via `curl`) |

Environment note (not a repo defect): this worktree's initial population left the
7 `.claude/hooks/*.sh` files CRLF on disk (`git ls-files --eol` = `i/lf w/crlf`)
even though the **index is LF** and `.gitattributes` pins `*.sh eol=lf`; a fresh
`git checkout --` of the same paths produces LF. The files were renormalized from
the index before linting. msys bash tolerated the CRLF copies (suite still
143/143), so this affected only local ShellCheck.

## 3. Independent score (fixed rubric, pre-fix state)

| Category | Weight | Score | Basis |
|---|---|---|---|
| Technical correctness | 15% | 7.0 | one live P1 (bootstrap masks single-`cp` failures, §6); all suites/validators green otherwise |
| Skill trigger quality | 15% | 8.6 | measured final run: recall 0.963, precision 1.000, no_load 0.037, stability 0.900 — but 20/37 skills covered |
| Hook correctness | 15% | 7.8 | 143/143 suite green, yet 16 measured policy deviations (§8–§10: quoted forms, case variants, option-first installs, semicolon-less DELETE) |
| Conflict avoidance | 10% | 9.0 | measured conflict_rate 0.000; disambiguated descriptions; explicit do-NOT-use pointers |
| Safety & permissions | 10% | 7.5 | `settings.local.json` editable without ask — a docs-verified guardrail-weakening path (§7) |
| Testing & evaluation | 15% | 8.3 | 143-case suite + 6 scoring tests + live routing evidence; missing: cp-failure regressions, stream-parser fixtures, offline routing tests in CI |
| Context efficiency | 5% | 8.5 | CLAUDE.md 4,884 words; 37 descriptions ≈ 19.8k chars always-resident; 200k chars of bodies load on demand |
| Team usability | 5% | 8.4 | strong HOW-TO/hooks README/installer; root README count stale (107 vs 143) |
| Maintainability | 5% | 8.8 | table-driven tests, shared lib, dynamic fixture clusters, duplicate-id rejection |
| Public-template readiness | 5% | 6.0 | no LICENSE (owner-gated), CHANGELOG missing the whole v4 cycle, stale README count |

**Weighted: 8.3 / 10.**

## 4. Test evidence (exact commands, observed results)

| Command | Exit | Observed summary |
|---|---|---|
| `bash tests/hooks/run-tests.sh` | 0 | `RESULT: pass=143 fail=0` — **authoritative suite count: 143** |
| `bash .claude/hooks/install.sh` | 0 | deps + settings valid + smoke + functional tests + override check all ✓ |
| `python tests/skills/routing/test_run_eval.py` | 0 | `routing scoring tests: 6/6 passed` |
| `python tests/skills/check_catalog.py` | 0 | `catalog: 37 skills checked` / `ALL CHECKS PASS` |
| `python -m py_compile` (run_eval, test_run_eval, check_catalog) | 0 | OK |
| `jq empty .claude/settings.json` / `settings.local.json` | 0 | valid JSON |
| PyYAML `safe_load` on `.github/workflows/test.yml` | 0 | valid YAML |
| PyYAML `safe_load` on `tests/skills/trigger-cases.yaml` | 0 | valid; 20 cases; 3 `evaluated_runs` entries |
| ShellCheck v0.10.0 `-x -P .claude/hooks` (8 hook scripts + run-tests.sh + claude-init.sh + seed-repo.sh) | 0 | clean |

## 5. Tracked/ignored hygiene evidence

- `git status --short`: empty at audit start.
- `git ls-files | wc -l`: **83** tracked files.
- `git ls-files '*.pyc'`: **none**. `git ls-files | grep __pycache__`: **none**.
  Any local bytecode is ignored, not tracked (`.gitignore:14 __pycache__/`,
  `.gitignore:15 *.pyc` cover it; `git check-ignore -v` confirms).
- `.claude/settings.local.json` exists locally, is **ignored (untracked)** —
  `.gitignore:2` — and `git status --porcelain --ignored` lists it under `!!`.
- Tracked external reviews: `external-review.md`, `external-review-v2.md` only
  (v3–v5 are untracked local files in the primary checkout).
- `git check-ignore -v` matrix (representative): `.env` → ignored (line 9),
  `.env.local` → ignored (line 10), `.env.example` → **re-included** (line 11),
  `.env.sample`/`.env.template`/`.env.dist`/`.env.test.example` → **ignored**
  (line 10 — see §11), `node_modules/`, `*.log`, `.claude/logs/` → ignored.

## 6. Bootstrap failure matrix (claude-init.sh)

Harness: PATH-injected `cp`/`mv` stubs fail **exactly one** targeted invocation
(match on the source argument) while every later operation would succeed;
template fixtures for installer-failure, slow-installer (interrupt), existing
destination. Assertions per failure case: nonzero exit, no destination, no
success message, no `.claude-init.*` leftover, caller cwd preserved.

```
case                | injected failure       | exit | dest        | temp     | cwd        | success msg | verdict
01-success          | (none)                 | 0    | complete    | none     | cd-to-dest | yes         | PASS (cd-to-dest is designed success behavior)
02-cp-claudemd      | cp CLAUDE.md           | 0    | PUBLISHED, missing CLAUDE.md      | none | cd-to-dest | YES | FAIL
03-cp-dotclaude     | cp -r .claude          | 1    | none        | none     | preserved  | no          | PASS (caught only because install.sh then 127s)
04-cp-gitignore     | cp .gitignore          | 0    | PUBLISHED, missing .gitignore     | none | cd-to-dest | YES | FAIL
05-cp-gitattributes | cp .gitattributes      | 0    | PUBLISHED, missing .gitattributes | none | cd-to-dest | YES | FAIL
06-installer-fails  | install.sh exit 1      | 1    | none        | none     | preserved  | no          | PASS
07-mv-fails         | mv tmp -> dest         | 1    | none        | none     | preserved  | no          | PASS
08-interrupted      | SIGTERM during install | 143  | none        | LEFTOVER | n/a        | no          | INFO: no trap — temp dir remains
09-existing-dest    | pre-existing proj/     | 1    | pre-existing kept | none | preserved | no          | PASS
10-temp-cleanup     | (asserted in every case above — `temp` column)
11-cwd-behavior     | (asserted in every case above — `cwd` column)
```

**Confirmed P1 (V5-1).** A failed copy of `CLAUDE.md`, `.gitignore`, or
`.gitattributes` is **masked**: the bootstrap exits 0, prints
`✅ Project 'proj' bootstrapped …`, and publishes an incomplete project. A
project missing `.gitignore` then stages `.env` on `git add -A` — the exact
hazard BOOT2 exists to prevent.

Root cause (verified against bash semantics, not the comment): the copy block is
`if ! ( set -e; cp …; cp …; cd …; bash install.sh ); then` — a compound command
that is the operand of `!` executes in a context where `-e` is **ignored**, and
per bash's documented rule, a `set -e` issued *inside* such a context has no
effect until the compound command completes. So no `cp` failure short-circuits;
the subshell's status is `install.sh`'s status alone. The in-file comment
(claude-init.sh:64–66) states this mechanism correctly but draws the wrong
conclusion — it relies on install.sh's status while install.sh does not depend
on `CLAUDE.md`/`.gitignore`/`.gitattributes` having been copied.
`.claude`-copy failure (case 03) is caught **accidentally** (bash cannot find
`install.sh` → 127).

Also measured: SIGTERM mid-install leaves the `.claude-init.XXXXXX` temp dir
(case 08) — there is no trap; the header claim "a failed bootstrap leaves … no
temp dir" overreaches for interrupts (P3, V5-12).

## 7. Local-settings assessment

Empirical (protect-files.sh, real payloads, all three tools):

```
path                              Edit   Write  NotebookEdit   current
.claude/settings.json             ask    ask    ask            (suffix rule, line 129)
.claude/hooks/example.sh          ask    ask    ask            (.claude+hooks segments, line 130)
.claude/settings.local.json       ALLOW  ALLOW  ALLOW          (no rule matches)
```

Current Claude Code documentation (code.claude.com/docs/en/settings, fetched
this session): local scope **overrides project and user settings**; Claude Code
saves "don't ask again" permission approvals there; **its permission `allow`
rules take effect without the workspace-trust step that `.claude/settings.json`
allow rules require**; any standard settings key — including `disableAllHooks` —
is accepted. An ungated write to `settings.local.json` is therefore a real,
unapproved path to weaken hooks and permissions (effective next session).

**Intended policy decision: ASK** (V5-2) — same tier as `settings.json` and
`hooks/`. Not DENY: the file is a legitimate per-developer knob, and the ask
tier is exactly "legitimate with the user's approval". Gating Claude's
Edit/Write/NotebookEdit does not interfere with Claude Code's own internal
persistence of approvals (that write is not a hooked tool call).

## 8. Command-policy matrix (block-destructive.sh, executed)

`expected` = documented policy (hooks README tiers / CLAUDE.md §2).
Current branch during evaluation: `claude/template-audit-v5-2b6bd3` (commit-to-
protected-branch is prose-level policy; no hook inspects the branch — recorded,
not a deviation: `git commit` is not in the hook's scope, `git push` is left to
the normal permission flow by documented design).

```
case  | command                                   | expected | actual | result
E1.01 | /bin/rm -rf /                             | deny     | deny   | agree
E1.02 | "/bin/rm" -rf /                           | deny     | allow  | DEVIATE (V5-4)
E1.03 | '/bin/rm' -rf /                           | deny     | allow  | DEVIATE (V5-4)
E1.04 | \rm -rf /                                 | deny     | deny   | agree
E1.05 | rm -rf /                                  | deny     | deny   | agree
E1.06 | rm -rf -- /                               | deny     | deny   | agree
E1.07 | rm -rf "$HOME"                            | deny     | deny   | agree
E1.08 | rm -rf ${HOME}                            | deny     | allow  | DEVIATE (V5-4)
E1.09 | rm -rf "${HOME}"                          | deny     | allow  | DEVIATE (V5-4)
E1.10 | rm -rf build/                             | allow    | allow  | agree (safe control)
E1.11 | echo 'rm -rf /'                           | allow    | allow  | agree (docs text)
E2.01 | git push origin main                      | allow    | allow  | agree (normal perm flow)
E2.02 | git push origin +main                     | deny     | deny   | agree
E2.03 | git push origin "+main"                   | deny     | allow  | DEVIATE (V5-4)
E2.04 | git push origin '+main'                   | deny     | allow  | DEVIATE (V5-4)
E2.05 | git push --force                          | deny     | deny   | agree
E2.06 | git push --force-with-lease               | deny     | deny   | agree
E2.07 | git commit -am wip                        | allow    | allow  | agree (hook scope)
E3.01 | DELETE FROM users                         | deny     | allow  | DEVIATE (V5-6)
E3.02 | DELETE FROM users;                        | deny     | deny   | agree
E3.03 | DELETE FROM dbo.Users                     | deny     | allow  | DEVIATE (V5-6)
E3.04 | DELETE FROM dbo.Users;                    | deny     | deny   | agree
E3.05 | DELETE FROM [dbo].[Users]                 | deny     | allow  | DEVIATE (V5-6)
E3.06 | DELETE FROM [dbo].[Users];                | deny     | deny   | agree
E3.07 | DELETE FROM users WHERE id = 1            | allow    | allow  | agree (guarded)
E3.08 | echo "DELETE FROM users"                  | allow    | allow  | agree (docs text)
E3.09 | git commit -m "document DELETE FROM users"| allow    | allow  | agree (docs text)
E4.01 | npm install lodash                        | ask      | ask    | agree
E4.02 | npm install --save-dev lodash             | ask      | allow  | DEVIATE (V5-5)
E4.03 | npm i -D lodash                           | ask      | allow  | DEVIATE (V5-5)
E4.04 | npm install -g typescript                 | ask      | allow  | DEVIATE (V5-5)
E4.05 | npm ci                                    | allow    | allow  | agree (restore)
E4.06 | pip install requests                      | ask      | ask    | agree
E4.07 | pip install --user requests               | ask      | allow  | DEVIATE (V5-5)
E4.08 | pip install -r requirements.txt           | allow    | allow  | agree (restore)
E4.09 | pip uninstall requests                    | ask      | ask    | agree
E4.10 | pnpm add lodash                           | ask      | ask    | agree
E4.11 | pnpm install                              | allow    | allow  | agree (restore)
E4.12 | yarn add lodash                           | ask      | ask    | agree
E4.13 | yarn install                              | allow    | allow  | agree (restore)
E4.14 | bun add lodash                            | ask      | ask    | agree
E4.15 | bun install                               | allow    | allow  | agree (restore)
E4.16 | uv add httpx                              | ask      | ask    | agree
E4.17 | uv sync                                   | allow    | allow  | agree (restore)
E4.18 | poetry add httpx                          | ask      | ask    | agree
E4.19 | poetry install                            | allow    | allow  | agree (restore)
E4.20 | cargo add serde                           | ask      | ask    | agree
E4.21 | cargo build                               | allow    | allow  | agree
E4.22 | go get example.com/x                      | ask      | ask    | agree
E4.23 | go build ./...                            | allow    | allow  | agree
E4.24 | bundle update                             | ask      | ask    | agree
E4.25 | bundle install                            | allow    | allow  | agree (restore)
E4.26 | gem install rails                         | ask      | ask    | agree
E4.27 | composer require vendor/pkg               | ask      | ask    | agree
E4.28 | composer install                          | allow    | allow  | agree (restore)
```

52 command rows: 36 agree (including every safe control), 16 deviations across
four families — quoted `rm` command word (2), brace-expanded `$HOME` (2), quoted
`+refspec` (2), semicolon-less unguarded DELETE (3), option-first installs (4),
plus §9's file-path rows. The hooks README states "unguarded `DELETE` (incl.
schema-qualified)" is denied without the semicolon caveat, so E3.01/.03/.05 are
simultaneously a coverage gap and a documentation drift.

## 9. Case-folding matrix (protect-files.sh, executed)

On this repo's primary platforms (Windows/macOS), case variants address the
**same file**, so a variant that bypasses is a real bypass.

```
case | path                     | expected | actual | result
F.01 | id_rsa                   | deny     | deny   | agree
F.02 | ID_RSA                   | deny     | allow  | DEVIATE (V5-3)
F.03 | Id_Rsa                   | deny     | allow  | DEVIATE (V5-3)
F.04 | secrets.yaml             | deny     | deny   | agree
F.05 | Secrets.yaml             | deny     | allow  | DEVIATE (V5-3)
F.06 | credentials.json         | deny     | deny   | agree
F.07 | Credentials.json         | deny     | allow  | DEVIATE (V5-3)
F.08 | .npmrc                   | ask      | ask    | agree
F.09 | .NPMRC                   | ask      | allow  | DEVIATE (V5-3)
F.10 | .pypirc                  | ask      | ask    | agree
F.11 | .PYPIRC                  | ask      | allow  | DEVIATE (V5-3)
F.12 | .netrc                   | ask      | ask    | agree
F.13 | .NETRC                   | ask      | allow  | DEVIATE (V5-3)
```

Root cause: only the `.env*` check and the key/cert extension check use
`${BASE,,}`; every `base_is` comparison (and the template allowlist) is exact-
case. Chosen normalization strategy (one, documented): **compare basenames
case-folded everywhere in protect-files.sh** (allowlist, deny names, ask
names), keep segment matching as-is, and keep the **original** casing in every
user-facing reason (`$FILE` is already printed verbatim).

## 10. Composite-action assessment

```
case | path                                  | expected | actual | result
G.01 | .github/actions/example/action.yml    | ask      | ask    | agree
G.02 | .github/actions/example/script.sh     | ask      | allow  | DEVIATE (V5-7)
G.03 | .github/actions/example/index.js      | ask      | allow  | DEVIATE (V5-7)
```

Decision: **the whole `.github/actions/` subtree requires approval.** A
composite action's `script.sh`/`index.js` executes in CI with exactly the trust
of the workflow that calls it; gating only `action.yml` leaves the executable
payload editable. Scope deliberately stays `actions/` (not all of `.github/` —
issue templates and PR templates are documentation).

## 11. Environment-template assessment

protect-files.sh allowlists 5 editable templates; `.gitignore` re-includes only
one of them:

| Template | Hook | Git |
|---|---|---|
| `.env.example` | editable | **committable** (`!.env.example`) |
| `.env.sample` | editable | ignored (`.env.*`) |
| `.env.template` | editable | ignored |
| `.env.dist` | editable | ignored |
| `.env.test.example` | editable | ignored |

The file hook and the tracking policy disagree for 4 of 5 names (V5-8): the hook
calls them "committed env templates" while `git add` silently drops them.
Resolution: add the four `!` re-includes to `.gitignore` (CLAUDE.md §7 says
templates ARE committed; the hook's list is the policy). The generated-project
`.gitignore` is the same file, so bootstrapped projects inherit the fix.

## 12. Secret-layer assessment

Executed probes (fresh `CLAUDE_PROJECT_DIR`, runtime-constructed GitHub-shaped
token, never a real one):

- Real-shaped `ghp_…` in Write content → **exit 2**; probing stdout, stderr and
  `.claude/logs/hooks.log` for the token, its middle, and its tail: **zero
  occurrences**. stderr carries only the pattern name + "value withheld".
- Same-shaped token with `EXAMPLE` inside the value → exit 0 with a logged
  `WARN Skipping secret-shaped fixture` (documented false-negative path).
- Suite cases SS1–SS11 confirm: Edit/Write/NotebookEdit field coverage,
  fake-then-real non-bypass, marker scoped to the value not the line.
- Boundary statement honesty: hook comments and hooks README state the scanner
  sees only inserted content, not reconstructed files, and recommend a
  pre-commit/CI scanner as the second layer — accurate. One drift found: hooks
  README "Log security" claims the matched value/prefix "goes only to Claude's
  stderr" — **false in the safe direction**; since cycle 4 the value goes
  nowhere (V5-11c).

Repository-level scanner: evaluated, **not installed** (explicit constraint). A
proposal for owner sign-off is recorded in §20 (P3) with tool/pin/integration/
false-positive expectations.

## 13. Routing recomputation

Independent recomputation of **all four** committed results (re-deriving every
per-run flag from raw `loaded`/`must_load`/`allowed_companions`/`must_not_load`,
then re-aggregating; not importing run_eval.py):

| Results file | rows | cases | committed vs recomputed | notes |
|---|---|---|---|---|
| routing-20260718-1221 | 57 | 19 | **MATCH** (all 8 fields) | pre-dates `cleanup-repo-recall` case |
| routing-20260718-1652 | 3 | 1 | **MATCH** | post-fix verification, `layout-root-mess` |
| routing-20260718-1656 | 3 | 1 | **MATCH** | recall pin, `cleanup-repo-recall` |
| routing-20260718-195349 | 60 | 20 | **MATCH** | final full run — **absent from `evaluated_runs`** |

Structural checks across all files: no duplicate `(case_id, run)` pairs; run
numbering complete (1..3 per case); every case id exists in the fixture; model
uniform `claude-sonnet-5`; stored derived fields agree with recomputation on all
123 rows. Final-run metrics (authoritative): recall **0.963**, precision
**1.000**, conflict_rate **0.000**, no_load_rate 0.037, stability 0.900,
runs_errored 0.

Provenance findings (V5-9):
1. `evaluated_runs` in trigger-cases.yaml has 3 entries; the final authoritative
   run `routing-20260718-195349` was never appended (run_eval's own docstring
   says to append it; the v4 report's "documentation follow-up" commit `f546f6f`
   updated reports only).
2. The three existing `evaluated_runs` entries hand-carry `cc_version: 2.1.214`
   while their own summary files record `"cc_version": null` (the auto-capture
   fallback landed only for the 195349 run) — plausible but not artifact-backed.
3. Per-row `cc_version` is null in **all** JSONL rows (the `system/init` event's
   `version` field was evidently absent in these streams); only the
   `claude --version` fallback populates summaries.

## 14. Stream-parser assessment

`run_eval.run_once` parses `claude -p --output-format stream-json` inline:
- a line that fails `json.loads` is **silently skipped** (`continue`);
- a stream with no parseable events and returncode 0 yields `loaded=[]`,
  `is_error=False` — i.e. **a parser failure scores as a valid no-load** (miss),
  the precise failure mode Phase 1.I warns about;
- there is `--fail-on-miss`/`--min-recall`/`--max-conflict` but **no
  `--fail-on-error`** gate;
- the extraction logic is not importable/unit-testable in isolation, and the
  offline tests (`test_run_eval.py`) cover scoring math only — none of the seven
  required extraction fixtures (single skill, multiple, unrelated event,
  malformed line, error event, missing-skill event, schema variation) exist;
- CI runs `check_catalog.py` but **not** `test_run_eval.py` (V5-10).

Assessment: extract the parsing into a pure function, count malformed lines and
require a terminal `result` event (else mark the row errored), add the seven
fixtures offline, add `--fail-on-error`, and run the offline tests in CI. No
live routing in ordinary CI (cost/auth), unchanged.

## 15. Documentation drift

| Doc claim | Reality | Verdict |
|---|---|---|
| README: "107-case hook regression suite" | suite prints `pass=143` (authoritative) | **stale** (V5-11a) |
| README: guardrail-not-sandbox warning | absent from root README (HOW-TO:513 and hooks README Limitations carry it) | **missing** (V5-11b) |
| CHANGELOG current cycle | last entry is cycle 3; the entire v4 cycle (`ba00728`…`f546f6f`, 9 commits incl. 6 fix/test commits) has no entries | **missing cycle** (V5-11d) |
| hooks README: secret value/prefix "goes only to Claude's stderr" | probe shows the value goes **nowhere** (stderr says "value withheld") | **stale, safe-direction** (V5-11c) |
| hooks README: "unguarded DELETE (incl. schema-qualified)" denied | only `;`-terminated statements deny (E3.01/03/05) | **overstates coverage** (V5-6) |
| Override docs (`CLAUDE_HOOK_OVERRIDE`) | verified live (BD10 + install.sh check + log line) | accurate |
| Exact final CI commit | `21cc3d5` green (run 29675660200) — recorded in §1 | current |
| Final routing metadata | summaries match recomputation; `evaluated_runs` missing final run (§13) | partly stale |
| Historical reports (v4 tail) | 143/143, routing table, PR/CI ids re-verified against artifacts/API this session | accurate |

## 16. Skill/context assessment

Measured:
- `CLAUDE.md`: **4,884 words / 32,791 chars**.
- 37 skill descriptions (always-resident routing surface): **2,683 words /
  19,751 chars**, mean 533 chars, all under the checked 1,536-char cap.
- Full skill bodies (on-demand): 26,675 words / 200,182 chars across
  `.claude/skills/**/*.md`.

`disable-model-invocation: true` evaluation (repository-cleanup, git-hygiene,
release-readiness, verification): **no change, on routing evidence.** The
fixture *requires* model-invocation of repository-cleanup
(`cleanup-repo-recall`) and git-hygiene (`cleanup-branch-sequence`,
`untrack-node-modules`), and the final run shows their activation is now
correct (precision 1.000 — zero extra loads anywhere in 60 runs, so no measured
idle-activation cost from release-readiness/verification either). Flipping any
of the four to manual-only would break measured recall while fixing no measured
problem. Re-evaluate only if future logs show unwanted activations.

`verify-done.sh` still uses `eval "$cmd"` (line 68) for internally-constructed
constant commands ( `$PM run typecheck` etc.). Not exploitable as-is (no
user-controlled input reaches it), but a safer arg-array dispatch is simple and
regression-covered by VD6–VD10 — worth doing while touching the file (P3).

## 17. Confirmed defects

| ID | Sev | Finding (evidence section) |
|---|---|---|
| V5-1 | **P1** | claude-init masks single-`cp` failures: exit 0 + success message + incomplete project published (§6, cases 02/04/05); `set -e` inert inside `if ! ( … )` |
| V5-2 | P2 | `.claude/settings.local.json` writable with no ask via Edit/Write/NotebookEdit; docs-verified path to weaken permissions/hooks (§7) |
| V5-3 | P2 | 7 sensitive-basename case variants bypass protect-files on case-insensitive filesystems (§9) |
| V5-4 | P2 | quoted `rm` command word, `${HOME}` brace form, quoted `+refspec` bypass block-destructive (§8, 6 rows) |
| V5-5 | P2 | option-first dependency installs (`npm install --save-dev`, `npm i -D`, `-g`, `pip install --user`) bypass the ask tier (§8, 4 rows) |
| V5-6 | P2 | semicolon-less unguarded `DELETE FROM` not denied while hooks README claims it is (§8, 3 rows; doc+pattern drift) |
| V5-7 | P2 | `.github/actions/**` executable payloads (`script.sh`, `index.js`) not gated; only `action.yml` asks (§10) |
| V5-8 | P2 | protect-files' 5-name template allowlist vs `.gitignore` re-including only `.env.example` (§11) |
| V5-9 | P2 | final routing run absent from `evaluated_runs`; hand-entered `cc_version` unsupported by summaries (§13) |
| V5-10 | P2 | stream-JSON parse failures silently become valid no-loads; no `--fail-on-error`; extraction untested; offline routing tests not in CI (§14) |
| V5-11 | P2 | doc drift: (a) README 107 vs 143; (b) README missing guardrail-not-sandbox warning; (c) hooks README secret-stderr claim; (d) CHANGELOG missing the v4 cycle (§15) |
| V5-12 | P3 | interrupt leaves `.claude-init.*` temp dir (no trap); header overclaims (§6 case 08) |
| V5-13 | P3 | verify-done `eval` on constant commands — safe today, safer dispatch available (§16) |
| V5-14 | P3 | local worktree CRLF checkout artifact for hook files (environment; index is LF) (§2) |

## 18. Rejected claims (re-verified, not carried forward)

| Prior claim | Verdict | Evidence |
|---|---|---|
| "Bootstrap is failure-atomic" | **Rejected** | atomic for installer/mv failures only; single-`cp` failures publish incomplete projects (§6) |
| "No live correctness defects exist" | **Rejected** | V5-1 is live and reachable (§6) |
| "The suite count is 143" | **Confirmed by rerun** | `RESULT: pass=143 fail=0` observed; README's 107 is the wrong number (§4, §15) |
| "Bytecode is tracked" | **Rejected** | `git ls-files '*.pyc'` empty; `__pycache__` ignored, never tracked (§5) |
| "Specific command forms bypass" | **Confirmed for 16 variants, rejected for core spellings** | §8 matrix: every unquoted/canonical dangerous form denies; quoted/braced/option-first/semicolon-less variants bypass |
| "Routing evidence is complete" | **Partly rejected** | all four summaries recompute identically, but the final run is unrecorded in `evaluated_runs` and `cc_version` provenance is inconsistent (§13) |

## 19. Strengths to preserve

- Table-driven 143-case suite whose expectations encode *correct* behavior, with
  safe-control counterexamples beside every deny widening.
- Deny/ask two-tier design with jq-built (injection-proof) ask JSON; override
  mechanism that is logged, tested, and documented.
- Secret scanner that provably never prints or persists matched material, with
  value-scoped fixture markers and honest boundary documentation.
- Component/basename path matching (no substring false positives — PF10/PF13
  keep passing), `..`-non-resolution documented as over-cautious.
- Live routing evaluation with per-run JSONL, machine-checkable summaries (all
  recompute identically), seeded domain repos, and duplicate-id rejection.
- Pinned, least-privilege CI (SHA-pinned actions, checksum-verified ShellCheck,
  concurrency cancellation) that tests the exact audited commit.
- Honest limitation docs (HOW-TO "guardrails, not a sandbox"; hooks README
  Limitations; ENFORCEMENT layer model).

## 20. Recommendations

**P1**
1. V5-1: make every copy short-circuit (`&&`-chain inside the subshell — `&&`
   works regardless of `set -e` context), validate the four required paths in
   `$tmp` before the rename, correct the misleading comment, and add
   one-failure-at-a-time PATH-stub regressions.

**P2**
2. V5-2: ASK-gate `settings.local.json` (policy §7) + 3-tool regressions.
3. V5-3: case-fold all basename comparisons in protect-files; mixed-case tests;
   original casing kept in reasons.
4. V5-4/V5-5/V5-6: extend block-destructive for quoted-rm, `${HOME}`, quoted
   `+refspec`, option-first installs, and end-anchored semicolon-less unguarded
   DELETE — each widening paired with safe controls (`echo`/commit-message/
   `WHERE`/restore forms stay allowed; measure before/after).
5. V5-7: ask-gate the `.github/actions/` subtree.
6. V5-8: re-include the four ignored template names in `.gitignore`.
7. V5-9: append the 195349 run to `evaluated_runs`; annotate the unsupported
   `cc_version` fields.
8. V5-10: extract + fixture-test the stream parser (7 cases), add
   `--fail-on-error`, treat missing-result/parse-error rows as errored, run
   offline routing tests in CI.
9. V5-11: README count + guardrail warning; hooks README secret-stderr and
   DELETE wording; CHANGELOG entries for cycles 4 and 5.

**P3**
10. V5-12: either add interrupt-cleanup guidance to the header comment
    (chosen: honest docs; a trap inside a *sourced function* would mutate the
    caller's shell traps) or document the leftover-name pattern.
11. V5-13: replace `eval` with direct arg execution in verify-done's
    `run_check`.
12. Repository-level secret scanner (owner approval required — **not**
    installed): gitleaks v8.x pinned by SHA in a pre-commit config and/or a CI
    job (`gitleaks detect --no-banner --redact`), expected false positives:
    runtime-constructed suite fixtures (already scanner-hostile by
    construction), `AKIA`-shaped strings inside hook regexes — mitigate with a
    `.gitleaks.toml` allowlist scoped to `tests/hooks/run-tests.sh` and
    `.claude/hooks/scan-secrets.sh` pattern lines. Decision, tool, and pin are
    the owner's.
13. Owner items unchanged: LICENSE, release tag/versioning, CONTRIBUTING/
    SECURITY, template-repo flag.

---

## Post-implementation validation (appended after Phases 3–5; Phase 1 above is unchanged)

Implementation commits on `claude/template-audit-v5-2b6bd3` (each fix landed
with its regression in the same cycle):

| Commit | Change |
|---|---|
| `d6b6949` | fix(bootstrap): `&&`-chained copies + staged-tree validation before rename (V5-1) |
| `237632f` | fix(hooks): case-folded basenames; settings.local.json / `.github/actions/` ask; `*.pem` deny→ask (V5-2/3/7, adjudication #12) |
| `f2a2d87` | fix(hooks): quoted/braced/option-first/semicolon-less variants; protected-branch commit ask (V5-4/5/6, adjudication #14) |
| `4de50fa` | refactor(hooks): verify-done `eval` → argument vectors (V5-13) |
| `f87b5c7` | chore: `.gitignore` re-includes all five supported env templates (V5-8) |
| `dd73465` | test(hooks): +44 regressions — suite 143 → **187** |
| `df2e181` | test(routing): pure `parse_stream`/`stream_anomaly`, 9 parser fixtures, `--fail-on-error`, results-consistency test, `evaluated_runs` completed (V5-9/10) |
| `934400c` | test: repo-wide Markdown link check |
| `9540d4a` | ci: offline routing/consistency/compile/YAML/cleanliness/link steps (V5-10d) |
| `24cb1ba` | docs: README warning + non-brittle count; hooks README behavior sync; CHANGELOG cycles 4+5; scanner proposal (V5-11, adjudication #13) |

### Full validation battery (final tree, all observed this session)

| Check | Result |
|---|---|
| Hook suite (`bash tests/hooks/run-tests.sh`) | exit 0 — `RESULT: pass=187 fail=0` |
| Installer (`bash .claude/hooks/install.sh`) | exit 0 |
| Bootstrap failure harness (11-case, PATH-stub) | 8/8 assertable cases PASS; case 08 (kill -TERM) = documented temp-dir limitation, now stated in the header |
| ShellCheck v0.10.0 (pinned, `-x -P .claude/hooks`, all 10 scripts) | exit 0 |
| Catalog checker | 37 skills, ALL CHECKS PASS |
| Routing scoring + stream-parser fixtures | 15/15 passed |
| Results/fixture consistency | ALL CHECKS PASS (4 result sets, 4 `evaluated_runs` entries, 20 fixture cases) |
| `py_compile` (5 files) / settings JSON / workflow+fixture YAML | all OK |
| Generated-file tracking | no tracked `*.pyc` / `__pycache__` |
| Markdown link check | 59 tracked files, ALL CHECKS PASS |
| Command/path policy matrix (74 rows, §7–§11 re-run) | **0 deviations** — every dangerous variant deny/ask, every safe control (prose, restores, WHERE-guarded, `rm -rf build/`, templates) still allowed |
| Live routing | **not re-run, by rule**: no skill description or invocation behavior changed this cycle; committed 195349 metrics remain authoritative |

### Re-score (same fixed rubric)

| Category | Weight | Pre | Post | Basis for change |
|---|---|---|---|---|
| Technical correctness | 15% | 7.0 | 9.2 | P1 fixed + 4 stub regressions; all validators green |
| Skill trigger quality | 15% | 8.6 | 8.6 | unchanged (no description edits); still 20/37 coverage |
| Hook correctness | 15% | 7.8 | 9.2 | 74-row matrix 0 deviations; residuals documented (quote-wrapped `;`-less SQL, semantic equivalents) |
| Conflict avoidance | 10% | 9.0 | 9.0 | unchanged (measured 0.000) |
| Safety & permissions | 10% | 7.5 | 9.0 | both settings layers gated; case-fold; actions subtree; protected-branch ask; PEM tier rationalized |
| Testing & evaluation | 15% | 8.3 | 9.2 | 187-case suite; parser fixtures; consistency gate; all offline checks in CI |
| Context efficiency | 5% | 8.5 | 8.5 | unchanged (measured, justified) |
| Team usability | 5% | 8.4 | 8.8 | docs synced; warning added; non-brittle count |
| Maintainability | 5% | 8.8 | 9.0 | eval removed; pure testable parser; consistency invariants |
| Public-template readiness | 5% | 6.0 | 6.5 | CHANGELOG complete, proposal ready — LICENSE/release still owner-gated |

**Weighted: 8.9 / 10** (up from 8.3). The 9.0-gate correctness conditions are
all met (no open P0/P1, bootstrap safe, settings gated, variants covered,
controls pass, parser tested, docs match); the weighted number stays below
9.0 because skill-routing coverage (20/37) and public-template readiness
(LICENSE, release policy — owner decisions) are unchanged by instruction.
9.5 is out of reach for the same reasons (not all categories ≥9, no
37-skill coverage, licensing/release incomplete). No change was made whose
only purpose was score movement.

### Final evidence chain

- Audited base: `21cc3d5` (CI run `29675660200`, success, recorded in §1).
- A committed report cannot contain its own commit's SHA or CI run id, so:
  the branch head is the commit that adds this section; its exact SHA, its
  CI run id, and the green/failed verdict for that exact SHA are recorded in
  the pull-request description and were verified **before** any "final
  commit is green" claim was made anywhere.
- Remaining limitations (unchanged by instruction): no LICENSE / release
  policy (owner), routing coverage 20/37 skills (live-model budget, owner),
  repository-level secret scanner not installed (owner;
  `reports/proposal-secret-scanner.md`), quote-wrapped semicolon-less SQL
  and semantic equivalents outside regex reach (documented tiers).
