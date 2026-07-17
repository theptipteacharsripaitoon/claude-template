---
name: sql-layout
description: Use when organizing or styling SQL code in a repository — folder structure for SQL objects, file naming, deploy-script layout, formatting conventions. Trigger on phrases like "organize these SQL files", "where should this proc live", "SQL folder structure", "clean up this SQL", "SQL file naming". Covers one-object-per-file, deploy-script batching, header comments, and style consistency (conventions are T-SQL/SQL Server-flavored — GO batches, bracketed schemas; adapt for other engines). Do NOT use for schema-change workflow or database object naming (database-migrations), query/proc correctness review (database-review), or writing migrations.
---

# SQL Layout

Extends `CLAUDE.md`. Owns SQL FILE organization and code style. Database OBJECT naming (tables, columns, indexes, constraints) and the schema-change workflow are owned by [database-migrations](../database-migrations/SKILL.md) — not restated here.

## Purpose

SQL repositories rot into "which of these five copies actually runs in production?" A predictable layout makes every object findable, diffable, and deployable.

## When to use

- Organizing loose `.sql` files; naming a new proc/view file; setting up multi-database deploy scripts; style questions during SQL review.

## When NOT to use

- Database object naming or DDL/migration workflow → [database-migrations](../database-migrations/SKILL.md).
- Query/proc correctness and performance review → database-review.

## Core rules

- **One object per file; file name = object name** (`usp_load_staging_ARMAST.sql` creates `usp_load_staging_ARMAST`). Exception: a deploy script that intentionally creates the same object across several databases stays one file, one `USE [db]; ... GO` batch per target.
- **Folders by object type** (`procs/`, `views/`, `tables/`, `jobs/`) **or by domain** at scale — follow the repo's existing convention (`CLAUDE.md` §1); never mix both schemes at the same level.
- **Header comment on every object file:** purpose, source → target, caller/schedule (SQL Agent job, SSIS package, DAG), side effects.
- **Schema-qualify every object** (`[dbo].[...]`). Unqualified names resolve per-user and break ownership chaining.
- **Explicit column lists** in saved objects — both INSERT and SELECT. `SELECT *` breaks the day the source table changes shape.
- **`GO` separates batches;** every `CREATE PROCEDURE` gets its own batch.
- **Environment-specific literals** (server names, database names, file paths) live only in deploy scripts or SQLCMD variables — never inside reusable logic.
- **Parameterized SQL only** — never concatenate input into SQL (canonical: `CLAUDE.md` §7).
- **Match the dominant style** (keyword case, indentation) of the repo; do not reformat files while reviewing them (`CLAUDE.md` §9).

## Cross-references

- [database-migrations](../database-migrations/SKILL.md) — object naming, schema-change workflow, lock-safe DDL
- `CLAUDE.md` §7 (injection), §8 (file organization), §9 (diff discipline)

## Done criteria (in addition to CLAUDE.md §14)

- [ ] File name matches the object it creates, or the file is a documented multi-DB deploy script.
- [ ] Header comment states purpose, source→target, and caller/schedule.
- [ ] All objects schema-qualified; all column lists explicit; no `SELECT *` in saved objects.
- [ ] No environment literals inside reusable logic.
