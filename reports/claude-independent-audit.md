# Independent Audit — claude-template (Phase 1)

Date: 2026-07-17 · Tree: `feat/skill-library-phase-d` @ `ecf7fd6` (audited working state; audit branch `feat/template-audit`)
Installed Claude Code: **2.1.212** · Method: three independent audit tracks (skills, docs/packaging/install, official-docs compatibility) plus an executed 31-case hook test suite.
`external-review.md` was **not opened, searched, or summarized** before this report was completed — the commit ordering in git history is the proof.

## Overall score: 6.2 / 10

| Category | Weight | Score | Basis |
|---|---|---|---|
| Technical correctness | 15% | 7 | Skill content sound; 3 executable hook defects; 1 confirmed doc error (`claude code`) |
| Skill trigger quality | 15% | 7 | Disciplined template, all under 1,536-char cap; 4 trigger-scope defects (D1, D2, D4, D5) |
| Hook correctness | 15% | 6 | Core blocking verified (28/31 hypotheses); Stop hook errors on the common path; malformed-JSON exit 4; NotebookEdit unmatched |
| Conflict avoidance | 10% | 8 | Exemplary canonical-ownership discipline; one unmarked triple duplicate (readiness rule); DB-trio engine incoherence |
| Safety & permissions | 10% | 7 | Override+logging design is strong; no shared `permissions` block; measured FNs (`pip install -r`); credential hygiene incident on audit machine |
| Testing & evaluation | 15% | 3 | Good tests exist but only inside `install.sh` (manual, latent counter bug); zero CI; no skill-trigger eval set shipped |
| Context efficiency | 5% | 9 | 37 descriptions ≈ 3.7–4.8k standing tokens, tight and uniform; bodies small; progressive disclosure honored |
| Team usability | 5% | 6 | Good ergonomics; no skill-disable path; snapshot-copy drift unsolved; no shared allowlist |
| Maintainability | 5% | 6 | Clean `lib.sh`; hand-maintained 3-place catalog with no drift check; quarterly audit has no tooling |
| Public-template readiness | 5% | 3 | No LICENSE, no root README/.gitignore/.gitattributes; `main` + tags still ship the 8-skill era |

Weighted total: **6.15 → 6.2/10**.

## Cross-cutting P0s (found during audit; act regardless of template scope)

- **P0-1 · Credential hygiene.** The *untracked* `.claude/settings.local.json` on the audit machine contains a plaintext database credential (values withheld per policy). It is protected only by this machine's *global* gitignore — protection that does not travel with the repo, and the template ships no root `.gitignore`. Recommendation: rotate the credential; ship a root `.gitignore` covering `.claude/settings.local.json`, `.claude/logs/`, `.env*`.
- **P0-2 · No LICENSE.** Default "all rights reserved" makes a template built for cloning legally unusable in public. Selecting a license is the owner's decision; shipping without one blocks publication.

## Hook-by-hook assessment (evidence: executed test suite, 31 cases)

Test harness: scratchpad `hooktests.sh` (to be shipped into `tests/` in Phase 4). All hooks pass `bash -n`. jq present on audit machine; `require_jq` fails OPEN by design (correct choice for guardrails).

| Hook | Verified working | Confirmed defects | Measured FP/FN profile |
|---|---|---|---|
| block-destructive | Blocks `git push --force`, `rm -rf /tmp/x`, `curl\|sh`, `npm install <pkg>`; allows `git status`, targeted `rm -rf build/`; override works (BD1–BD10) | Malformed JSON → **exit 4** (BD11) — neither clean-allow (0) nor block (2); surfaces as hook error noise | FP: blocks `git commit -m "…DROP TABLE…"` (BD3) and quoted `curl\|sh` mentions (BD8) — regex matches inside string literals. FN: `DELETE FROM t` without `;` passes (BD4); `pip install -r reqs.txt` passes despite §2 intent (BD5). FPs consistent with the hook's stated conservative philosophy; FNs are documented limitations |
| protect-files | Blocks `.env`, lockfiles, `migrations/`, spaced paths; allows `.env.example`, source files, Unicode paths (PF1–PF8) | Malformed JSON → exit 4 (PF9) | FP: `.env` **substring** match blocks `src/config.environments.ts` (PF3) — real-world false positive on legitimate filenames |
| scan-secrets | Blocks AWS-key shape, GH token shape, PEM header, secret-shaped assignments, multiple secrets in one write, Edit `new_string` field; allows fake-marker fixtures and normal code (SS1–SS7) | Malformed JSON → exit 4 (SS8) | Live evidence: the user-level copy of this hook blocked this audit's own first test-file Write (exit-2 + stderr feedback confirmed working under v2.1.212) |
| check-diff-size | Blocks ≥1000-line writes; warns-without-block in 300–999 band; allows small writes (CD1–CD3) | none found | — |
| verify-done (Stop) | Dirty-tree reminder works (VD1: exit 0 + DoD reminder); no-git exits 0 (VD3) | **P1: exits 1 on every CLEAN stop** (VD2) — `grep \| wc -l` fails under `lib.sh`'s `pipefail` when zero code files changed; the *common case* takes the error path. **P2: no `stop_hook_active` re-entry guard** (documented Stop-hook input field) — infinite-loop risk in opt-in blocking mode only | — |
| install.sh (test harness) | 11 embedded functional tests, both block- and allow-direction — genuinely good | **P1: `((FAIL++)) ` under `set -euo pipefail` kills the runner on the FIRST failing test** instead of counting (isolated repro executed; fix pattern `FAIL=$((FAIL+1))` verified) | Tests run only when a human runs install.sh — no CI |
| lib.sh | Auto-named hooks, centralized audit log, logged override mechanism | `set -euo pipefail` exported into sourcing hooks is the root cause of the malformed-JSON exit-4 and VD2 defects | — |

## Compatibility with installed Claude Code (2.1.212)

Validated against official docs (hooks-guide, hooks, tools-reference, skills):
- Hooks settings schema: **current and valid**. `$CLAUDE_PROJECT_DIR`: supported. Exit-2 + stderr blocking: works (live-observed).
- **`MultiEdit` no longer exists** → matcher entry is dead (harmless). **`NotebookEdit` exists and is NOT matched** → notebook edits bypass protect-files/scan-secrets/check-diff-size (confirmed gap).
- JSON `hookSpecificOutput.permissionDecision` is now the preferred PreToolUse control; exit codes remain supported (modernization opportunity, not a defect).
- Skills: project-skill auto-discovery and description-based progressive disclosure are documented behavior. All 37 descriptions within the 1,536-char cap (max: security-review, 614). Spec offers `disable-model-invocation` for manual-only skills — relevant to D2/repository-cleanup below.
- Windows: Git Bash is the documented default hook shell when present; hooks run on this machine. Fresh-clone risk is line endings (see packaging).

## Skill-by-skill assessment (37)

Verdicts: **A** keep-automatic · **A\*** keep-automatic with noted tightening · **D** needs-description-fix · **S** needs-scope-fix. Precision = would fire when it shouldn't; recall = would miss natural phrasing.

| Skill | Lines | Precision / recall notes | Verdict |
|---|---|---|---|
| agent-design | 45 | recall: misses "chatbot", "RAG", "tool use" | A |
| airflow | 144 | claims "reviewing" + generic "ETL job/data pipeline" beyond body (D4) | D |
| airflow-layout | 44 | clean | A |
| airflow-review | 44 | clean | A |
| api-design | 175 | bare "deprecate" slightly broad; body >150 (pre-dates cap) | A |
| api-review | 44 | clean | A |
| ci-review | 46 | clean (longest description, 86 words) | A |
| config-management | 45 | "add an environment variable" brushes §7/documentation territory | A |
| database-migrations | 143 | generic triggers, **Postgres-only body** (discloses it) | D |
| database-review | 66 | generic "is this query safe" triggers, **T-SQL-only body** (D1) | D |
| dependency-review | 50 | clean | A |
| design-system | 44 | recall: misses "theme", "storybook" | A |
| docker | 87 | clean | A |
| docker-review | 43 | clean | A |
| documentation | 61 | clean | A |
| etl-review | 48 | "data is missing rows" may fire mid-debug — acceptable | A |
| fastapi-review | 51 | clean | A |
| frontend-layout | 42 | React-flavored examples; Vue/Svelte recall gap | A |
| git-hygiene | 63 | **"move these files"/"rename this module" fire on everyday requests and force branch + clean-tree + commit-sequence ceremony (D2)** | S |
| kubernetes | 128 | clean | A |
| llm-evaluation | 48 | clean | A |
| observability | 161 | "log this" broad; body >150 (pre-dates cap) | A |
| project-layout | 61 | co-fires with cleanup/git-hygiene on "organize" — complementary | A |
| prompt-engineering | 48 | recall: misses "system message" | A |
| python-layout | 44 | clean | A |
| python-performance | 50 | clean | A |
| python-refactor | 49 | "clean up this module" forces characterization-tests-first (D5) | A\* |
| python-review | 57 | clean | A |
| release-readiness | 45 | deliberate phrases; safe | A |
| repository-cleanup | 125 | "declutter"/"organize the project" load a heavyweight orchestrator; mitigated by read-only Phase-1 gates | A\* |
| security-review | 46 | clean | A |
| sql-layout | 45 | T-SQL-flavored body under generic name (part of D1) | D |
| ssis-review | 59 | clean; engine-specificity is declared in the name | A |
| testing | 171 | broad by design; body >150 (pre-dates cap) | A |
| ui-review | 43 | clean | A |
| verification | 65 | clean | A |
| web-security | 195 | "external API call"/"rate limit" fire on non-security work; body >150 (pre-dates cap) | A |

Context cost measured: 2,599 description words ≈ 3.7k tokens standing load (mean ~70 words/description, max 86); consistent with the README's ~100-token/skill claim. No wasteful outliers.
Frontmatter: 37/37 names match folders; single-line plain scalars; zero colon-space hazards. Links: **229/229 relative links resolve**, including `ci-review → ../../ENFORCEMENT.md`.

## Confirmed defects (all evidence-backed)

Hooks/infra:
- **H1 (P1)** verify-done exits 1 on every clean stop (VD2; pipefail + empty grep).
- **H2 (P1)** NotebookEdit not covered by file-hook matcher; MultiEdit entry stale (docs-verified).
- **H3 (P1)** install.sh failure counter dies under `set -e` on first failure (isolated repro).
- **H4 (P2)** All three jq hooks exit 4 on malformed JSON instead of failing open cleanly.
- **H5 (P2)** verify-done lacks `stop_hook_active` re-entry guard (blocking mode only).

Skills:
- **D1 (P0-routing)** Engine incoherence in the DB trio: database-review + sql-layout are SQL-Server/T-SQL-only, database-migrations is Postgres-only — all under generic names; a Postgres shop gets T-SQL review advice and vice versa.
- **D2 (P0-routing)** git-hygiene over-fires: everyday move/rename triggers force the full restructuring ceremony.
- **D3 (P1)** Readiness/health-check rule duplicated without canonical marker across observability:108, kubernetes:16, docker:22.
- **D4 (P1)** airflow description over-claims "reviewing" and generic ETL.
- **D5 (P2)** python-refactor's "clean up this module" trigger forces tests-first workflow on routine phrasing.

Docs/install/packaging:
- **K1 (P0)** No LICENSE. **K2 (P1)** No root README (GitHub landing renders nothing). **K3 (P1)** No root .gitignore (bootstrapped projects can commit settings.local.json/.env). **K4 (P1)** No .gitattributes; `.sh` files are CRLF in Windows working trees (autocrlf) — breaks WSL/strict-bash clones; docs prescribe dos2unix only for the copy path. **K5 (P1)** `main` and tags v1.0/v2.0 still ship the 8-skill era; the audited 37-skill library exists only on feature branches. **K6 (P1)** claude-init.sh TEMPLATE path hardcoded with no env override (DEST_ROOT has one). **K7 (P1)** No CI — the enforcement layer is itself unenforced against regression. **K8 (P2)** HOW-TO uses `claude code` (not a subcommand; verified against `claude --help`). **K9 (P2)** HOW-TO Phase 4 instructs creating claude-init.sh via heredoc although the repo ships it. **K10 (P2)** ENFORCEMENT.md recipes diverge from shipped scripts (weaker patterns, pnpm-only). **K11 (P2)** macOS zsh users get a no-op `.bashrc` wiring. **K12 (P2)** settings.json ships no `permissions` block (no shared team baseline). **K13 (P2)** No skill-disable documentation; hand-maintained 3-place catalog has no drift check.

## Unconfirmed concerns (not classified as defects)

- Whether multi-skill co-fire on "organize…" routes cleanly at runtime (needs live routing evals at scale).
- Whether the GitHub "Template repository" flag is set (server-side).
- Five absolute rules that may warrant conditionality (docker "multi-stage always"; api-design 6-month deprecation floor; database-migrations "every migration reversible"; testing/ci-review "never retry"; database-review mandatory proc preamble) — defensible defaults, flagged for judgment.
- `claude code` phrasing behaves as a prompt argument rather than an error — impact is confusion, not failure.

## Strengths to preserve

1. Canonical-ownership discipline with grep-verifiable `(canonical: …)` markers — the hardest property of a multi-skill library, done well.
2. Authoring-vs-review skill pairs that delegate instead of duplicate.
3. Universal "When NOT to use" boundaries naming the adjacent owner.
4. `lib.sh` design: fail-open `require_jq`, logged override mechanism, secret previews kept out of persistent logs.
5. install.sh functional tests assert both block AND allow directions.
6. Honest docs about limits (semantic-equivalent bypasses, no sandboxing).
7. 229/229 link integrity; 37/37/37 catalog consistency; tight uniform trigger descriptions.

## Recommendations

**P0:** rotate the local credential + ship root `.gitignore` (P0-1) · add LICENSE decision to publish gate (K1, owner's call) · fix D1 engine labeling · fix D2 git-hygiene trigger scope.
**P1:** fix H1 (pipefail-safe count) with regression test · extend matcher to NotebookEdit, drop MultiEdit (H2) · fix H3 counter · root README + .gitattributes (K2, K4) · merge/tag the current library so `main` ships what was audited (K5) · CI running the hook suite (K7) · TEMPLATE env override (K6) · D3 canonical marker · D4 description fix.
**P2:** H4 malformed-JSON guard · H5 stop_hook_active guard · K8–K13 doc fixes · D5 trigger tightening · consider `disable-model-invocation`/"invoke deliberately" note for repository-cleanup · ship the 31-case hook suite + skill-trigger eval set in `tests/`.

## Audit limitations

- shellcheck, shfmt, and bats are not installed on the audit machine and were not installable without approval; shell validation was `bash -n` + executed behavior tests only.
- Skill-trigger quality was assessed by description analysis plus two live headless-session probes (earlier evidence: `ssis-review` and `repository-cleanup` auto-loaded correctly); no large-scale routing eval was run.
- Windows-native (no Git Bash) hook behavior not tested — no such environment available.
- Single audit machine; CRLF findings depend on `core.autocrlf=true` (Git-for-Windows default) which was verified locally.
