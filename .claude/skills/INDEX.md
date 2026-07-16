# Skill Index

One line per skill, the dependency graph, and build status. Details live in each skill's `SKILL.md`; conventions and maintenance rules in [README.md](README.md).

## Built skills

| Skill | Summary |
|---|---|
| [agent-design](agent-design/SKILL.md) | LLM agent architecture: tool contracts, guardrails, bounded loops, run logging |
| [airflow](airflow/SKILL.md) | DAG authoring, idempotency, deferrable operators, XCom hygiene, DAG testing |
| [airflow-layout](airflow-layout/SKILL.md) | DAG repo conventions at scale, naming, env separation (complements airflow) |
| [airflow-review](airflow-review/SKILL.md) | DAG change review: parse, schedule impact, contracts, backfill blast radius |
| [api-design](api-design/SKILL.md) | Public API/REST/GraphQL contracts, versioning, deprecation, pagination |
| [api-review](api-review/SKILL.md) | API change review: breaking-change classification, schema-diff evidence |
| [ci-review](ci-review/SKILL.md) | CI/CD change review: SHA-pinned actions, least-privilege tokens, blocking gates |
| [config-management](config-management/SKILL.md) | Config precedence hierarchy, typed Settings loading, what lives where |
| [database-migrations](database-migrations/SKILL.md) | Schema changes, expand-migrate-contract, zero-downtime, lock-safe DDL |
| [database-review](database-review/SKILL.md) | Proc/job safety, transaction scope, deadlock avoidance, swap-table publish |
| [dependency-review](dependency-review/SKILL.md) | Unused/missing/duplicate/obsolete dependency audit with evidence |
| [design-system](design-system/SKILL.md) | Shared-component governance: reuse-before-create, tokens, deprecation |
| [docker](docker/SKILL.md) | Dockerfile/compose, multi-stage builds, image security and size |
| [docker-review](docker-review/SKILL.md) | Container change review: build/scan/size evidence, secrets in layers |
| [documentation](documentation/SKILL.md) | README/.env.example/CONTRIBUTING proposals, cleanup final report |
| [etl-review](etl-review/SKILL.md) | End-to-end pipeline review: reconciliation, watermarks, rerun safety, publish |
| [fastapi-review](fastapi-review/SKILL.md) | FastAPI review: async discipline, Pydantic edges, yield-deps, startup |
| [frontend-layout](frontend-layout/SKILL.md) | Frontend structure: feature folders, colocation, barrel discipline, api layer |
| [git-hygiene](git-hygiene/SKILL.md) | Clean-tree gate, git mv, move-first-rename-later, cleanup commit sequence, .gitignore |
| [kubernetes](kubernetes/SKILL.md) | Manifests/Helm/Kustomize, pod security, RBAC, GitOps |
| [llm-evaluation](llm-evaluation/SKILL.md) | Golden sets, graded dimensions, judge calibration, blocking regressions |
| [observability](observability/SKILL.md) | Metrics/traces/logs, golden signals, OpenTelemetry, SLO alerting |
| [project-layout](project-layout/SKILL.md) | Minimal root, project-type layouts, naming review, migration strategy |
| [prompt-engineering](prompt-engineering/SKILL.md) | Prompt structure, schema-first outputs, injection resistance, versioning |
| [python-layout](python-layout/SKILL.md) | Python packaging: pyproject home, __init__ discipline, entry points |
| [python-performance](python-performance/SKILL.md) | Profile-first optimization, the optimization order, chunked big data |
| [python-refactor](python-refactor/SKILL.md) | Behavior-preserving refactor workflow: characterize, one transform per commit |
| [python-review](python-review/SKILL.md) | Python review checklist: mutable defaults, except breadth, async traps |
| [release-readiness](release-readiness/SKILL.md) | Release checklist: verification, secrets, docs, changelog, tag, rollback plan |
| [repository-cleanup](repository-cleanup/SKILL.md) | Cleanup orchestrator: audit → approval → execute → verify; evidence, archive-over-delete |
| [security-review](security-review/SKILL.md) | Repo secret scan, never-print-values, rotation, history cleanup |
| [sql-layout](sql-layout/SKILL.md) | SQL file organization, one-object-per-file, deploy scripts, style |
| [ssis-review](ssis-review/SKILL.md) | Dtsx review, Derived Column, Thai Unicode cleanup, Buddhist Era dates |
| [testing](testing/SKILL.md) | Test pyramid, property-based, mutation, contract testing, flakiness |
| [ui-review](ui-review/SKILL.md) | UI change review: state matrix, visual evidence, a11y, Thai text rendering |
| [verification](verification/SKILL.md) | Per-commit verification commands, blocking failures, surgical rollback |
| [web-security](web-security/SKILL.md) | Auth, sessions, CSRF/SSRF, headers, uploads, crypto (OWASP) |

## Dependency graph (skill → references)

```
repository-cleanup → project-layout, git-hygiene, verification,
                     dependency-review, security-review, documentation
                     (+ references/config-consolidation.md)
release-readiness  → verification, security-review, documentation, git-hygiene
git-hygiene        → security-review, verification
project-layout     → git-hygiene
dependency-review  → verification
documentation      → api-design, security-review
security-review    → web-security
verification       → testing
etl-review         → sql-layout, database-review, airflow-review, ssis-review, verification
ssis-review        → database-review, sql-layout, verification
database-review    → database-migrations, sql-layout, verification
sql-layout         → database-migrations
airflow-review     → airflow, airflow-layout, verification
airflow-layout     → airflow, project-layout
fastapi-review     → python-review, api-review, config-management, docker-review,
                     web-security, security-review, observability, verification
python-review      → python-layout, dependency-review, verification, testing
python-refactor    → repository-cleanup, testing, verification
python-performance → repository-cleanup, database-review, verification, testing
python-layout      → project-layout
config-management  → security-review, documentation
docker-review      → docker, verification, security-review
api-review         → api-design, testing, verification
agent-design       → prompt-engineering, llm-evaluation, observability
prompt-engineering → agent-design, llm-evaluation
llm-evaluation     → prompt-engineering, agent-design, verification
ci-review          → testing, security-review, verification
frontend-layout    → project-layout
ui-review          → testing, design-system, frontend-layout
design-system      → ui-review, frontend-layout, api-design, testing
```

(The AI trio — agent-design, prompt-engineering, llm-evaluation — are deliberate peers that
reference each other; ci-review additionally links the repo's `ENFORCEMENT.md` Layer-3 doc.)

Module edge: `repository-cleanup/references/config-consolidation.md` → config-management, documentation, security-review, verification.

Standalone (extend only `CLAUDE.md`): kubernetes.

## Planned (not built)

None — all phases (A–D) of the skill-library taxonomy are built. The taxonomy's Phase D `observability` entry was already covered by the pre-existing observability skill and was deliberately not recreated (single source of truth).
