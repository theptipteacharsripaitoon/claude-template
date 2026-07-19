---
name: fastapi-review
description: >-
  Use when reviewing or hardening a FastAPI service — routes, dependencies,
  Pydantic models, async handlers, startup, error handlers. Trigger: "review
  the FastAPI app", "async route", "Depends", "response_model". Do NOT use for
  API contract design (api-design) or generic Python review (python-review).

---

# FastAPI Review

Extends `CLAUDE.md`. Composition skill: the contract is reviewed per [api-review](../api-review/SKILL.md), the Python per [python-review](../python-review/SKILL.md), config per [config-management](../config-management/SKILL.md), the container per [docker-review](../docker-review/SKILL.md), auth per [web-security](../web-security/SKILL.md). This skill owns only what is FastAPI-specific.

## Purpose

FastAPI makes it easy to ship an app that works in dev and collapses under load — one misdeclared `async def` with a blocking driver stalls the whole event loop. These are the framework-specific review points.

## When to use

- Reviewing FastAPI route/dependency/middleware changes; hardening a service before production; diagnosing "slow under load".

## When NOT to use

- Contract questions (breaking changes, versioning, error shape) → [api-review](../api-review/SKILL.md) / api-design.
- Generic Python findings → [python-review](../python-review/SKILL.md).

## FastAPI-specific checks (owned here)

1. **Async declaration matches the body.** Blocking work (sync DB driver, `requests`, heavy CPU) inside `async def` stalls the event loop — the #1 FastAPI production bug. Either use truly async clients, or declare the route plain `def` so FastAPI runs it in the threadpool. (General blocking-in-async trap: canonical [python-review](../python-review/SKILL.md).)
2. **Pydantic at both edges.** Request bodies/queries validated by models (boundary rule: `CLAUDE.md` §7); every route declares `response_model` (or a typed return) so responses are filtered and documented — never raw ORM objects or ad-hoc dicts.
3. **Dependencies own resources.** DB sessions/clients come from `Depends` with `yield` and release in the teardown path (`CLAUDE.md` §19 release-what-you-acquire); auth is a dependency, not per-route copy-paste (implementation standards: [web-security](../web-security/SKILL.md)); no mutable request-scoped state in module globals or an `app.state` grab-bag.
4. **Error handlers keep the contract.** Exception handlers map failures to the project's standard error shape (canonical: api-design via [api-review](../api-review/SKILL.md)); no default 500s with stack traces reaching clients (`CLAUDE.md` §12).
5. **Settings are injected.** One typed `Settings` (canonical: [config-management](../config-management/SKILL.md)) provided via dependency; `os.environ` reads inside routes are findings.
6. **Startup fails loud.** Config validated at startup (`CLAUDE.md` §7); health/readiness endpoints reflect real dependency state (standard: [observability](../observability/SKILL.md)).
7. **Routers carry the versioning scheme** (`/v1` prefix or equivalent) and tags so the generated OpenAPI stays accurate (contract rules: api-design).

## Workflow

Contract diff → [api-review](../api-review/SKILL.md) checklist. Code diff → [python-review](../python-review/SKILL.md) checklist + items 1–7 above. Config/container touched → [config-management](../config-management/SKILL.md) / [docker-review](../docker-review/SKILL.md). Verify the changed routes actually execute (integration test hitting the endpoint — `CLAUDE.md` §14; blocking policy: [verification](../verification/SKILL.md)).

## Cross-references

- [python-review](../python-review/SKILL.md) · [api-review](../api-review/SKILL.md) · [config-management](../config-management/SKILL.md) · [docker-review](../docker-review/SKILL.md)
- [web-security](../web-security/SKILL.md) — auth/sessions/CORS implementation
- [security-review](../security-review/SKILL.md) — secrets discovered in service config, env files, or images
- [observability](../observability/SKILL.md) — health checks, metrics
- [verification](../verification/SKILL.md) — verifying the changed paths
- `CLAUDE.md` §7, §12, §19

## Done criteria (in addition to CLAUDE.md §14)

- [ ] No blocking calls inside `async def` routes; declarations match bodies.
- [ ] Every route has validated input models and a declared response model.
- [ ] Resources released via yield-dependencies; settings injected, not read ad hoc.
- [ ] Errors conform to the standard shape; startup validates config; health endpoints truthful.
