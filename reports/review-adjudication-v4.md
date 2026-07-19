# External Review v4 — Adjudication

Adjudicates every finding in `external-review-v4.md` (OpenAI GPT-5.6 Thinking,
overall 7.7/10) against my independent Phase-1 reproductions
(`claude-independent-audit-v4.md`, 7.6/10), the current repository, shell/git
behavior, the committed routing data, and CI evidence.

**Convergence:** the two audits agree closely. Every external P0/P1 hook and
bootstrap finding was *independently* reproduced in Phase 1 before this file was
opened. Verdicts below use: **Confirmed**, **Partly confirmed**, **Rejected**,
**Not reproducible**, **Obsolete**, **Subjective**.

Scores are within 0.1 of each other (7.7 vs 7.6). No external finding contradicts
a Phase-1 conclusion; the disagreements are two *recommendations* (skill
manual-only; fixture dependency companions) where I have evidence the current
design is better, and are argued below.

---

## Confirmed — implement (map to Phase-1 defect IDs)

| # | External finding | Verdict | Phase-1 ID | Fix |
|---|---|---|---|---|
| P0 | Stop verification disabled in linked worktree (`.git` file) | **Confirmed** | D1 | `git rev-parse --is-inside-work-tree`; + worktree regression |
| P1 | `.claude/worktrees/` not ignored | **Confirmed** | D7 | add to `.gitignore` |
| P1 | change detection: untracked-in-new-dir missed; misleading "this session" wording | **Confirmed** | D2, D3 | `--untracked-files=all`; reword to "uncommitted"; document that true session attribution needs a SessionStart baseline (out of scope) |
| P1 | secret scanner prints 8-char prefix to stderr | **Confirmed** | D4 | remove preview; + no-secret-in-output regression |
| P1 | bootstrap copies machine-local `.claude` state | **Confirmed** | D6 | prune denylist after copy; + exclusion tests |
| P1 | log record-injection (raw TSV) | **Confirmed** | D5 | escape `\t`/`\n`/`\r`/control chars in `log_event`; + hostile-field test |
| P1 | command FN: `/bin/rm`, `\rm`, `rm -rf -- /`, `rm --recursive --force -- /` | **Confirmed** | D9 | extend command-start anchor to `[/\\]`; handle bare `--` |
| P1 | command FN: `DELETE FROM dbo.Users;`, `[dbo].[Users]` | **Confirmed** | D8 | widen table-name class to include `. [ ]`; keep WHERE-guard allowed |
| P1 | command FN: `git push origin +main` | **Confirmed** | D10 | add `+refspec` force pattern |
| P1 | protected paths: `id_rsa`,`*.pem`,`*.key`,`.netrc`,`.npmrc`,`.pypirc`,`action.yml`,`.gitmodules` ungated | **Confirmed** | D11, D13 | DENY key/cert; ASK cred + composite-action + `.gitmodules` |
| P1 | HOW-TO omits `.gitignore`/`.gitattributes` that claude-init requires | **Confirmed** | D16 | add to Option B + required-tree |
| P1 | ENFORCEMENT stale `MultiEdit` matcher (copyable) | **Confirmed** | D17 | → `NotebookEdit`; note re-entry guard + segment matching |
| Routing | no post-fix full 20×3 run; no unit tests; no threshold; MISS exits 0; hardcoded `CLUSTER_KEYS`; no dup-id reject; minute-precision overwrite; cc_version manual | **Confirmed** | D14, D15 | full rerun (Phase 5); dynamic clusters; dup-id guard; overwrite guard; optional threshold; scoring-math unit tests |
| Testing | missing worktree / log-injection / secret-output / bootstrap-exclusion / untracked-dir / command-prefix tests; scratch dir leaks (no EXIT trap) | **Confirmed** | (test gaps) | add the regressions; add `trap 'rm -rf "$SCRATCH"' EXIT` |

### New, valid findings the external review caught that Phase 1 under-weighted

- **`..` not collapsed → false-positive ASK.** `protect-files` matches the `infra`
  segment in `/repo/infra/../src/app.py` even though it resolves to `/repo/src/`.
  **Confirmed** (over-cautious ASK, not a dangerous ALLOW — low severity). Phase 1
  noted `..` isn't resolved but framed it only as an FN-avoidance detail; the FP
  direction is the real (minor) cost. Fix: document the limitation precisely (the
  header already claims "normalized path components" — tighten that wording) and,
  optionally, skip protection when a segment is immediately followed by `..`.
- **CLAUDE.md "§1-18" mislabel.** `HOW-TO.md:475` labels CLAUDE.md as "universal
  §1-18"; it actually has **§0–§20**. **Confirmed** factual doc error. Fix: "§0-20".
- **ENFORCEMENT Recipe 5 Stop hook lacks the `stop_hook_active` re-entry guard**
  and Recipe 2 teaches raw-substring path matching; Recipe 3 uses `-0`-unsafe
  `xargs`. **Confirmed** as copyable footguns (labeled illustrative, but worth a
  guard note + a pointer to the shipped segment-matching hook).

---

## Partly confirmed — decision differs from the reviewer's prescription

### P1 "Strict verification still allows 'nothing verified'"
**Verdict: Partly confirmed; keeping exit 0, improving documentation.** The
behavior is real: `CLAUDE_VERIFY_BLOCK=1` + code changed + no discoverable checker
→ honest warning, exit 0. The reviewer wants exit 2 (or a renamed option).

Evidence against changing the exit code: with the `stop_hook_active` re-entry
guard, a blocking exit 2 would force **one** no-op continuation (Claude cannot
conjure a checker that doesn't exist), and the second Stop passes anyway — so
blocking buys no enforcement, only friction. The current path is *honestly
reported* ("nothing was verified … run the project's checks manually") and the
hook README already documents the semantics ("0 = all discovered checks passed **or
none could run — reported honestly, never as 'passed'**"). This is the protocol's
"preserve current behavior when evidence shows it is better" case. **Decision:
keep exit 0**; add one sentence to the README making explicit that BLOCK mode
enforces *"discovered checks pass"*, not *"checks exist"*. (Protocol Phase-4 asks
to "decide and document strict zero-check behavior" — this is the decision.)

### P1 "Approval and diff-size hooks can conflict"
**Verdict: Partly confirmed — documentation, not code.** A 1000+-line write to a
protected path is `ask` (protect-files) **and** hard-deny (check-diff-size); deny
wins, so approval can't authorize the oversized rewrite. This is **correct by
design** (an oversized rewrite should be split regardless of path approval), and
overridable via `CLAUDE_DIFF_BLOCK_LINES` or `CLAUDE_HOOK_OVERRIDE`. The
`max(old,new)`-lines heuristic is a documented proxy. **Decision:** add a short
note to the hook README that protected-path approval does **not** override the
oversized-diff block, and how to override intentionally. No code change.

### P1 "Command policy and command hook do not match"
**Verdict: Confirmed (FN/FP) + partly (policy wording).** The FN/FP reproductions
are all confirmed (see D8/D9/D10 above; the `echo "…DROP TABLE…"` / commit-message
FPs are the documented deliberate tradeoff — see Rejected below). The *policy-
alignment* half is valid: CLAUDE.md §2 lists broad "requires confirmation" items,
while the hook implements deny/ask/allow tiers and routes the rest through Claude
Code's normal permission flow. **Decision:** document the three tiers explicitly
(deny / ask / normal-permission-flow / known-uncovered-semantic-equivalents) in
the hook README + ENFORCEMENT, so policy and implementation visibly agree — without
weakening the hook (plain `git push`, `kubectl apply` still go through CC's
permission prompt; they are not silently executed).

`DROP VIEW/PROCEDURE/INDEX` (reviewer's FN list): **partly** — undetected but
recoverable (definition, not data). Will add them to the DROP pattern for
consistency with the conservative stance (accepting the same doc-mention FP that
already applies to DROP TABLE).

### P1 "Protected-path coverage" — the policy/docs files
**Verdict: Partly confirmed.** `id_rsa/*.pem/*.key/.netrc/.npmrc/.pypirc/action.yml/
.gitmodules` → **Confirmed**, will gate (D11/D13). But `CLAUDE.md`,
`.claude/ENFORCEMENT.md`, `.claude/skills/**/SKILL.md`: these are **meant to be
edited** (the template's entire setup workflow fills CLAUDE.md and authors skills);
gating them would fight the product. **Decision:** leave editable, document as
intentional. Root `Dockerfile`/`main.tf`: root-infra is a defensible ASK candidate;
I will gate **root-level `*.tf` and `Dockerfile`** as ASK (consistent with the
already-gated `terraform/` and prod compose) since infra edits warrant a confirm,
while keeping deeply-nested app Dockerfiles… on reflection, to avoid noisy FPs for
container-authoring projects, I will gate **`*.tf` anywhere** (infra is always
sensitive) and leave `Dockerfile` to the docker skill + normal flow. Documented.

---

## Rejected — with evidence

### "Fixture/dependency contradictions" (make dependency skills `allowed_companions`)
**Verdict: Rejected.** The reviewer reads a dependency edge (`api-review →
api-design`) as implying the dependency should be an allowed companion, not
`must_not_load`. This misreads the architecture: a skill *reference* is loaded
**on demand** when the skill body points the reader to it — it is **not**
auto-loaded from the user's prompt. The `must_not_load` entries test a **precision
boundary**: a *review* prompt should fire the review skill, not the *design* skill.

Decisive evidence: in the committed 57-run baseline, **none** of these forbidden
skills ever loaded (the only conflict was `layout-root-mess → repository-cleanup`,
now fixed). So the `must_not_load` entries produce **zero** false conflicts — they
are correctly measuring that specific-vs-general routing holds. The fixture
**already** uses `allowed_companions` where co-loading is legitimate
(`review-dag-deploy` allows `airflow`). Converting the others to companions would
*weaken* the precision test — it would stop catching a real regression where a
design/general skill spuriously fires on a review/specific prompt. Preserve current
fixture design.

### "Make side-effect skills manual-only (`disable-model-invocation: true`)"
**Verdict: Rejected as a mandate** (protocol §"Do not make them manual-only solely
to reduce metrics… Do not change code solely because the external reviewer
suggested it"). Evidence:
1. **Routing is correct.** `move-utils-file` (one-off move) loads *neither*
   git-hygiene nor repository-cleanup; `cleanup-branch-sequence`/`untrack-node-modules`
   → git-hygiene; `cleanup-repo-recall` → repository-cleanup — all measured, correct.
2. **The skills self-gate side effects.** `git-hygiene` says "approved moves only",
   "remove tracked secrets ONLY if approved", and its description explicitly excludes
   one-off moves and automated commits. It does not autonomously mutate git.
3. **The `verification` "auto git revert" claim is overstated.** The skill (line 45)
   advises the *surgical* rollback technique — "roll back ONLY the failing change …
   e.g. `git revert <commit>`; never a bulk reset." That is correct guidance for
   *when* you roll back, not a mandate to mutate git unprompted.
4. **Defense in depth.** Even if a skill fired, `block-destructive.sh` independently
   denies/asks on `git reset --hard`, force-push, etc., and CLAUDE.md §2 governs.

I therefore **preserve model-invocability**. (If a future measured case shows a
side-effect skill auto-firing and driving an unwanted mutation, revisit — but no
such case exists in the data.)

### "Redesign / substantially narrow 13 skills; conditionalize 18 skills"
**Verdict: Subjective — rejected as a mandate.** These are broad stylistic
recommendations ("converting production defaults into universal mandates") with no
reproduced defect, no measured routing harm, and no CLAUDE.md/skill contradiction
cited per skill. The protocol explicitly forbids changing skills because "a rule
sounds like best practice" or "the external reviewer suggested it." A 31-skill
rewrite is a large, behavior-changing scope with regression risk and zero evidence
of net benefit. **Not implementing.** (Individual over-absolute lines can be
softened opportunistically if a concrete contradiction surfaces, but not as a sweep.)

### "Remove the redundant 'explicitly open SKILL.md' instruction" (CLAUDE.md:5)
**Verdict: Subjective — not changing.** The instruction ("you MUST explicitly open
and read the relevant SKILL.md … Do not rely on memory") doubles as an
**anti-hallucination guard** (§3: read-before-decide), which is load-bearing for a
template whose whole thesis is "prompts drift; verify." Whether the Skill mechanism
also injects the body is a Claude-Code-version-dependent detail; the read-the-file
instruction is a safe superset. No measured harm; removing it trades a guarantee
for a marginal token saving. Keep.

### "Context is too large" (efficiency scored 6.2)
**Verdict: Subjective weighting.** The measurements match mine (CLAUDE.md ~8.2k
tokens; 37 descriptions ~4.9k; bodies load one-at-a-time). ~13k always-on is a
justifiable footprint for a governance contract; no *measured* benefit from
trimming binding rules was demonstrated. I keep my 8.5 vs the reviewer's 6.2 and do
not trim CLAUDE.md (removing binding rules to save tokens is exactly the wrong
trade for a policy file). No change.

---

## Partly / organizational (owner or note)

- **Audit archive policy.** `external-review.md` and `external-review-v2.md` are
  committed in the repo root; v3/v4 are (by design) kept outside for independence.
  The reviewer's "old reviews in the public root without a policy" is a fair
  organizational nit. `review-adjudication-v3.md` referencing an absent
  `external-review-v3.md` is **intended** (independence), not a defect. **Owner
  decision:** define an archive layout (e.g., `reports/archive/`); I will not
  relocate committed history in this cycle without direction.
- **Public readiness:** LICENSE, CONTRIBUTING, SECURITY, version/compat policy,
  install profiles, template-update propagation, template-repo flag. **Confirmed
  gaps.** LICENSE and any new release tag are explicit **owner actions** (protocol).
  CONTRIBUTING/SECURITY could be added but are reported for owner decision rather
  than fabricated in this cycle.

---

## Adjudication tally

- **Confirmed (implementing):** P0 worktree; worktrees gitignore; untracked-all +
  wording; secret preview; bootstrap prune; log escaping; rm prefix/`--`; SQL
  schema-qualified DELETE (+ DROP VIEW/PROC/INDEX); force-refspec; key/cert/cred +
  action.yml/.gitmodules + `*.tf` path gating; `..` FP wording; HOW-TO required
  files + §0-20; ENFORCEMENT MultiEdit/guard/xargs notes; routing robustness +
  unit tests + full rerun; test regressions + scratch EXIT trap.
- **Partly confirmed (documenting, not re-coding exit/precedence):** strict
  zero-check exit; diff-size/approval precedence; command-policy tier documentation.
- **Rejected with evidence:** fixture dependency-companions rewrite; manual-only
  side-effect skills; 31-skill redesign; remove-open-SKILL.md instruction;
  context-too-large trim.
- **Owner actions:** LICENSE; release tag / version+compat policy;
  CONTRIBUTING/SECURITY; archive layout; template-repo flag.

This report is committed **before** any source file is modified.

---

## Implementation status (added post-Phase-4)

All **Confirmed** findings were implemented with a failing-first regression test
(commits `ba00728`, `295546c`, `ca90acb`, `99e0c68`, `df376a4`, `653b04e`,
`b1ae106`, `f2cb449`, `7a7a6fc`; full mapping in
`claude-independent-audit-v4.md` § Post-implementation). **Partly-confirmed**
findings were resolved by documentation, not code change: the strict zero-check
exit stayed at 0 (blocking-on-absence adds no enforcement) with the semantics now
explicit in the hook README; the diff-size/approval precedence and the deny/ask/
normal-flow/uncovered command tiers are documented there too. **Rejected**
findings were left unchanged as argued. Hook suite 143/143, routing scoring
6/6, ShellCheck clean, and CI green on the pushed commit `7a7a6fc`
(run 29658887577).
