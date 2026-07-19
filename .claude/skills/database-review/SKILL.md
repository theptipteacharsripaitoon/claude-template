---
name: database-review
description: >-
  Use when reviewing SQL Server / T-SQL code before it ships — procs, queries,
  DML jobs — correctness, safety, performance, deadlocks, batching. Trigger:
  "review this proc", "is this query safe", "deadlock", "query is slow".
  T-SQL-specific mechanics. Do NOT use for schema migrations
  (database-migrations) or SQL file layout (sql-layout).

---

# Database Review (SQL Server / T-SQL)

Extends `CLAUDE.md` (especially §12, §14, §19). Owns the review standard for database CODE — procs, queries, DML jobs. The mechanics below are SQL Server-specific; on another engine, keep the review structure and swap the engine mechanics. Schema/DDL changes are owned by [database-migrations](../database-migrations/SKILL.md); file organization and style by [sql-layout](../sql-layout/SKILL.md).

## Purpose

Database code fails in production through unsafe defaults, oversized transactions, row-by-row writes, and deadlocks. This checklist catches those at review time, before the 2 a.m. page.

## When to use

- Reviewing a proc, query, or scheduled DML job; diagnosing deadlocks or slow queries in review; hardening ETL SQL.

## When NOT to use

- DDL, indexes, and migration workflow → [database-migrations](../database-migrations/SKILL.md).
- File naming/organization/style → [sql-layout](../sql-layout/SKILL.md).

## Proc and job safety

- Every proc starts with `SET NOCOUNT ON; SET XACT_ABORT ON;` — without `XACT_ABORT`, a failed statement can leave a half-done transaction open.
- TRY/CATCH around the work; CATCH rolls back (`IF @@TRANCOUNT > 0 ROLLBACK`), records the failure, and re-raises with `THROW` — never swallow (canonical: `CLAUDE.md` §12).
- Scheduled/unattended jobs write a run log — start/end time, duration, rows deleted/inserted, status, error message and line — to a process-log table (the `ETL_ProcessLog` pattern). Universal rule: `CLAUDE.md` §19 (unattended jobs are observable); this skill owns the SQL shape.
- **Keep transactions tight.** Bulk pre-cleanup (batched `DELETE TOP (@BatchSize) ... WHERE ...` loop driven by `@@ROWCOUNT`) runs BEFORE `BEGIN TRANSACTION`; only the atomic insert/publish sits inside.
- Set-based DML, batched for volume (canonical: `CLAUDE.md` §19 bulk-over-loops). Row-by-row cursors over large tables are a finding.

## Deadlock avoidance (canonical here)

- **One set-based UPDATE per table per step.** Multiple concurrent UPDATEs against the same table from parallel job branches are the classic ETL deadlock — consolidate into a single statement, or serialize the writers.
- Procs that share tables touch them in a consistent order.
- Keep read/write locks short; for reads of tables being loaded, prefer snapshot isolation/RCSI. `WITH (NOLOCK)` only where approximate reads are explicitly acceptable — never for financial figures.
- `WITH (TABLOCK)` on bulk loads INTO staging tables is deliberate and fine (one lock; minimal logging additionally requires the SIMPLE or BULK_LOGGED recovery model) — staging only, never on shared live tables.

## Publish safety — swap-table pattern (canonical here)

Readers must never see a half-loaded table. Load into a staging table, verify counts, then publish atomically — `sp_rename` swap, `ALTER SCHEMA ... TRANSFER`, partition switch, or synonym repoint. The previous table survives until the swap commits, so rollback is instant.

## Query review

- **Execution plan reviewed** on realistic volume for new/changed queries (canonical: `CLAUDE.md` §14 SQL row): large-table scans justified, predicates SARGable (no functions wrapped around indexed columns), no implicit conversions — NVARCHAR/VARCHAR mismatches are the classic one on Thai text columns.
- Explicit column lists and style per [sql-layout](../sql-layout/SKILL.md); parameterization per `CLAUDE.md` §7.
- Writes are idempotent/rerun-safe (canonical: `CLAUDE.md` §19): keyed upsert, or delete-then-insert scoped by batch/source key (`DELETE ... WHERE DB = @db_name` then insert).

## Workflow

Read the proc top to bottom → safety preamble → transaction scope → write patterns (set-based, batched, idempotent) → locks and hints → execution plan on realistic volume → run log present. Verification commands and blocking rules: [verification](../verification/SKILL.md).

## Cross-references

- [database-migrations](../database-migrations/SKILL.md) — DDL, indexes, object naming, backfills
- [sql-layout](../sql-layout/SKILL.md) — file organization and SQL style
- [verification](../verification/SKILL.md) — how review findings get verified
- `CLAUDE.md` §12 (errors), §14 (SQL verification), §19 (reliability)

## Done criteria (in addition to CLAUDE.md §14)

- [ ] `SET NOCOUNT ON; SET XACT_ABORT ON;` present; TRY/CATCH rolls back and re-raises with THROW.
- [ ] Unattended jobs log start/end/rows/status/error to a process-log table.
- [ ] Transactions tight; bulk cleanup batched outside them; DML set-based and rerun-safe.
- [ ] No overlapping concurrent UPDATEs on one table; no unjustified NOLOCK; TABLOCK only on staging loads.
- [ ] Publish is atomic (swap/switch), never in-place on a table being read.
- [ ] Execution plan reviewed on representative data volume.
