# Skill Index

One line per skill, the dependency graph, and build status. Details live in each skill's `SKILL.md`; conventions and maintenance rules in [README.md](README.md).

## Built skills

| Skill | Summary |
|---|---|
| [airflow](airflow/SKILL.md) | DAG authoring, idempotency, deferrable operators, XCom hygiene, DAG testing |
| [api-design](api-design/SKILL.md) | Public API/REST/GraphQL contracts, versioning, deprecation, pagination |
| [database-migrations](database-migrations/SKILL.md) | Schema changes, expand-migrate-contract, zero-downtime, lock-safe DDL |
| [dependency-review](dependency-review/SKILL.md) | Unused/missing/duplicate/obsolete dependency audit with evidence |
| [docker](docker/SKILL.md) | Dockerfile/compose, multi-stage builds, image security and size |
| [documentation](documentation/SKILL.md) | README/.env.example/CONTRIBUTING proposals, cleanup final report |
| [git-hygiene](git-hygiene/SKILL.md) | Clean-tree gate, git mv, move-first-rename-later, cleanup commit sequence, .gitignore |
| [kubernetes](kubernetes/SKILL.md) | Manifests/Helm/Kustomize, pod security, RBAC, GitOps |
| [observability](observability/SKILL.md) | Metrics/traces/logs, golden signals, OpenTelemetry, SLO alerting |
| [project-layout](project-layout/SKILL.md) | Minimal root, project-type layouts, naming review, migration strategy |
| [release-readiness](release-readiness/SKILL.md) | Release checklist: verification, secrets, docs, changelog, tag, rollback plan |
| [repository-cleanup](repository-cleanup/SKILL.md) | Cleanup orchestrator: audit → approval → execute → verify; evidence, archive-over-delete |
| [security-review](security-review/SKILL.md) | Repo secret scan, never-print-values, rotation, history cleanup |
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
```

Standalone (extend only `CLAUDE.md`): airflow, api-design, database-migrations, docker, kubernetes, observability, testing, web-security.

## Planned (not built)

| Phase | Skill | Note |
|---|---|---|
| B | etl-review | will reference sql-layout, database-review, airflow-review, verification |
| B | sql-layout | |
| B | database-review | must reconcile scope with existing `database-migrations` |
| B | airflow-layout | |
| B | airflow-review | must reconcile scope with existing `airflow`; will reference airflow-layout |
| B | ssis-review | no existing SSIS skill found in Phase 0 inventory — production lessons to be authored fresh |
| C | python-layout, python-review, python-refactor, python-performance | |
| C | fastapi-review | will reference python-review, api-review, config-management, docker-review |
| C | api-review | must reconcile scope with existing `api-design` |
| C | config-management | will own config target locations; `repository-cleanup/references/config-consolidation.md` points here once built |
| C | docker-review | must reconcile scope with existing `docker` |
| D | agent-design, prompt-engineering, llm-evaluation | on explicit request only |
| D | ci-review | on explicit request only |
| D | frontend-layout, ui-review, design-system | on explicit request only |

Note: the source taxonomy also lists `observability` under DevOps — it already exists as a built skill; Phase D must extend it, not recreate it.
