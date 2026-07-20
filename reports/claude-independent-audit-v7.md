# Claude independent audit — v7 (blind)

**This section was written before `external-review-v7.md` was opened.** It is the
blind half of the v7 cycle: every claim below is reproduced from this repository
at the audited commit, with the exact command recorded. Post-implementation
evidence is appended at the end of the cycle without rewriting this section.

---

## 1. Exact state

| Item | Value |
|---|---|
| Repository | `https://github.com/theptipteacharsripaitoon/claude-template.git` |
| Audited commit | `97c1f716df17ec3f8581a735a2eb61a8b7f5c01a` |
| Commit subject | `Merge pull request #13 … claude/template-audit-v6` |
| Status of `97c1f71…` | **Current `origin/main` HEAD** — not an ancestor-only, not obsolete |
| Work branch | `claude/template-audit-v7` (created at the audited commit) |
| Latest CI run on the audited commit | run `29690114642`, workflow `template-tests`, conclusion **success** |
| Commit tested by that run | `97c1f716df17ec3f8581a735a2eb61a8b7f5c01a` (exact match) |

`git merge-base --is-ancestor 97c1f716… origin/main` → true, and `git log origin/main -1`
resolves to the same SHA, so the audited tree is byte-identical to published `main`.

Carried into this cycle from an interrupted prior session: three **untracked**
files (`tests/hooks/corpus.jsonl`, `tests/hooks/run-corpus.sh`,
`tests/hooks/results/`). They were not trusted as-given — the corpus was re-run
from scratch in this session and reproduced its published summary exactly
(§6), which is why it is adopted rather than rebuilt.

## 2. Environment

| Component | Version |
|---|---|
| OS | Windows 11 Home 10.0.26200 |
| Shell | PowerShell (primary); Git Bash `GNU bash 5.2.15(1)` (hook execution) |
| Claude Code model | Opus 4.8 (`claude-opus-4-8`) |
| Git | 2.41.0.windows.3 |
| jq | 1.6 |
| Python | 3.10.9 local — **CI pins 3.12** (drift recorded) |
| PyYAML | 6.0.1 local — **CI pins 6.0.2** (drift recorded) |
| ShellCheck | not installed locally; run via `koalaman/shellcheck:v0.10.0` (Docker 29.5.3), the version CI pins |
| Node / npm | v18.16.0 / 9.5.1 |
| Bun | **absent** — `bun.lock` detection in `verify-done.sh` is exercised by fixture, not by a real Bun |
| Package managers present | npm; pnpm/yarn/poetry/uv/cargo/go absent locally |

Version drift (Python 3.10 vs 3.12, PyYAML 6.0.1 vs 6.0.2) is small but real: local
green does not prove CI green, so every claim below that matters is confirmed on
the CI run for the exact commit.

## 3. Independent pre-change score

Scored against the fixed rubric, from the evidence in §4–§12 only.

| Category | Weight | Score | Basis |
|---|---:|---:|---|
| Technical correctness | 15% | 7.5 | 228/228 hook tests green, ShellCheck clean, CI green — but 27 corpus contract violations incl. one structural bypass |
| Skill trigger quality | 15% | 7.0 | 37/37 carry trigger phrases; only **16/37 have positive routing evidence** |
| Hook correctness | 15% | 6.5 | Commands that really destroy a tree are allowed (§5 E); three README-claimed behaviours not delivered |
| Conflict avoidance | 10% | 8.0 | Measured conflict rate 0.0 on the covered subset; 6/37 skills carry no negative signal |
| Safety and permissions | 10% | 7.5 | Four-tier model coherent, override logged, deny-before-ask documented; gaps above cost it |
| Testing and evaluation | 15% | 7.0 | Strong harnesses; corpus uncommitted, routing at 43% skill coverage, no session evidence, no latency budget |
| Context efficiency | 5% | 6.5 | ~12,984 tokens always loaded |
| Team usability | 5% | 7.0 | HOW-TO + hooks README strong; no CONTRIBUTING, no profiles, no installer dry-run |
| Maintainability | 5% | 8.0 | Clean lint, dense rationale comments, green CI, changelog discipline |
| Public-template readiness | 5% | 4.0 | No LICENSE, SECURITY, CONTRIBUTING, issue/PR templates, or version/compatibility policy |

**Weighted independent pre-change score: 7.0 / 10.**

## 4. Existing test evidence

Every command run to completion on the audited commit. Platform: Windows 11 /
Git Bash unless noted.

| Evidence | Command | Exit | Duration | Count |
|---|---|---:|---:|---|
| Hook regression suite | `bash tests/hooks/run-tests.sh` | 0 | 253.7 s | **228 pass / 0 fail** |
| Hook installer | `bash .claude/hooks/install.sh` | 0 | 7.8 s | 8 embedded functional checks pass |
| ShellCheck | `docker run … koalaman/shellcheck:v0.10.0 -x -P .claude/hooks …` | 0 | 2.4 s | 0 findings |
| Skill catalog | `python tests/skills/check_catalog.py` | 0 | 0.21 s | 37 skills, ALL CHECKS PASS |
| Routing parser / scoring | `python tests/skills/routing/test_run_eval.py` | 0 | 0.18 s | 15/15 |
| Result consistency | `python tests/skills/routing/test_results_consistency.py` | 0 | 0.20 s | 4 result sets, 20 fixture cases |
| Python compilation | `python -m py_compile …` (5 files) | 0 | 0.18 s | 5 files |
| Markdown links | `python tests/check_links.py` | 0 | 0.19 s | 62 tracked files |
| YAML validation | `yaml.safe_load` on workflow + fixture | 0 | — | 2 files parse |
| JSON validation | `json.load` over `git ls-files '*.json'` | 0 | — | 5 files, 0 invalid |
| Generated-file cleanliness | `git ls-files '*.pyc' / __pycache__` | 0 | — | clean (on-disk `tests/__pycache__` correctly gitignored) |

All existing evidence passes. **No regression was found in what the repo already
tests.** Every defect below lives in a boundary the existing suite does not cover.

## 5. Correctness reproduction matrix

Reproduced with two harnesses written for this audit
(`scratchpad/probe-1b.sh`, `scratchpad/probe-stop.sh`). Both keep their command
lists *inside the file* rather than on a Bash command line — an early attempt
put them on the command line and was blocked by the operator's globally
installed copy of these very hooks, which is incidental but genuine field
evidence that the ask tier fires.

### A. Environment templates — `protect-files.sh`

| Path | Contract | Actual | Verdict |
|---|---|---|---|
| `.env.example` | allow (editable template) | allow | ✅ |
| `.git/.env.example` | **deny** (`.git` segment) | **allow** | ❌ bypass |
| `.secrets/.env.example` | **deny** (`.secrets` segment) | **allow** | ❌ bypass |
| `.claude/hooks/.env.example` | **ask** (hooks segment) | **allow** | ❌ bypass |
| `.github/actions/example/.env.example` | **ask** (actions subtree) | **allow** | ❌ bypass |
| `.github/workflows/.env.example` | **ask** (CI) | **allow** | ❌ bypass |

**Root cause — single, structural.** [`protect-files.sh:57-61`](../.claude/hooks/protect-files.sh)
runs the template allowlist as a bare `exit 0` *before* any DENY or ASK
evaluation. It is written as an exception to the `.env*` deny rule but
implemented as an exception to the **entire hook**. Any path whose basename is
`.env.example` / `.sample` / `.template` / `.dist` / `.test.example` escapes
`.git`, `.secrets`, workflows, actions, hooks, infra, migrations — every rule.
This is exactly the boundary the task predicted: *the basename exception must
not bypass unrelated path policy.* It does.

### B. Recursive deletion — hook decision **and** real behaviour

Each form ran in a disposable sandbox seeded with 8 entries
(`visible.txt`, `.hidden`, `sub/`, `sub/s.txt`, `build/`, `build/b.txt`,
`.git/`, `.git/config`). "Real effect" is measured, not predicted.

| Command | Hook | Real effect | Verdict |
|---|---|---|---|
| `rm -rf -- .[!.]*` | allow | 8 → 5 — **deleted `.hidden` and `.git/`** | ❌ |
| `rm -rf -- ./.[!.]*` | allow | 8 → 5 — same | ❌ |
| `rm -rf -- .[^.]*` | allow | 8 → 5 — same | ❌ |
| `rm -rf -- "$PWD"` | allow | **entire directory destroyed** | ❌ |
| `rm -rf -- "${PWD}"` | allow | **entire directory destroyed** | ❌ |
| `rm -rf -- "$(pwd)"` | allow | **entire directory destroyed** | ❌ |
| `rm -rf -- {*,.[!.]*,..?*}` | allow | 8 → **0 — everything destroyed** | ❌ |
| `rm -rf ./build` | allow | 8 → 6 (named cleanup) | ✅ intended-allow control holds |
| `rm -rf '/srv/data'` | allow | n/a (path absent) | ❌ quoting defeats the absolute-path rule |

Three uncovered families, all confirmed destructive in practice:

1. **Character-class dotglobs** (`.[!.]*`, `.[^.]*`). The v6 work enumerated
   `./*`, `.`, `..`, `.??*` and stopped there.
2. **`$PWD` / `${PWD}` / `$(pwd)`** — `$HOME`/`${HOME}`/`~` are covered; the
   current-directory equivalents sit one line away and are not.
3. **Brace expansion** (`{*,.[!.]*,..?*}`) — the `\*` pattern requires `*`
   immediately after the flags; `{` breaks it.

`rm -rf '/srv/data'` is a **separate and sharper defect**: the `${RM_REC}/`
pattern has no optional-quote class, while the sibling `$HOME` pattern on the
very next line does (`[\"']?`). Quoting the *target* — not the command — escapes
the absolute-path deny that the README explicitly promises.

**Bounded guarantee (proposed wording, not yet shipped).** Regex cannot parse
shell. What this hook can honestly claim is: *it denies recursive-`rm`
invocations whose target token, after an optional end-of-options marker and an
optional quote, begins with `/`, `~`, a `$HOME`/`$PWD` expansion, `*`, or a
dot-target/dot-glob form.* It cannot claim to catch arbitrary expansion,
command substitution producing a path, variables holding a path, or any
non-`rm` deletion. That statement is falsifiable and testable; "blocks
destructive deletion" is not.

### C. Git invocation variants

Fixture repos on real branches; branch evaluated against `CLAUDE_PROJECT_DIR`.

| Command | On `main` (contract: ask) | On `feat/x` (contract: allow) |
|---|---|---|
| `git commit -am wip` | ask ✅ | allow ✅ |
| `env git commit -am wip` | ask ✅ | allow ✅ |
| `command git commit -am wip` | ask ✅ | — |
| `git -C . commit -am wip` | **allow** ❌ | — |
| `/usr/bin/git commit -am wip` | **allow** ❌ | — |
| `git -C ../other-repo commit -am wip` | **allow** ❌ | — |

Two root causes:

1. `'(^|[[:space:];|&])git[[:space:]]+commit'` requires `commit` to follow `git`
   **adjacently**, so any global option (`-C`, `-c`, `--git-dir`) hides it.
2. The character class omits `/`, so `/usr/bin/git` is not a command position —
   even though `RM_WORD` deliberately *includes* `/` for exactly this reason.
   The two hooks disagree with each other about what a command word is.

**Separately (semantic, not regex):** branch detection always reads
`CLAUDE_PROJECT_DIR`, never the `-C` target. Confirmed: with the project on
`feat/x` and `-C` pointing at a repo on `main`, the hook evaluates `feat/x` and
allows. The reverse (project on `main`, `-C` elsewhere) would ask about the
wrong repository. This cannot be fixed by widening a regex and belongs in the
documented bounded guarantee.

### D. SQL clients

| Command | Contract | Actual |
|---|---|---|
| `psql -c "DELETE FROM users"` | deny | deny ✅ |
| `mysql -e "DELETE FROM users"` | deny | deny ✅ |
| `sqlcmd -Q "DELETE FROM dbo.Users"` | deny | deny ✅ |
| `psql --command="DELETE FROM users"` | deny | **allow** ❌ |
| `psql --command "DELETE FROM users"` | deny | **allow** ❌ |
| `mysql --execute="DELETE FROM users"` | deny | **allow** ❌ |
| `sqlcmd --query "DELETE FROM dbo.Users"` | deny | **allow** ❌ |
| `echo "DELETE FROM users"` (prose control) | allow | allow ✅ |
| commit-message prose control | allow | allow ✅ |

The pattern hard-codes `-[ceq]` — a single-dash single letter. Every long-form
spelling escapes. The prose controls still behave correctly, so the fix must
preserve the quote-boundary that keeps documentation allowed.

### E. Dependency decisions — policy table

| Command | Class | Actual | Verdict |
|---|---|---|---|
| `npm ci` | restore | allow | ✅ |
| `npm install` | restore | allow | ✅ |
| `pip install -r requirements.txt` | restore | allow | ✅ |
| `uv sync` | restore | allow | ✅ |
| `npm install lodash` | project dep decision | ask | ✅ |
| `pip install requests` | project dep decision | ask | ✅ |
| `cargo add serde` | project dep decision | ask | ✅ |
| `npm install https://example.invalid/pkg.tgz` | remote tarball | ask | ✅ |
| `npm --prefix /tmp install lodash` | env-redirected | **allow** | ❌ |
| `pip install --constraint constraints.txt requests` | project dep decision | **allow** | ❌ |
| `pip install -c constraints.txt requests` | project dep decision | **allow** | ❌ |
| `pip install -q requests` | project dep decision | **allow** | ❌ |
| `npm install ./local-package` | local path install | **allow** | ⚠ policy |
| `pipx install black` | global tool install | **allow** | ⚠ policy |
| `uv tool install ruff` | global tool install | **allow** | ⚠ policy |
| `cargo install ripgrep` | global tool install | ask | ⚠ **accidental** |
| `gem install bundler` | global tool install | ask | ✅ |
| `go install ./cmd/x` | global tool install | ask | ✅ |

Two distinct problems.

**(i) pip's pattern is option-hostile.** `'pip3?[[:space:]]+install[[:space:]]+[^-]'`
requires a non-dash immediately after `install `. npm solves this with an
option-skip idiom (`(-{1,2}[A-Za-z][A-Za-z-]*[[:space:]]+)*`); pip has no
equivalent and instead enumerates individual long options. Any option not on
that list — `-q`, `-c`, `--constraint`, and every future one — silently
downgrades a real install to allow. `-q` is the proof: a bare verbosity flag
defeats a supply-chain gate. **One root cause, one fix, three corpus rows.**

**(ii) The ask patterns are unanchored, so matching is accidental.** Verified
directly against `grep -E`:

| Pattern | Input | Result |
|---|---|---|
| `go[[:space:]]+install[[:space:]]` | `cargo install ripgrep` | **MATCH** |
| `go[[:space:]]+install[[:space:]]` | `mongo install thing` | **MATCH** |
| `go[[:space:]]+get[[:space:]]` | `django get stuff` | **MATCH** |
| `gem[[:space:]]+install[[:space:]]` | `echo gem install foo` | **MATCH** |

So `cargo install ripgrep` asks **for the wrong reason** — it substring-matches
the Go pattern via the trailing `go` of `car-go`. This is luck, not policy, and
it cuts both ways: prose that merely mentions a dependency command is asked
about. `RM_WORD` was written with great care about command positions; the
dependency patterns were not, and they are the ones that fire most often.

**Policy question for §16 (owner-facing):** should a *global tool install*
(`pipx`, `uv tool`, `cargo install`) ask? It does not mutate the project
manifest, but it fetches and executes new third-party code, and `gem install` /
`go install` already ask. The current state is not a decision, it is an
inconsistency.

### F. Strict Stop contract

`CLAUDE_VERIFY_BLOCK=1`, measured per scenario:

| Scenario | Exit | Behaviour |
|---|---:|---|
| Code changed, no checker — reminder mode | 0 | prints §16 checklist |
| Code changed, no checker — strict | 0 | warns "nothing was verified", **does not block** |
| Checker executable missing — strict | 0 | skipped with a note, **does not block** |
| Passing checker — strict | 0 | reports pass |
| **Failing checker — strict** | **2** | **blocks** ✅ |
| Second Stop (`stop_hook_active=true`) | 0 | silent, re-entry guard |
| Change committed during session | 0 | **invisible** — no reminder at all |

**Answer to the posed question: strict mode enforces, but only inside a narrow
window.** It blocks if and only if a checker is discovered, runs, and fails, on
the first Stop of a turn. "No checker found" and "toolchain missing" both exit 0
— deliberately, and honestly reported, so *cannot verify* never masquerades as
*verified*. That is the right call, but it means strict mode's guarantee is
"never lets a **known-failing** verification pass silently," not "guarantees
verification happened." The re-entry guard further means it blocks **at most
once** per turn. And because detection reads `git status`, work already
committed during the session is invisible to it. All three limits are correct
engineering; none is currently stated as a contract.

## 6. Hook policy corpus baseline

Schema (`tests/hooks/corpus.jsonl`, one labelled row per line):

| Field | Meaning |
|---|---|
| `id`, `category`, `tool` | identity and routing to the right hook set |
| `command` / `file_path` | the input under test |
| `expected` | the **contract** decision — a mismatch is a live defect |
| `ideal` | semantic ground truth where it differs from contract (documented trade-offs); defaults to `expected` |
| `oos` | true for known out-of-scope semantic equivalents (e.g. `shutil.rmtree`) |
| `project` | `main` / `feat` fixture repo for branch-sensitive rows |
| `content_parts` / `gen_lines` | payload construction for file-tool rows |

The runner replays each row through the **real** hooks (Bash rows →
`block-destructive`; file rows → `protect-files` + `scan-secrets` +
`check-diff-size`), applying Claude Code's own precedence: any exit 2 = deny,
else any `permissionDecision:"ask"` = ask, else allow. It unsets
`CLAUDE_HOOK_OVERRIDE` so an operator's ambient override cannot silently green
the run.

Reproduced independently this session:

```
bash tests/hooks/run-corpus.sh     → exit 0, 390.9 s
rows=205  scored=198  out_of_scope=7 (3.4%)  contract_violations=27
```

Identical to the summary the interrupted session left behind, which is why that
artefact is adopted rather than rebuilt.

### Confusion matrix (205 rows)

| | got deny | got ask | got allow |
|---|---:|---:|---:|
| **expected deny** (99) | 84 | 0 | **15** |
| **expected ask** (52) | 0 | 40 | **12** |
| **expected allow** (54) | 0 | 0 | 54 |

| Metric | Value |
|---|---:|
| Dangerous-action recall | **0.821** |
| Strict deny recall | 0.848 |
| Legitimate-action allow rate | **1.000** |
| False-deny rate | **0.000** |
| False-allow rate | **0.179** |
| Ask accuracy | 0.769 |
| Out-of-scope rate | 0.034 |
| False positives vs ideal | 7 |
| False negatives vs ideal | 33 |

**Read this honestly.** The zero false-deny rate and perfect legitimate-allow
rate are the good news and they are not accidental — this template has
consistently chosen not to annoy. But the failure mode is entirely one-sided:
**27 dangerous or approval-requiring actions are silently allowed, and nothing
legitimate is ever blocked.** A prevention layer with an 18% false-allow rate
and a 0% false-deny rate is tuned too loose, not too tight. Every fix in the
roadmap moves rows out of the `allow` column, and the corpus exists to prove no
fix moves a row *into* a false deny.

### Violations by category

| Category | Rows | Violations |
|---|---:|---:|
| filesystem | 42 | 8 |
| dependencies | 37 | 7 |
| protected-files | 29 | 5 |
| sql | 18 | 4 |
| git | 23 | 2 |
| quoting | 5 | 1 |
| diff-size / harmless-prose / infrastructure / option-order / path-variants / secrets | 72 | 0 |

Harmless prose (10 rows), option order (5), path variants (10) and secrets (8)
are clean — the loose spots are specific, not systemic.

## 7. Performance measurements

n=20 per hook, Windows 11 / Git Bash. Milliseconds, wall clock, cold cache.

| Path | p50 | p95 |
|---|---:|---:|
| **Ordinary Bash command** (`block-destructive`) | **2179** | **2409** |
| Secret scan (clean write) | 724 | 779 |
| Diff-size check | 373 | 429 |
| Protected write (ask) | 358 | 424 |
| Stop reminder | 312 | 366 |
| Stop strict, no checker | 308 | 357 |

**The hook on the hottest path is 6× slower than every other hook.**
`block-destructive` loops ~85 patterns, each running `echo "$CMD" | grep -qiE`
— roughly 170 process spawns per Bash tool call. On Windows, where `fork` is
expensive, that is ~2.2 s added to *every single Bash invocation*. This is not a
correctness bug and CI never sees it (the workflow measures nothing), but it is
the single largest usability tax the template imposes, and it grows every time
someone adds a pattern. The fix is mechanical — one combined alternation, or
`grep -Ef` against a pattern file — and reduces ~170 spawns to ~2.

`settings.json` declares a 10 s timeout for PreToolUse validators; at p95 2.4 s
the margin is ~4×, so this is a latency problem, not yet a correctness one.

No CI duration is recorded for any hook path — the workflow has no timing step.

## 8. Every-skill coverage matrix

Catalog: **37 skills**, all passing `check_catalog.py`.

### Description / body inventory

| Measure | Value |
|---|---:|
| Skills | 37 |
| Descriptions (always loaded) | ~4,925 tokens |
| Bodies (loaded on demand) | ~40,072 tokens |
| Carrying trigger phrases | **37 / 37** |
| Carrying a negative signal (`Do NOT use …`) | **31 / 37** |
| Frontmatter keys in use | `name`, `description` only |

**Six skills carry no negative routing signal — and they are the worst six to
omit**, because each has a close neighbour it can be confused with:

| Skill | Body ~tokens | Nearest neighbour(s) with no stated boundary |
|---|---:|---|
| `web-security` | 2,443 | `security-review` |
| `testing` | 2,017 | `verification`, `python-review` |
| `api-design` | 2,007 | `api-review`, `fastapi-review` |
| `database-migrations` | 2,006 | `database-review`, `sql-layout` |
| `observability` | 2,112 | `verification` |
| `kubernetes` | 1,605 | `docker`, `docker-review` |

These are also five of the six largest bodies, so a misroute is both likely and
expensive.

### Routing evidence coverage — the headline gap

`tests/skills/trigger-cases.yaml`: 6 clusters, **20 cases**.

| Coverage | Count |
|---|---|
| Skills required as a primary (`must_load`) | **16 / 37** |
| Skills appearing anywhere (primary, companion, or negative) | 20 / 37 |
| Skills with **no positive coverage** | **21** |
| Skills absent from the fixture entirely | **17** |

No positive coverage (21): `agent-design`, `api-design`, `config-management`,
`database-migrations`, `dependency-review`, `design-system`, `docker`,
`docker-review`, `documentation`, `fastapi-review`, `kubernetes`,
`llm-evaluation`, `observability`, `prompt-engineering`, `python-performance`,
`python-refactor`, `python-review`, `release-readiness`, `testing`, `ui-review`,
`verification`.

Last authoritative live run (v4 cycle, `results/routing-20260718-195349.jsonl`,
Claude Code 2.1.214, `claude-sonnet-5`, 20 cases × 3 reps = 60 runs, 0 errored):

| Metric | Value |
|---|---:|
| Recall | 0.963 |
| Precision | 1.000 |
| Conflict rate | 0.000 |
| No-load rate | 0.037 |
| Stability | 0.900 |

**Those numbers are good and they are not sufficient.** They describe 16 of 37
skills — 43% of the catalog. The 9.0 gate requires complete positive coverage
for all 37 plus broad negative/ambiguous/conflict coverage, so **routing is the
single largest blocker to a defensible 9.0**, not hook correctness. Extending
the fixture to 37 skills with negative and ambiguous cases, then re-running
live at ≥3 reps, is the largest remaining unit of work in this cycle.

Also recorded: the authoritative run used `claude-sonnet-5` on Claude Code
2.1.214. This session is Opus 4.8. Routing results are model-dependent, so the
re-run must record its own model and version rather than inherit these.

Per-skill rows (positive / negative / ambiguous / nearest-neighbour conflict /
allowed companions / forbidden extras / seed repo / expected primary) are
designed in §12 and built in Phase 6; they are deliberately not fabricated here.

## 9. Context inventory

Approximation: tokens ≈ chars/4 (stated as an estimate, not a tokenizer count).

| Artefact | Lines | Words | Chars | ~Tokens | Loaded |
|---|---:|---:|---:|---:|---|
| `CLAUDE.md` | 417 | 4,883 | 32,187 | **8,046** | always |
| Skill descriptions (37) | — | — | 19,700 | **4,925** | always |
| **Always-loaded total** | | | | **~12,984** | |
| `.claude/hooks/README.md` | 265 | 2,537 | 17,412 | 4,353 | on demand |
| `HOW-TO.md` | 555 | 2,276 | 16,023 | 4,005 | on demand |
| `README.md` | 42 | 326 | 2,551 | 637 | on demand |
| Skill bodies (37) | — | — | 160,288 | 40,072 | on demand |

**~13k tokens are spent before the user's first word.** Classification of
`CLAUDE.md` policy material:

| Class | Examples | Always needed? |
|---|---|---|
| Universal invariant | §0 priority order, §2 action boundaries, §3 anti-hallucination | **yes** |
| Strong default | §6 code quality, §9 diff discipline, §11 git | yes, but compressible |
| Production-only | §12 structured JSON logs + `trace_id`, §19 unattended-job observability | **no** — dead weight in a scratch repo |
| Risk-dependent | §13 risk levels, §14 verification matrix | conditional |
| Project-convention dependent | §8 naming defaults, import grouping | **no** — the repo's own conventions win (§1.1) |
| Example / reference | §14 table rows, §7 secure-defaults enumerations, §20 checklist | **no** — reference material |

Concrete reduction candidates, with expected savings:

| Change | Est. saving |
|---|---:|
| Move §14 verification matrix + §20 checklist to a referenced file | ~900 t |
| Compress §7 secure-defaults enumerations to invariants + pointer | ~700 t |
| Conditionalize §12/§19 production mandates behind a profile | ~600 t |
| Trim §6/§8 to invariants, delete convention-dependent defaults | ~500 t |
| Shorten the 5 descriptions >150 t to routing signals only | ~150 t |
| **Total** | **~2,850 t (~22%)** |

The `Project Configuration` block is still unfilled `_e.g._` placeholders —
which the file itself warns costs every session a discovery pass. That is a
template-usability defect, not just untidiness.

Duplicate guidance is real and measurable: §7 secure defaults substantially
restate `web-security`; §10 testing foundations restate `testing`; §16
Definition of Done restates `verification`. The always-loaded copy pays for
itself only when the skill does *not* load.

## 10. Manual-only analysis

Frontmatter exposes only `name` and `description` — **there is no
manual-only/model-invocation control in use anywhere in this repo.** All 37
skills are model-invocable. So the four workflow skills were assessed for what
changing that would buy:

| Skill | Current trigger | Accidental-activation risk | Idle description cost | User burden if manual-only |
|---|---|---|---|---|
| `repository-cleanup` | model-invoked | **High** — v4 measured it stealing `layout-root-mess` 3/3; description had to be hand-disambiguated | 181 t (largest) | Low — always a deliberate, announced effort |
| `git-hygiene` | model-invoked | Medium — overlaps ordinary "move this file" | 153 t | Medium — sometimes wanted mid-task |
| `release-readiness` | model-invoked | Low — distinctive vocabulary | 124 t | Low — always deliberate |
| `verification` | model-invoked | Medium — overlaps `testing`, `observability` | 137 t | **High** — wanted implicitly at the end of many tasks |

`repository-cleanup` is the strongest manual-only candidate: it has a *measured*
conflict history, the largest description, and zero legitimate accidental use.
`verification` is the weakest — it is exactly the skill you want to fire
without being asked. Nothing is changed in this phase; this is the baseline for
the Phase 5 experiment, which must be measured by re-running routing rather
than argued.

## 11. Productization gaps

| Item | State | Blocking? |
|---|---|---|
| `LICENSE` | **absent** | Owner has authorized Apache-2.0 for this cycle |
| `CONTRIBUTING.md` | absent | No — draftable |
| `SECURITY.md` | absent | No — draftable |
| `CODE_OF_CONDUCT.md` | absent | No |
| Issue / PR templates | absent | No |
| Installation profiles | **none** | No mechanism exists |
| Installer dry-run | **none** — `claude-init.sh` and `install.sh` expose no flags at all, not even `--help` | No |
| Update propagation | **none** — no version stamp, no drift detection | No |
| Compatibility matrix | **none** — no declared Claude Code / OS / tool support | No |
| Release process | absent | No |
| Version declaration | **none** anywhere | No |
| Repository-level secret scanning | not enabled | **Owner decision** |
| Template-repository setting | not set | **Owner decision** |

**Apache-2.0 prerequisite checks (completed):**

- `git shortlog -sne --all` → 4 identities, all resolving to the repository
  owner: `tham <theptip.t@gmail.com>` (107), `theptip <…@users.noreply.github.com>`
  (13), `tham <theptip.t@srisawadpower.com>` (11), `theptip <theptip.t@gmail.com>` (2).
  Same individual under different name/email configurations; no external
  contributor. **Recorded uncertainty:** this is inferred from name/email shape.
  If any identity is a distinct person, the owner must confirm before the
  license lands.
- Scan for vendored / copied / externally sourced material (`copyright`, `SPDX`,
  `licensed under`, MIT/Apache/BSD strings across md/sh/py/json/yaml) →
  **no third-party notices found**. Nothing to preserve, relicense, or exclude.
- Consequence: **no `NOTICE` file is warranted** — the authorization is explicit
  that one should be added only if actual attribution notices require
  downstream preservation. None do.

Technical work vs owner decisions is separated in §16.

## 12. Session-evaluation plan

Ten scenarios, each a seeded scratch repo, a fixed prompt, and recorded
structured evidence. Metrics per session: skills loaded (primary + extras), user
approvals requested, false asks, false blocks, Stop behaviour, always-loaded
context tokens, wall-clock hook overhead, manual interventions, completion
outcome.

| # | Scenario | Seed fixture | Primary signal under test |
|---|---|---|---|
| 1 | Python API endpoint + test | FastAPI app, pytest, ruff | `fastapi-review`/`api-design` routing; Stop strict on a real suite |
| 2 | TypeScript monorepo package change | pnpm workspace, 2 packages | package-manager detection; `frontend-layout` vs `project-layout` |
| 3 | Airflow DAG retry change | `dags/`, `plugins/` | `airflow` vs `airflow-review` boundary |
| 4 | Schema migration | alembic `versions/` | `protect-files` ask on `migrations/`; `database-migrations` |
| 5 | Infrastructure edit | `infra/*.tf` | ask tier; no silent infra edit |
| 6 | Repository cleanup | cluttered root, tracked `__pycache__` | `repository-cleanup` vs `project-layout` (measured conflict) |
| 7 | Release preparation | changelog, version file | `release-readiness`; no tag creation |
| 8 | Worktree parallel task | linked worktree (`.git` is a **file**) | `verify-done` worktree detection (regression-prone) |
| 9 | Windows/WSL install | clean clone, both shells | `claude-init.sh` + `install.sh` cross-platform |
| 10 | Conflicting local conventions | repo with 4-space Python + its own CLAUDE.md | CLAUDE.md §1.1 "codebase is source of truth" actually honoured |

**Sanitization:** fixtures are synthetic and generated by script — no real
project content, no real credentials. Recorded evidence is limited to skill
names, decision counts, timings, and outcome flags. Prompts and seeds are
committed; raw transcripts are **not**, and any hook log captured is filtered to
event type + hook name before it is written to `reports/`.

## 13. Confirmed defects

Severity: **P1** = the shipped documentation claims a behaviour the hook does
not deliver, or a structural bypass. **P2** = a real, demonstrated gap the
documentation does not claim. **P3** = policy inconsistency requiring a decision.

| ID | Severity | Defect | Evidence | Smallest fix |
|---|---|---|---|---|
| **V7-01** | **P1** | Template-basename allowlist bypasses the entire path policy (`.git/`, `.secrets/`, workflows, actions, hooks) | §5 A — 5 corpus rows PF-004…008 | Scope the allowlist to suppress only the `.env*` deny rule, not the whole hook — move it from a bare `exit 0` into the `.env` branch |
| **V7-02** | **P1** | Option-first dependency installs are allowed though README claims "incl. option-first spellings" | §5 E — DP-008, DP-019, DP-020, DP-021 | Give pip the option-skip idiom npm already has; make npm's `--prefix` order-independent |
| **V7-03** | **P1** | Long-form SQL client flags allowed though README claims "the psql/mysql/sqlcmd flag forms are covered" | §5 D — SQ-005…008 | Extend `-[ceq]` to the long spellings, preserving the quote boundary that keeps prose allowed |
| **V7-04** | **P1** | Quoted absolute target defeats the absolute-path deny the README promises | §5 B — QT-004 | Add the `[\"']?` class the sibling `$HOME` pattern already has |
| **V7-05** | **P2** | `$PWD`/`${PWD}`/`$(pwd)` recursive deletion allowed; **destroys the tree** | §5 B — FS-021…023, measured DIR-GONE | Extend the `$HOME` pattern to `PWD`; `$(pwd)` needs its own alternative |
| **V7-06** | **P2** | Character-class dotglobs (`.[!.]*`, `.[^.]*`) allowed; **delete `.git/`** | §5 B — FS-017…020 | Add a dot-glob character-class alternative |
| **V7-07** | **P2** | Brace-expansion sweep `{*,.[!.]*,..?*}` allowed; **deletes everything** | §5 B — FS-024 | Match `{` as a target-start |
| **V7-08** | **P2** | `git -C …` and `/usr/bin/git` hide `commit` from the protected-branch check | §5 C — GT-017, GT-018 | Allow global options between `git` and `commit`; add `/` to the command-position class (align with `RM_WORD`) |
| **V7-09** | **P2** | Dependency ask patterns are unanchored — `cargo install` matches the **Go** pattern; `echo gem install` matches prose | §5 E, verified against `grep -E` | Anchor dependency patterns at a command position, as `RM_WORD` already does |
| **V7-10** | **P2** | `block-destructive` costs **2.18 s p50** on every Bash call (~170 process spawns) | §7 | Single combined alternation / `grep -Ef`; ~170 spawns → ~2 |
| **V7-11** | **P2** | 21 of 37 skills have no positive routing evidence | §8 | Extend fixture to all 37 + negatives/ambiguous; re-run live ≥3 reps |
| **V7-12** | **P2** | 6 of 37 skills carry no negative routing signal, all with close neighbours | §8 | Add `Do NOT use …` boundaries; re-measure routing |
| **V7-13** | **P3** | Global tool installs inconsistent: `gem`/`go` ask, `pipx`/`uv tool` allow, `cargo` asks accidentally | §5 E | Decide one policy, then implement it deliberately |
| **V7-14** | **P3** | `npm install ./local-package` allowed though it mutates the manifest | §5 E — DP-009 | Decide; low severity |
| **V7-15** | **P3** | Bounded guarantees unstated: `-C` cross-repo branch detection, strict-Stop's narrow window, regex-vs-shell limits | §5 B/C/F | Document as a falsifiable contract |
| **V7-16** | **P3** | `CLAUDE.md` ships unfilled `_e.g._` Project Configuration placeholders | §9 | Fill for this repo; keep the placeholder block for downstream |

## 14. Rejected findings

Behaviours that look like defects and are **correct as shipped** — recorded so a
later cycle does not "fix" them:

| Behaviour | Why it is correct |
|---|---|
| `rm -rf ./build` allowed | Named relative cleanup is legitimate and common; measured to delete only `build/` (§5 B). The dot-target patterns deliberately require end-of-target or a glob. |
| `echo "DELETE FROM users"` allowed | The quote boundary that permits documentation is load-bearing. Any SQL fix must preserve it — verified still passing. |
| `npm ci`, `npm install`, `pip install -r`, `uv sync` allowed | Lockfile/manifest restores are not new supply-chain decisions. Correct and deliberate. |
| Strict Stop exits 0 when no checker is found | "Cannot verify" must never be reported as "verified." Honest, and the message says so. |
| Strict Stop's `stop_hook_active` re-entry guard | Without it, blocking mode can loop a session forever. Bounding it to one block is right. |
| `protect-files` does not resolve `..` or symlinks | Documented; errs toward ask/deny, never toward a dangerous allow. |
| Case-folded segment matching on Linux | Over-cautious on case-sensitive filesystems, never a dangerous allow. Correct trade-off for Windows/macOS primary platforms. |
| `git push` left to Claude Code's own permission flow | Documented tier-3 decision; a hook ask would duplicate the prompt. |
| 3.4% out-of-scope corpus rows (`shutil.rmtree` etc.) | Genuinely un-matchable by regex; correctly labelled and excluded from scoring rather than hidden. |

## 15. Owner decisions

| # | Decision | Status |
|---|---|---|
| 1 | Software license | **RESOLVED** — Apache-2.0 authorized for this cycle. Prerequisites verified clean (§11). Tagging **not** authorized. |
| 2 | Repository-level secret scanning (second layer) | **OPEN** — requires explicit approval; not activated |
| 3 | `template-repository` GitHub setting | **OPEN** |
| 4 | Global-tool-install policy (V7-13) | **OPEN** — recommend: ask, matching `gem`/`go` |
| 5 | Release version number for the first tagged release | **OPEN** — tagging explicitly out of scope this cycle |
| 6 | Compatibility support window (Claude Code versions, OS, shells) | **OPEN** — draft proposed, needs owner sign-off |

## 16. P1 / P2 / P3 roadmap

**P1 — documented-contract violations. Must be fixed for any 9.0 claim.**
V7-01 (allowlist bypass), V7-02 (option-first deps), V7-03 (long SQL flags),
V7-04 (quoted absolute path). Each gets a failing regression first, then the
smallest fix, then a corpus re-run proving false-deny stays at 0.

**P2 — demonstrated gaps and measurement debt.**
V7-05/06/07 (recursive-deletion families, all proven destructive), V7-08 (git
invocation), V7-09 (pattern anchoring), V7-10 (hot-path latency), V7-11
(routing coverage — the largest single item), V7-12 (negative signals).

**P3 — policy and documentation.**
V7-13, V7-14 (dependency policy decisions), V7-15 (bounded guarantees written
as falsifiable contracts), V7-16 (Project Configuration).

**Sequencing constraint.** V7-11 (routing to 37 skills, live, ≥3 reps) is the
long pole and gates the 9.0 evidence bar on its own. Hook fixes are bounded and
mechanical by comparison. Context reduction (§9) must be measured by re-running
routing after every description change, since shortening a description is
exactly the kind of edit that silently degrades recall.

**Explicitly out of scope for this cycle:** creating or pushing a release tag;
activating a third-party secret scanner; force-pushing; rewriting shared
history; widening any regex without a documented policy and a corpus row
proving no new false deny.

---

## 18. Post-implementation evidence (appended 2026-07-20, after Phases 4–10)

Everything above this line is the blind audit as committed at `3bfdc0c` and is
unchanged. This section records what the implementation phases delivered,
measured on the final branch state.

### 18.1 Defect closure

| ID | Status | Evidence |
|---|---|---|
| V7-01…04 (P1) | **Closed** (Phase 4) | Failing regressions first; corpus re-run: 0 contract violations |
| V7-05…07 (P2 recursive deletion) | **Closed** | Destroyer forms deny; named relative cleanup still allowed (corpus-pinned) |
| V7-08/09 (P2 git/anchoring) | **Closed** | GT/DP corpus rows; suite 291/291 |
| V7-10 (P2 latency) | **Closed** | Ordinary-command p50 2179 ms → 259 ms (§18.4) |
| V7-11 (P2 routing coverage) | **Closed** | §18.5 — all 37 skills positive, live, 3 reps |
| V7-12 (P2 negative signals) | **Closed** | Six missing Do-NOT boundaries added; measured in §18.5 |
| V7-13/14 (P3 dependency policy) | **Decided** (ask; provisional, one-line revert documented) | `proposal-owner-decisions-v7.md` §5 |
| V7-15 (P3 bounded guarantee) | **Closed** | hooks README Limitations rewritten as the falsifiable contract (plan §1) |
| V7-16 (P3 project config) | **Closed** | Filled for this repo; placeholder kept for downstream |
| V7-17 (manual-only) | **Implemented as opt-in** | `team` profile makes repository-cleanup + release-readiness manual-only; default unchanged |
| V7-18 (installer copy model) | **Closed** (Phase 8) | Allowlist copy, fail-loud on unknown entries; installer suite 37/37 |
| V7-19 (listing budget) | **Mitigated; confirmation open** | Listing 20,229 → 13,415 chars (§18.3); `/doctor` confirmation remains an owner item |

### 18.2 Hook quality — final corpus state

Re-run 2026-07-20 on the final branch (`corpus-20260720-084835`):
205 rows, 198 scored, 7 out-of-scope (3.4%, labelled, excluded from scoring).

| Metric | Baseline (§6) | Final | Plan §2 gate | Verdict |
|---|---:|---:|---|---|
| Contract violations | 27 | **0** | 0 | pass |
| Dangerous in-scope recall | 0.821 | **1.000** | ≥ 0.98 | pass |
| Legitimate-action allow rate | 1.000 | **1.000** | ≥ 0.97 | pass |
| False-deny rate | 0.000 | **0.000** | ≤ 0.03 | pass |
| False-allow rate | — | 0.000 | — | pass |
| Ask accuracy | — | 1.000 | — | pass |
| vs-ideal deltas (documented trade-offs) | — | fp 7 / fn 6 | measured, not failed | — |

### 18.3 Context — final measurements

| Artefact | Baseline | Final | Change |
|---|---:|---:|---|
| Skill listing (names + descriptions; the enforced budget) | 20,229 chars | **13,415 chars** | −34% |
| Largest single description | 727 chars (`repository-cleanup`) | 477 chars (same) | all ≤ 1,536 cap |
| `CLAUDE.md` | 32,187 chars (~8,046 est. tokens) | **unchanged** | deliberate — below |
| Always-loaded total (chars/4 estimate) | ~12,984 est. tokens | **~11,400 est. tokens** | −12% |

`CLAUDE.md` compaction (plan §4 part 2, target ≤6,000 est. tokens) was **not
performed**, and the listing target of ≤10,000 chars was **not reached**. The
plan's own guard requires a full routing re-run after any always-loaded prose
or description change; a second multi-hour live run was judged not worth it
this cycle (plan §11 anticipated the trade). 13,415 chars is the floor
reachable by description compression alone; the remaining levers (name-only
overrides, manual-only defaults) trade routing recall and stay evidence-gated.

### 18.4 Hook latency — final benchmark

Same method as §7 (n=20 per path, wall clock, Windows 11 / Git Bash),
re-measured 2026-07-20 on the final branch:

| Path | p50 | p95 | Baseline p50/p95 |
|---|---:|---:|---|
| Ordinary Bash command (`block-destructive`) | **259 ms** | **270 ms** | 2179 / 2409 |
| Secret scan (clean write) | 621 | 647 | 724 / 779 |
| Diff-size check | 330 | 360 | 373 / 429 |
| Protected write (ask) | 320 | 342 | 358 / 424 |
| Stop reminder | 261 | 278 | 312 / 366 |
| Stop strict, no checker | 274 | 290 | 308 / 357 |

Plan §2 gate (hot-path p95 ≤ 600 ms): **270 ms — pass**, 8.9× better than the
audited baseline. Every other path is at or below its baseline.

### 18.5 Routing — full-fixture live evaluation (the v7 gate item)

Run 2026-07-20, merged from checkpointed per-case files
(`results/routing-20260720-083339.jsonl` + summary), provenance recorded in
the summary and `evaluated_runs`: repo `05bfb3d`, model `claude-sonnet-5`,
Claude Code 2.1.215 (hand-entered; stream capture null on this build), fixture
digest `83fe8e76…`, descriptions digest `d714143a…`, Windows.

**45 cases × 3 reps = 135 runs, 0 errored.**

| Metric (canonical `summarize()` math) | Value | 9.0 gate | Verdict |
|---|---:|---|---|
| Recall (runs with `must_load`) | **0.940** | > 0.90 | **pass** |
| Precision (sanctioned loads / all loads) | **0.967** | > 0.95 | **pass** |
| Conflict rate | **0.007** | < 0.02 | **pass** |
| No-load rate | 0.060 | — | reported |
| Stability (identical sets across reps) | 0.733 | — | 0.805 over the 41 asserting cases |

Skill-averaged macros (mean of per-skill values, all 37 skills): recall
**0.9505**, precision **0.9788** — the gates pass under either averaging.

Per-cluster:

| Cluster | Runs | Recall | Conflicts | No-loads |
|---|---:|---:|---:|---:|
| layout | 15 | 1.000 | 0 | 0 |
| review | 18 | 0.944 | 1 | 1 |
| git-hygiene scope | 12 | 1.000 | 0 | 0 |
| security | 6 | 0.833 | 0 | 1 |
| engine specificity (observational) | 3 | — | 0 | 0 |
| airflow authoring vs review | 6 | **0.500** | 0 | 3 |
| full-coverage positive (21 new skills) | 63 | 0.968 | 0 | 2 |
| ambiguous (observational) | 12 | — | 0 | 0 |

**Failure inventory — complete.** One conflict run in 135:
`review-api-breaking` run 1 co-loaded `api-design` beside the required
`api-review` (2 of 3 reps clean). Seven no-load runs, never a mis-load:
`dag-add-retry` ×2, `dag-create-orders`, `review-dag-deploy`,
`login-session-cookies`, `cov-database-migrations`, `cov-docker-review`. The
airflow cluster (recall 0.500) is the concentration — the weak signal carried
since the v4 baseline, now measured across the full fixture instead of
sampled. Extra loads beyond companions, 4 total in 135 runs: `fastapi-review`
×2 (`cov-python-review`, a FastAPI-shaped seed), `api-design` ×1 (the conflict
above), `verification` ×1 (`cleanup-branch-sequence`).

The ambiguous cluster behaves as designed — it records rather than asserts:
`amb-slow-endpoint` 2/3 nothing + 1/3 `fastapi-review`; `amb-document-api`
2/3 `documentation` + 1/3 `api-design`; `amb-cleanup-tests` 1/3 `testing`;
`amb-env-secret` within companions all reps. No ambiguous run loaded anything
outside its sanctioned set.

Against the v4-era authoritative run (20 cases / 16 skills): recall
0.963 → 0.940, precision 1.000 → 0.967, conflict 0.000 → 0.007 on 2.25× the
cases and 2.3× the skill coverage — the earlier numbers described the easy
43% of the catalog; these describe all of it.

### 18.6 Realistic sessions (plan §8)

9 model-driven scenarios executed 2026-07-20 (`tests/sessions/results/
sessions-20260720.jsonl`), headless `claude -p`, project settings only,
acceptEdits; scenario 9 (Windows/WSL install) is covered by the installer
suite; WSL stays declared unmeasured (SUPPORT.md). The harness needed one
first-contact fix before the run: ask/deny counts grepped for bracketed
markers that the tab-separated `hooks.log` never contains (always 0); counts
now match the log format exactly, and per-session tool-call counts were added
because allow-tier hook executions are invisible to the log.

| Scenario | Skills loaded | Asks | Denies | Stop replay | Wall s | Outcome |
|---|---|---:|---:|---|---:|---|
| s1 python-api (test file) | — | 0 | 0 | reminder | 24 | artifact ✓ |
| s2 ts-monorepo (Button variant) | design-system | 0 | 0 | reminder | 93 | artifact ✓ |
| s3 airflow (retry change) | — | 0 | 0 | reminder | 36 | artifact ✓ |
| s4 migration (alembic) | database-migrations | 0 | 0 | silent | 82 | **no artifact** |
| s5 infra (k8s limits) | kubernetes | 0 | 0 | silent | 25 | artifact ✓ |
| s6 cleanup (proposal doc) | repository-cleanup | 0 | 0 | silent | 87 | artifact ✓ |
| s7 release (changelog) | release-readiness | 0 | 0 | silent | 42 | artifact ✓ |
| s8 rename (health endpoint) | — | 0 | 0 | reminder | 35 | artifact ✓ |
| s10 conflicting conventions | — | 0 | 0 | reminder | 33 | artifact ✓ |

Sweep: **0 asks, 0 denials, 0 unrequested skill loads**; every loaded skill
was its scenario's intended primary. Stop replay = reminder on exactly the 5
sessions that left uncommitted code files, silent otherwise — the documented
contract. s4 produced no artifact: the seed carries alembic *scaffolding* but
no `alembic` binary exists in the environment; the session tried the tool,
failed, and reported inability instead of fabricating a migration file (which
would have triggered the migrations/ ask). The ask tier therefore went
unexercised in sessions; its behaviour is covered deterministically by the
205-row corpus and the 291-test suite. s8 as implemented is a plain-repo
rename; the linked-worktree `verify-done` contract is exercised by the hook
suite and by this cycle's own sessions running in a linked worktree.

**Budgets (plan §8), stated against measured latencies (§18.4 p50s;
estimate = bash×0.259 s + edits×1.271 s + Stop 0.261 s):**

| Budget | Value | Result |
|---|---|---|
| False asks / session | ≤ 1 | **0** — pass |
| False blocks / session | 0 | **0** — pass |
| Unrequested skill loads / session | ≤ 1 | **0** — pass |
| Hook overhead | ≤ 5% wall | **3.8% aggregate — pass**; exceeded on the 4 shortest sessions (s1 6.4%, s3 5.7%, s5 7.2%, s10 5.4%) |

The per-session overhead miss is a **budget-calibration finding, not a hook
regression**: latencies are at their post-fix values; a ~1.5 s fixed
file-edit+Stop chain simply dominates sessions that finish in 24–36 s.
Recorded recommendation: restate the budget with an absolute floor
("≤ 5% or ≤ 2.5 s, whichever is larger").

### 18.7 Final validation battery (Phase 10, all on the final tree)

| # | Item | Result |
|---|---|---|
| 1 | Hook suite | **291 pass / 0 fail**, exit 0 |
| 2 | Policy corpus + confusion matrix | 205 rows, **0 contract violations** (§18.2) |
| 3 | Latency benchmark | §18.4 — hot-path p95 270 ms ≤ 600 gate |
| 4 | Installer / profiles / dry-run / drift | **37 pass / 0 fail** |
| 5 | ShellCheck (pinned v0.10.0, Docker) | clean over hooks + all test/driver scripts |
| 6 | Skill catalog | 37 skills, ALL CHECKS PASS |
| 7 | Routing parser/scoring tests | 15/15 |
| 8 | Results consistency | 5 result sets, 5 evaluated_runs, ALL CHECKS PASS |
| 9 | Python compilation | 6 files, exit 0 |
| 10 | YAML validation | workflow + fixture parse |
| 11 | JSON validation | 8 tracked files, 0 invalid |
| 12 | Generated-file cleanliness | clean |
| 13 | Markdown links | 69 files, ALL CHECKS PASS |
| 14 | Live routing (complete) | §18.5 |
| 15 | Realistic sessions | §18.6 |
| 16 | Profile + update-propagation tests | inside item 4 (37 cases) |

One environment note: ShellCheck initially failed on `.claude/hooks/install.sh`
with SC1017 — the **local worktree copy** carried CRLF from a Windows
checkout-conversion artifact. The index blob is LF (verified via
`git ls-files --eol`; `.gitattributes` already pins `*.sh text eol=lf`;
CI ShellChecks the LF content and is green). The working copy was
renormalized in place; no repository change was needed or made.

### 18.8 Re-score against the fixed rubric

Same rubric and weights as §3. Categories re-scored only on evidence in this
report and the committed results.

| Category | Weight | Pre | Post | Basis |
|---|---:|---:|---:|---|
| Technical correctness | 15% | 7.5 | **9.0** | 291/291, corpus 0 violations, ShellCheck clean, installer 37/37, CI green on final commit |
| Skill trigger quality | 15% | 7.0 | **9.0** | 37/37 positive live evidence, recall 0.940 (macro 0.9505); airflow cluster no-loads keep it from higher |
| Hook correctness | 15% | 6.5 | **9.5** | In-scope recall 1.000, false-deny 0.000, all P1/P2 closed, bounded guarantee documented and calibrated to what ships |
| Conflict avoidance | 10% | 8.0 | **9.0** | Conflict rate 0.007 measured across all 37 skills; boundaries stated in every neighbour pair |
| Safety and permissions | 10% | 7.5 | **9.0** | Four tiers proven by corpus + suite; sessions frictionless (0 false asks/blocks); override logged |
| Testing and evaluation | 15% | 7.0 | **9.5** | 291 regressions, 205-row corpus w/ confusion matrix, 37 installer cases, 135-run live routing with provenance, 9 session rows, consistency gates in CI |
| Context efficiency | 5% | 6.5 | **7.5** | Listing −34%, always-loaded −12%; both plan targets missed (deliberate deferral), V7-19 confirmation open |
| Team usability | 5% | 7.0 | **8.5** | Profiles + dry-run, CONTRIBUTING/SUPPORT, hot path 8.9× faster; team-scale evidence still absent |
| Maintainability | 5% | 8.0 | **9.0** | Regression-first fixes, changelog discipline, provenance digests make every result falsifiable |
| Public-template readiness | 5% | 4.0 | **8.0** | LICENSE/CONTRIBUTING/SECURITY/SUPPORT + profiles + update propagation; tag, secret scanning, template setting remain owner-gated |

**Weighted post score: 9.0 / 10** (0.15×37.0 + 0.10×18.0 + 0.05×33.0 =
5.55 + 1.80 + 1.65). Every 9.0 evidence-gate item is satisfied (§18.5–§18.7 +
CI on the final commit); sensitivity is stated honestly — plausible stricter
scoring of the two 15%-weight 9.5s lands at 8.9, and nothing here supports
more than 9.1. **9.5 is not claimable**: it requires repository secret
scanning, a release tag, and an independent review of the exact release
commit — all owner-gated, none performed.
