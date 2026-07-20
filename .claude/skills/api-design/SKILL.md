---
name: api-design
description: >-
  Use when designing or changing a public API, REST endpoint, GraphQL schema,
  RPC method, or service contract — versioning, compatibility, deprecation,
  pagination, error contracts. Trigger: "add an endpoint", "design the API",
  "breaking change", "OpenAPI", or files under api/, routes/, schema.graphql.
  Do NOT use for reviewing an API change before merge (api-review) or FastAPI
  code review (fastapi-review).

---

# API Design & Backwards Compatibility

Extends `CLAUDE.md`. When this skill loads, its rules and Done criteria apply on top of the universal baseline.

## Versioning rules

- **All externally-exposed APIs are versioned** from day one. URL path (`/v1/`), header (`Accept: application/vnd.company.v1+json`), or media type. Pick one and apply consistently.
- **Semantic versioning** for public APIs:
  - **Major:** breaking change (renamed/removed field, new required field, changed semantics).
  - **Minor:** backwards-compatible feature (new endpoint, new optional field).
  - **Patch:** bug fix that preserves contract.
- Internal APIs between services owned by the same team can be unversioned, but breaking changes still require coordination.

## What counts as a breaking change

**Breaking (requires major version bump and deprecation cycle):**
- Renaming or removing a field, parameter, header, or endpoint.
- Adding a new required field to a request.
- Changing a field's type, format, or units.
- Tightening validation (e.g., shrinking max length).
- Changing default values that callers depend on.
- Changing error codes or error semantics.
- Changing pagination, sorting, or filtering defaults.
- Removing or restricting an enum value the API previously returned.

**Non-breaking (safe to add in a minor version):**
- Adding a new optional field to a request.
- Adding a new field to a response.
- Adding a new endpoint.
- Adding a new optional query parameter.
- Loosening validation.
- Adding a new enum value the API may return — **but only if** clients are expected to ignore unknown values (state this in the contract).

## Deprecation cycle

When a breaking change is necessary:

1. **Announce** in a changelog and migration guide. Include the date when the deprecated path will be removed.
2. **Add the new endpoint/field/version** alongside the old. Both work.
3. **Mark old as deprecated:**
   - REST: `Sunset: <http-date>` response header (RFC 8594) for the removal date; `Deprecation: <http-date>` header (RFC 9745, 2025) to signal the field/endpoint is deprecated. They are two different RFCs — don't attribute both to 8594.
   - OpenAPI: `deprecated: true` on the operation/field.
   - GraphQL: `@deprecated(reason: "use Foo.bar")`.
4. **Track usage** of the deprecated path. Reach out to active consumers.
5. **Minimum 6-month deprecation period** for public APIs (longer for enterprise consumers).
6. **Remove** only after: deprecation period elapsed, usage at zero or known consumers acknowledged.

Never remove without a deprecation cycle, even if you "know" no one uses it.

## REST conventions

### Resources
- **Nouns, plural, lowercase, kebab-case for multi-word:** `/users`, `/order-items`.
- **Hierarchical only when the relationship is true containment:** `/users/{id}/orders` only if orders cannot exist without a user.
- **Avoid deep nesting:** `/users/{u}/orders/{o}/items/{i}` is a smell. Top-level `/order-items?order_id=...` is usually better.
- **No verbs in paths.** `POST /users` creates; `POST /users/{id}/promote` is acceptable for actions that don't fit CRUD.

### Methods and idempotency
- `GET` — safe and idempotent. Never has side effects.
- `PUT` — idempotent replace. Same request twice = same result.
- `DELETE` — idempotent. Deleting an already-deleted resource returns 204 or 404 consistently.
- `POST` — non-idempotent create or action.
- `PATCH` — partial update; specify the patch format (RFC 7396 merge or RFC 6902 JSON Patch).

### Status codes (use precisely)
- `200 OK` — success with body.
- `201 Created` — resource created; include `Location` header.
- `202 Accepted` — async accepted; include polling URL.
- `204 No Content` — success without body.
- `400 Bad Request` — client validation failed; include error details.
- `401 Unauthorized` — missing or invalid auth.
- `403 Forbidden` — authenticated but not allowed.
- `404 Not Found` — resource doesn't exist (or shouldn't be visible to caller).
- `409 Conflict` — state conflict (duplicate, version mismatch).
- `410 Gone` — was here, deliberately removed.
- `422 Unprocessable Entity` — well-formed but semantically invalid (some teams prefer this over 400).
- `429 Too Many Requests` — rate-limited; include `Retry-After`.
- `5xx` — server error; never use for client-caused failures.

### Error responses
Use a consistent shape for all errors. RFC 9457 (Problem Details) is the standard:
```json
{
  "type": "https://api.example.com/problems/insufficient-funds",
  "title": "Insufficient funds",
  "status": 402,
  "detail": "Account balance is 5.00; requested amount is 10.00.",
  "instance": "/transfers/abc123",
  "code": "INSUFFICIENT_FUNDS",
  "errors": [
    {"field": "amount", "message": "exceeds balance"}
  ]
}
```
- `code` is machine-readable, stable across versions.
- `detail` is human-readable, may change.
- Never expose stack traces, internal IDs, SQL, or paths in errors.

### Pagination
- **Cursor-based** (preferred) for large or growing datasets:
  ```json
  {"items": [...], "next_cursor": "eyJp..."}
  ```
- **Offset/limit** acceptable for small, bounded datasets only.
- **Always include** total count only when cheap; omit if computing it requires a full scan.
- **Page size:** sensible default (e.g., 20), explicit max (e.g., 100). Reject larger.

### Filtering, sorting, search
- Filter via query params: `?status=active&created_after=2024-01-01`.
- Sort: `?sort=-created_at,name` (`-` prefix for descending).
- Search: `?q=...` for full-text.
- Document allowed values; reject unknown filters loudly.

### Other headers
- **Idempotency:** `Idempotency-Key` header on `POST` for safe retries.
- **Conditional requests:** `ETag` + `If-Match` for optimistic concurrency.
- **Rate limits:** `X-RateLimit-Limit`/`X-RateLimit-Remaining`/`X-RateLimit-Reset` are a widespread **vendor convention** (GitHub, Stripe, Twitter), not an IETF standard; the active IETF work (`draft-ietf-httpapi-ratelimit-headers`) standardizes un-prefixed `RateLimit`/`RateLimit-Policy` with different semantics. Pick one style and document it; don't present the `X-` headers as a finalized standard.
- **Tracing:** propagate `traceparent` (W3C Trace Context).

## GraphQL conventions

- **Schema-first** design. The schema is the contract; resolvers fulfill it.
- **No nullable fields by default**, but be honest — make a field nullable if it can genuinely be absent.
- **Connections** for paginated lists (Relay spec):
  ```graphql
  type UserConnection {
    edges: [UserEdge!]!
    pageInfo: PageInfo!
  }
  ```
- **Mutations return the modified resource**, not a boolean.
- **Custom scalars** for typed values: `EmailAddress`, `URL`, `DateTime`, `UUID`.
- **`@deprecated`** for field deprecation; never silently remove.
- **Persisted queries** in production to control attack surface.
- **Depth and complexity limits** on every server (prevent malicious deep queries).
- **Field-level authorization** — the resolver is the boundary, not the gateway.

## Documentation

Every public endpoint documents:
- Path, method, purpose.
- Request: headers, params, body schema, examples.
- Response: status codes, body schema, examples.
- Errors: codes and meanings.
- Auth: required scopes/roles.
- Rate limits.
- Idempotency behavior.
- Deprecation status (if any).

Tooling: OpenAPI 3.1 for REST, GraphQL SDL with generated docs (e.g., GraphiQL, Voyager). Generate docs from the same source as validation — drift between docs and reality is the worst kind of bug.

## Compatibility testing

- **Contract tests** (Pact or OpenAPI-validated mocks) at the consumer-provider boundary.
- **Schema diff** in CI: compare new schema to baseline, flag breaking changes.
- For GraphQL: `graphql-inspector` for schema diffing.
- For OpenAPI: `oasdiff` or `openapi-diff`.
- Block PRs that introduce undocumented breaking changes.

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Endpoint/field follows project naming conventions.
- [ ] No breaking change without major version bump and deprecation entry.
- [ ] Errors use the project's standard error shape with stable `code`.
- [ ] Pagination, filtering, sorting follow project conventions.
- [ ] OpenAPI / GraphQL schema updated in the same PR as the implementation.
- [ ] Schema diff CI step passes (or breaking change is intentional and documented).
- [ ] Auth and rate limit requirements documented.
- [ ] Idempotency behavior documented for state-changing endpoints.
- [ ] Changelog entry added for any change visible to consumers.
