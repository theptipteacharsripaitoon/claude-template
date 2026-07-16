# Skill Index

One line per skill, the dependency graph, and build status. Details live in each skill's `SKILL.md`; conventions and maintenance rules in [README.md](README.md).

## Built skills

| Skill | Summary |
|---|---|
| [airflow](airflow/SKILL.md) | DAG authoring, idempotency, deferrable operators, XCom hygiene, DAG testing |
| [airflow-layout](airflow-layout/SKILL.md) | DAG repo conventions at scale, naming, env separation (complements airflow) |
| [airflow-review](airflow-review/SKILL.md) | DAG change review: parse, schedule impact, contracts, backfill blast radius |
| [api-design](api-design/SKILL.md) | Public API/REST/GraphQL contracts, versioning, deprecation, pagination |
| [database-migrations](database-migrations/SKILL.md) | Schema changes, expand-migrate-contract, zero-downtime, lock-safe DDL |
| [database-review](database-review/SKILL.md) | Proc/job safety, transaction scope, deadlock avoidance, swap-table publish |
| [dependency-review](dependency-review/SKILL.md) | Unused/missing/duplicate/obsolete dependency audit with evidence |
| [docker](docker/SKILL.md) | Dockerfile/compose, multi-stage builds, image security and size |
| [documentation](documentation/SKILL.md) | README/.env.example/CONTRIBUTING proposals, cleanup final report |
| [etl-review](etl-review/SKILL.md) | End-to-end pipeline review: reconciliation, watermarks, rerun safety, publish |
| [git-hygiene](git-hygiene/SKILL.md) | Clean-tree gate, git mv, move-first-rename-later, cleanup commit sequence, .gitignore |
| [kubernetes](kubernetes/SKILL.md) | Manifests/Helm/Kustomize, pod security, RBAC, GitOps |
| [observability](observability/SKILL.md) | Metrics/traces/logs, golden signals, OpenTelemetry, SLO alerting |
| [project-layout](project-layout/SKILL.md) | Minimal root, project-type layouts, naming review, migration strategy |
| [release-readiness](release-readiness/SKILL.md) | Release checklist: verification, secrets, docs, changelog, tag, rollback plan |
| [repository-cleanup](repository-cleanup/SKILL.md) | Cleanup orchestrator: audit → approval → execute → verify; evidence, archive-over-delete |
| [security-review](security-review/SKILL.md) | Repo secret scan, never-print-values, rotation, history cleanup |
| [sql-layout](sql-layout/SKILL.md) | SQL file organization, one-object-per-file, deploy scripts, style |
| [ssis-review](ssis-review/SKILL.md) | Dtsx review, Derived Column, Thai Unicode cleanup, Buddhist Era dates |
| [testing](testing/SKILL.md) | Test pyramid, property-based, mutation, contract testing, flakiness |
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
```

Standalone (extend only `CLAUDE.md`): docker, kubernetes, observability.

## Planned (not built)

| Phase | Skill | Note |
|---|---|---|
| C | python-layout, python-review, python-refactor, python-performance | |
| C | fastapi-review | will reference python-review, api-review, config-management, docker-review |
| C | api-review | must reconcile scope with existing `api-design` |
| C | config-management | will own config target locations; `repository-cleanup/references/config-consolidation.md` points here once built |
| C | docker-review | must reconcile scope with existing `docker` |
| D | agent-design, prompt-engineering, llm-evaluation | on explicit request only |
| D | ci-review | on explicit request only |
| D | frontend-layout, ui-review, design-system | on explicit request only |

Note: the source taxonomy also lists `observability` under DevOps — it already exists as a built skill; Phase D must extend it, not recreate it.
