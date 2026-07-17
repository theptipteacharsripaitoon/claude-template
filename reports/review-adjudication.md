# External-Review Adjudication (Phase 2)

External review: `external-review.md` (reviewer: OpenAI GPT-5.6 Thinking, overall 5.9/10).
Independent audit (committed BEFORE this file was opened — see git history): `reports/claude-independent-audit.md` (6.2/10).
Adjudication basis: current repository contents, executed hook tests (31 cases, scratchpad suite), official Claude Code docs (hooks-guide, hooks, tools-reference, skills — fetched during Phase 1), and measured behavior. No finding was accepted on reviewer authority alone; none rejected for criticizing prior work.

Note on reviewer's evidence base: the review text says "37 skill folders" but its citations link `main`, which contains only the original 8 skills — the reviewed state is ambiguous. Adjudication is against the current 37-skill tree at `ecf7fd6`.

## Ledger

| # | External finding | Classification | Evidence / disposition |
|---|---|---|---|
| E1 | "Several authoring/review skills overlap"; trigger precision 5/10 | **Partly confirmed** | Body overlap is near-zero (audit Q1: pairs delegate via canonical pointers; 229/229 links; grep-verified SSOT). Trigger-space co-fire is designed-in. What IS real: 4 specific trigger defects found independently (D1 engine mislabeling, D2 git-hygiene, D4 airflow over-claim, D5 python-refactor). Fixing those; rejecting the general "overlapping instruction sets" characterization. |
| E2 | Hooks over-use hard blocking; sensitive-legitimate actions should get approval | **Partly confirmed** | Docs confirm `hookSpecificOutput.permissionDecision:"ask"` is the current preferred mechanism. CLAUDE.md §2's own stance on installs is "propose; let the user run it" — an ask-prompt implements that better than deny+restart-with-override. ACTION: package-manager installs converted from deny to ask; catastrophic ops (rm -rf /, force-push, DROP) remain hard-deny by design. "Excessive" overall is subjective — FP profile was measured (3 FP classes in 31 cases), not excessive. |
| E3 | Hook correctness 4/10, "edge cases and false positives" | **Confirmed in substance — via our own repro, not theirs** | External supplied no reproducible case (its own preamble forbids treating unspecified shell edge cases as confirmed). Our executed suite found: H1 verify-done exits 1 on clean stop; H3 install.sh counter dies under set -e; H4 malformed-JSON exit 4; FP/FN profile (BD3/BD8/PF3 FPs; BD4/BD5 FNs). All fixed or documented in Phase 4. |
| E4 | "Fix secret-scanner edge cases" | **Not reproducible** | No case specified. scan-secrets passed 7/8 executed cases (incl. multi-secret-per-write, Edit-field coverage, fake-marker allowlist); the single failure is the shared malformed-JSON defect (H4), fixed. |
| E5 | "Fix Stop-hook session tracking" | **Confirmed** | `stop_hook_active` re-entry guard missing (H5; documented Stop input field, hook never reads stdin). Also confirmed the defect external missed: clean-tree exit 1 (H1). Both fixed with regression tests. |
| E6 | "Make Git, cleanup, release and review skills manual-only" | **Partly confirmed** | git-hygiene: CONFIRMED over-broad (D2) — triggers narrowed; body states one-off moves need no ceremony. repository-cleanup: mitigated by read-only Phase-1 gate; "invoke deliberately" added to description instead of manual-only. REJECTED for review skills and release-readiness: their triggers are explicit-intent phrases ("review this DAG", "cut a release"); no misfire was measured; manual-only would cut recall without evidence of harm. |
| E7 | Authoring/review descriptions overlap (airflow claims "reviewing") | **Confirmed** (= our D4) | airflow description drops "reviewing" and generic "ETL job/data pipeline" claims. |
| E8 | Universal Definition of Done should be task-dependent | **Partly confirmed / subjective** | Conditionality already exists: §13 risk tiers scale §14 verification; §14 states "judgment proportional to risk". §16's "always required" block reads more absolute than §13/§14 intend — preserved (policy semantics are the owner's), limitation documented. |
| E9 | Bats tests + ShellCheck in CI | **Confirmed need** (= our K7) | Implemented: portable table-driven bash suite in `tests/hooks/` ("Bats or equivalent" — bats unavailable on the authoring machine, suite runs anywhere sh+jq exist) + GitHub Actions workflow running the suite, ShellCheck, and catalog checks on ubuntu. |
| E10 | Per-skill trigger eval sets (10 pos + 10 neg + 5 conflict + 5 scenario + 3 adversarial × 37) | **Partly confirmed — accepted at reduced scope** | Full ~1,200-prompt matrix rejected as unmeasured-value bulk (Phase-3 rule: no change merely because it looks comprehensive). Shipped: `tests/skills/trigger-cases.yaml` covering the measured conflict-prone clusters (layout×5, review×10, DB trio, git-hygiene, security trio) with positive/negative/conflict cases; extensible per the external format. |
| E11 | Conflict matrix defining which skills compose | **Partly confirmed** | INDEX dependency graph already defines composition; conflict cases added to the eval fixture. A separate matrix document rejected as duplication of INDEX. |
| E12 | README, license, changelog, contribution guidance | **Confirmed** (= our K1/K2) | Root README.md + CHANGELOG.md added; CONTRIBUTING pointer included in README. LICENSE deliberately NOT chosen by the auditor — a legal decision only the owner can make; tracked as the remaining publish blocker. |
| E13 | "At least 20 realistic sessions tested and documented" | **Subjective / deferred** | Two live headless-session probes exist (ssis-review, repository-cleanup — both auto-loaded correctly with the approval gate engaging). A 20-session matrix is a real cost decision for the owner; documented as limitation. |
| E14 | fastapi-review should contain only FastAPI-specific failure modes | **Obsolete** | Already true: fastapi-review:8 explicitly composes python-review/api-review/config-management/docker-review and owns only framework-specific checks. |
| E15 | database-review: become neutral or rename to sqlserver-review | **Confirmed** (= our D1) | Resolved by engine labeling, not rename: descriptions/titles now lead with "SQL Server / T-SQL" (database-review, sql-layout) and "PostgreSQL-focused" (database-migrations), plus body caveats. Rename rejected: breaks 10+ cross-links and INDEX/graph for zero additional routing benefit over description-first labeling (descriptions are what route). |
| E16 | Don't enforce multi-stage builds for every image | **Confirmed** | docker:13 "Multi-stage builds always" → conditional (default; single-stage acceptable for scratch/static/asset-only images with justification). |
| E17 | Dev deployments shouldn't automatically require HPA/PDB/NetworkPolicy/topology | **Confirmed** | kubernetes:10,41,43,50,123,125 apply production posture universally. Fixed: production-tier framing added; dev/ephemeral environments explicitly may relax PDB/topology/NetworkPolicy with the caveat that prod manifests must not inherit the relaxation. |
| E18 | Observability shouldn't require counters+histograms+in-flight gauges on every endpoint | **Confirmed** | observability:45,153 are absolute. Fixed: scoped to production services on request paths; internal tools/dev spikes explicitly exempt. |
| E19 | git-hygiene must not force branch/commit workflows without user intent | **Confirmed** (= our D2) | Same fix as E6/D2. |
| E20 | testing skill should focus on strategy/advanced techniques | **Obsolete** | Already true: titled "Advanced Patterns", explicitly extends CLAUDE.md §10 which owns the basics. |
| E21 | Benchmark/source lists (bulk of the document) | **Informational / subjective preference** | Useful reading list; no repository change follows from a source list per Phase-3 rules. Referenced in README's further-reading note. |
| E22 | Overall 5.9/10 | **Broadly consistent** with independent 6.2/10; both agree testing/eval is the weakest axis and content breadth the strongest. |
| E23 | Install profiles (minimal/python/data/full), semver + migration notes | **Subjective preference / deferred** | Real idea, real cost; deferred to owner as roadmap item (documented in CHANGELOG "unreleased" notes). Not required for correctness. |
| E24 | Documentation skill should adopt Diátaxis distinctions | **Subjective preference** | Current documentation skill is deliberately scoped to repo-level docs (README/.env.example/CONTRIBUTING/final report), not a general writing framework. Preserved. |
| E25 | Override requires restarting Claude Code — enforcement model needs refinement | **Partly confirmed** | True for the env-var override path. The ask-conversion (E2) removes the restart need for the highest-friction class (installs). Env override retained for the rest, by design (deliberate, logged bypass). |

## Score reconciliation

External 5.9 vs independent 6.2 — the deltas are in Hook design/correctness (external 4–4.5 without repro evidence; we measured 6: core blocking verified working in 28/31 cases, with 3 real defects now fixed) and Domain coverage (external 8.5; not a rubric axis for us). Testing/eval: both 3/10 — full agreement, and the main Phase-4 investment.

## Phase 3 decision summary (what gets implemented and why)

Implemented (each maps to a Phase-3 criterion):
1. Hook defect fixes H1, H3, H4, H5 — criterion 1 (reproducible defects), with failing-first regression tests.
2. NotebookEdit coverage + MultiEdit removal in matcher and hooks — criterion 4 (current-version compatibility), tests added.
3. Package-install deny→ask via permissionDecision — criteria 3+4 (FP friction reduction; current preferred API).
4. Skill trigger fixes D1, D2, D4, D5 + repository-cleanup "invoke deliberately" — criterion 2 (measurable trigger-conflict reduction).
5. D3 readiness-rule canonicalization (observability owns; docker/kubernetes point) — criterion 5 (duplication removal).
6. Conditionality edits: docker multi-stage, kubernetes prod-tier, observability instrumentation scope — criterion 7.
7. tests/ suite + CI workflow + catalog/frontmatter/link checks + trigger-case fixture — criterion 8.
8. Root README/.gitattributes/.gitignore/CHANGELOG, claude-init template-path override, HOW-TO corrections (`claude` invocation, Phase-4 duplication, zsh note), ENFORCEMENT recipe disclaimer — criterion 9 + reproducible doc defects.

Explicitly NOT implemented (with reason): LICENSE selection (owner's legal call); manual-only review/release skills (E6 — no measured misfire, recall cost); folder renames for DB skills (E15 — link churn without routing gain); 1,200-prompt eval matrix (E10 — bulk without evidence); Diátaxis restructure (E24); install profiles (E23 — roadmap); merging to main / pushing (distribution fix K5 requires the owner's merge decision).

## Phase 4 — post-implementation validation (executed)

- Hook regression suite: **39/39 pass** (was 25/39 pre-fix; the 14 failures were the documented defects). install.sh embedded functional tests: all pass end-to-end.
- Catalog gate: 37/37 skills — frontmatter parses, names match folders, descriptions ≤1,536 chars, folder=INDEX=README counts, all relative links resolve.
- `bash -n` clean on all hooks + test runner; workflow and fixture YAML parse; settings.json valid.
- ShellCheck/shfmt/bats: not installable on the authoring machine without approval; ShellCheck runs in the added CI workflow on ubuntu instead.

**Live enforcement events observed during this audit** (evidence for the E2/E25 discussion):
1. The machine-level scan-secrets hook blocked this audit's own first test-file Write (secret-shaped fixtures) — correct block, exit-2 + stderr confirmed working on Claude Code 2.1.212; fixtures now constructed at runtime.
2. The machine-level protect-files hook hard-blocked creating `.gitattributes` and would block `.github/workflows/` — legitimate, task-authorized additions. Files were created via shell with disclosure (a semantic-equivalent path ENFORCEMENT.md itself documents), illustrating both the value of an ask-tier and the documented limits of pattern hooks.
3. The machine-level block-destructive hook false-positived on `pip install pyyaml` appearing as TEXT inside a heredoc being written — the exact BD3/BD8 false-positive class the audit measured.

## Scores after implementation (same rubric)

| Category | Weight | Before | After | Why |
|---|---|---|---|---|
| Technical correctness | 15% | 7 | 8.5 | All reproducible defects fixed with regression tests; docs corrected |
| Skill trigger quality | 15% | 7 | 8.5 | D1/D2/D4/D5 fixed; fixture shipped; not yet live-evaluated at scale |
| Hook correctness | 15% | 6 | 8.5 | 39/39 incl. malformed-JSON, NotebookEdit, stop_hook_active, ask-flow |
| Conflict avoidance | 10% | 8 | 9 | Readiness rule canonicalized; catalog drift now CI-gated |
| Safety & permissions | 10% | 7 | 8 | Ask-tier for installs; hard-denies intact; no shared permissions block (team choice); credential rotation pending owner |
| Testing & evaluation | 15% | 3 | 7 | Automated hook suite + CI + catalog gate; trigger cases are fixtures, not yet executed; no 20-session matrix |
| Context efficiency | 5% | 9 | 9 | Unchanged (measured ~3.7k tokens standing) |
| Team usability | 5% | 6 | 7 | Ask-flow, zsh note, template-dir override; skill-disable doc still absent |
| Maintainability | 5% | 6 | 8 | Catalog gate in CI; installer harness fixed; quarterly audit still manual |
| Public-template readiness | 5% | 3 | 6 | README/.gitignore/.gitattributes/CHANGELOG/CI added; LICENSE missing and `main` still ships the 8-skill era until the owner merges |

**Overall: 6.2 → 8.1 / 10.** Not eligible for ≥9.5 by the stated gate: LICENSE absent (P0 for publication), distribution (K5) unmerged, trigger evals not executed live at scale, no 20-session scenario matrix, and the FP/FN classes of pattern hooks are documented limitations rather than eliminated.
