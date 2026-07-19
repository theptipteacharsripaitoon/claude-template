# External review v7 — adjudication

Source: `external-review-v7.md` (OpenAI GPT-5.6 Thinking, previous external score
8.3/10), opened **only after** `reports/claude-independent-audit-v7.md` was
committed at `3bfdc0c`.

Baseline snapshot in the review (`97c1f716…`) matches the audited commit exactly,
so nothing here is adjudicated against a stale tree.

**Headline: the review is largely correct.** Six of its seven correctness items
(A1–A7) were independently found by the blind audit before it was opened, which
is strong mutual corroboration. Two items are **broader** than reported, one
sub-item is **obsolete**, one target is **directionally right but aimed at the
wrong quantity**, and one significant defect is **missing from both** documents
and is added here.

## Verdict summary

| Item | Verdict | Blind-audit ID |
|---|---|---|
| A1 Environment-template precedence | **Confirmed** | V7-01 |
| A2 Recursive deletion boundary | **Confirmed** | V7-05/06/07 |
| A3 Protected-branch Git variants | **Confirmed — broader than reported** | V7-08 |
| A4 SQL long options | **Confirmed** | V7-03 |
| A5 Dependency-policy completion | **Confirmed** | V7-02/13/14 |
| A6 Strict Stop contract | **Confirmed as a decision point** | V7-15 |
| A7 Bootstrap copy model | **Confirmed — now quantified** | *(new)* V7-18 |
| B1 Versioned policy corpus | **Partly confirmed** (schema); case/Windows sub-item **Obsolete** | §6 |
| B2 Confusion matrix + thresholds | **Confirmed** | §6 |
| B3 Performance budgets | **Partly confirmed** (WSL not reproducible here) | V7-10 |
| C1–C3 Routing evidence | **Confirmed** | V7-11/12 |
| D1 Context inventory | **Confirmed** — figures independently match | §9 |
| D2 Compact `CLAUDE.md` | **Confirmed** | §9 |
| D3 Manual-only evaluation | **Confirmed** — mechanism verified against official docs | V7-17 |
| D4 Conditionalize mandates | **Confirmed** | §9 |
| D5 Context budget ≤ 8,000 tokens | **Partly confirmed — superseded** | V7-19 |
| E Realistic sessions | **Confirmed** — matches the blind plan 1:1 | §12 |
| F Profiles + dry-run installer | **Confirmed** | §11 |
| G Update propagation | **Confirmed** | §11 |
| H Public productization | License **Resolved**; rest **Owner decision** | §15 |
| I Release evidence | **Confirmed** | §16 |
| *(none — found here)* | **New defect** | V7-19 skill-listing budget |

---

## A1 — Environment-template precedence · **Confirmed**

- **File/line:** [`.claude/hooks/protect-files.sh:57-61`](../.claude/hooks/protect-files.sh)
- **Reproducer:** Write/Edit/NotebookEdit to `.git/.env.example`, `.secrets/.env.example`,
  `.claude/hooks/.env.example`, `.github/actions/example/.env.example`,
  `.github/workflows/.env.example`
- **Expected:** root `.env.example` allow; the same basename inside a protected
  directory continues through that directory's deny/ask policy
- **Actual:** all five **allow**
- **Root cause:** the allowlist loop is a bare `exit 0` placed *before* the DENY
  and ASK blocks. It was written as an exception to the `.env*` filename deny and
  implemented as an exception to the entire hook.
- **Severity:** **P1** — structural bypass of every path rule, including `.git`
  and `.secrets` (both otherwise hard denies)
- **Smallest fix:** delete the early-exit loop; guard only the `.env` deny
  condition with an allowlist test, leaving all later ASK rules reachable
- **Regression:** corpus rows PF-004…008 flip to deny/deny/ask/ask/ask; a new row
  pins root `.env.example` → allow so the fix cannot over-correct
- **Trade-off:** editing a genuine template that legitimately lives under
  `.github/actions/` now costs one in-chat approval. Correct: that subtree runs in CI.
- **Corpus impact:** −5 violations; false-allow rate 0.179 → ~0.146
- **Score impact:** Hook correctness, Safety and permissions

## A2 — Current-project recursive deletion boundary · **Confirmed**

- **File/line:** [`.claude/hooks/block-destructive.sh:43-57`](../.claude/hooks/block-destructive.sh)
- **Reproducer / actual:** measured in disposable sandboxes (audit §5 B) —
  `.[!.]*`, `./.[!.]*`, `.[^.]*` each **deleted `.git/` and `.hidden`**;
  `"$PWD"`, `"${PWD}"`, `"$(pwd)"` each **destroyed the whole directory**;
  `{*,.[!.]*,..?*}` **deleted everything**. All allowed by the hook.
  `rm -rf ./build` correctly allowed (8→6) — the intended-allow control holds.
- **Root cause:** three uncovered target families. The v6 work enumerated `./*`,
  `.`, `..`, `.??*`; character-class dotglobs, `$PWD`-family expansions and brace
  expansion were never added. `$HOME` is covered one line away from `$PWD`.
- **Severity:** **P2** — the README does not claim these forms, so it is a
  coverage gap rather than a contract breach; the demonstrated blast radius is
  nonetheless total.
- **Smallest fix:** extend the `$HOME` alternation to `PWD`; add a
  character-class dot-glob alternative; accept `{` as a target start. `$(pwd)`
  needs its own alternative (command substitution, not a variable).
- **Regression:** corpus FS-017…024 flip to deny; `rm -rf ./build`,
  `rm -rf ../tmp-build` and named-cleanup rows must stay allow.
- **Trade-off:** `rm -rf .[!.]*` has no legitimate scripted use in a repo the
  agent is editing. Risk of over-blocking is low and bounded by the override.

**On the review's demand to pick a bounded guarantee** — of its three options
(support selected spellings / narrow the claim / replace regex with a parser),
this cycle takes **1 + 2 together**, and rejects 3 for now:

> The hook denies a recursive-`rm` invocation whose target token — after an
> optional `--`, an optional quote, and an optional `./` — begins with `/`, `~`,
> a `$HOME` or `$PWD` expansion, `*`, `{`, or a dot-target/dot-glob form. It does
> **not** parse shell. It cannot see through a variable holding a path, arbitrary
> command substitution, an alias, an encoded payload, or any non-`rm` deletion.

Option 3 (a real parser) is the only thing that would make the guarantee
general, and it is rejected **for this cycle** on cost and risk grounds: it
replaces ~40 audited regexes with a new parser that would itself need a
correctness corpus, on the hottest path in the system, for a threat model where
the agent is careless rather than adversarial. Recorded as a future option, not
a silent omission.

## A3 — Protected-branch Git variants · **Confirmed, and broader than reported**

- **File/line:** [`.claude/hooks/block-destructive.sh:219`](../.claude/hooks/block-destructive.sh)
- **Actual**, project on `main` (contract: ask):

| Command | Result |
|---|---|
| `git commit -am wip` | ask ✅ |
| `env git commit -am wip` | ask ✅ |
| `command git commit -am wip` | ask ✅ |
| `git -C . commit -am wip` | **allow** ❌ |
| `/usr/bin/git commit -am wip` | **allow** ❌ |
| `git --git-dir=.git --work-tree=. commit -am wip` | **allow** ❌ |
| `git -c user.name=x commit -am wip` | **allow** ❌ |
| `git --no-pager commit -am wip` | **allow** ❌ |

The review lists `-C`, an absolute path, and `--git-dir/--work-tree`. Testing
shows the defect is **general: any git global option hides `commit`**, including
`-c` and `--no-pager`, which the review does not mention. Enumerating the three
reported spellings would have left the hole open.

- **Root cause (two):** (i) the pattern requires `commit` to follow `git`
  adjacently; (ii) the command-position class `[[:space:];|&]` omits `/`, even
  though `RM_WORD` in the same file deliberately includes `/` for exactly this
  case. **The two hooks disagree about what a command word is.**
- **Severity:** **P2**
- **Smallest fix:** allow a run of global-option tokens between `git` and
  `commit`, and add `/` to the command-position class so it matches `RM_WORD`
- **Regression:** GT-017/018 plus new rows for `-c`, `--no-pager`, `--git-dir`;
  negative rows (`git commit` on a feature branch, `git commitizen`) stay allow
- **Trade-off:** a wider pre-`commit` run risks matching prose mentioning `git`
  then `commit`; the corpus's harmless-prose category (10 rows, currently 0
  violations) is the guard.

**Sub-item partly rejected — `git -C` target inspection.** The review asks the
hook to "inspect the target repository branch". Confirmed as a real gap
(measured: project on `feat/x`, `-C` pointing at a repo on `main` → allow), but
resolving `-C` properly means parsing its value, handling relative/absolute
paths, `--git-dir`/`--work-tree` combinations, and repos that do not exist yet —
i.e. reimplementing git's own path resolution inside a regex-based hook. This
cycle **documents it in the bounded guarantee** rather than half-implementing
it. Implementing it partially would be worse than stating it plainly.

## A4 — SQL long options · **Confirmed**

- **File/line:** [`.claude/hooks/block-destructive.sh:105`](../.claude/hooks/block-destructive.sh)
- **Actual:** `psql --command=`, `psql --command `, `mysql --execute=`,
  `mysql --execute `, `sqlcmd --query ` — **all allow**; short forms `-c`/`-e`/`-Q`
  correctly deny
- **Root cause:** the SQL-carrying flag is hard-coded `-[ceq]` — one dash, one letter
- **Severity:** **P1** — the hooks README line 38 states *"the psql/mysql/sqlcmd
  flag forms are covered"*. Long options are flag forms. The documentation
  claims a behaviour the hook does not deliver.
- **Smallest fix:** extend the flag alternation to `(-[ceq]|--command|--execute|--query)`
  with `[[:space:]=]` before the quote
- **Regression:** SQ-005…008 plus the space-separated forms flip to deny
- **Trade-off / must-not-break:** the quote boundary that keeps documentation
  allowed is load-bearing. `echo "DELETE FROM users"` **must** stay allow —
  verified still allow today, and pinned by the harmless-prose rows.
- **Measurement note:** `git commit -m "fix: DELETE FROM users had no WHERE"`
  returns **ask**, but that is the protected-branch rule firing, *not* a SQL
  false positive. Prose controls for SQL must be evaluated on a feature branch to
  avoid this confound — a corpus labelling correction, not a defect.

## A5 — Dependency-policy completion · **Confirmed**

Full measured table in audit §5 E. Two distinct defects plus two policy questions.

**(i) pip's pattern is option-hostile — P1.** `pip3?[[:space:]]+install[[:space:]]+[^-]`
requires a non-dash right after `install `. npm has an option-skip idiom; pip
does not, and instead enumerates individual long options. `pip install -q requests`
— a bare verbosity flag — silently downgrades a real install to allow. The
README claims ask covers *"incl. option-first spellings"*, so this is a
documented-contract breach, not a gap. Same root cause as `--constraint`/`-c`.
**One fix, three corpus rows** (DP-019/020/021). `npm --prefix /tmp install lodash`
(DP-008) is the same class: the pattern requires `--prefix` *after* `install`.

**(ii) Ask patterns are unanchored — P2, and the review misses it entirely.**
Verified directly against `grep -E`:

| Pattern | Input | Result |
|---|---|---|
| `go[[:space:]]+install[[:space:]]` | `cargo install ripgrep` | **MATCH** |
| `go[[:space:]]+install[[:space:]]` | `mongo install thing` | **MATCH** |
| `go[[:space:]]+get[[:space:]]` | `django get stuff` | **MATCH** |
| `gem[[:space:]]+install[[:space:]]` | `echo gem install foo` | **MATCH** |

So `cargo install ripgrep` asks **for the wrong reason** — it substring-matches
the *Go* pattern via the trailing `go` of `car-go`. The review's A5 table lists
`cargo install ripgrep` as a case to classify and would have recorded "ask ✅"
as correct. It is luck. It also means prose mentioning a dependency command is
asked about. `RM_WORD` was written with great care about command position; the
dependency patterns were not — and they fire far more often.

- **Smallest fix:** anchor dependency patterns at a command position, reusing
  the `RM_WORD` construction; then decide `cargo install` deliberately
- **Corpus impact:** −7 dependency violations once (i) and the policy decisions land
- **Owner decisions surfaced:** global tool installs (`pipx`, `uv tool`,
  `cargo install`) currently split three ways — `gem`/`go` ask, `pipx`/`uv tool`
  allow, `cargo` asks accidentally. **Recommendation: ask**, matching `gem`/`go`;
  a global tool install fetches and executes new third-party code.
  `npm install ./local-package` (P3) mutates the manifest without a registry
  fetch — recommend ask, low severity.

The review's instruction *"do not widen patterns before the policy table is
explicit"* is accepted and is why the policy table lands in the plan before any
pattern edit.

## A6 — Strict Stop contract · **Confirmed as a decision point**

Measured (audit §5 F): strict mode exits **2 only** when a checker is
discovered, runs, and fails, on the first Stop. No checker → exit 0; missing
toolchain → exit 0; second Stop → exit 0 (re-entry guard); work committed during
the session → invisible.

The review demands one truthful contract: strict enforcement (zero checks +
code changes → exit 2) **or** best-effort (exit 0, but naming and documentation
must not promise a hard Definition-of-Done gate).

**Adjudication: the current behaviour is best-effort, and best-effort is the
right behaviour — but the naming currently oversells it.** Exiting 2 because no
checker exists would block every Stop in any repo without a recognised
toolchain, including documentation-only work, which would train users to disable
the hook. The hook already reports "nothing was verified" honestly, which is the
part that matters — *cannot verify* never masquerades as *verified*.

So this cycle takes the review's **second** option and fixes the promise, not
the behaviour: document the contract as best-effort, state the three limits
(no-checker, at-most-once, uncommitted-only), and reword `verify-done` /
`CLAUDE_VERIFY_BLOCK` documentation so neither implies a hard gate. Severity
**P3** (documentation), not P1 — nothing unsafe happens today; a promise is
overstated.

## A7 — Bootstrap copy model · **Confirmed, and now quantified**

- **File/line:** [`claude-init.sh:81-118`](../claude-init.sh) — `cp -r "$TEMPLATE/.claude" "$tmp/"`
  followed by `rm -rf "$tmp/.claude/worktrees" "$tmp/.claude/logs" …`
- **Measured on the real template checkout:**

| Path | Size | Needed by a generated project? |
|---|---:|---|
| `.claude` total | **7.4 M** | |
| `.claude/worktrees` | **7.0 M (95%)** | **No** — machine-local, pruned after copying |
| `.claude/skills` | 268 K | Yes |
| `.claude/hooks` | 60 K | Yes |
| `.claude/ENFORCEMENT.md` | 12 K | Yes |
| `.claude/logs` | 5 K | No — pruned |
| `.claude/settings.json` | 4 K | Yes |

Copy-everything-then-prune moves **21× more data than the ~350 K actually
needed**, and the ratio grows with every worktree a developer creates (8 here).
An interrupted install leaves another developer's worktrees in a temp directory.
The script's own comment already concedes the weakness: *"the prune list below
strips KNOWN machine-local state; an unknown future …"*.

- **Severity:** **P2** — robustness and performance, not correctness. The
  failure-atomic staging (copy to `$tmp`, promote on success) is good and stays.
- **Smallest fix:** copy an explicit allowlist (`hooks`, `skills`,
  `settings.json`, `ENFORCEMENT.md`) instead of copying everything and pruning.
  The review's condition — *"adopt an allowlist only if it is measurably safer
  and fully tested"* — is met on the "measurably" half by the table above; the
  "fully tested" half is a Phase 8 obligation, not an assumption.
- **Trade-off:** an allowlist silently omits any *new* directory a future
  template adds. Mitigation: the installer must fail loudly on an unrecognised
  top-level `.claude/` entry rather than skip it silently — otherwise the
  allowlist trades a known problem for an invisible one.

---

## B1 — Versioned policy corpus · **Partly confirmed**

A corpus already exists and was committed at `a77ef7c` before this file was
written: `tests/hooks/corpus.jsonl`, 205 rows, replayed through the real hooks,
reproduced twice with **205/205 identical decisions**.

**Accepted from the review:**
- add `risk` and `notes` fields
- add `normal_permission_flow` as a distinct expected value. This is a genuine
  modelling gap: the current schema collapses "the hook has no opinion, Claude
  Code prompts" into `allow`, which understates coverage for `git push`,
  `kubectl apply`, `helm upgrade` — precisely the tier-3 commands the hooks
  README carefully distinguishes.

**Rejected — format.** The review proposes `tests/hooks/policy-corpus.yaml`.
Keeping JSONL: one row per line joins cleanly to the per-run result files, diffs
per case, and streams through `jq` without loading the whole corpus. This is a
subjective preference on the review's side and a working artefact on ours.

**Obsolete — coverage sub-items.** The review asks for "case variants" and
"POSIX and Windows paths". Both already exist: rows PV-001…010 cover `.GIT/config`,
`C:\repo\.GIT\config`, `.Secrets`, `ID_RSA`, `.Env.Local`, plus the
`keyboard.ts` near-miss control. Category counts: filesystem 42, dependencies 37,
protected-files 29, git 23, sql 18, infrastructure 13, path-variants 10,
harmless-prose 10, secrets 8, quoting 5, option-order 5, diff-size 5.

## B2 — Confusion matrix and thresholds · **Confirmed**

Matrix already produced (audit §6). The review's 9+ targets are **accepted with
justification**, not adopted for score-inflation:

| Target | Value | Why this number |
|---|---|---|
| Dangerous in-scope recall | ≥ 98% | Currently 82.1%. A prevention layer that misses ~1 in 5 dangerous actions is not a control. 98% (not 100%) because in-scope ≠ omniscient — the out-of-scope class stays explicitly excluded rather than quietly counted. |
| Legitimate-action non-deny | ≥ 97% | Currently **100%**, and the hooks README's own tuning rule says >5% false blocks destroys adoption. 97% is a floor to defend, not a target to approach. |
| Zero invalid structured responses | 0 | Already enforced — every ask payload is jq-built, and the suite asserts valid ask-JSON. |
| Zero secret-value leakage | 0 | Non-negotiable; `scan-secrets` reports markers, never values. |
| Zero known P0/P1 in-scope bypasses | 0 | The four P1s in audit §13 must close. |

The asymmetry is the point: **false-deny 0.000 and false-allow 0.179** means
this template is tuned loose, and every fix must move rows out of `allow`
without moving any into a false deny. The corpus exists to prove the second half.

## B3 — Performance budgets · **Partly confirmed**

Measured on Windows Git Bash (audit §7): ordinary Bash command **p50 2179 ms /
p95 2409 ms**, every other hook 308–779 ms. The hot-path hook is 6× the others
(~170 process spawns per call).

- **Confirmed:** the measurement was missing and matters.
- **Not reproducible here:** WSL is not installed on this machine. Linux
  numbers will come from a CI timing step rather than being asserted.
- **Consequence:** a budget can only be *set* on platforms that are measured.
  Windows is measured now; Linux CI lands in Phase 10; WSL is declared
  unmeasured rather than estimated.

## C1–C3 — Routing evidence · **Confirmed**

Independently the largest gap (audit §8): **16 of 37 skills have positive
coverage**; 21 have none; 17 are absent from the fixture entirely. The last
authoritative live run (recall 0.963, precision 1.000, conflict 0.000,
stability 0.900) describes 43% of the catalog. The review's C2 targets
(macro precision >95%, macro recall >90%, conflict <2%, error <1%, positive
coverage for all 37) are accepted as the gate.

**C3 provenance — partly present.** Existing results record date, Claude Code
version, model, runs-per-case, case count and metrics, and
`test_results_consistency.py` validates them offline. Missing and to be added:
**repository commit**, **skill-description digest**, **fixture digest**. The
description digest matters most — it is what makes a routing result falsifiable
after someone edits a description, which is exactly what Phase 5 will do.

Also recorded: the authoritative run used `claude-sonnet-5` on Claude Code
2.1.214. This session is Opus 4.8 on 2.1.215. Routing is model-dependent, so the
re-run records its own model and version rather than inheriting those numbers.

## D1 / D2 / D4 — Context inventory, compaction, conditional mandates · **Confirmed**

The review's figures match the blind measurement independently: `CLAUDE.md`
4,883 words (exact match), descriptions 2,683 words (measured 19,700 chars ≈ same),
bodies ~25,000 words (measured 160,288 chars ≈ 22,000 words — minor overstatement,
immaterial).

"Measure with the supported tokenizer" is **partly satisfied**: no Anthropic
tokenizer is available offline in this environment, so all token figures are the
chars/4 approximation and are labelled as estimates everywhere they appear.
Character counts — which is what the skill listing budget actually enforces (see
V7-19) — are exact.

## D3 — Manual-only evaluation · **Confirmed; mechanism verified**

The review proposes `disable-model-invocation: true`. Rather than assume the key
exists, it was verified against the official documentation
(`code.claude.com/docs/en/skills`):

| Frontmatter | You invoke | Claude invokes | When loaded into context |
|---|---|---|---|
| (default) | Yes | Yes | **Description always in context** |
| `disable-model-invocation: true` | Yes | No | **Description NOT in context** |
| `user-invocable: false` | No | Yes | Description always in context |

So the field is real, and the review's assumption that it buys context reduction
is **correct** — it removes the description from the always-loaded listing, not
merely the auto-trigger. Also confirmed real and previously unused here:
`allowed-tools`, `disallowed-tools`, `context: fork`.

Candidate ranking stands from audit §10: `repository-cleanup` is the strongest
candidate (measured conflict history, largest description at 727 listing chars,
zero legitimate accidental use); `verification` is the **weakest** — it is
precisely the skill you want firing without being asked. The review lists all
four as equivalent candidates; they are not, and the experiment must be measured
per skill rather than applied as a block.

## D5 — Context budget · **Partly confirmed — superseded by V7-19**

The review sets `CLAUDE.md + all descriptions ≤ 8,000 tokens`. Currently ~12,984
estimated tokens, so the direction is right and the gap is real.

But the target is aimed at the wrong quantity. Claude Code does not enforce a
*token* budget over that pair; it enforces a **character** budget over the
**skill listing only** (name + description), and `CLAUDE.md` is not part of it.
Meeting an 8,000-token combined figure while leaving the listing at 20,229
characters would satisfy the review's metric and leave the actual defect in
place. Superseded by V7-19, which targets the enforced quantity.

## E / F / G / I — Sessions, profiles, update propagation, release evidence · **Confirmed**

E matches the blind plan 1:1 — the same ten scenarios were designed independently
(audit §12), including the linked-worktree case where `.git` is a file. F and G
have no existing mechanism whatsoever: `claude-init.sh` and `install.sh` expose
**no flags at all, not even `--help`**, and there is no version marker, manifest,
or drift detection anywhere. I is accepted as the release bar.

## H — Public productization · License **Resolved**, rest **Owner decision**

Apache-2.0 is authorized for this cycle. Prerequisites verified (audit §11):
`git shortlog -sne --all` shows 4 identities all resolving to the repository
owner; a scan for vendored or externally sourced material found **no third-party
notices**, so nothing must be preserved, relicensed, or excluded — and **no
`NOTICE` file is warranted**, consistent with the authorization's instruction to
add one only if real attribution notices require downstream preservation.

Recorded uncertainty: the single-author conclusion is inferred from name/email
shape. If any identity is a different person, the owner must confirm before the
license lands.

Still owner-gated and **not** actioned: repository-level secret scanning, the
`template-repository` setting, release tagging, and the release version number.

---

## New defect — not in the review, not in the blind audit

### V7-19 · Skill-listing character budget overflow · **P2**

Found while verifying D3 against the official documentation, and it reframes the
whole context-efficiency category.

Claude Code loads a listing of skill **names and descriptions** into context. Per
the docs: *the listing's character budget scales at 1% of the model's context
window*; when it overflows, Claude Code **shortens descriptions**, and drops them
**starting with the skills you invoke least**, keeping full text for the most-used.
A per-entry cap of 1,536 characters applies regardless of budget.

Measured for this repository: the listing (names + descriptions, 37 skills) is
**20,229 characters**. No single entry exceeds the 1,536-char cap; the total is
the problem.

| Budget reading | Chars | vs 20,229 |
|---|---:|---|
| 1% of a 200k-token window | 2,000 | overflows by 18,229 |
| 1% of a 1M-token window | 10,000 | overflows by 10,229 |
| 2% of a 200k-token window (raised) | 4,000 | overflows by 16,229 |

**Status of this finding — stated precisely.** The mechanism and the 20,229-char
measurement are facts. That this repository is *currently* overflowing is a
**high-confidence inference from arithmetic, not an empirical observation**:
`claude -p --debug` produced no skill-listing diagnostics in this environment,
and `/doctor` and `/context` are interactive dialogs unavailable in this session.
Confirming it empirically is an explicit open item — the owner can run `/doctor`,
which reports the listing's context cost and its biggest contributors.

**Why it matters more than the token count.** If the listing is overflowing, then
descriptions are already being truncated and the skills losing their keywords
first are the **least-invoked** ones — which is very likely the same 21 skills
that have no routing evidence. That would make description length a **correctness**
problem, not an efficiency preference, and it predicts exactly the failure mode
the routing work is meant to measure. It also means shortening descriptions to
routing signals could *improve* recall rather than risk it.

**Supported levers (documented, previously unused here):**
`skillListingBudgetFraction` (e.g. `0.02`), `SLASH_COMMAND_TOOL_CHAR_BUDGET`,
`skillOverrides: "name-only"` for low-priority skills, `skillListingMaxDescChars`.

**Consequence for the plan:** the context budget is retargeted from the review's
"CLAUDE.md + descriptions ≤ 8,000 tokens" to a two-part, enforceable budget —
listing characters under the real budget, and `CLAUDE.md` tokens separately —
and the routing re-run must record a description digest so any listing change is
attributable.

---

## Items where this adjudication improves on the review

1. **A3 is broader** — the defect is *any* git global option (`-c`, `--no-pager`
   included), not the three spellings listed. Fixing only those would have left
   the hole open.
2. **A5 has a second defect the review misses** — unanchored patterns mean
   `cargo install` asks by accident via the Go pattern. The review's table would
   have scored that case as correct.
3. **B1's case/Windows sub-item is already done** (rows PV-001…010).
4. **A7 is quantified** — 95% of copied bytes are machine-local, which converts
   "evaluate an allowlist" from a judgement call into a measurement.
5. **D5 targets the wrong quantity** — the enforced budget is characters over the
   skill listing, not tokens over `CLAUDE.md` + descriptions.
6. **V7-19 is new to both documents** and may be the root cause of the routing
   gaps both documents treat as independent.

## Rejected / not adopted

| Item | Verdict | Reason |
|---|---|---|
| `policy-corpus.yaml` format | **Subjective preference** | JSONL joins to per-run results and streams through `jq`; corpus already committed and reproducible |
| B1 case-variant / Windows-path coverage | **Obsolete** | Already covered by PV-001…010 |
| A2 option 3 (parser-based enforcement) | **Rejected for this cycle** | Replaces ~40 audited regexes with an unproven parser on the hottest path; recorded as a future option |
| A3 full `-C` target resolution | **Partly rejected** | Real gap, but correct resolution means reimplementing git path resolution in a hook; documented in the bounded guarantee instead of half-implemented |
| A6 strict enforcement (exit 2 on zero checks) | **Rejected** | Would block Stops in any repo without a recognised toolchain and train users to disable the hook; fix the promise, not the behaviour |
| D5 8,000-token combined target | **Superseded** | Aimed at a quantity Claude Code does not enforce; replaced by V7-19's two-part budget |

## Owner decisions carried forward

| # | Decision | Status |
|---|---|---|
| 1 | License | **Resolved** — Apache-2.0 authorized; prerequisites verified clean; tagging **not** authorized |
| 2 | Repository-level secret scanning | **Open** — required for any 9.5 claim |
| 3 | `template-repository` GitHub setting | **Open** |
| 4 | Global-tool-install policy (`pipx`, `uv tool`, `cargo install`) | **Open** — recommend ask |
| 5 | Release version number / tag | **Open** — tagging out of scope this cycle |
| 6 | Compatibility support window | **Open** — draft to be proposed |
| 7 | Confirm sole authorship of all four git identities | **Open** — inferred, not verified |
