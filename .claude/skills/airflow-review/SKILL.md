---
name: airflow-review
description: Use when reviewing an Airflow DAG change before merge or deploy — a review checklist over parse integrity, schedule impact, idempotency, and task contracts. Trigger on phrases like "review this DAG", "is this DAG safe to deploy", "check the schedule change", "DAG PR review", "will this backfill". The airflow skill owns the authoring standards; this skill owns the review process. Do NOT use for authoring or debugging DAGs (airflow) or for whole-pipeline data review (etl-review).
---

# Airflow DAG Review

Extends `CLAUDE.md`. The [airflow](../airflow/SKILL.md) skill owns the authoring standards and Done criteria — this skill owns the review PROCESS for a DAG change. Check the diff against those standards; do not restate them.

## Purpose

A DAG change reviewed by eyeball ships backfill storms and silent contract breaks. This checklist makes the review evidence-based: every item produces an observable answer, not a feeling.

## When to use

- Reviewing a DAG PR; pre-deploy check of schedule/dependency changes; assessing the blast radius of a task rename or XCom change.

## When NOT to use

- Writing or debugging DAG logic → [airflow](../airflow/SKILL.md).
- End-to-end data correctness across the pipeline → etl-review.

## Review checklist (in order — each item needs evidence)

1. **Parse integrity** — DAG integrity tests and `airflow dags list` pass in CI or locally. Commands, blocking policy, and failure protocol: [verification](../verification/SKILL.md).
2. **Authoring compliance** — walk the [airflow](../airflow/SKILL.md) Done criteria against the diff (canonical standards live there).
3. **Schedule-change impact** — any change to `start_date`, `schedule`, or `catchup`: state explicitly how many runs will spawn on deploy. An unstated answer is a finding — this is how backfill storms ship.
4. **Idempotency answer** — for every changed task: "retried twice mid-run, this leaves what state?" must have a written answer (standard: airflow skill; universal rule: `CLAUDE.md` §19).
5. **Contract compatibility** — changed `task_id`s, XCom keys, or Dataset URIs: list the consumers. A renamed `task_id` silently breaks downstream sensors, XCom pulls that reference it, and run history (Datasets are URI-keyed and survive a task rename if the outlet URI is unchanged).
6. **Concurrency and pools** — new/changed pools, `max_active_runs`, `max_active_tis_per_dag`: check the capacity of the system being hit (DB, API), not just the Airflow side.
7. **Alerting still wired** — `on_failure_callback` / SLA intact on critical DAGs after the change.
8. **Placement and naming** — per [airflow-layout](../airflow-layout/SKILL.md).

## Cross-references

- [airflow](../airflow/SKILL.md) — canonical authoring standards and Done criteria
- [airflow-layout](../airflow-layout/SKILL.md) — placement, naming, environment separation
- [verification](../verification/SKILL.md) — parse checks, blocking policy, rollback protocol

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Every checklist item answered with evidence, not assertion.
- [ ] Backfill/run-spawn impact of schedule changes stated explicitly.
- [ ] Consumers of any changed task_id/XCom/Dataset listed and checked.
