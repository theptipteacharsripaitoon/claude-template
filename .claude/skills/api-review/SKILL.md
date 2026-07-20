---
name: api-review
description: >-
  Use when reviewing an API change before merge — breaking vs non-breaking,
  deprecation compliance, schema-diff evidence, contract tests. Trigger:
  "review this endpoint change", "is this a breaking change", "can we remove
  this field". Do NOT use for designing new APIs (api-design) or
  framework-level review (fastapi-review).

---

# API Review

Extends `CLAUDE.md`. The [api-design](../api-design/SKILL.md) skill owns ALL the standards — breaking-change classification, deprecation cycle, error shape, pagination, documentation requirements. This skill owns the review PROCESS: what evidence an API change must show before it merges.

## Purpose

API breakage ships as a small diff that looks harmless. Review is where "renamed a field" gets recognized as "broke every consumer" — before consumers find out.

## When to use

- Reviewing any PR that touches an externally-consumed contract: endpoints, response shapes, GraphQL schema, published event payloads.

## When NOT to use

- Designing endpoints/schemas from scratch → [api-design](../api-design/SKILL.md).
- FastAPI implementation specifics → fastapi-review.

## Review checklist (each item needs evidence)

1. **Classify every contract-visible change** against the breaking/non-breaking lists (canonical: [api-design](../api-design/SKILL.md)). "Probably fine" is not a classification.
2. **Breaking changes carry their process:** major version + deprecation entry + migration note, per the deprecation cycle (canonical: api-design). A breaking change without one is a BLOCKER.
3. **Schema-diff evidence in the PR** — the diff tool output (`oasdiff`/`openapi-diff`/`graphql-inspector` — tooling: api-design) attached or run in CI; reviewer does not eyeball-diff JSON.
4. **Error responses conform** to the project's standard shape with stable `code`s (canonical: api-design).
5. **Contract tests updated** on the touched boundary ([testing](../testing/SKILL.md) contract-testing section); consumers' expectations still pass.
6. **Docs move with the change** — OpenAPI/SDL updated in the same PR; changelog entry present for anything consumer-visible (canonical: api-design Done criteria).
7. **Auth and rate limits stated** for new/changed endpoints (design rules: api-design; implementation: web-security via the framework skill).
8. **Verify** the changed paths actually execute — schema validation and integration test per `CLAUDE.md` §14 public-API row; blocking policy: [verification](../verification/SKILL.md).

## Cross-references

- [api-design](../api-design/SKILL.md) — canonical standards this review checks against
- [testing](../testing/SKILL.md) — contract tests
- [verification](../verification/SKILL.md) — verification and blocking policy
- `CLAUDE.md` §14 — public-API verification row

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Every contract-visible change classified with evidence; breaking ones carry version + deprecation.
- [ ] Schema-diff output attached; contract tests green; docs and changelog in the same PR.
