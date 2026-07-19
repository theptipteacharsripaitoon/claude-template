# External Review Adjudication — v6

Adjudicates every finding in `external-review-v6.md` (opened only **after**
committing `reports/claude-independent-audit-v6.md` at `074fa5c`). Every verdict
below was reproduced against `2c3520125fb6f86b9848f8e84b98684e33f9c9f8` in this
session; evidence tables live in the blind audit report (cited as "audit §N").
No source file was modified before this report was committed.

Verdict key: **Confirmed** / **Partly confirmed** / **Rejected** /
**Not reproducible** / **Obsolete** / **Subjective preference**.

## Summary table

| # | Finding | Verdict | Action |
|---|---|---|---|
| 1 | Bun test execution wrong (`bun test` vs `bun run test`) | **Confirmed** (P1) | fix |
| 2 | `bun.lock` not detected | **Confirmed** (P1) | fix |
| 3 | Bun regression test host-dependent | **Confirmed** (P2) | fix |
| 4 | Protected directory segments case-sensitive | **Confirmed** (P1) | fix |
| 5 | Destructive current-directory globs allowed | **Confirmed** (P2) | fix |
| 6 | Client-wrapped semicolon-less SQL bypass | **Confirmed** (P2, documented residual) | fix (client-aware) |
| 7 | Option-first dependency policy incomplete | **Partly confirmed** (P3) | fix 3 gaps + document |
| 8 | Quoted executable-path false positives | **Confirmed as designed trade-off** | measure + document (no behavior change) |
| 9 | Bootstrap cwd documentation contradiction | **Partly confirmed** (P3) | one-parenthetical wording fix |
| 10 | Hook README override contradiction (diff-size) | **Confirmed** (P2) | fix code to honor override |
| 11 | Secret-output wording contradiction | **Confirmed** (P3, docs) | fix one sentence |
| 12 | Policy vs normal permission flow conflated | **Partly confirmed** (P3, docs) | clarify four levels; correct one over-claim |
| 13 | Bootstrap copy-then-prune trade-off | **Confirmed as trade-off; allowlist rejected on evidence** | document residual |
| 14 | Routing coverage narrower than catalog | **Confirmed** (limitation) | document; no fixture change without a live run |
| 15 | No manual-only workflow skills | **Partly confirmed** (evaluated; change rejected on evidence) | document |
| 16 | Always-loaded context large | **Confirmed as measurement; Subjective preference on action** | no change |
| 17 | `eval` in verify-done.sh | **Obsolete** (removed in v5) | none |
| 18 | Exact final-commit CI verification | **Confirmed as process requirement** | satisfy in Phase 4 |
| 19 | Suite runtime/portability | **Partly confirmed** (measured; no change) | record durations |
| — | Owner decisions (license/scanner/release/etc.) | **Confirmed as open** | proposals prepared, inactive |

---

## 1. Bun test execution — Confirmed (P1)

- **File/line:** `.claude/hooks/verify-done.sh:112` (`run_check "test" "$PM" test`).
- **Reproducer:** Bun project with passing `package.json` `test` script, no
  native `*.test.*` files, `CLAUDE_VERIFY_BLOCK=1`; stub `bun` records argv;
  real Bun 1.3.14 via Docker `oven/bun:1` (audit §5).
- **Expected:** the script-gated check (only runs when `.scripts.test` exists)
  executes that script → `bun run test` → exit 0.
- **Actual:** hook invokes `bun test` (stub argv log); real `bun test` exits
  **1** with `No tests found!`; `bun run test` exits 0 printing the script
  output.
- **Root cause:** `"$PM" test` is correct for npm/pnpm/yarn (all alias `run
  test`) but for Bun selects the native runner, which ignores the very script
  the check is gated on.
- **Severity:** P1 — blocking mode reports failure on a healthy project.
- **Fix:** run `"$PM" run test` uniformly (identical semantics for
  npm/pnpm/yarn; correct for Bun), per the reviewer's preferred shape.
- **Regression:** stub-PM cases asserting the exact argv `run test` (new VD
  cases), plus existing VD1–VD11 staying green.
- **Trade-off:** a Bun project relying *only* on native test files with no
  `test` script gets no test check — unchanged from today (the check is gated
  on the script), and honest per the hook's "cannot verify ≠ failed" policy.

## 2. `bun.lock` not detected — Confirmed (P1)

- **File/line:** `.claude/hooks/verify-done.sh:87` (`elif [[ -f bun.lockb ]]`).
- **Reproducer:** four fixture projects (`bun.lock` / `bun.lockb` / both /
  neither) through blocking mode with stub bun present and absent (audit §5);
  `bun install` with a real dependency in Docker.
- **Expected:** either Bun lockfile selects PM=bun.
- **Actual:** `bun.lock`-only selects **npm** (misdetection); Bun 1.3.14 writes
  **text `bun.lock` by default**, so every new Bun project takes this path.
- **Root cause:** detection predates Bun 1.2's lockfile format change.
- **Severity:** P1 — with npm present the wrong PM runs the script; with npm
  absent a Bun-equipped machine still reports "npm is not installed".
- **Fix:** `elif [[ -f bun.lock || -f bun.lockb ]]; then echo "bun"` (order
  before the `package-lock.json` branch, as today).
- **Regression:** `bun.lock`-only + stub bun → bun selected, `run test` argv.
- **Trade-off:** none identified; both files are Bun-exclusive names.

## 3. Bun test host-dependence — Confirmed (P2)

- **File/line:** `tests/hooks/run-tests.sh` case VD9 (asserts the honest
  "no verification" message for a `bun.lockb` project, valid only when the host
  lacks bun).
- **Reproducer:** stub matrix (audit §5): with a stub `bun` prepended to PATH
  the same fixture runs checks instead of skipping — VD9's expectation depends
  on the host.
- **Expected/fix:** force bun-absent deterministically (restricted PATH built
  from tool symlinks/wrappers, or run with PATH pruned of bun) and add a
  bun-present case via stub.
- **Severity:** P2 (test correctness/portability, not runtime behavior).
- **Regression:** the reworked cases themselves.
- **Trade-off:** slightly more harness code; removes an implicit environment
  assumption.

## 4. Protected directory-segment case — Confirmed (P1)

- **File/line:** `.claude/hooks/protect-files.sh:43` (`SEG` built from
  unfolded path; `has_segment` case-sensitive), `:146` (settings glob,
  case-sensitive), design comment `:38-39`.
- **Reproducer:** 12-path × Write/Edit/NotebookEdit matrix + NTFS same-file
  proof (audit §7): writing via `.CLAUDE/settings.local.json` changed the file
  read via `.claude/…`; `[test] injected` appended via `.GIT/config` was read
  back by `git config` itself.
- **Expected:** on the template's primary platforms (Windows/macOS,
  case-insensitive filesystems) case variants address the same file and must
  gate identically — the hook's own rationale for basename folding.
- **Actual:** `.GIT/config`, `.Secrets/token.txt` (deny tier) and
  `.CLAUDE/settings.local.json`, `.GITHUB/actions/…`, `.github/ACTIONS/…`,
  `MIGRATIONS/0001.sql` (ask tier) are all **ALLOW**.
- **Root cause:** deliberate v5 scoping ("folders are conventions, not
  secrets") that doesn't survive the same-file argument on case-insensitive
  filesystems.
- **Severity:** P1 — deny-tier bypass reaching real `.git` internals.
- **Fix:** case-fold the segment haystack and the settings-path comparison;
  keep `$FILE` original casing in reasons/logs (already the rule for
  basenames). On case-sensitive Linux a genuinely distinct `.GIT/` dir then
  errs toward ask/deny — endorsed by the hook's own "over-cautious, never a
  dangerous allow" philosophy (protect-files.sh:16-17).
- **Regression:** case-variant deny/ask cases + `src/app.py` allow control +
  backslash form.
- **Trade-off:** the Linux over-caution above; accepted.

## 5. Destructive current-directory globs — Confirmed (P2)

- **File/line:** `.claude/hooks/block-destructive.sh:43-46` (dangerous-target
  list: `/`, `*`, `$HOME`, `~` — no dot-forms).
- **Reproducer:** hook matrix + real deletions in disposable sandboxes
  (audit §6): `rm -rf ./*`, `-- ./*`, `./.??*`, `./* ./.??*`, `"./"*` all
  ALLOW and all really delete; `rm -rf .` / `./` / `..` are ALLOW but inert
  (GNU rm POSIX refusal, exit 1) — reproducing the reviewer's own correction.
- **Expected policy:** deny the glob forms (destructive breadth equal to the
  already-denied bare `*`) and the dot-targets (destructive intent, zero
  legitimate use); keep `rm -rf ./build`, `rm -rf ../temporary-build`,
  `rm -rf build/` allowed.
- **Severity:** P2 (real deletion, but scoped to cwd; bare `*` equivalent was
  already deny).
- **Fix:** three additional dangerous-target regexes on the existing `RM_REC`
  anchor (dot/dot-dot target; `./`-prefixed `*` incl. quoted `"./"*`;
  `.??*` hidden-glob with optional `./` prefix).
- **Regression:** failing-first deny cases for all five forms + allow controls.
- **Trade-off:** denies prose like `echo "rm -rf ./*"` (same measured FP class
  as existing rm patterns, audit §10); named relative cleanup stays allowed as
  required.

## 6. Client-wrapped semicolon-less SQL — Confirmed (P2; was a documented residual)

- **File/line:** `.claude/hooks/block-destructive.sh:78-84`; residual disclosed
  at `.claude/hooks/README.md:38`.
- **Reproducer:** audit §8 — `psql -c "DELETE FROM users"` (both quote styles),
  `mysql -e …`, `sqlcmd -Q …` all ALLOW while executing an unguarded delete;
  `;`-terminated forms DENY; `WHERE` form correctly ALLOW; prose controls
  (`echo`, `git commit -m`, `printf`) correctly ALLOW.
- **Root cause:** the no-`;` DELETE anchor deliberately treats a closing quote
  as an allow boundary to spare prose; client invocations sit inside quotes.
- **Fix (client-aware, per reviewer direction):** one pattern matching
  `psql|mysql|sqlcmd` + intervening options + `-c|-e|-Q` + a quote +
  `DELETE FROM <name>` + optional `;` + closing quote — WHERE still breaks the
  match; prose controls untouched (no client token). DROP/TRUNCATE client forms
  already deny (unanchored patterns) — verified.
- **Regression:** four deny cases, WHERE allow control, prose controls
  re-asserted.
- **Trade-off:** other clients (e.g. `sqlite3 db "DELETE FROM x"`) remain a
  documented residual; README updated to name the honest boundary.

## 7. Dependency option policy — Partly confirmed (P3)

Reproduced classification (audit §9): the reviewer's list is right for
`npm install --prefix /tmp lodash`, `pip install --target /tmp requests`,
`pip install --no-deps requests` (all ALLOW today; all install new code), and
right that restores must stay allowed (`npm ci`, `-r requirements.txt`, bare
install, `uv sync`, `poetry install`, `bundle install`, `composer install` all
ALLOW ✓). **`npm install --workspace app lodash` already ASKs** (the option-skip
pattern reads `app` as a package token) — that item is not a gap.
`pip install --index-url … requests` reproduced ALLOW in Phase 3's failing-first
run; treated as a supply-chain-relevant ASK (non-default index).

- **Fix:** targeted ASK patterns for `--prefix`/`--target`/`--no-deps`/
  `--index-url` forms (a fully general "option with value then package" regex
  cannot distinguish `-r FILE` from `-X pkg` by shape — it would re-ask
  restores, which the reviewer forbids). Classification table added to the
  hooks README (dependency mutation / user-site or global mutation /
  environment-only install / restore).
- **Regression:** deny…ask cases for the four forms + restore allow controls.
- **Trade-off:** `pip install --index-url mirror -r requirements.txt` (mirror
  restore) will ask — accepted, documented: a non-default index is itself a
  supply-chain decision.

## 8. Quoted executable-path false positives — Confirmed as designed trade-off

Reproduced (audit §10): `echo "/bin/rm" -rf /`, `printf '%s\n' '"/bin/rm" -rf /'`,
`git commit -m 'document "/bin/rm" -rf /'` all DENY. This is the intentional
v5 quoted-path catch (`block-destructive.sh:26-28` documents it); the measured
counter-controls (`echo 'rm -rf /'`, `git log --grep "rm -rf"`, all DELETE
prose) stay ALLOW. Also measured live: the session's own hook denied this
audit's Bash call containing `echo "DROP TABLE users"` (README:40's documented
behavior). **Action:** keep behavior; the trade-off is now measured and
documented in audit §10 and the README's FP wording is already accurate.
No code change — matching the reviewer's "measure and document".

## 9. Bootstrap cwd documentation — Partly confirmed (P3)

- **Reproduced:** behavior is coherent and deliberate — failed bootstrap leaves
  cwd untouched (assembly `cd` is inside the `if ! ( … )` subshell,
  claude-init.sh:74-85); successful bootstrap intentionally ends with
  `cd "$dest"` (line 118) and prints `Currently at:`.
- **The defect is one parenthetical:** "(all cd's happen in a subshell)"
  (line 11) over-generalizes — the success-path `cd` does not.
- **Fix:** reword the parenthetical to scope it to the assembly phase and state
  the success-path `cd` explicitly. No behavior change ("choose one behavior"
  is already satisfied; the doc just needs to say it exactly).

## 10. Diff-size override contradiction — Confirmed (P2)

- **File/line:** `.claude/hooks/check-diff-size.sh:68-77` (hard-block branch,
  no `check_override` call) vs `.claude/hooks/README.md:44` ("… or raise
  `CLAUDE_DIFF_BLOCK_LINES` / set `CLAUDE_HOOK_OVERRIDE`").
- **Reproducer:** 1200-line Write payload; exit **2** under
  `CLAUDE_HOOK_OVERRIDE=check-diff-size` **and** `=all`; 400-line warn control
  exits 0 (audit §11).
- **Root cause:** the hook predates the override convention and was never
  wired to `lib.sh`'s `check_override`.
- **Fix decision:** fix the **code** (honor the override, logged), not the doc —
  every other blocking hook honors it, `lib.sh:68-90` documents it as the
  universal mechanism, and the README's promise is the desired contract. The
  reviewer's alternative (document `CLAUDE_DIFF_BLOCK_LINES` only) would leave
  one hook inconsistent with the repo's own override design.
- **Regression:** failing-first: override set → exit 0 (logged); unset →
  exit 2. `CLAUDE_DIFF_BLOCK_LINES` path re-asserted.
- **Trade-off:** override now bypasses the oversized-write gate too — that is
  exactly what the documented, logged, deliberate override is for.

## 11. Secret-output wording — Confirmed (P3, docs)

- **File/line:** `.claude/hooks/README.md:97`: "sensitive content stays in
  stderr, not in the log" — read literally, it instructs future hook authors to
  put sensitive content **into** stderr, contradicting lines 87-94 and the
  implementation (scan-secrets.sh:114-127: value withheld from both).
- **Reproduced:** the implementation is correct (suite case SS11); only the
  guidance sentence is wrong. Missed in the blind pass (audit §11 verified the
  value-withholding claims but not this sentence) — credited to the external
  review.
- **Fix:** reword: actionable *context* (paths, pattern names) goes to stderr;
  the log gets only pattern names; secret **values** go to neither.

## 12. Policy vs permission flow — Partly confirmed (P3, docs)

- **Reproduced:** CLAUDE.md §2 requires "explicit user confirmation in the
  current message" for `git push` / `kubectl apply` / `helm upgrade`; the hook
  layer deliberately leaves these to Claude Code's normal permission flow
  (hooks README:37). The README row claims such commands are "still surfaced to
  you by Claude Code, never silently executed" — **not unconditionally true**:
  a user pre-allowlist (settings permissions) executes them without a prompt.
  Not hook-testable; verified against Claude Code's documented settings
  behavior and the README's own settings.local.json rationale
  (protect-files.sh:141-145 documents allowlists taking effect).
- **Fix:** correct that clause and add a short four-level distinction
  (deterministic hook ask → normal permission prompt → user pre-allowlist →
  CLAUDE.md's in-chat confirmation norm), stating plainly that prose policy is
  not deterministically enforced for tier-3 commands.

## 13. Bootstrap copy-then-prune — Confirmed as trade-off; allowlist rejected on evidence

Measured (audit §13): +250 MB of local state costs <0.1 s (install.sh
self-tests dominate at ~13 s); prune list works; SIGKILL leaves only the
documented temp dir and never publishes; **unknown future `.claude/` files do
leak** (reproduced). An allowlist would trade a low-severity residual (template
checkouts are normally clean clones) for permanent silent-omission risk on
every future template file. Decision: keep the model; document the residual in
the claude-init header. Matches the reviewer's own bar ("do not add complexity
unless the benefit is clear and tested" — it is not).

## 14. Routing coverage — Confirmed (limitation, no change this cycle)

20 cases / 16 distinct `must_load` skills vs 37 catalog skills (audit §12).
Expansion requires a new **live** eval run (the consistency gate requires the
newest full-fixture run to match the fixture count, so fixture edits without a
live run break CI). No description or invocation changes are being made this
cycle, so no live run is triggered; the limitation is recorded in both reports
and the 9.5 acceptance gate is explicitly not claimed.

## 15. Manual-only workflow skills — Partly confirmed (evaluated; no change)

Evaluation performed as requested (audit §12): `repository-cleanup` and
`git-hygiene` are live-eval `must_load` targets (1 and 2 cases) — manual-only
would mechanically regress measured recall; `release-readiness` and
`verification` have zero eval coverage and zero measured over-triggering
(precision 1.0, conflict 0.0), so there is no evidence basis to change them.
Idle description cost measured: 727 + 615 + 497 + 548 chars. Per the cycle
mandate ("do not change invocation behavior without routing/usability
evidence"): **no change**, documented.

## 16. Always-loaded context — Confirmed as measurement; Subjective preference on action

Measured (audit §12): CLAUDE.md 4,884 words / 32,791 chars; 37 descriptions
mean 533.8 chars; bodies 181,647 chars. The reviewer's own guardrail ("do not
reduce safety-critical clarity merely to save tokens") applies; with routing
precision 1.0 there is no misrouting signal to trade against. No change.

## 17. `eval` in verify-done.sh — Obsolete

Removed in v5. Verified by reading the current file: `run_check` executes an
argument vector; the comment cites §7 (verify-done.sh:65-77). Audit §15.

## 18. Exact final-commit CI verification — Confirmed as process requirement

Baseline recorded (audit §1): run `29681254044` green on exactly `2c35201…`.
The same record (SHA / run id / conclusion / summary) will be captured for the
final v6 commit in Phase 4 before any "green" claim.

## 19. Suite runtime/portability — Partly confirmed

Measured: Windows Git Bash **3m49s** for 187 cases (audit §4); CI (ubuntu)
duration to be recorded in Phase 4 from the run metadata. WSL is not installed
on this host — stated, not fabricated. No code change: the suite is CI's gate
(fast there), the local cost is documented, and a subset/filter mechanism is
declined this cycle as scope creep.

## Owner decisions — Confirmed as open; proposals prepared, inactive

License, secret-scanner layer, release/version + compatibility policy,
SECURITY/CONTRIBUTING, template-repository setting, update mechanism,
installation profiles → consolidated in `reports/proposal-owner-decisions-v6.md`
(Phase 3) with options and recommendations. **Nothing activated**: no license
chosen, no scanner installed, no tag created, per the standing constraints.

---

## Planned implementation set (Phase 3)

| Change | Files | Findings |
|---|---|---|
| Bun: detect `bun.lock`, run `"$PM" run test` | `verify-done.sh` | 1, 2 |
| Host-independent bun cases (restricted PATH + stub) | `tests/hooks/run-tests.sh` | 3 |
| Case-fold directory segments + settings comparison | `protect-files.sh` | 4 |
| Deny current-dir glob/dot rm targets | `block-destructive.sh` | 5 |
| Client-aware no-`;` DELETE pattern | `block-destructive.sh` | 6 |
| ASK for `--prefix`/`--target`/`--no-deps`/`--index-url` installs | `block-destructive.sh` | 7 |
| Honor override in diff-size hard block | `check-diff-size.sh` | 10 |
| README: override wording verified-true, secret-guidance sentence, tier-3 permission clarity, coverage rows, dependency classification table, SQL residual update | `.claude/hooks/README.md` | 6, 7, 10, 11, 12 |
| claude-init header: cwd parenthetical + unknown-file residual | `claude-init.sh` | 9, 13 |
| CHANGELOG sixth-cycle entry; README sync if needed | `CHANGELOG.md`, `README.md` | 18 |
| Owner proposals (inactive) | `reports/proposal-owner-decisions-v6.md` | owner block |

Each fix lands with a failing-first regression, then focused tests, then the
complete suite + ShellCheck + offline checks (Phase 4 battery).
