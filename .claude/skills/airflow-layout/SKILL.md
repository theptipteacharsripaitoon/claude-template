---
name: airflow-layout
description: >-
  Use when organizing an Airflow repository — DAG file placement and naming,
  per-domain foldering, environment separation, where DAG configs live.
  Trigger: "organize the dags folder", "DAG naming convention", "where should
  this DAG live". Do NOT use for writing or debugging DAGs (airflow) or
  general repo structure (project-layout).

---

# Airflow Repository Layout

Extends `CLAUDE.md`. The canonical folder tree (`dags/`, `plugins/`, `include/`, `tests/`) and every DAG authoring rule are owned by [airflow](../airflow/SKILL.md) — this skill only adds the repo-scale conventions on top. Do not restate authoring rules from there.

## Purpose

A DAG repo with three DAGs organizes itself; one with sixty needs conventions — naming, foldering, environment separation — so any engineer can find the pipeline that owns a table in seconds.

## When to use

- Growing `dags/` past a handful of files; agreeing naming conventions; splitting per team/domain; deciding where DAG-adjacent config lives; separating dev from prod.

## When NOT to use

- Authoring, debugging, or reviewing DAG logic → [airflow](../airflow/SKILL.md).
- Non-Airflow repository structure → [project-layout](../project-layout/SKILL.md).

## Core rules

- **`dag_id` equals the file name** (`sales_daily_load.py` → `dag_id="sales_daily_load"`) — one grep finds both.
- **Name by domain and cadence:** `<domain>_<what>_<cadence>` (`finance_armast_daily`). Prefix per team when several teams share one repo.
- **Subfolder `dags/` by domain at scale** (`dags/finance/`, `dags/crm/`), never deeper than two levels. The tree inside each domain still follows the airflow skill's canonical layout.
- **Tag values are fixed per repo.** The airflow skill mandates `tags=['team', 'domain', 'tier']`; the ALLOWED values are defined once in the repo docs — not invented per DAG.
- **Environment separation by deployment, not by logic.** Dev/staging/prod get separate Airflow deployments (or deploy branches); never `if env == "prod"` inside a DAG definition.
- **Variables/connections defined as code** (definitions, not values) live under `include/configs/`; secret VALUES stay in the secrets backend (canonical: [airflow](../airflow/SKILL.md) + `CLAUDE.md` §7).
- **Retired DAGs are removed or archived,** not left paused forever — a paused DAG with no owner is repository noise.

## Cross-references

- [airflow](../airflow/SKILL.md) — canonical folder tree, DAG authoring, testing, operations
- [project-layout](../project-layout/SKILL.md) — general repository structure standards
- `CLAUDE.md` §7 (secrets), §8 (file organization)

## Done criteria (in addition to CLAUDE.md §14)

- [ ] `dag_id` matches its file name; name follows the domain_what_cadence convention.
- [ ] Domain subfolders ≤2 levels; tags use the repo's fixed value set.
- [ ] No environment conditionals inside DAG definitions.
- [ ] No new orphaned/paused-forever DAGs introduced.
