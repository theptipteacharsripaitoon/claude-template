# Independent Audit v4 — claude-template

Fourth-round staged audit. Phase 1 was performed **without** reading `external-review-v4.md`
and without modifying any repository source file. Every defect below was classified only
after a minimal reproducer ran; expected and actual output are recorded for each.

## 1. Audited state and environment (Phase 0)

| Item | Value |
|---|---|
| Repository | https://github.com/theptipteacharsripaitoon/claude-template |
| Audited branch | `main` (via fresh work branch, see below) |
| Audited commit | `2f7ea45333c4b1c9477585c3e29b4a64084d539d` — "Merge pull request #9" (2026-07-19 00:43 +0700) |
| HEAD == origin/main | Yes (verified after `git fetch` on 2026-07-19) |
| `c475b12ecb24003b027ef4060f5ab0e89fa292c3` | Confirmed ancestor of HEAD (v3 work merged via PR #9) |
| `2f7ea45333c4b1c9477585c3e29b4a64084d539d` | Is HEAD itself (the "uploaded-main identifier") |
| Work branch | `claude/template-audit-v4-e9e221` (Claude Code worktree branch created from current `main`; name carries the worktree suffix) |
| Claude Code | 2.1.214 |
| Model | claude-fable-5 |
| OS | Windows 11 Home 10.0.26200 (MINGW64_NT-10.0-26200, MSYS 3.4.7) |
| Shell | Git Bash — GNU bash 5.2.15(1)-release (PowerShell 5.1 available) |
| Git | 2.41.0.windows.3 |
| jq | jq-1.6 |
| Python | 3.10.9 (local) / 3.12 (CI) |
| ShellCheck | not installed locally; CI pins v0.10.0 (sha256-verified); local runs via Docker `koalaman/shellcheck:v0.10.0` |
| gh CLI | **not installed** — GitHub Actions inspected via public REST API |

### CI runs at audit time (public API, 2026-07-19)

| Run | Commit | Status | Event | Link |
|---|---|---|---|---|
| 29654472614 | `2f7ea453` (audited HEAD) | completed/**success** | push (main) | https://github.com/theptipteacharsripaitoon/claude-template/actions/runs/29654472614 |
| 29654460989 | `b2301c07` | completed/success | pull_request | https://github.com/theptipteacharsripaitoon/claude-template/actions/runs/29654460989 |
| 29653928831 | `c3406442` | completed/success | push | https://github.com/theptipteacharsripaitoon/claude-template/actions/runs/29653928831 |
| 29653854968 | `c475b12e` | completed/success | push | https://github.com/theptipteacharsripaitoon/claude-template/actions/runs/29653854968 |

Job for run 29654472614: `hooks-and-catalog` — all steps succeeded
(checkout, setup-python, pinned ShellCheck install, hook regression suite, installer
end-to-end, ShellCheck all hooks, skill catalog consistency).
Job link: https://github.com/theptipteacharsripaitoon/claude-template/actions/runs/29654472614/job/88106239371

Classification: this is a **real successful workflow execution** on the exact audited
commit — not a platform failure, not an unscheduled run. The billing lock observed in
earlier cycles is cleared (Actions has executed since run 29643662878 on 2026-07-18).

**What CI does NOT run** (relevant later): YAML validation of the workflow itself,
settings.json validation, routing-result validation, worktree Stop-hook tests,
documentation link checks, and the live routing evaluation (documented as local-only).

---

# Phase 1 — Independent full-system audit

Written **before** opening `external-review-v4.md`. Every defect was reproduced
in a throwaway scratch repo/worktree; the repository tree was not modified. Local
baseline before any change: **hook suite 107/107 pass**, installer end-to-end
passes, catalog `37 skills checked · ALL CHECKS PASS`.

## 2. Independent pre-change score — 7.6 / 10

| Category | Weight | Score | Basis |
|---|---|---|---|
| Technical correctness | 15% | 7.5 | Tests green + CI green, but real defects: worktree Stop-disable, bootstrap leak, log injection, command/path bypasses |
| Skill trigger quality | 15% | 8.0 | Measured recall 0.902 / precision 0.939 / conflict 0.053, but on a 19-case pre-fix baseline; ~20 of 37 skills covered |
| Hook correctness | 15% | 6.5 | Headline defects concentrate here (worktree disable P1, log-injection, secret-prefix, FN/FP command & path cases) |
| Conflict avoidance | 10% | 8.5 | Fixture internally consistent; the one measured conflict already disambiguated |
| Safety & permissions | 10% | 7.5 | Deny/ask tiers sound, but key/cert files ungated, `.ENV` case bypass, force-via-refspec |
| Testing & evaluation | 15% | 7.5 | 107-case suite + routing harness strong; missing worktree/log-injection/secret-output tests and a current full routing run |
| Context efficiency | 5% | 8.5 | ~13k tokens always-on (CLAUDE.md + descriptions); justifiable |
| Team usability | 5% | 8.0 | Good docs, but HOW-TO ⟷ claude-init required-file contradiction |
| Maintainability | 5% | 8.5 | Clean, documented, regression-tested |
| Public-template readiness | 5% | 6.0 | No LICENSE / CONTRIBUTING / SECURITY |

Weighted total ≈ **7.6**. (Do-not-optimize-for-score honored: this reflects reproduced behavior, not a target.)

## 3. Category scores
See the table in §2.

## 4. Full hook assessment

Five hooks + `lib.sh`, wired in `.claude/settings.json` (PreToolUse: Bash →
block-destructive; Edit|Write|NotebookEdit → protect-files, scan-secrets,
check-diff-size; Stop → verify-done). Shell hazard review under `set -euo
pipefail`: counters use POSIX `$((X+1))` (not `((X++))`), `grep -c ... || true`
guards the clean-stop path, `json_get` fails open on malformed JSON, arrays are
`${arr[@]}`-safe, `require_jq` fails open. **No `set -e` abort defects found** in
the current scripts — the v2/v3 increment and grep-exit bugs are fixed and
regression-locked (VD6, BD11, install INST1). Defects that remain are logic/scope,
not shell-fatal:

| Hook | Verdict | Notes |
|---|---|---|
| block-destructive | Sound core; FN/FP edges | see §7 |
| protect-files | Sound core; coverage gaps | see §9 |
| scan-secrets | Correct blocking; **stderr prefix leak** | see §10 |
| check-diff-size | Correct | warn 300 / block 1000; NotebookEdit covered |
| verify-done | **Broken in worktrees** + 2 lesser issues | see §6 |
| lib.sh log_event | **Record-injection** | see §11 |

## 5. Worktree reproduction

Created a real linked worktree with `git worktree add` (its `.git` is a **file**:
`gitdir: .../.git/worktrees/linked`). `git rev-parse --is-inside-work-tree`
returns `true`; `git status --porcelain` works normally.

- **`.claude/worktrees/` is NOT gitignored** (`git check-ignore` finds no rule).
  `git add -A` in a repo with `.claude/worktrees/somebranch/file.txt` **stages it**
  (`A  .claude/worktrees/somebranch/file.txt`). `.claude/logs/` *is* correctly ignored.
- `seed-repo.sh:20` strips `.claude/worktrees` + `.claude/logs` from seeded repos — correct.
- `claude-init.sh` copies `.claude` wholesale (`cp -r`) → worktrees/logs would be copied (§13).

## 6. Stop-hook matrix (`verify-done.sh`)

Reproduced across the protocol's cases. Exit codes and the reminder/blocking text
are correct in **normal checkouts** (matches suite VD1–VD10). Defects:

| # | Finding | Evidence | Severity |
|---|---|---|---|
| **D1** | **Linked-worktree disable.** `verify-done.sh:24` guards on `[[ ! -d .git ]]`; in a worktree `.git` is a *file*, so the hook `exit 0`s before checking anything. Dirty tracked `a.py` in the worktree → **exit 0, no reminder** (normal checkout emits it). Disables the Stop hook in *every* Claude Code `.claude/worktrees/` session. | orig hook in linked worktree: `exit=0 reminder=0` | **P1** |
| **D2** | **Untracked-in-new-dir miss.** Uses default `git status --porcelain`, which collapses new dirs to `?? newdir/` (ends in `/`, fails the `\.(py\|…)$` regex). An untracked `sub/c.py` under a new dir is **not counted** (orig counts 1 where 2 exist). `--untracked-files=all` surfaces `sub/c.py`. | orig: "1 … changed"; fixed: "2 … uncommitted" | P2 |
| **D3** | **Inaccurate wording.** "changed in this session" — no session baseline is captured, so it over-counts pre-existing dirty files and under-counts files modified-and-committed during the session. | code review + no baseline var | P3 |

Fix prototype proven (repo untouched): replacing the guard with `git rev-parse
--is-inside-work-tree` and adding `--untracked-files=all` makes the linked
worktree emit the reminder (exit 0, "2 code file(s) with uncommitted changes")
and preserves normal-checkout + clean-tree + no-git behavior.

Strict-mode (`CLAUDE_VERIFY_BLOCK=1`) zero-check honesty (VD5/VD9), passing/failing
checkers (VD6/VD7), polyglot (VD8), multiple failures (VD10), `stop_hook_active`
re-entry guard (VD4) all behave correctly and are regression-covered.

## 7. Command threat-model table (`block-destructive.sh`)

Full matrix run by feeding synthetic `Bash` tool-call JSON to the hook.
Legend: DENY = exit 2, ASK = permission ask JSON, ALLOW = no opinion.

| Command | Expected | Actual | Matched rule | Note |
|---|---|---|---|---|
| `rm -rf /` / `rm -fr /` / `rm -r -f /` / `rm --recursive --force /` | DENY | **DENY** | `RM_REC…/` | ✓ |
| `rm -rf "$HOME"` | DENY | **DENY** | `RM_REC…$HOME` | ✓ |
| `rm -rf build/` | ALLOW | **ALLOW** | — | ✓ (safe target) |
| `/bin/rm -rf /` | DENY | **ALLOW** | — | **FN D9** — path prefix defeats anchor |
| `\rm -rf /` | DENY | **ALLOW** | — | **FN D9** — escape prefix |
| `rm -rf -- /` / `rm --recursive --force -- /` | DENY | **ALLOW** | — | **FN D9** — `--` end-of-options |
| `find / -delete` / `find build -delete` | DENY | **DENY** | `find…-delete` | ✓ (find build also denied — mild FP, acceptable) |
| `python -c "…shutil.rmtree('/')"` | ALLOW* | **ALLOW** | — | documented semantic-equivalent limit (README) |
| `git reset --hard` / `git clean -fd` / `-df` | DENY | **DENY** | git rules | ✓ |
| `git push` / `git push origin main` | (normal perm) | **ALLOW** | — | intentional — plain push goes through CC permission flow |
| `git push --force` / `--force-with-lease` | DENY | **DENY** | `push…--force` | ✓ |
| `git push origin +main` | DENY | **ALLOW** | — | **FN D10** — force via `+refspec` |
| `git update-ref -d …` | DENY | **DENY** | `update-ref -d` | ✓ |
| `DROP TABLE users` (+ psql/mysql/sqlcmd wrappers, mixed case) | DENY | **DENY** | `DROP (TABLE\|DATABASE\|SCHEMA)` | ✓ |
| `DROP VIEW/PROCEDURE/INDEX …` | (scope) | **ALLOW** | — | gap: only TABLE/DATABASE/SCHEMA — recoverable objects; documented scope |
| `TRUNCATE TABLE events` | DENY | **DENY** | `TRUNCATE TABLE` | ✓ |
| `DELETE FROM users;` | DENY | **DENY** | `DELETE FROM \w+;` | ✓ |
| `DELETE FROM dbo.Users;` / `DELETE FROM [dbo].[Users];` | DENY | **ALLOW** | — | **FN D8** — class `[a-zA-Z_]+` excludes `.` `[` `]` |
| `DELETE FROM users WHERE id=1;` | ALLOW | **ALLOW** | — | ✓ (WHERE-guarded) |
| `echo "safe DROP TABLE in docs"` | ALLOW | **DENY** | `DROP (TABLE…)` | **FP** — documented deliberate tradeoff |
| `git commit -m "docs: … DROP TABLE …"` | ALLOW | **DENY** | `DROP (TABLE…)` | **FP** — same tradeoff |
| `terraform apply` / `destroy` | DENY | **DENY** | `terraform (apply\|destroy)` | ✓ |
| `kubectl delete namespace x` | DENY | **DENY** | rule | ✓ |
| `kubectl apply -f …` / `helm upgrade …` | (scope) | **ALLOW** | — | gap: not gated (normal perm flow); `terraform apply` is — mild inconsistency |
| `helm uninstall` / `aws s3 rb …--force` / `gcloud … delete` | DENY | **DENY** | rules | ✓ |
| `curl … \| sh` / `\| bash` / `\| sudo bash` / `wget … \| sh` | DENY | **DENY** | curl/wget-pipe | ✓ |

## 8. Dependency-operation matrix

Verified against the suite (ASK1–17, AL1–11) and re-run. Policy is **coherent and
correct**: add/remove/upgrade → ASK (jq-built permission JSON); lockfile/manifest
**restore** (`npm ci`, bare `npm/pnpm/yarn/bun install`, `pip install -r`,
`pip install -e .`, `uv sync`, `poetry/bundle/composer install`) → ALLOW. Covers
npm/pnpm/yarn/bun/pip/uv/poetry/cargo/go/gem/bundle/composer. `go get`/`go install`
correctly ASK (mutate go.mod). **No defect** — this matches CLAUDE.md §2 ("install,
upgrade, or remove — propose") and the reasoning is documented inline.

## 9. Protected-path matrix (`protect-files.sh`)

| Path (or form) | Expected | Actual | Note |
|---|---|---|---|
| `.env`, `.env.local`, `my docs/.env.local` | DENY | **DENY** | ✓ |
| `.env.example/.sample/.template/.dist` | ALLOW | **ALLOW** | ✓ templates |
| `.env.example.secret` | DENY | **DENY** | ✓ (`.env.*`) |
| `.git/config` | DENY | **DENY** | ✓ |
| `.github/workflows/ci.yml`, `.claude/settings.json`, `.claude/hooks/x.sh`, `terraform/`, `migrations/`, `k8s/prod/`, lockfiles | ASK | **ASK** | ✓ |
| `config.environment.ts`, `infrastructure/service.ts` | ALLOW | **ALLOW** | ✓ no substring FP |
| `../escape/.env`, `C:\repo\.env` (backslash) | DENY | **DENY** | ✓ basename + normalize |
| **`id_rsa`, `server.pem`, `tls.key`** | DENY | **ALLOW** | **D11** — private-key/cert files ungated |
| **`.netrc`, `.npmrc`, `.pypirc`** | ASK/DENY | **ALLOW** | **D11** — credential files ungated |
| **`.ENV`, `.Env.Local`** | DENY | **ALLOW** | **D12** — case-sensitive check; same file as `.env` on Windows/macOS |
| `.github/actions/example/action.yml` | ASK | **ALLOW** | **D13** — composite actions (CI-executing) not gated |
| `.gitmodules` | ASK | **ALLOW** | **D13** — submodule source file not gated |
| `CLAUDE.md`, `.claude/ENFORCEMENT.md`, `Dockerfile` (root/nested) | ALLOW | **ALLOW** | intentional: edited during setup / governed by skills — documented |

Normalization is honest: backslash→slash + slash-bounded segment matching. It does
**not** resolve `..`/symlinks (a real limitation); `../escape/.env` is still caught
because the *basename* is `.env`, not because the path was resolved. Documented as such.

## 10. Secret-scanner assessment (`scan-secrets.sh`)

Blocking is correct across Write/Edit/NotebookEdit, multi-match, same-pattern
fake-then-real (SS9), fake-word-elsewhere-on-line (SS10), split fixtures,
malformed JSON (fail-open), and the marker-in-value fixture path. Value-scoped
fixture markers (not line-scoped) are correct. **The log is clean of secret
values** (only the regex *name* is persisted — verified: `grep` for the key
substring in `hooks.log` → not found).

**D4 — stderr prefix leak.** `scan-secrets.sh:121` prints `${MATCH:0:8}...`. For
token-shaped secrets this is 8 real characters: `AKIA1234` (a real-shape AWS key),
`ghp_abcd` (4 chars of a GitHub token body). The protocol bar is *no prefix
anywhere, incl. stderr*. The preview adds nothing for Claude — Claude authored the
content and already holds the full value — so it is a pure exposure surface.
Fix: replace with a non-secret message; add a regression asserting no known secret
substring appears in stdout/stderr/logs.

Boundary documented and confirmed accurate: the hook scans **inserted content per
edit**, not the reconstructed final file (a secret split across two edits is
invisible — README already states this, and §7 requires a pre-commit scanner as
the second layer).

## 11. Log-safety assessment

`.claude/logs/hooks.log` is **TSV via raw `printf '%s\t…\n'`** in `lib.sh:53`, with
**no escaping**. Fields include user-controlled data (`$FILE` in protect-files &
check-diff-size).

**D5 — record injection.** A single ASK event on a file path containing a newline
produced **two** log lines, the injected one beginning with an attacker-chosen
timestamp `2099-01-01T00:00:00Z\tBLOCK\tfake-hook…`, indistinguishable from a real
record. Not strict JSONL, not safely-escaped TSV → forgeable. Mitigating context:
the README already frames the log as a *local tuning artifact, not a centralized
audit trail*, and secret **values** are never logged. Fix: sanitize `\t`/`\n`/`\r`/
control chars in `log_event` fields (keeps the documented `awk -F'\t'` queries
working; JSONL would break them). Logs are unbounded (README documents manual
rotation) — acceptable for a local artifact.

## 12. Cross-hook interaction assessment

For one Edit|Write|NotebookEdit, settings.json runs protect-files → scan-secrets →
check-diff-size in order. Observed precedence (Claude Code semantics): any hook
exit 2 **denies** the action; an ASK from protect-files does not suppress a later
DENY from scan-secrets (a protected path that also contains a secret is hard-denied,
not merely asked). check-diff-size only warns/blocks on size. No hook can *upgrade*
a deny to an allow. The override env var is per-hook (`CLAUDE_HOOK_OVERRIDE=<name>`)
or `all`, and every override is logged. This layering is correct and matches the
docs; **no defect** — recorded as a strength.

## 13. Bootstrap assessment (`claude-init.sh`)

Name validation (`../escape`, `a/b`, `.`/`..`, leading `-`, spaces, Unicode),
missing-source rejection, installer-failure atomicity (temp sibling + rename, cwd
preserved), and `.env`/LF inheritance are all correct and regression-covered
(BOOT1–8).

**D6 — machine-local-state leakage.** `claude-init.sh:67` does `cp -r
"$TEMPLATE/.claude"`. Seeding a template `.claude` with local state and
bootstrapping copied **all** of it into the generated project:
`settings.local.json`, `logs/hooks.log`, `worktrees/somebranch/f.txt`,
`CLEANUP_PLAN.md`, `CLEANUP_EXECUTION.md`. The generated `.gitignore` ignores the
first two + cleanup plans, but **`.claude/worktrees/…` is staged** (D7) →
committable into the new project. This is live, not hypothetical: `.claude/logs/`
appears the moment any hook fires in the template, and `.claude/worktrees/` the
moment Claude Code runs a worktree session in the template. Fix: prune the
machine-local denylist after copy (mirroring `seed-repo.sh:20`), + tests.

## 14. Routing metric recomputation

Independently recomputed from committed JSONL — **matches the committed summaries exactly**:

| Run | Cases×runs | recall | precision | conflict | no_load | stability |
|---|---|---|---|---|---|---|
| 1221 baseline | 19×3=57 | 0.902 | 0.939 | 0.053 | 0.039 | 0.895 |
| 1652 (layout-root-mess) | 1×3 | 1.0 | 1.0 | 0.0 | 0.0 | 1.0 |
| 1656 (cleanup-repo-recall) | 1×3 | 1.0 | 1.0 | 0.0 | 0.0 | 1.0 |

Every baseline row maps to a fixture case; 3 runs each; 0 errored; sole conflict =
`layout-root-mess → repository-cleanup` (3/3), exactly as the fixture note claims.
Definitions in `run_eval.py` are sound (precision = good-loads / all-loads over
runs that loaded anything; recall = required-subset over must_load runs; conflict =
any-forbidden over all runs).

**D14 — no current full-suite run.** Fixture defines **20** cases; the baseline
(1221) ran only **19** (omits `cleanup-repo-recall`) and **predates** the current
`repository-cleanup` description (the fix that resolved the sole conflict). Runs
1652/1656 are 1-case spot-checks. So **no single committed artifact reflects the
current descriptions over the full fixture.** Requires a fresh 20×3 run (Phase 5).

**Provenance:** `model` is captured (`claude-sonnet-5`), but **`cc_version` is null**
in every JSONL row — the fixture's `cc_version: 2.1.214` is hand-entered, not
machine-captured (the stream-json `init` event's version field is empty in this CC).

## 15. Routing fixture / dependency conflicts

Fixture is **internally consistent**: 20 unique ids, no `must_load ∩ must_not_load`,
no `allowed_companions ∩ must_not_load`. Spot-checked the named boundaries against
the INDEX dependency graph — all consistent (e.g., `review-dag-deploy` allows
`airflow` as companion because `airflow-review → airflow`; `review-api-breaking`
forbids `api-design` auto-load though `api-review → api-design` as an on-demand
reference — correct distinction). **D15 — `run_eval.py` robustness gaps:** hardcoded
`CLUSTER_KEYS` (no dynamic cluster discovery — a new YAML cluster is silently
ignored); minute-precision output filename (`routing-%Y%m%d-%H%M`) → **same-minute
runs overwrite silently**; no duplicate-id rejection across clusters; **no
metric-threshold / MISS exit** (always exit 0 — a routing regression can't fail a
gate); no scoring-math unit tests.

## 16. Every-skill disposition

All 37 skills reviewed. No skill warrants retire/merge. Dispositions:

- **Keep as-is (33):** the domain skills (docker*, airflow*, python*, database*,
  api*, web-security, testing, verification, kubernetes, observability, etc.) —
  descriptions are specific, bodies self-contained (~5–11 KB), and the measured
  conflict rate is low.
- **Manual-only candidates evaluated (`disable-model-invocation`):**
  repository-cleanup, git-hygiene, release-readiness, verification. The protocol
  warns against making these manual-only *solely* to reduce metrics. Evidence: the
  fixture already tests their negative/positive routing (move-utils-file →
  neither; cleanup-branch-sequence/untrack-node-modules → git-hygiene;
  cleanup-repo-recall → repository-cleanup) and they route **correctly** (recall
  1.0 on their own prompts, and they stay out of one-off moves). **Recommendation:
  do NOT disable model invocation** — recall/workflow benefit outweighs the small
  precision risk, and the v3 description disambiguation already fixed the one real
  overlap. Preserve current behavior.
- **Narrow-description candidate:** none confirmed by measurement; the pre-fix
  overlap (repository-cleanup vs project-layout) is already resolved (1652 run).

**Context sizes:** CLAUDE.md 417 lines / ~8.2k tokens always-loaded; 37 frontmatter
descriptions ~4.9k tokens (always in catalog); SKILL.md bodies ~46k tokens total but
**loaded one-at-a-time on trigger**; 1 reference file (~0.5k). Always-on footprint
≈ 13k tokens — justifiable for a governance template; no mandated reduction (no
*measurable* benefit demonstrated from trimming binding rules).

## 17. Context-size analysis
See §16 final paragraph.

## 18. CI evidence
See §1. Real successful run 29654472614 on the audited commit `2f7ea453`; all steps
green. CI does **not** run: workflow-YAML lint, settings-JSON validation, routing-
result validation, worktree Stop tests, or doc-link checks (all local-only). Actions
are SHA-pinned (`actions/checkout@08c6903…`, `setup-python@ece7cb0…`), runner pinned
(`ubuntu-24.04`), ShellCheck pinned + checksum-verified (`v0.10.0`,
`SHELLCHECK_SHA256`), `permissions: contents: read` (least privilege), concurrency
+ cancel-in-progress, 10-minute timeout. No secrets used; PR code runs only lint/
test (no privileged token). **CI hygiene is a clear strength.**

## 19. Documentation drift

- **D16 — HOW-TO ⟷ claude-init contradiction.** HOW-TO "Option B" (lines 106–107)
  and the "Required template structure" tree (118–139) copy/show only `CLAUDE.md` +
  `.claude/`, **omitting `.gitignore` and `.gitattributes`**. But `claude-init.sh:41–42`
  *requires* both and hard-fails ("Template is incomplete — missing: .gitignore
  .gitattributes"). Following HOW-TO exactly, then bootstrapping, fails. Fix: add both
  to Option B + the tree.
- **D17 — stale `MultiEdit` matcher in copyable recipes.** `ENFORCEMENT.md:114,133`
  show `"matcher": "Edit|Write|MultiEdit"` (tool removed from current Claude Code;
  shipped `settings.json` correctly uses `NotebookEdit`, asserted by test SET1). A
  reader copies a dead matcher. Fix: update to `Edit|Write|NotebookEdit`.
  (Recipe 3's `jq … | xargs -r npx prettier` is also `-0`-unsafe on paths with
  spaces — minor, in a labeled-illustrative recipe.)
- Non-issues (keep): `check-diff-size.sh:55` and `scan-secrets.sh:16` reference
  `MultiEdit` deliberately for backward-compat / as a comment; CHANGELOG & prior
  reports mention it historically. HOW-TO hook count ("5 enforcement hooks", "7 .sh
  files") is accurate.

## 20. Public-template readiness

- **LICENSE missing** — **owner action** (protocol forbids me choosing one).
- **CONTRIBUTING.md, SECURITY.md, CODE_OF_CONDUCT.md missing** — recommended for a
  public template; reporting rather than fabricating.
- Tags `v1.0`, `v2.0` exist (version history present). Protocol forbids me creating/
  pushing a new tag.
- `.gitattributes` enforces `*.sh eol=lf` (the key Windows-clone failure mode) — good.
- GitHub "template repository" flag: not verifiable from the local clone — owner to confirm.

## 21. Confirmed defects (P-ranked)

| ID | Sev | Area | One-line |
|---|---|---|---|
| D1 | **P1** | verify-done | Stop hook disabled in linked worktrees (`.git` file) — affects every CC worktree session |
| D6 | **P1** | claude-init | Machine-local `.claude` state (settings.local/logs/worktrees/cleanup) leaks into generated projects |
| D4 | P2 | scan-secrets | 8-char secret prefix printed to stderr |
| D5 | P2 | lib.sh log | TSV log record-injection via newline in file path |
| D7 | P2 | .gitignore | `.claude/worktrees/` not ignored → stageable |
| D8 | P2 | block-destructive | `DELETE FROM dbo.Users;` / bracketed forms bypass (no WHERE) |
| D9 | P2 | block-destructive | `/bin/rm`, `\rm`, `rm -rf -- /` bypass |
| D2 | P2 | verify-done | Untracked code file in a new dir not counted |
| D11 | P2 | protect-files | `id_rsa`/`*.pem`/`*.key`/`.netrc`/`.npmrc`/`.pypirc` ungated |
| D12 | P2 | protect-files | `.ENV` case bypass on Windows/macOS |
| D14 | P2 | routing | No current full-suite run (baseline predates current descriptions) |
| D16 | P2 | docs | HOW-TO omits `.gitignore`/`.gitattributes` that claude-init requires |
| D3 | P3 | verify-done | "changed in this session" wording inaccurate |
| D10 | P3 | block-destructive | `git push origin +main` (force via refspec) not denied |
| D13 | P3 | protect-files | `.github/actions/**/action.yml`, `.gitmodules` ungated |
| D15 | P3 | routing | run_eval.py: no dynamic clusters / dup-id reject / overwrite guard / threshold exit; no scoring tests |
| D17 | P3 | docs | ENFORCEMENT.md stale `MultiEdit` matcher in copyable recipes |

## 22. Unconfirmed concerns / deliberate tradeoffs (not defects)

- **SQL false positives** (`echo "…DROP TABLE…"`, commit messages) — deliberate,
  documented ("false positives better than a real disaster"); narrowing risks FNs
  (`psql -c "$(echo drop table…)"`). Lean: keep, document; revisit only on strong
  external evidence.
- **`DROP VIEW/PROC/INDEX`, `kubectl apply`, `helm upgrade`, plain `git push`
  ungated** — scope choices routed through CC's normal permission flow; not silent
  execution. Document, don't necessarily gate.
- **CLAUDE.md always-on ~8.2k tokens** — heavy but binding; no measured trim benefit.
- **cc_version null in results** — provenance-capture limitation of the CC
  stream-json, not a repo bug per se; worth auto-capturing if available.

## 23. Strengths to preserve

- ASK decisions built with `jq --arg` (hostile-safe; PFH1–6 pass with quotes/tabs/
  newlines/backslash/Unicode/300-char basenames) — **never** switch to printf interpolation.
- Log records secret *pattern names*, never values.
- Counters use POSIX `$((X+1))`; `grep -c … || true`; `json_get` + `require_jq`
  fail **open** on malformed input.
- claude-init atomicity (temp sibling + rename, cwd preserved, name validation).
- `seed-repo.sh` strips worktrees/logs before seeding.
- CI: SHA-pinned actions, checksum-pinned ShellCheck, least-privilege, concurrency,
  timeout.
- 107/107 hook regression cases, catalog gate, installer functional tests.

## 24. Recommendations (P0–P3)

- **P0:** none (no data-loss-on-run or secret-value-persist defect found).
- **P1:** D1 (worktree Stop detection via `git rev-parse`), D6 (bootstrap local-state
  prune) + D7 (gitignore `.claude/worktrees/`).
- **P2:** D4 (drop secret preview + no-output regression), D5 (escape log fields),
  D8/D9 (SQL schema-qualified + rm prefix/`--`), D2 (`--untracked-files=all`), D11
  (key/cert/cred path gating), D12 (case-fold `.env`), D14 (fresh full routing run),
  D16 (HOW-TO required files).
- **P3:** D3 (wording), D10 (force-refspec), D13 (action.yml/.gitmodules), D15
  (run_eval robustness + scoring tests), D17 (ENFORCEMENT MultiEdit).
- **Owner actions:** choose a LICENSE; add CONTRIBUTING/SECURITY; confirm GitHub
  template-repository flag; decide any new release tag.

*End of Phase 1. This report is committed before opening `external-review-v4.md`.*
