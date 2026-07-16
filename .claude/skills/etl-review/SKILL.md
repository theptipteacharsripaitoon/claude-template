---
name: etl-review
description: Use when reviewing a data pipeline end-to-end — source-to-target correctness, reconciliation, incremental logic, rerun safety — across SQL jobs, SSIS, Airflow, or Python loaders. Trigger on phrases like "review the pipeline", "is the load correct", "numbers don't match the source", "check the incremental logic", "ETL review", "data is missing rows". Covers mapping, row-count reconciliation, watermarks, duplicates, and publish safety. Do NOT use for reviewing a single DAG (airflow-review), a single proc (database-review), or a single package (ssis-review).
---

# ETL Pipeline Review

Extends `CLAUDE.md` (especially §19). Reviews the pipeline END-TO-END — the data path across extract, transform, load — whatever the engine (SQL Agent + procs, SSIS, Airflow, Python). Component-level review is owned by [database-review](../database-review/SKILL.md), [airflow-review](../airflow-review/SKILL.md), and [ssis-review](../ssis-review/SKILL.md); this skill checks the whole.

## Purpose

Every component can be individually correct while the pipeline still loses rows, double-counts on rerun, or publishes partial data. The end-to-end questions live here.

## When to use

- Reviewing a new or changed pipeline before production; investigating "target doesn't match source"; auditing an inherited pipeline.

## When NOT to use

- Single-component depth → [database-review](../database-review/SKILL.md) (SQL), [airflow-review](../airflow-review/SKILL.md) (DAGs), [ssis-review](../ssis-review/SKILL.md) (packages).
- Authoring pipelines (the engine skills own authoring standards).

## Review checklist (each item needs evidence)

1. **Mapping** — source→target documented per table: what is extracted, filtered out, transformed, loaded. An undocumented transform is a finding.
2. **Reconciliation** — row counts (and sums, for money columns) source vs target recorded per run in the run log (log shape: [database-review](../database-review/SKILL.md); universal rule: `CLAUDE.md` §19). A pipeline that cannot answer "did everything arrive?" fails review.
3. **Rerun safety** — the WHOLE pipeline, rerun after a mid-run failure, converges to the same final state (canonical: `CLAUDE.md` §19 idempotency; engine mechanics: the component skills).
4. **Incremental logic** — watermark/delta boundaries checked for: off-by-one at the boundary, late-arriving data, the watermark column's timezone and calendar, overlap policy on rerun.
5. **Duplicates** — dedup strategy explicit: business keys, which copy wins, where it is enforced.
6. **Boundary validation** — external input validated at entry: types, lengths, encoding. Thai-data specifics — invisible Unicode, Buddhist Era years — are owned by [ssis-review](../ssis-review/SKILL.md) and apply to any engine loading Thai text. Reject/quarantine path defined (`CLAUDE.md` §7).
7. **Publish safety** — readers never see partial data: atomic publish (canonical: [database-review](../database-review/SKILL.md) swap-table; task-level atomicity: airflow skill).
8. **Failure behavior** — every step logs start/end/counts/status; failures alert a named owner (`CLAUDE.md` §19); the resume point after partial failure is defined.
9. **Schedule and ownership** — cadence documented, owner named, downstream consumers and their deadlines listed.

## Cross-references

- [sql-layout](../sql-layout/SKILL.md) — where the pipeline's SQL lives and how it reads
- [database-review](../database-review/SKILL.md) — proc/job safety, run logging, publish mechanics
- [airflow-review](../airflow-review/SKILL.md) — DAG-level review when Airflow orchestrates
- [ssis-review](../ssis-review/SKILL.md) — package-level review and Thai-data lessons
- [verification](../verification/SKILL.md) — verifying findings and fixes

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Reconciliation recorded per run; source-vs-target answerable from the log alone.
- [ ] "Rerun converges" has a written answer for the whole pipeline, not just tasks.
- [ ] Watermark boundary conditions (off-by-one, late data, timezone/calendar) checked.
- [ ] Publish is atomic; owner and consumers documented.
