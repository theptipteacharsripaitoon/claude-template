# External Review v5 — Adjudication

Source: `../external-review-v5.md` (OpenAI GPT-5.6 Thinking, snapshot
`21cc3d5`), opened **only after** the blind audit was committed (`87f080f`,
`reports/claude-independent-audit-v5.md` — cited below as **audit §n**).
Every verdict below was reproduced in this session against `main@21cc3d5`;
nothing was carried forward from prior cycles or taken on the reviewer's word.

## Cross-check of the review's "authoritative evidence from v4"

All of it reproduces exactly (audit §4, §13): hook suite **143/0**, catalog
**37**, scoring tests **6/6**, final 20×3 metrics recall 0.963 / precision
1.000 / conflict 0.000 / no_load 0.037 / stability 0.900, and the two no-loads
are precisely `review-api-breaking` run2 and `dag-add-retry` run2 (re-queried
from the JSONL). One number differs: "full skill bodies 22,149 words" — I
measure 25,017 words (SKILL.md only) / 26,675 (all `.md` under skills); basis
difference, no bearing on any finding.

## Verdict summary

| # | Finding | Verdict | Cycle action |
|---|---|---|---|
| 1 | Bootstrap publishes incomplete project on masked `cp` failure | **Confirmed (P1)** | fix + 4 regressions |
| 2 | `settings.local.json` unprotected | **Confirmed (P2)** | ASK policy + 3-tool regressions |
| 3 | Command variants bypass (quoted/braced/option-first/semicolon-less) | **Confirmed (P2)** — all 11 listed reproduced | widen patterns + safe controls |
| 4 | Inconsistent basename case-folding | **Confirmed (P2)** — 7 variants reproduced | fold all basenames + mixed-case tests |
| 5 | Final evidence must point to final commit | **Partly confirmed** | adopted as Phase-5 gate |
| 6 | Final routing run not in `evaluated_runs` | **Confirmed (P2)** | record + consistency test |
| 7 | CI lacks new durable checks | **Confirmed (P2)** | add offline checks (no live routing) |
| 8 | Stream-JSON extraction untested | **Confirmed (P2)** | pure parser + 7 fixtures + `--fail-on-error` |
| 9 | Root documentation stale | **Confirmed (P2)** | README/CHANGELOG/hooks-README fixes |
| 10 | Env-template hook vs `.gitignore` disagreement | **Confirmed (P2)** | unignore all 5 supported names |
| 11 | Composite-action scripts bypass review | **Confirmed (P2)** | ask whole `.github/actions/` subtree |
| 12 | Generic `*.pem` deny too broad | **Confirmed (design trade-off)** | `*.pem` → ask; key containers stay deny |
| 13 | Repository-level secret scanner | **Confirmed as proposal-only** | proposal committed; **not installed** (owner) |
| 14 | Protected-branch guard | **Partly confirmed** | low-noise ASK for `git commit` on protected branch |
| 15 | 20 prompts ≠ 37-skill validation | **Confirmed limitation** | documented; no live expansion (no description changes this cycle) |
| 16 | Manual-only side-effect skills | **Evaluated → rejected as change** | evidence-based no-change |
| 17 | Always-loaded context large | **Partly confirmed** | sizes verified; trimming rejected as unevidenced |
| 18 | Replace `eval` in verify-done.sh | **Confirmed (P3)** | direct arg execution |
| 19 | LICENSE | **Confirmed — owner decision** | untouched by instruction |
| 20 | Release/compatibility policy | **Confirmed — owner decision** | untouched |
| 21 | README guardrail-not-sandbox warning | **Confirmed (P2)** | one-paragraph warning near intro |
| — | "Tracked Python bytecode" | **Rejected — concur** | `git ls-files` evidence; cleanliness CI check added instead |

## Confirmed findings — detail

### 1. Bootstrap masked copy failure — Confirmed, P1
- **File/line:** `claude-init.sh:67–79` (the `if ! ( set -e; cp…; bash install.sh )` block); misleading comment at 64–66.
- **Reproducer:** PATH-stub `cp` failing only on the `CLAUDE.md` source argument; run `claude-init proj` (audit §6, harness case 02; identical results for `.gitignore` 04 and `.gitattributes` 05).
- **Expected:** nonzero exit, no destination, no success message.
- **Actual:** exit **0**, `✅ Project 'proj' bootstrapped …`, destination published **without** the file.
- **Root cause:** bash ignores `-e` for any command in a `!`/`if` context, and a `set -e` issued *inside* a compound command already in that context has no effect until it completes — so nothing short-circuits and the subshell's status is `install.sh`'s alone. The reviewer's mechanism statement matches what I derived from bash semantics and proved empirically.
- **Severity:** P1 — publishes a project missing root protections (`.gitignore` case ⇒ `git add -A` stages `.env`).
- **Fix:** `&&`-chain every step inside the subshell (`&&` short-circuits regardless of `set -e` context); add an explicit required-files validation of `$tmp` before the `mv`; correct the comment; keep temp-sibling + rename atomicity and cwd isolation.
- **Regression:** four one-failure-at-a-time PATH-stub cases (CLAUDE.md / `.claude` / `.gitignore` / `.gitattributes`) asserting nonzero exit + no dest + no temp + cwd preserved, in `tests/hooks/run-tests.sh`.
- **Trade-off:** none measurable; success path identical.

### 2. `settings.local.json` — Confirmed, P2; policy decision = **ASK**
- **File/line:** `.claude/hooks/protect-files.sh:129` (suffix rule covers only `settings.json`).
- **Reproducer/actual:** Edit/Write/NotebookEdit payloads all **allow** (audit §7 matrix).
- **Expected:** same ask tier as `settings.json`/`hooks/` — official docs (fetched this session) confirm local scope overrides project settings, its `allow` rules bypass workspace trust, and `disableAllHooks` is accepted there.
- **Fix:** extend the rule to both settings basenames under `.claude/`; document rationale.
- **Regression:** 3 tools × local-settings path, plus `settings.json` unchanged-tier guard.
- **Trade-off:** one extra in-chat approval when Claude legitimately edits local settings — the tier's purpose. Claude Code's own "don't ask again" persistence is not a hooked tool call and is unaffected.

### 3. Command variants — Confirmed, P2
- **File/line:** `.claude/hooks/block-destructive.sh:30` (`RM_REC` anchor/target), `:58` (`+refspec`), `:72` (DELETE requires `;`), `:95–101` (install patterns reject option-first).
- **Reproducer:** audit §8 matrix — all 11 reviewer variants reproduced as allows (E1.02/03/08/09, E2.03/04, E3.01/03/05→ semicolon-less forms, E4.02/03/04/07).
- **Expected/actual:** deny (or ask) per documented tier vs observed allow.
- **Root cause:** regex anchors admit no quote characters around the command word or refspec; `\$HOME` does not admit braces; DELETE pattern requires a terminating `;`; install patterns require the package name immediately after the verb.
- **Severity:** P2 (deny-layer completeness; each has a plausible non-adversarial spelling).
- **Fix:** quoted-`rm` alternation (closing-quote after `rm`, or balanced quotes around bare `rm`); `\$\{?HOME\}?`; optional quote before `+` in refspec; option-tolerant npm/pip install matching that still exempts `-r/--requirement/-e/-c` restores; DELETE without `;` denied when the statement ends at the command/quote boundary and has no `WHERE`.
- **Regression:** every widened form as a deny/ask case **plus** safe controls staying allowed: `echo 'rm -rf /'`, `echo "DELETE FROM users"`, `git commit -m "document DELETE FROM users"`, `rm -rf build/`, `pip install -r requirements.txt`, `npm ci`, `npm install`, WHERE-guarded DELETE.
- **Trade-off:** measured false-positive surface unchanged on the documentation-text controls (verified in the post-fix matrix).

### 4. Case-folding — Confirmed, P2
- **File/line:** `protect-files.sh:56–60` (`base_is` exact-case), `:39–50` (allowlist exact-case) vs `:67–74` (folded `.env`/extensions).
- **Reproducer:** audit §9 — `ID_RSA`, `Id_Rsa`, `Secrets.yaml`, `Credentials.json`, `.NPMRC`, `.PYPIRC`, `.NETRC` all allowed.
- **Fix (one documented strategy):** case-fold **all** basename comparisons (deny names, ask names, allowlist); segments unchanged; original casing preserved in reasons (`$FILE` already printed verbatim).
- **Regression:** mixed-case deny/ask rows; lowercase rows unchanged; `src/keyboard.ts`-class substring controls unchanged.
- **Trade-off:** on case-sensitive Linux, a file literally named `Secrets.yaml` now also gates — over-caution consistent with the hook's stated posture.

### 5. Final evidence → final commit — Partly confirmed
The v4 report itself distinguished the states and flagged the follow-up commit;
the exact final head `f546f6f` in fact has green runs (`29675656944`,
`29675646660`) — but those postdate the report, so at reporting time "CI green"
named `7a7a6fc`, not the final head. **Adopted as this cycle's Phase-5 gate:**
the final pushed commit is not called green until that exact SHA has a
successful run (recorded in the post-implementation sections).

### 6. `evaluated_runs` — Confirmed, P2
- **File/line:** `tests/skills/trigger-cases.yaml:113–140` (3 entries; the 195349 full run absent), `run_eval.py:22–23` (docstring instructs appending).
- Also confirmed (audit §13): the three existing entries hand-carry
  `cc_version: 2.1.214` while their own summary files record `null`.
- **Fix:** append the 195349 entry (model, cc_version 2.1.214 — this one IS
  artifact-backed by its summary — runs, metrics, results file); annotate the
  older entries' unsupported `cc_version`; add an offline consistency test that
  recomputes every summary from its JSONL and cross-checks `evaluated_runs`
  entries against the files they cite.
- **Trade-off:** none; metadata only.

### 7. CI durable checks — Confirmed, P2
Adopted into `.github/workflows/test.yml` (all offline, seconds each): routing
scoring + stream-parser fixtures, results/fixture consistency, `py_compile`,
workflow+fixture YAML validation, generated-file cleanliness
(`git ls-files '*.pyc'` / `__pycache__` must be empty), and a repo-wide
relative-Markdown-link check. Live model routing stays out of CI (auth + cost),
per both the review and the task constraints.

### 8. Stream-JSON extraction — Confirmed, P2
- **File/line:** `run_eval.py:144–168` — `json.JSONDecodeError → continue`
  (silent), no terminal-`result` requirement, no `--fail-on-error`; a garbage
  stream with exit 0 scores as a valid no-load (audit §14).
- **Fix:** extract a pure `parse_stream(lines)` returning loaded/model/version/
  error state **plus** malformed-line count and result-event presence; a run
  with parse anomalies or no result event is marked errored (excluded from
  metrics, counted in `runs_errored`), never a scored no-load; add
  `--fail-on-error`; unit-fixtures for: one skill, multiple skills, unrelated
  events, malformed line, error event, missing-skill-input event, schema
  variation (content absent / non-list), plus garbage-only stream.
- **Regression:** fixtures run offline in the same test file, and in CI (#7).
- **Trade-off:** a future benign schema change now surfaces as loud errored
  runs instead of silent zeros — intended.

### 9. Root documentation — Confirmed, P2
Reproduced (audit §15): README "107-case" vs authoritative 143; CHANGELOG's
newest entries are cycle 3 (the nine v4 commits `ba00728…f546f6f` added none);
hooks README claims the matched secret value "goes only to Claude's stderr"
while the probe shows it goes nowhere, and its "unguarded DELETE" wording
overstates the pre-fix pattern. Fix: correct hooks README behavior claims; add
cycle-4 (retroactive, from the commit log) and cycle-5 CHANGELOG entries;
README count replaced with a **non-brittle** phrasing per the review's own
"avoid brittle exact numbers" guidance (the runner's RESULT line stays the
authoritative count).

### 10. Environment templates — Confirmed, P2
`.gitignore:10` ignores `.env.*` re-including only `.env.example`, while
`protect-files.sh:39–45` allowlists five template names as "committed env
templates" (audit §11). **Chosen policy: unignore every explicitly supported
template name** (CLAUDE.md §7 says templates are committed; the hook list is
the policy). Regression: `git check-ignore` expectations for all five names +
`.env`/`.env.local` still ignored — encoded in the suite via a scratch repo.

### 11. Composite-action subtree — Confirmed, P2
`protect-files.sh:102` gates only `action.yml|yaml`; `script.sh`/`index.js`
under `.github/actions/**` edit freely (audit §10). **Decision: the whole
`.github/actions/` subtree asks** — the scripts execute with workflow trust.
Regression: three subtree rows ask; `.github/ISSUE_TEMPLATE.md` control stays
allowed (subtree scope is `actions/`, not all of `.github/`).

### 12. Generic PEM — Confirmed as a design trade-off
`protect-files.sh:72–74` hard-denies every `*.pem`, which also blocks public
certificate chains. **Decision:** `*.pem` → **ask** (human approves cert
edits); `*.key|*.p12|*.pfx|*.keystore|*.jks` and `id_*` stay **deny**;
private-key *content* remains hard-blocked by scan-secrets' BEGIN-PRIVATE-KEY
pattern regardless of filename. Regression updated deliberately: PFK2
(`certs/server.pem`) now expects ask; `tls.key` still deny. Not a weakening to
"allow": every `.pem` edit still requires explicit approval.

### 14. Protected-branch guard — Partly confirmed → low-noise ASK implemented
CLAUDE.md §2 forbids commits to protected branches; no hook inspects the
branch (audit §8 note). Plain `git push` stays in Claude Code's normal
permission flow (documented tier — an extra ask would duplicate it), but a
branch-aware **ask** for `git commit` while on `main`/`master`/`production`/
`release/*` is cheap and matches written policy. Regression: scratch repos —
commit on `main` asks, commit on `feat/x` stays plain-allowed, non-git cwd
stays allowed. Trade-off: solo workflows that commit straight to `main` see
one approvable prompt; that is the policy CLAUDE.md already states.

### 18. `eval` in verify-done.sh — Confirmed, P3
`verify-done.sh:65–75` (`run_check` → `eval "$cmd"`). Commands are
internally-constructed constants, so no live injection — but direct arg
execution (`"$@"`) is strictly safer, matches §7 guidance, and VD6–VD10 pin
behavior. Implemented with no output change.

### 21. README warning — Confirmed, P2
Root README has no guardrail-not-sandbox statement (HOW-TO:513 and hooks
README Limitations do). One short paragraph added near the intro, pointing to
the detailed docs.

## Not implemented as changes (with evidence)

### 13. Repository-level scanner — proposal only (owner approval required)
Recommended (the Write/Edit scanner's inserted-content boundary is honestly
documented and real). **Not installed, not selected** — explicit constraint.
Proposal committed at `reports/proposal-secret-scanner.md`: gitleaks pinned by
version+SHA, pre-commit and CI integration sketches, expected false positives
in this repo and the allowlist scoping to address them.

### 15. Routing coverage 20/37 — confirmed limitation, no expansion this cycle
Descriptions and invocation behavior are unchanged this cycle, so no live
rerun is warranted (task: live routing only if those change). Expansion toward
per-skill positive/negative/ambiguous/conflict cases remains the documented
path to the 9.5 bar and needs live-model budget the owner controls.

### 16. Manual-only workflow skills — evaluated, no change (evidence)
The fixture **requires** model-invocation for three of the four candidates
(`cleanup-repo-recall`, `cleanup-branch-sequence`, `untrack-node-modules`);
the final run's precision is 1.000 over 60 rows — zero extra loads, i.e. no
measured idle-activation from `release-readiness`/`verification` either.
Flipping `disable-model-invocation: true` would break measured recall to fix
an unmeasured problem. Re-evaluate on observed misfires (audit §16).

### 17. Context size — partly confirmed, no trim
Sizes verified (audit §16). The review's own caveat — "do not remove useful
safeguards merely to reduce token count" — plus zero measured routing/conflict
cost from the current descriptions means no evidence-backed trim exists this
cycle. The reopen-instruction/scoped-rules restructuring is an architecture
change deferred to an owner-scoped cycle.

### 19/20. LICENSE, release/compatibility policy — owner decisions, untouched
README continues to state "all rights reserved" until the owner chooses.

## Rejected claim — concur

**Tracked Python bytecode: rejected.** `git ls-files '*.pyc'` and
`git ls-files | grep __pycache__` are empty at `21cc3d5`; `.gitignore:14–15`
covers both; local `__pycache__` from test runs is ignored-untracked (audit
§5). No removal commit exists or is needed; a CI cleanliness check (#7) guards
the future instead.

---

Implementation follows this commit; every Confirmed item above lands with its
regression in the same cycle, validated by the full Phase-5 matrix.

---

## Implementation status (appended post-Phase-5; adjudication above unchanged)

Every **Confirmed** finding landed with its regression in this cycle:
#1 → `d6b6949` + BOOT10–13; #2/#4/#11/#12 → `237632f` + PFS/PFF/PFI/PFK
cases; #3/#14 → `f2a2d87` + BD60–75/ASK18–21/AL12/PBC1–4; #18 → `4de50fa`
(VD6–VD10 unchanged); #10 → `f87b5c7` + GI1; #6/#8 → `df2e181` (parser
fixtures, `--fail-on-error`, consistency test, `evaluated_runs` completed);
#7 → `9540d4a`; #9/#21 → `24cb1ba`; #13 → proposal committed, **nothing
installed** (owner). Suite 143 → **187/187**; 74-row command/path matrix
re-run: **0 deviations**, all safe controls unchanged. #5 is honored by
construction: the head's own CI run id and verdict are recorded in the PR
description, and no green claim precedes that exact run.

**Not changed, as adjudicated:** #15 (no live rerun — descriptions and
invocation untouched), #16 (manual-only rejected on routing evidence),
#17 (no context trim without evidence), #19/#20 (owner: LICENSE, release
policy). Post-fix weighted score: **8.9** (rescore table in
`claude-independent-audit-v5.md`).
