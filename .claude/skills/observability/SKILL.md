---
name: observability
description: >-
  Use when adding or modifying metrics, traces, structured logs, health
  checks, dashboards, or alerts. Trigger: "add a metric", "instrument this",
  "add tracing", "health check", "alert on", "Prometheus", "OpenTelemetry". Do
  NOT use for verifying a repo still works after changes (verification) or
  dev-log formatting rules (CLAUDE.md §12).

---

# Observability

Extends `CLAUDE.md §12` (Error Handling & Logging). The universal logging foundations (no secrets in logs, structured JSON, levels, trace_id) live there. This skill covers metrics, traces, and the operational philosophy behind them.

## The four golden signals (every service)

For every user-visible service, monitor:

1. **Latency** — how long requests take. Track p50, p95, p99. Average is useless.
2. **Traffic** — request rate (RPS, QPS).
3. **Errors** — error rate, both as count and as fraction of traffic.
4. **Saturation** — how close to capacity (CPU, memory, queue depth, connection pool).

A dashboard that shows all four at a glance is the foundation. Anything else is supplementary.

## Metrics

### Naming
- Lowercase, snake_case, suffix indicates unit:
  - `*_total` for monotonic counters: `http_requests_total`.
  - `*_seconds` for durations: `http_request_duration_seconds`.
  - `*_bytes` for sizes: `response_size_bytes`.
  - No suffix for gauges: `active_connections`, `queue_depth`.
- Stable names. Renaming a metric breaks dashboards and alerts.

### Types (Prometheus / OpenTelemetry vocabulary)
- **Counter:** monotonically increasing. Requests, errors, bytes processed.
- **Gauge:** can go up or down. Active connections, queue depth, memory in use.
- **Histogram:** distribution of values. Request latency, response size.
- **Summary:** like histogram but with client-side quantiles (rarely the right choice; histograms are preferred for aggregation).

### Cardinality discipline
- **High-cardinality labels destroy your bill and your query performance.**
- Never label with: user ID, session ID, request ID, full URL, raw error message, IP address.
- Bound cardinality: status code (~50), HTTP method (~7), route template (`/users/:id` not `/users/123`), service name, environment.
- Rule of thumb: if a label can have >1000 distinct values, it's a trace attribute, not a metric label.

### What to instrument
- **Every external call** (DB, cache, queue, third-party API): duration histogram + outcome counter.
- **Every production endpoint on a request path:** request counter, duration histogram; add an in-flight gauge where saturation matters. Internal tools and dev spikes are exempt until they take production traffic.
- **Every queue:** depth gauge, enqueue/dequeue counters, age histogram.
- **Every background job:** runs counter, duration histogram, outcome counter.
- **Resource pools** (DB connections, thread pools): in-use, idle, waiters.
- **Business metrics** that tie tech to outcomes: signups/min, payments_total.

### Anti-patterns
- Logging counts and reading them back from logs. Use a counter.
- One giant histogram per service. Split by route/operation.
- Resetting counters. Counters are monotonic; use rate() in queries.

## Tracing (OpenTelemetry)

### When traces matter most
Distributed systems where one user request crosses 3+ services. Latency and errors are felt at the request level; traces show *where* in the chain.

### What to capture
- **Span per logical unit of work.** HTTP handler, DB query, cache lookup, external API call, queue operation, significant in-process function.
- **Span attributes:** user ID (or hashed), tenant ID, route, query type, status code, error class. These are high-cardinality but cheap in trace storage (sampled).
- **Events** for milestones inside a span: cache miss, retry attempt, validation failure.
- **Links** between spans across async boundaries (queue producer → consumer).

### Propagation
- **W3C Trace Context** (`traceparent`, `tracestate` headers) — the modern standard.
- **B3** is acceptable for legacy interop.
- Propagate across HTTP, gRPC, queues, and async tasks. Missing propagation = broken traces.

### Sampling
- **Head-based sampling** (decide at root): cheap, biases toward common traffic.
- **Tail-based sampling** (decide at trace end): catches all errors and slow traces; needs a collector.
- Production starting point: tail-based, keep 100% of errors, 100% of slow (>p99), 1–5% of normal traffic.

### Exemplars
- Link metric histogram buckets to representative trace IDs. Click a slow histogram bucket → jump to a real slow trace. Most modern stacks (Prometheus + OTel) support this.

## Logging (operational view)

Reiterating and extending `CLAUDE.md §12`:

- **Structured JSON in production.** No printf strings.
- **Levels:**
  - `debug`: dev only; never on by default in prod.
  - `info`: lifecycle events (server start, scheduled job ran).
  - `warn`: recoverable issue worth noticing (retry, fallback used).
  - `error`: operation failed; needs investigation.
  - `fatal`: process must exit.
- **Every log line in a request path includes `trace_id` and `span_id`.** Without these, logs are unsearchable in a distributed system.
- **Sample debug logs** in production if kept on at all. `info` and above unsampled.
- **No PII or secrets in logs.** Mask in the logger, not in every call site.

### Don't log what a metric tells you better
- Bad: `info("request took 423ms")` — use a histogram.
- Bad: `info("queue size now 1532")` — use a gauge.
- Good: log the *outliers* with context. The metric tells you *that* it's slow; the log tells you *why* this one was.

## Health checks

Three distinct checks, three distinct meanings:

- **Liveness:** is the process alive and not deadlocked? Cheap; restart on failure.
- **Readiness:** is the process ready to serve traffic? Reflects dependency status (DB connection, cache warmed, config loaded).
- **Startup** (Kubernetes): for slow-starting apps that need a long grace period.

A health check that always returns 200 is worse than no health check — it gives false confidence. A readiness check **should** reflect whether this replica can serve — which usually means checking the dependencies it cannot function without. **Beware amplification:** if every replica shares one dependency, a dependency blip that flips all readiness probes at once can pull the whole service out of rotation and turn a partial degradation into a full outage. When a dependency is shared (not per-replica), prefer a circuit breaker / cached-status check over a live probe on every readiness call, or degrade gracefully instead of reporting unready. (The docker and kubernetes skills point here for the mechanics.)

## Alerts

### SLO-driven alerting
Define a Service Level Objective per critical user journey: e.g., "99.9% of checkout requests succeed in under 500ms over 30 days."

Alert on **error budget burn rate**, not raw thresholds:
- Fast burn (consuming month's budget in <1h) → page immediately.
- Slow burn (consuming month's budget in <3 days) → ticket, fix during the week.

This pages on real user pain, not cosmetic spikes.

### What NOT to alert on
- Raw CPU usage as a proxy for user pain — page on SLO burn instead. Sustained CPU **saturation** (e.g. ≥90% for 15+ min, or run-queue depth) IS worth a ticket/alert when tied to a capacity SLO: it precedes latency collapse. The rule is "don't page on a cosmetic CPU spike," not "never alert on CPU."
- Container restarts. (One restart isn't an outage; a pattern of restarts is.)
- Individual deploys, log lines, or low-level events.
- Anything you wouldn't want to be woken at 3 AM for.

### Alert hygiene
- Every alert has: a runbook URL, an owner, a severity, a precise meaning.
- Alerts that fire and resolve without human action are noise — fix the alert or the system.
- Track: false positive rate, time to acknowledge, time to resolve. They are leading indicators of operational health.

## Dashboards

- **One dashboard per service**, owned by the team that owns the service.
- Top of dashboard: golden signals.
- Below: per-endpoint or per-operation breakdown.
- Below: dependencies (DB, cache, queue, downstream services).
- Below: business metrics tied to this service.

Every panel answers a question someone asks during an incident. If a panel never answers a question, delete it.

## Tooling (2026 baseline)

- **Instrumentation:** OpenTelemetry SDKs everywhere. Vendor-agnostic; export to whatever backend.
- **Metrics backend:** Prometheus + remote-write to long-term storage (Mimir, Thanos, Cortex), or vendor (Datadog, New Relic, Honeycomb).
- **Trace backend:** Tempo, Jaeger, or vendor.
- **Log backend:** Loki, Elasticsearch, or vendor.
- **Visualization:** Grafana for OSS stacks; vendor's UI for SaaS.
- **Collector:** OpenTelemetry Collector as the universal pipeline (parsing, sampling, routing).

## Done criteria (in addition to CLAUDE.md §14)

- [ ] New production endpoint/operation has request counter and duration histogram (in-flight gauge where saturation matters).
- [ ] External call instrumented with duration + outcome.
- [ ] Errors increment a counter with labels (type, cause), not just logged.
- [ ] Trace context propagated end-to-end through the change.
- [ ] Log lines in request paths include `trace_id`.
- [ ] No high-cardinality labels (user ID, raw URL, error message text).
- [ ] Health check (if added/modified) reflects real dependency status.
- [ ] If alerting added: runbook, owner, severity, SLO basis specified.
- [ ] Dashboard updated if a new operation is user-visible.
