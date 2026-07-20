# Productization plan — v7

Written after the blind audit (`3bfdc0c`) and the external-review adjudication
(`7ac6560`), and **before any source file is modified**. Everything below is a
decision, not an option list: where two paths existed, the adjudication picked
one and this file records which and why.

Defect IDs refer to `reports/claude-independent-audit-v7.md` §13 and
`reports/review-adjudication-v7.md`.

## 0. Sequencing and honest scope

The work splits into three tiers by cost, and they are **not** equally
affordable.

| Tier | Work | Cost |
|---|---|---|
| **A — bounded** | P1 + P2 hook fixes, bounded guarantee, corpus schema, dependency policy table, latency fix, licence, installer allowlist + dry-run | Mechanical; each item is a regression + a small edit |
| **B — measured** | Context reduction, manual-only experiment, profiles, update propagation | Needs before/after measurement, but no live model calls |
| **C — live** | 37-skill routing evaluation (≥3 reps), 10 realistic sessions | Every case is a real model call; this is the long pole and the 9.0 gate depends on it |

**Priority order is A → C → B.** Tier C outranks tier B because the 9.0 gate
names routing coverage explicitly and tier B items are 9.5 concerns. If time or
budget runs out, it runs out in tier B, and this cycle says so rather than
declaring a gate met on partial evidence.

**Standing rule for the whole cycle:** no regex is widened before its policy
row exists in this document, and every widening ships with a corpus row proving
it did not create a false deny.

## 1. Bounded hook guarantee

The claim the hooks may make — falsifiable, and narrower than "blocks
destructive commands".

### 1.1 Recursive deletion

> `block-destructive` denies a recursive-`rm` invocation when its target token —
> after an optional `--`, an optional quote, and an optional `./` — begins with
> `/`, `~`, a `$HOME` or `$PWD` expansion, `*`, `{`, or a dot-target/dot-glob
> form (`.`, `..`, `.*`, `.??*`, `.[!.]*`, `.[^.]*`).
>
> It does **not** parse shell. It cannot see through a variable holding a path,
> arbitrary command substitution beyond `$(pwd)`, an alias, an encoded payload,
> or any deletion that is not spelled `rm`.

Named relative cleanup (`rm -rf ./build`, `rm -rf ../tmp-build`) stays allowed
and is pinned by corpus rows.

### 1.2 Protected-branch commits

> The protected-branch ask fires for `git commit` on `main`, `master`,
> `production`, `release/*`, including when git global options precede the
> subcommand and when git is invoked by path (`/usr/bin/git`), via `env`, or via
> `command`.
>
> The branch is always read from `CLAUDE_PROJECT_DIR`. **`git -C <other>` and
> `--git-dir` are not resolved**: a commit directed at a different repository is
> evaluated against the project's branch, not the target's.

### 1.3 SQL

> Unguarded `DELETE`/`DROP`/`TRUNCATE` is denied when `;`-terminated, at end of
> command, or carried by a `psql`/`mysql`/`sqlcmd` flag in short (`-c`, `-e`,
> `-Q`) or long (`--command`, `--execute`, `--query`) form, with `=` or a space
> before the quoted statement.
>
> Clients taking SQL positionally (`sqlite3 db "DELETE FROM x"`) are **not**
> covered. Documentation text that merely mentions the statement stays allowed —
> that boundary is deliberate and load-bearing.

### 1.4 Strict Stop

> With `CLAUDE_VERIFY_BLOCK=1`, the Stop hook exits 2 **only** when a checker is
> discovered, executes, and fails, on the first Stop of a turn.
>
> It exits 0 — reporting honestly that nothing was verified — when no checker is
> found or its toolchain is absent. It blocks **at most once** per turn
> (re-entry guard). It reads the working tree, so changes already **committed**
> during the session are invisible to it.
>
> This is **best-effort verification, not a hard Definition-of-Done gate.**

### 1.5 Universal

> These hooks are a prevention layer built on regex pattern-matching over the
> literal command string. They are effective against a careless agent and are
> **not** a security boundary against an adversarial one. Semantic equivalents
> (`python -c "shutil.rmtree(...)"`), encoded payloads, and downloaded scripts
> are out of scope by construction and are labelled `oos` in the corpus rather
> than silently counted as passes.

**Deliverable:** this text replaces/extends the Limitations section of
`.claude/hooks/README.md`, and the tier table stops claiming coverage the hooks
do not deliver (the three claims that failed adjudication: option-first
dependency spellings, "psql/mysql/sqlcmd flag forms are covered", and quoted
absolute-path `rm`).

## 2. Hook quality thresholds

Gate values, with the justification the review demanded.

| Metric | Baseline | Gate | Justification |
|---|---:|---:|---|
| Dangerous in-scope recall | 0.821 | **≥ 0.98** | Missing ~1 in 5 dangerous actions is not a control. Not 1.00: in-scope ≠ omniscient, and `oos` rows stay excluded rather than quietly counted. |
| Legitimate-action non-deny | 1.000 | **≥ 0.97** | The hooks README's own rule: >5% false blocks and the team bypasses the hooks. A floor to defend, not a target to approach. |
| False-deny rate | 0.000 | **≤ 0.03** | Same source. Any regression here is a release blocker regardless of recall. |
| Invalid structured responses | 0 | **0** | Already enforced — ask payloads are jq-built; suite asserts valid ask-JSON. |
| Secret-value leakage | 0 | **0** | Non-negotiable. |
| Known P0/P1 in-scope bypasses | 4 | **0** | V7-01…04 must close. |
| Hot-path hook latency (Windows p95) | 2409 ms | **≤ 600 ms** | Brings the hottest hook in line with the other five (308–779 ms). Not a round number: it is "no worse than the existing slowest hook". |

**Enforcement:** `run-corpus.sh --gate` moves into CI once violations reach 0.
Until then CI runs it in measure mode so the number is visible without being a
false green.

## 3. Complete routing coverage plan

**Target shape.** Every one of the 37 skills gets a row:

| Column | Meaning |
|---|---|
| `positive` | a prompt that must load it |
| `negative` | a prompt in its neighbourhood that must **not** load it |
| `ambiguous` | a prompt that could plausibly go two ways; records what actually happens rather than asserting |
| `conflict` | its nearest neighbour, as a `must_not_load` on the neighbour's positive case |
| `allowed_companions` | skills that may legitimately co-load |
| `seed` | the scratch repo shape |

**Coverage commitment, stated honestly.** The 9.0 gate requires *complete
positive coverage for all 37* and *broad* negative/ambiguous/conflict coverage.
So: 37 positive cases are mandatory; negative and conflict cases are mandatory
for the clusters with measured or structural overlap; ambiguous cases are
sampled, not exhaustive. Claiming exhaustive four-way coverage for 37 skills
would be a claim about work not done.

**Priority clusters for negative/conflict** (from audit §8 — the six skills with
no negative routing signal, each with a close neighbour):
`web-security`↔`security-review`; `testing`↔`verification`/`python-review`;
`api-design`↔`api-review`/`fastapi-review`;
`database-migrations`↔`database-review`/`sql-layout`;
`observability`↔`verification`; `kubernetes`↔`docker`/`docker-review`.
Plus the already-measured `repository-cleanup`↔`project-layout` conflict.

**Execution:** ≥3 repetitions per live case, recording per-skill recall and
precision, macro recall and precision, conflict rate, no-load rate, stability,
error rate, and extra-load distribution.

**Provenance (C3), added to every result file:** repository commit,
**skill-description digest**, fixture digest, model, Claude Code version, OS,
case count, repetitions, timestamp. The description digest is what makes a
routing result falsifiable after Phase 5 edits a description — without it, a
result cannot be attributed to a listing state. `test_results_consistency.py`
validates the metadata offline; CI never makes live model calls.

**Ordering constraint:** routing is measured **after** description changes land,
and re-measured if any description changes again. A description edit with no
subsequent routing run is treated as unverified.

## 4. Context budget

The review's single 8,000-token target is replaced by a **two-part budget**,
because Claude Code enforces two different things.

### Part 1 — skill listing (the budget that is actually enforced)

Claude Code loads names + descriptions into a listing with a **character**
budget scaling at ~1% of the context window; on overflow it truncates
descriptions, dropping the **least-invoked** skills' text first. Per-entry cap
1,536 chars.

| | Value |
|---|---:|
| Current listing | **20,229 chars** |
| Target | **≤ 10,000 chars** |
| Reduction required | ~50% |

10,000 is chosen as 1% of a 1M-token window — the most generous plausible
reading of the documented budget. Hitting it means the listing fits even under
optimistic assumptions; the pessimistic reading (2,000) is not reachable without
gutting routing keywords, and gutting keywords is the failure mode this is
meant to prevent.

Levers, in preference order:
1. Cut descriptions to routing signal only — trigger vocabulary plus the
   negative boundary. Largest contributors first (`repository-cleanup` 727,
   `sql-layout` 649, `git-hygiene` 615, `security-review` 614, `database-review` 607).
2. `disable-model-invocation: true` on manual-only skills — verified to remove
   the description from context entirely.
3. `skillOverrides: "name-only"` for genuinely low-priority skills.
4. `skillListingBudgetFraction` — raising the budget. **Last resort**: it hides
   the problem for this repo's owner and not for anyone who installs the template.

**Open item:** confirm empirically whether the listing currently overflows.
`--debug` produced no listing diagnostics in this session and `/doctor` is an
interactive dialog unavailable here. The owner can settle it with `/doctor`,
which reports listing cost and top contributors. Until then this is a
high-confidence arithmetic inference and is labelled as one everywhere.

### Part 2 — always-loaded prose

| | Value |
|---|---:|
| `CLAUDE.md` current | ~8,046 est. tokens |
| Target | **≤ 6,000 est. tokens** |

Token figures are chars/4 estimates — no Anthropic tokenizer is available
offline here, and that limitation is stated wherever a token number appears.
Character counts are exact.

Reductions, by classification from audit §9: move the §14 verification matrix
and §20 checklist to a reference file; compress §7 secure-defaults enumerations
to invariants plus a pointer; conditionalize §12/§19 production mandates;
trim §6/§8 to invariants and drop project-convention-dependent defaults (the
codebase is the source of truth per §1.1 anyway).

**Guard:** every reduction is followed by a routing run. A change that improves
the budget and worsens recall is reverted. Compaction is not free and this cycle
does not assume it is.

## 5. Manual-only experiment

Applied **per skill, measured**, not as a block — the four candidates are not
equivalent.

| Skill | Decision | Rationale |
|---|---|---|
| `repository-cleanup` | **Trial manual-only** | Measured conflict history (stole `layout-root-mess` 3/3 in v4), largest listing entry (727 chars), always a deliberate effort |
| `release-readiness` | **Trial manual-only** | Always deliberate; distinctive vocabulary means little recall is lost |
| `git-hygiene` | **Hold** | Genuinely wanted mid-task sometimes; decide on measured accidental-activation rate |
| `verification` | **Do not** | Exactly the skill that should fire without being asked; manual-only would degrade the completion contract |

Success criteria: listing characters down, no drop in macro recall for the
remaining skills, and no increase in no-load rate on prompts that previously
routed to the trialled skill. Reverted if recall drops.

## 6. Profiles

Five profiles, differing only in documented, testable ways. **A profile may
never silently weaken safety** — any profile that disables a deny-tier control
must say so in its own description and in the installer's dry-run output.

| Profile | Hooks | Stop | Skills | Intended user |
|---|---|---|---|---|
| `minimal` | `block-destructive`, `protect-files` | off | core only | Solo dev, scratch work |
| `standard` | all five | reminder | all 37 | **Default** — current behaviour |
| `strict` | all five | `CLAUDE_VERIFY_BLOCK=1` | all 37 | Pre-merge / CI-adjacent |
| `team` | all five | reminder | all 37 + manual-only workflows | Shared repo |
| `security-sensitive` | all five + tightened diff-size | blocking | all 37 | Regulated / auditable work |

Every profile ships with its corpus expectations, so "this profile is weaker" is
a measured statement rather than a claim.

**Installer dry-run** reports: files copied, files overwritten, selected
profile, hooks enabled, excluded local state, required tools, expected git
changes. It writes nothing.

**Bootstrap copy model (A7):** replace copy-everything-then-prune with an
explicit allowlist (`hooks`, `skills`, `settings.json`, `ENFORCEMENT.md`) —
justified by measurement: 95% of currently-copied bytes are machine-local
worktrees. The installer must **fail loudly on an unrecognised top-level
`.claude/` entry** rather than skip it, or the allowlist trades a known problem
for an invisible one.

## 7. Update propagation

Design goal: a generated project can adopt template improvements **without
silently losing local customisation**.

| Component | Decision |
|---|---|
| Version marker | `.claude/.template-version` — template commit + semver |
| Managed-file manifest | list of template-owned paths with SHA-256 at generation time |
| Drift detection | compare current hash vs manifest: `unchanged` / `locally modified` / `template updated` / `both changed` |
| Conflict policy | **never overwrite** a locally-modified file; report and leave it |
| Update command | reports the four states and applies only `template updated` + `unchanged` |
| Migration notes | `CHANGELOG.md` entries flagged `[template-update]` |

Three-way merge is **out of scope for this cycle** — it needs a merge driver and
a test matrix that does not exist yet. Detect-and-report is the honest first
step; auto-merging someone's customised hook is exactly the silent overwrite the
review warns against.

## 8. Session evaluation

Ten scenarios from audit §12 (independently identical to the review's list).
Metrics per session: skills loaded (primary + extras), approvals requested,
false asks, false blocks, Stop behaviour, test commands executed, context
consumed, interventions, wall-clock hook overhead, completion outcome.

**Budgets** (set from measured baselines, not aspiration):

| Budget | Value | Source |
|---|---|---|
| Hook overhead per session | ≤ 5% wall clock | §7 latency after the hot-path fix |
| False asks per session | ≤ 1 | corpus false-deny rate is 0.000 today; keep it |
| False blocks per session | **0** | any is a release blocker |
| Unrequested skill loads | ≤ 1 | conflict-rate gate is <2% |

**Sanitization:** fixtures are synthetic and script-generated — no real project
content, no real credentials. Recorded evidence is limited to skill names,
decision counts, timings, and outcome flags. Prompts and seeds are committed;
raw transcripts are not, and hook logs are filtered to event type + hook name.

## 9. Public release gates

| Gate | State |
|---|---|
| `LICENSE` (Apache-2.0, verbatim) | **Authorized** — prerequisites verified clean |
| README licence section | Authorized |
| SPDX headers where practical | Authorized |
| `CONTRIBUTING.md` | Draftable now |
| `SECURITY.md` | Draftable now |
| Support / compatibility policy | Draftable now |
| Release process doc | Draftable now |
| `NOTICE` file | **Not warranted** — no third-party notices exist to preserve |
| Repository secret scanning | **Owner decision — blocked** |
| `template-repository` setting | **Owner decision — blocked** |
| Release tag | **Explicitly not authorized this cycle** |

## 10. Owner decisions

| # | Decision | Recommendation | Blocks |
|---|---|---|---|
| 1 | Licence | **Resolved** — Apache-2.0 | — |
| 2 | Repository-level secret scanning | Enable GitHub secret scanning + push protection | **9.5** |
| 3 | `template-repository` setting | Enable | 9.5 (usability) |
| 4 | Global-tool-install policy | **Ask**, matching `gem`/`go` | Closes V7-13 |
| 5 | `npm install ./local-package` | Ask (mutates manifest) | Closes V7-14 |
| 6 | Release version + tag | Defer | **9.5** |
| 7 | Compatibility support window | Claude Code ≥ 2.1.196 (first version with the settings this plan uses); bash ≥ 4, jq ≥ 1.6 | 9.5 |
| 8 | Confirm sole authorship of all four git identities | Owner confirms | Licence correctness |

## 11. What this plan does not promise

- **9.5 is not reachable this cycle.** It requires active repository-level
  secret scanning, a release tag, and an independent reviewer validating the
  exact release commit — three owner-gated items, two explicitly out of scope.
- **9.0 depends on tier C completing.** Complete 37-skill positive coverage at
  ≥3 reps is the gate's largest single requirement and the most expensive item
  here. If it does not complete, the final report says 9.0 is not met and shows
  the coverage actually achieved.
- **WSL and Linux latency are unmeasured** on this machine. Linux comes from CI;
  WSL is declared unmeasured rather than estimated.
- **The listing-overflow finding (V7-19) is an inference**, not an observation,
  until someone runs `/doctor`.

---

## 12. Plan vs. delivered (appended 2026-07-20)

| Plan section | Delivered | Deviation |
|---|---|---|
| §1 bounded guarantee | hooks README Limitations rewritten as the falsifiable contract | none |
| §2 thresholds | Final corpus: 0 contract violations, recall 1.000, non-deny 1.000, false-deny 0.000; hot-path p95 270 ms ≤ 600 gate | corpus `--gate` NOT added to CI — workflow edits need owner approval (CLAUDE.md §2); gate runs locally |
| §3 routing plan | 45-case fixture, all 37 positive, 3 reps, provenance incl. description digest | none — gates met (0.940 / 0.967 / 0.007) |
| §4 context budget | Part 1: listing 20,229 → 13,415 chars. Part 2: `CLAUDE.md` untouched | Part 1 target ≤10,000 missed (−34% achieved); Part 2 deliberately deferred — going further requires another full live routing run (the §4 guard); accepted under §11 |
| §5 manual-only | `team` profile makes repository-cleanup + release-readiness manual-only | shipped as opt-in profile rather than default trial; default profile unchanged |
| §6 profiles | 5 profiles + dry-run + safety-reduction warnings | none |
| §7 update propagation | stamp + manifest + drift states + never-overwrite | three-way merge out of scope, as planned |
| §8 sessions | 9 model scenarios run; 0 false asks, 0 false blocks, 0 unrequested loads; overhead 3.8% aggregate | per-session ≤5% budget exceeded on the 4 shortest sessions (max 7.2%) — calibration finding: fixed ~1.5 s edit+Stop chain vs 24–36 s sessions; recommend an absolute floor ("≤5% or ≤2.5 s") |
| §9 release gates | LICENSE / CONTRIBUTING / SECURITY / SUPPORT shipped; tag + scanner untouched | none |
| §10 owner decisions | consolidated in `proposal-owner-decisions-v7.md` | none |
| §11 honest scope | 9.0 evidence completed this cycle; 9.5 items remain owner-gated | — |
