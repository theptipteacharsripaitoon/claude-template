# Skills

Skills extend `CLAUDE.md` with domain-specific rules that load only when relevant. Each skill is a folder containing a `SKILL.md` with YAML frontmatter that tells Claude when to use it.

## How it works

Claude scans every skill's `description` field on each prompt (cheap — ~100 tokens per skill). When a description matches the user's request, the full `SKILL.md` body loads into context. This is **progressive disclosure**: many skills installed, only relevant ones loaded.

## Current skills

| Skill | Triggers when working on... |
|---|---|
| `docker/` | Dockerfile, docker-compose, image builds, container hardening |
| `kubernetes/` | K8s manifests, Helm charts, kustomize, deployment |
| `airflow/` | DAGs, custom operators, data pipelines, ETL |
| `testing/` | Advanced testing patterns (pyramid, property-based, mutation, contract) |
| `database-migrations/` | Schema changes, migrations, indexes, lock-safe DDL |
| `api-design/` | Public APIs, REST, GraphQL, versioning, deprecation |
| `web-security/` | Auth, sessions, cookies, CSRF, SSRF, file uploads, headers |
| `observability/` | Metrics, traces, logs, health checks, SLO alerts |
| `repository-cleanup/` | Repo audits, cleanup, decluttering, safe restructuring (orchestrator) |
| `verification/` | Post-commit verification commands, blocking failures, rollback protocol |
| `git-hygiene/` | Work branches, git mv, move-first-rename-later, cleanup commit sequence, .gitignore |
| `security-review/` | Repo secret scans, leaked credentials, rotation, history cleanup |
| `project-layout/` | Folder structure proposals, root cleanup, project-type layouts |
| `dependency-review/` | Unused/missing/duplicate/obsolete dependency audits |
| `documentation/` | README, .env.example, CONTRIBUTING proposals, cleanup final report |
| `release-readiness/` | Release checklist: tag, changelog, verification, rollback plan |

See [`INDEX.md`](INDEX.md) for the full dependency graph and per-skill build status.

## Maintaining

- **Audit quarterly.** Remove skills not used in 90 days. List unused with `git log --since=90.days.ago` on each skill folder.
- **Audit `description` fields** — if a skill isn't loading when expected, the description's trigger words may not match what users actually type. Fix the description first; the body second.
- **Split mega-skills.** A `SKILL.md` over ~200 lines is usually two skills.
- **Add new skills only when you re-paste the same context to Claude 3+ times.** That's the signal it's a skill, not a one-off.
- **Commit skills to git** so the whole team (and everyone's Claude) uses the same playbook.

## Adding a new skill

```bash
mkdir -p .claude/skills/<name>
cat > .claude/skills/<name>/SKILL.md <<'EOF'
---
name: <name>
description: Use when [verb]ing [noun]... Trigger on phrases like "...", "...". Covers [topics].
---

# <Title>

Extends `CLAUDE.md`. ...

## Done criteria (in addition to CLAUDE.md §14)
- [ ] ...
EOF
```

Trigger words in the description should match what users **actually type** — verbs they use, file names they reference. Skills that read like documentation ("This skill is responsible for...") trigger less reliably than skills that read like instructions ("Use when modifying...").
