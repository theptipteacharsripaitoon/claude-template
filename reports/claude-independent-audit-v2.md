# Independent Audit v2 — claude-template

Second-cycle independent audit. Produced **before** opening `external-review-v2.md`.
Nothing from the first cycle (reports, scores, tests, fixes) was assumed correct.

## Phase 0 — Audited state

| Item | Value |
|---|---|
| Repository | https://github.com/theptipteacharsripaitoon/claude-template |
| Audited ref | `origin/main` = `3127a65ae33a44058eb581cb81d955f192d8ec5e` (merge of PR #5) |
| Working branch | `claude/template-second-audit-71e140` @ `6ccb791d4b2bd9aa4c89bf08a166b5d23fdcdc75` |
| Tree identity | `git diff origin/main HEAD` is empty — the worktree tree is byte-identical to pushed `main` |
| Date | 2026-07-18 |
| Claude Code | 2.1.214 |
| OS / shells | Windows 11 Home 10.0.26200; Git Bash 5.2.15 (msys), PowerShell 5.1 |
| Tools present | jq 1.6, Python 3.10.9 (PyYAML 6.0.1), Docker 29.5.3, git 2.x, curl |
| Tools absent | `gh`, `shellcheck`, `shfmt` (ShellCheck/shfmt run via pinned Docker images; GitHub via REST API) |

### GitHub Actions status at audit start: RED — but not a code failure

All three `template-tests` runs (run 29634524233 on `main`@3127a65; runs 29634363072 and
29634328988 on `feat/template-audit`@6ccb791) concluded `failure` with **zero steps executed**
(~2 s duration). The check-run annotation on every run reads:

> `The job was not started because your account is locked due to a billing issue.`

Evidence: `GET /repos/.../actions/runs/29634524233/jobs` → `steps: []`;
`GET /repos/.../check-runs/88054381032/annotations` → the message above (same for jobs
88053923142 and 88053825693). Log download returns 403 without admin rights.

**Implication:** the workflow has never executed on GitHub. Any prior claim that CI validates
this repo is unsupported. Local execution of the workflow's steps at `6ccb791`:

| CI step | Local result |
|---|---|
| `bash tests/hooks/run-tests.sh` | PASS — `RESULT: pass=39 fail=0` |
| `bash .claude/hooks/install.sh` | PASS — exit 0, all functional tests green |
| `shellcheck .claude/hooks/*.sh tests/hooks/run-tests.sh` | not runnable natively on this machine; evaluated via Docker in §CI below |
| `python tests/skills/check_catalog.py` | PASS — "37 skills checked / ALL CHECKS PASS" |

**Unblocking CI is an owner action (resolve the GitHub billing lock). No repo change can turn CI green.**

---

# Phase 1 — Independent audit

Produced without opening `external-review-v2.md`. Every item labelled **CONFIRMED**
has an executable reproduction in this report. Items labelled **concern** are
inspection-only and not yet reproduced.

## Overall score before changes: **7.2 / 10**

| Category (weight) | Score | Basis |
|---|---:|---|
| Technical correctness (15%) | 7.5 | Hooks function; real secret-scanner bypasses; verify-done can't distinguish "no checks ran". |
| Skill trigger quality (15%) | 7.5 | Descriptions well-scoped; measured docker/airflow review over-load; one recall miss. |
| Hook correctness (15%) | 6.5 | Two confirmed scan-secrets bypasses; protect-files substring false positive; hard-deny ignores approval. |
| Conflict avoidance (10%) | 7.0 | Measured docker+airflow double-load; DoD-vs-risk policy contradiction. |
| Safety & permissions (10%) | 7.5 | block-destructive strong; protect-files can't honor in-chat approval; fail-open on missing jq. |
| Testing & evaluation (15%) | 7.0 | Genuine 39-case suite passes, but misses the confirmed bypasses; trigger fixtures never executed. |
| Context efficiency (5%) | 8.0 | Skills reasonably sized; good INDEX. |
| Team usability (5%) | 8.0 | Strong HOW-TO / README / hooks guide. |
| Maintainability (5%) | 7.5 | Catalog gate + table-driven tests; doc drift; CRLF-in-worktree confusion. |
| Public-template readiness (5%) | 6.0 | CI red (billing + latent ShellCheck); bootstrap stages `.env`; no LICENSE. |

Weighted total ≈ **7.2**.

## 1. Hook-by-hook assessment

### `lib.sh` (shared)
Sound design: derives hook name, fail-open `json_get`/`require_jq` on malformed input,
override mechanism is logged, secret values kept out of the on-disk log. **No defect.**

### `block-destructive.sh` — PreToolUse: Bash
Hard-denies destructive patterns (exit 2); dependency installs emit a structured
`permissionDecision:"ask"` (verified). Malformed JSON fails open (BD11). **No functional defect.**
Lint: **SC2016** at line 24 (`'…\$HOME'`) — intentional literal-`$` regex, but bare
`shellcheck` reports it and returns non-zero (see §CI). Header comment says matcher
`Bash` (correct).

### `protect-files.sh` — PreToolUse: Edit|Write|NotebookEdit
Blocks protected paths via **uncontrolled substring** match against the full path.
- **CONFIRMED false positive:** `/repo/src/config.environment.ts` → **blocked** (exit 2)
  because `config.environment` contains the substring `.env`. A legitimate source file
  is uneditable. Repro: `fp '/repo/src/config.environment.ts' | protect-files.sh` → exit 2.
- **Rejected external-style claim:** `.env.example.secret` is **correctly blocked** (exit 2)
  and the allowlist uses suffix (`*X`) not substring, so it is not an allowlist bypass.
- **Approval-vs-enforcement gap (CONFIRMED by design):** every match is a hard deny (exit 2).
  There is no structured `ask`, so a user's in-chat "yes, edit the workflow" cannot unblock —
  only `CLAUDE_HOOK_OVERRIDE` (needs a session restart) or manual editing. `block-destructive`
  already demonstrates the `ask` path; protect-files does not use it for the approvable set
  (CI/infra/migrations/lockfiles), which `CLAUDE.md` §2 treats as "confirm", not "never".
- Header comment stale: says matcher `Edit|Write|MultiEdit`; actual is `Edit|Write|NotebookEdit`.
- Redundant patterns: `.env` already subsumes `.env.local`/`.env.production`/`.env.staging`.

### `scan-secrets.sh` — PreToolUse: Edit|Write|NotebookEdit
Two **CONFIRMED bypasses** (both reproduced, exit 0 = not blocked):
- **Fake-then-real, same pattern:** line 1 `k1="AKIA…MNOP"  # EXAMPLE`, line 2 `k2="AKIA1B2C…"` (real) →
  **exit 0**. Root cause: the scanner takes only `grep … | head -1` for both the match and
  the "is-fake" line, so once the first matching line is fake it `continue`s and never
  inspects later matches of the same pattern.
- **Real secret with a fake word elsewhere on its line:** `api_key="AKIA1B2C…"  # see config.example` →
  **exit 0**. Root cause: the fake-marker test is line-scoped and any marker anywhere on the
  line suppresses the real match.
- Control: a lone real key with no marker → **exit 2** (correct).
These matter because the hook is a security control; the existing suite (SS1–SS8) does not
cover either case. Malformed JSON fails open (SS8, correct). Header stale (`MultiEdit`).

### `check-diff-size.sh` — PreToolUse: Edit|Write|NotebookEdit
Warn ≥300, block ≥1000 lines. NotebookEdit covered (NB3). Large deletion (big `old_string`,
tiny `new_string`) → blocked via `max(old,new)` — defensible. **No defect;** header stale (`MultiEdit`).

### `verify-done.sh` — Stop
Reminder by default; blocking under `CLAUDE_VERIFY_BLOCK=1`. Re-entry guard honored (VD4).
- **CONFIRMED "no checks ran ≠ checks passed":** in blocking mode, a repo with a changed
  `.py` but no `pyproject.toml`/`package.json`/etc. prints **"✓ All verification checks passed."**
  though **zero** checks executed. Repro in this report. It cannot distinguish passed /
  failed / none-discovered / unavailable.
- **Polyglot gap (inspection):** `if [[ -f package.json ]] … elif [[ -f pyproject.toml ]]` runs
  only the first ecosystem; a Node+Python repo silently skips Python checks.
- **Attribution (inspection):** `git status --porcelain` counts *all* dirty files, not just
  this session's — pre-existing user edits are attributed to Claude. Low severity (reminder only).
- Both blocking-mode issues are off by default.

### `install.sh`
Robust: counter survives `set -e` (INST1); functional block/allow/ask assertions;
override assertion. **SC2155** at line 8 (`export X="$(…)"`) — real ShellCheck finding (see §CI).

### Cross-cutting
- **Fail-open on missing `jq`:** all four PreToolUse hooks `exit 0` when jq is absent → no
  enforcement at all. Intentional ("fail open is safer") and documented, but worth noting for a
  security control.
- **Structured decisions:** only block-destructive emits `permissionDecision`; the file hooks
  rely on exit 2. Consistent with current Claude Code hook semantics.

## 2. Skill assessment (38 skills)

Descriptions are generally high quality, with explicit "Do NOT use for…" boundaries and
authoring/review split (airflow/airflow-review, api-design/api-review, database-*/sql-layout, etc.).
Catalog gate (`check_catalog.py`) passes. Key findings:

- **docker description over-claims review (CONFIRMED by routing).** `docker`'s description says
  "creating, modifying, building, **or reviewing** Dockerfile … or any container-related task" and
  contains **no** `docker-review` disclaimer (grep count 0), while every sibling pair disclaims the
  other side. Measured: **"Review the Dockerfile before we merge" loaded BOTH `docker-review` and
  `docker`** — a routing conflict. `airflow` already carries "Do NOT use for reviewing a DAG change
  (airflow-review)"; docker should mirror it.
- **docker Done-criteria contradiction (CONFIRMED by inspection).** Body line 13: "Single-stage is
  acceptable for scratch/static-binary or asset-only images — state the justification." Done line 80:
  "[ ] Dockerfile uses multi-stage build." (unconditional). The Done gate contradicts the stated
  exception.
- **database-migrations reversibility tension (minor).** Body: "Every migration is reversible"
  (absolute); Done: "reversible (`up`+`down`), **or** `down` unsafety is documented" (conditional).
  The Done gate already has the escape hatch; the body overstates. Wording alignment only.
- **kubernetes HPA — rejected as over-broad.** HPA appears in the body ("consider `behavior` block")
  but is **not** a Done checkbox; the "requires HPA too broadly" concern is not supported.
  `readinessProbe` "must reflect dependency readiness" is a defensible-but-debatable default (subjective).
- **Workflow skills route well on explicit intent (measured) → keep auto-invoked.**
  `repository-cleanup` loaded only on "Clean up this repo and get it ready for team handover";
  `release-readiness` only on "Get this repo ready to release". Neither over-fired on unrelated
  prompts in the sample. No evidence supports blanket `disable-model-invocation: true` for the four
  workflow skills. `repository-cleanup`'s description already says "invoke deliberately".

## 3. Policy applicability matrix (CLAUDE.md)

**Contradiction (CONFIRMED):** §16 lists six items as **"Always required"** — compiles/runs without
warnings, all existing tests pass, **new tests cover the change**, linter+formatter+type-checker pass,
**Conventional Commits message**, and executing the changed code path. §13 (LOW = "minimal
verification") and §14 ("scale effort to risk … a trivial typo fix does not require an integration
test") describe *proportional* behavior. For non-code tasks the §16 "always" list is impossible or
irrelevant, and it mandates a commit even when the user requested none.

| Task type | tests apply | new tests | typecheck | execute code path | commit required | §16 "always" holds? |
|---|---|---|---|---|---|---|
| Behavioral code change | yes | yes | if TS/typed | yes | if requested | mostly |
| Bug fix | yes (repro) | yes | if typed | yes | if requested | mostly |
| Refactor | yes (unchanged) | no new | if typed | yes | if requested | partial |
| Config change | maybe | maybe | no | maybe | if requested | partial |
| Infra / IaC | plan/dry-run | no | no | dry-run | if requested | partial |
| Migration | up/down/up | migration test | no | on test DB | if requested | partial |
| Dependency change | smoke | no | maybe | smoke | if requested | partial |
| Documentation-only | no | no | no | no | if requested | **no** |
| Review-only | no | no | no | no | **no** | **no** |
| Architecture analysis | no | no | no | no | no | **no** |
| Investigation-only | no | no | no | no | no | **no** |
| Git operation | n/a | no | no | n/a | n/a | **no** |
| Release preparation | run suite | no | yes | yes | tag | partial |
| Repository cleanup | per-commit verify | no | no | verify | yes (moves) | partial |

Six of fourteen task types cannot satisfy the "Always required" list. §16 needs a task-type
applicability gate that preserves strictness for behavioral/high-risk code (already the spirit of §13/§14).

## 4. Bootstrap assessment (`claude-init.sh`)

**CONFIRMED defect with reproduction.** `claude-init.sh` copies `CLAUDE.md` and `.claude/` only
(lines 34–35). A simulated generated project therefore has **no `.gitignore` and no `.gitattributes`**.
Consequences reproduced:
- `git init && git add -A` in the generated project **stages `.env`** (`A .env`) — a secret-leak
  vector. The template's own `.gitignore` ignores `.env`, `.claude/settings.local.json`, and
  `.claude/logs/*.log` (verified via `git check-ignore`), but none of that protection is inherited.
- No `.gitattributes` ⇒ on Windows the `*.sh` hooks can be checked out **CRLF**, which breaks
  `bash`/ShellCheck (the exact SC1017 failure seen locally on this worktree's own stale checkout).
- `.claude/logs/*.log` is covered by the nested `.claude/logs/.gitignore` (which *is* copied);
  `settings.local.json` was not staged on this machine only because of a global excludes file —
  not something a generated project can rely on.
Fix: copy `.gitignore` and `.gitattributes` in `claude-init.sh`. Do **not** copy `reports/` or
`external-review*.md` into generated projects.

## 5. CI assessment

**Two independent reasons CI is not green:**
1. **Billing lock (owner action).** All three runs failed with *zero* steps —
   "account is locked due to a billing issue". The workflow has never executed on GitHub.
2. **Latent ShellCheck failure (fixable in repo).** On the committed **LF** blobs (Docker
   `koalaman/shellcheck:v0.10.0`), bare `shellcheck` exits **1**:
   - `install.sh:8` **SC2155** (warning) — `export X="$(…)"` masks the return value. Real; fix by
     splitting declare/assign.
   - `block-destructive.sh:24` **SC2016** (info) — intentional literal-`$` in a single-quoted regex;
     bare shellcheck still returns non-zero. Fix with a scoped `# shellcheck disable=SC2016` +
     justification. `--severity=warning` does **not** clear it (SC2155 remains).
   So even after billing is resolved, the ShellCheck step would go red on current content.
   (The local worktree's CRLF SC1017 errors are a Windows checkout artifact — committed blobs are
   LF per `.gitattributes`; not a repo defect.)

**Workflow vs its own `ci-review` skill (CONFIRMED violations):**
- No explicit `permissions:` block (skill item 2 requires `contents: read` minimum).
- No `timeout-minutes` on the job (skill item 7).
- `pip install --quiet pyyaml` is **unpinned** (skill item 6 — determinism/pinned tool versions).
- Compliant: `actions/checkout` SHA-pinned with version comment (skill item 1).
- The three test steps do block the merge (skill item 5 — gates are real).

**shfmt:** no shfmt gate exists today. `shfmt -i 2 -ci` reports drift, but it is only comment
re-alignment that would *remove* the current intentional column alignment — adding an enforcing
shfmt gate would be a large no-behavior diff that hurts readability. Optional at best; not a defect.

## 6. Measured routing results

Live `claude -p … --output-format stream-json --permission-mode acceptEdits --max-turns 3`,
model **claude-sonnet-5**, Claude Code **2.1.214**, 2026-07-18. Because the *template* repo has no
domain artifacts, the model correctly detects "skills template" and explores instead of routing —
so measurement was run in a **scratch project** seeded with representative files (`Dockerfile`,
`db/procs/*.sql`, `dags/*.py`, `migrations/*.sql`, `frontend/components/*.tsx`) plus the skills.

| Prompt | Skills loaded | Verdict |
|---|---|---|
| Where should this stored procedure file live? | `sql-layout` | ✓ |
| Review this stored procedure for deadlocks | `database-review` | ✓ |
| Organize this project - the root is a mess | *(none)* | recall miss / uncertain (scratch root not truly cluttered) |
| Review the Dockerfile before we merge | `docker-review`, **`docker`** | ✗ conflict (docker over-load) |
| Clean up this repo and get it ready for team handover | `repository-cleanup` | ✓ |
| Review this DAG before we deploy it | `airflow-review`, **`airflow`** | minor over-load (airflow already disclaims review) |
| Structure this Python project so it is importable | `python-layout` | ✓ |
| Get this repo ready to release | `release-readiness` | ✓ |
| Organize the dags folder by team | `airflow-layout` | ✓ |

Measured on this 9-case sample: correct primary skill in **7/9**; **2** conflicts (docker cleanly
fixable via description; airflow already disclaims, model imperfection); **1** recall miss. I do
**not** claim a full 19-case precision/recall — the empty-template confound makes the
domain-artifact-dependent fixtures unreliable without per-domain seed projects, and only a sample
was executed. `trigger-cases.yaml`'s own header already states it is not auto-executable; its
`evaluated_runs` remain empty.

## 7. Confirmed defects (with reproduction) — priority-ranked

- **P1 — scan-secrets fake-then-real bypass.** Real second key of a pattern escapes when the first
  match is fake. Repro above (exit 0).
- **P1 — scan-secrets nearby-marker bypass.** Real key on a line mentioning "example" escapes. Repro (exit 0).
- **P1 — CI ShellCheck latent failure.** SC2155 + SC2016 make the gate exit 1 on committed LF content.
- **P1 — bootstrap stages `.env`.** `claude-init.sh` omits `.gitignore`/`.gitattributes`; `git add -A`
  stages `.env`. Repro above.
- **P2 — protect-files substring false positive.** `config.environment.ts` blocked. Repro (exit 2).
- **P2 — verify-done "no checks ran" reported as passed** (blocking mode). Repro above.
- **P2 — docker description review over-load.** Measured double-load with docker-review.
- **P2 — DoD §16 "Always required" contradicts §13/§14 and non-code tasks.**
- **P2 — workflow missing `permissions:`/`timeout-minutes`/pinned pyyaml** (violates own ci-review skill).
- **P3 — doc drift:** hooks README `claude code` (×2, should be `claude`); README table lists package
  installs under "Hard block" though they `ask`; NotebookEdit absent from hooks README; three hook
  headers say `MultiEdit`.
- **P3 — docker Done multi-stage unconditional** vs stated single-stage exception.

## 8. Unconfirmed concerns (inspection only)

- verify-done polyglot `if/elif` runs one ecosystem (blocking mode, off by default).
- verify-done dirty-tree attribution counts pre-existing edits (reminder only).
- Fail-open on missing `jq` disables all enforcement (intentional).
- kubernetes readiness "must reflect dependency readiness" — debatable default, not a defect.
- database-migrations body "every migration is reversible" overstates vs its own conditional Done.

## 9. Strengths to preserve

- Genuine, table-driven **39-case** hook suite that constructs secret fixtures at runtime (keeps the
  repo scanner-clean) and passes.
- Override mechanism is **logged and auditable**; secret values never written to disk.
- Secret values kept out of persistent logs (stderr-only preview).
- Strong skill boundaries and a `check_catalog.py` consistency gate.
- SHA-pinned checkout action; `.gitattributes eol=lf` keeps Linux CI clean.
- Thorough operator docs (hooks README, ENFORCEMENT.md, HOW-TO.md).

## 10. Recommendations

**P0:** none purely in-repo (billing lock is owner-only).
**P1:** fix scan-secrets (scan all matches; line-local marker logic that doesn't suppress a real
sibling); fix ShellCheck SC2155 + scoped SC2016 disable; make `claude-init.sh` copy
`.gitignore`+`.gitattributes`.
**P2:** protect-files → component/basename/glob matching for extensionless patterns + a structured
`ask` path for the approvable set; verify-done → distinguish passed/failed/none/unavailable;
docker description → drop "reviewing", add docker-review disclaimer; make §16 DoD task-type
conditional; add workflow `permissions:`+`timeout-minutes`+pin pyyaml.
**P3:** doc-drift fixes; docker Done multi-stage conditional; migrations reversibility wording.

*(Adjudication against `external-review-v2.md` follows in `review-adjudication-v2.md`, produced after
this report is committed.)*
