---
name: airflow
description: Use when creating, modifying, debugging, or reviewing Airflow DAGs, custom operators, hooks, sensors, plugins, or any data pipeline orchestration task. Trigger on phrases like "add a DAG", "fix this task", "DAG is failing", "schedule a job", "Airflow", "data pipeline", "ETL job", or any file under dags/, plugins/, include/. Covers DAG authoring, idempotency, deferrable operators, XCom hygiene, and DAG testing.
---

# Airflow & Data Pipelines

Extends `CLAUDE.md` (especially §19 Reliability & Resource Safety). When this skill loads, its rules and Done criteria apply on top of the universal baseline.

## DAG authoring

**The cardinal rule: DAGs parse on every scheduler tick.** Anything at module level runs hundreds of times per minute. This causes most Airflow performance issues.

- **No top-level I/O.** No DB queries, API calls, file reads, `Variable.get()`, or `Connection.get()` outside the DAG context. They run every parse.
- **Static `start_date`** (`datetime(2024, 1, 1)`), never `datetime.now()`, `days_ago(...)`, or `pendulum.now()`. Dynamic start dates produce non-deterministic schedules.
- **`catchup=False`** unless backfill is the explicit intent. Default `True` will spawn historical runs on first deploy.
- **`max_active_runs`** set explicitly per DAG (typically 1–3). Default of 16 will overwhelm downstreams.
- **`dagrun_timeout`** set explicitly. Untimed runs hold slots forever.
- **Tags** on every DAG (`tags=['team', 'domain', 'tier']`) for filtering and ownership.

## Tasks

**Idempotency is non-negotiable.** A retried task must produce the same outcome. Patterns:
- Use `INSERT ... ON CONFLICT` or `MERGE`, never plain `INSERT`.
- Partition outputs by `data_interval_start` / `logical_date`; overwrite the partition on rerun.
- Tag every output row with `dag_run_id` for traceability.

**Atomicity:** A task either fully succeeds or leaves no trace. No partial writes to durable storage. Use staging tables + atomic swap, or transactions where the engine supports them.

**Authoring style:**
- **TaskFlow API** (`@task` decorator) for new DAGs. Avoid `PythonOperator` boilerplate unless interfacing with existing operators.
- **TaskGroups** for organization. SubDAGs are deprecated and broken; do not use them.
- **One task = one logical unit of work.** If the docstring needs "and," split it.
- **Tasks must accept context kwargs** (`**kwargs`) to access `ti`, `data_interval_start`, etc.

## Operators & sensors

- **Deferrable operators** for any I/O-bound wait >30s (S3, HTTP, SQL polling). They free the worker slot.
- **Sensors:** `mode='reschedule'` for waits >60s; `mode='poke'` only for short polls (<60s).
- **`timeout`** set on every sensor; default is 7 days, far too long.
- **Pools** for resource-bound external systems (`max_active_tis_per_dag`, `pool_slots`). Without pools, a single DAG can saturate downstream APIs/DBs.
- **Connections and Variables** via Airflow UI or Secrets backend (AWS Secrets Manager, Vault). Never hardcode. Read inside tasks, not at module level.

## Reliability

```python
default_args = {
    'retries': 3,
    'retry_delay': timedelta(minutes=5),
    'retry_exponential_backoff': True,
    'max_retry_delay': timedelta(hours=1),
    'execution_timeout': timedelta(minutes=30),
    'on_failure_callback': alert_on_failure,
    'sla': timedelta(hours=2),  # only on critical paths
}
```

- `execution_timeout` on every task. Untimed tasks block downstream forever.
- `on_failure_callback` for alerting on critical DAGs (PagerDuty/Slack).
- **SLAs only on critical paths.** SLA misses generate noise if applied broadly.
- **Datasets** (Airflow 2.4+) for cross-DAG dependencies. Avoid `ExternalTaskSensor` chains — they create scheduler load and tight coupling.

## Data hygiene

- **Never pass large data through XCom.** XCom backend is the metadata DB; >1 KB is too much. Pass paths/IDs to object storage instead.
- **Partition destination tables by execution date** to enable idempotent reruns: `WRITE_TRUNCATE` partition, not table.
- **Watermarks and run IDs** in every output row: `_dag_run_id`, `_logical_date`, `_loaded_at`.
- **Schema validation** on write for analytics tables (Pandera, Great Expectations, dbt tests).
- **No `if not exists` schema mutations** inside tasks — DDL belongs in migrations, not pipelines.

## Code organization

```
dags/                  # one DAG per file unless tightly coupled
plugins/               # custom operators, hooks, sensors
include/               # SQL templates, configs, shared Python
  └── sql/
  └── configs/
tests/
  ├── dags/            # DAG integrity tests
  └── tasks/           # unit tests for callables
```

- **No business logic in DAG files.** DAGs orchestrate; logic lives in `include/` or a packaged module so it can be unit-tested without Airflow.
- **Importable modules:** structure `include/` as a Python package (with `__init__.py`) or use `PYTHONPATH` config.
- **Docstrings** on every DAG explaining purpose, owner, SLA, runbook URL, upstream/downstream datasets.

## Testing

- **DAG integrity test** in CI: import all DAGs, assert no import errors, no cycles, no top-level I/O, parse time <2s per DAG.
- **Unit-test task callables** in isolation. Pure Python; do not rely on Airflow runtime for logic correctness.
- **Smoke-test new DAGs** in a staging Airflow before promoting to production.
- **Render templated SQL** in tests to catch Jinja errors before runtime.

Example DAG integrity test:
```python
import pytest
from airflow.models import DagBag

@pytest.fixture(scope='session')
def dagbag():
    return DagBag(dag_folder='dags/', include_examples=False)

def test_no_import_errors(dagbag):
    assert not dagbag.import_errors, dagbag.import_errors

def test_all_dags_have_owner_and_tags(dagbag):
    for dag_id, dag in dagbag.dags.items():
        assert dag.default_args.get('owner'), f"{dag_id} missing owner"
        assert dag.tags, f"{dag_id} missing tags"

def test_no_dag_takes_too_long_to_parse(dagbag):
    # measured during DagBag init; check DagBag.dagbag_stats
    for stats in dagbag.dagbag_stats:
        assert stats.duration.total_seconds() < 2.0, stats.file
```

## Forbidden patterns

- `dag_run.conf` reads at parse time — only valid at execution time inside a task.
- `Variable.get()` at the top of a DAG file — parses on every scheduler tick.
- Long-running tasks (>4h) without checkpointing — split into smaller idempotent steps.
- Cross-DAG triggering via `TriggerDagRunOperator` chains for ordering — use Datasets instead.
- Hardcoded paths, dates, environment names — use Airflow Variables, Connections, or env vars.
- `PythonOperator` calling huge inline functions — extract to `include/` and unit-test.

## Operations

- Use the proper executor for the workload: KubernetesExecutor (or KubernetesPodOperator) for isolation; CeleryExecutor with autoscaling for high task volume; LocalExecutor only for dev.
- Pin provider package versions in `requirements.txt`. Provider upgrades break DAGs silently.
- Monitor scheduler heartbeat, parse times, DAG run duration, task queue depth — these are the leading indicators of cluster health.

## Done criteria (in addition to CLAUDE.md §14)

- [ ] No top-level I/O (verified by reading the DAG file end-to-end).
- [ ] `start_date` is static; `catchup` set explicitly.
- [ ] `max_active_runs`, `dagrun_timeout`, and per-task `execution_timeout` defined.
- [ ] All tasks idempotent and atomic; rerun produces identical state.
- [ ] Retries with exponential backoff configured.
- [ ] No large payloads through XCom (paths/IDs only).
- [ ] DAG passes integrity tests (import, parse time, owner, tags).
- [ ] Task callables have unit tests independent of Airflow runtime.
- [ ] Owner, tags, and runbook documented in DAG docstring.
- [ ] New providers/dependencies pinned in `requirements.txt`.
