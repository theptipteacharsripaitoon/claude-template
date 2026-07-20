---
name: testing
description: >-
  Use when writing, reviewing, or improving tests — unit, integration, e2e,
  fixtures, mocking, flakiness. Trigger: "write tests for", "add test
  coverage", "this test is flaky", "mock this", "fix the failing test". Do NOT
  use for choosing which verification commands to run after restructuring
  (verification) or reviewing non-test code (python-review).

---

# Testing (Advanced Patterns)

Extends `CLAUDE.md §10` (Testing Foundations). The basic rules (every feature ships with tests, never skip-to-pass, behavior-not-implementation, mock at the boundary) live there. This skill covers the deeper patterns.

## Test pyramid (target distribution)

- **~70% unit tests** — fast (<100ms each), pure logic, no I/O.
- **~20% integration tests** — module boundaries, real DB/queue/cache via testcontainers.
- **~10% end-to-end tests** — happy-path user journeys only; the smoke test layer.

The inverted pyramid (lots of E2E, few unit) is a common mistake. Symptoms: slow CI, flaky tests, high maintenance cost, low confidence per minute.

## What to test

- **Public APIs of every module** — never test private functions directly.
- **Branch coverage for business logic**, not line coverage chasing.
- **Boundary conditions:** empty, one, many, max, off-by-one, null, negative, unicode, very large.
- **Error paths and timeout/retry behavior**, not just happy paths.
- **Idempotency** for any retried operation.
- **Concurrency** for any code with shared state — race conditions hide in untested corners.

## What NOT to test

- Framework internals (e.g., that React rerenders, that the ORM saves a row).
- Implementation details — tests must survive refactors that preserve behavior.
- Log output, error message strings, or anything not part of the contract.
- Generated code, type definitions, trivial getters/setters.
- Private helpers as a workaround for not-quite-right public API design (fix the API instead).

## Modern techniques (use when they fit)

### Property-based testing
Use for pure functions with input domains: parsers, serializers, math, sort/dedup logic.

- **JS/TS:** [`fast-check`](https://github.com/dubzzz/fast-check)
- **Python:** [`hypothesis`](https://hypothesis.readthedocs.io)
- **Rust:** `proptest` or `quickcheck`

```python
from hypothesis import given, strategies as st

@given(st.lists(st.integers()))
def test_sort_is_idempotent(xs):
    assert sorted(sorted(xs)) == sorted(xs)
```

Catches edge cases (empty input, duplicates, max int, NaN) you'd never write by hand.

### Mutation testing
Use on critical business logic to validate that tests actually assert.

- **JS/TS:** [`stryker-mutator`](https://stryker-mutator.io)
- **Python:** [`mutmut`](https://github.com/boxed/mutmut) or `cosmic-ray`
- **Rust:** `cargo-mutants`

A mutant that survives = a test that doesn't actually check the thing. Aim for >80% mutation score on critical modules; do not chase 100%.

### Contract testing
Use at service boundaries instead of brittle multi-service E2E.

- [`Pact`](https://docs.pact.io) — consumer-driven contracts.
- OpenAPI-based contract validation as a lighter alternative.

The consumer asserts what it expects from the provider; the provider runs the consumer's contract as a test against its real implementation. Breakage shows up before deploy, not in production.

### Snapshot testing
- Only for stable serialized output: formatted JSON, schema exports, generated code.
- **Never for UI screenshots** — use visual regression (Chromatic, Percy, Playwright + `toHaveScreenshot`) for that.
- Snapshots that change frequently are noise; delete them.

### Testcontainers
Use real dependencies, not mocks, for integration tests.

- **JS/TS:** [`testcontainers`](https://node.testcontainers.org)
- **Python:** [`testcontainers-python`](https://testcontainers-python.readthedocs.io)
- Spin up real Postgres, Redis, Kafka, etc. in Docker for the test run.
- Slower than mocks but catches integration bugs that mocks hide (SQL dialect quirks, real serialization, version mismatches).

## Test hygiene

### Naming
- Pattern: `should_<behavior>_when_<condition>` or describe the behavior plainly.
  - ✅ `should_reject_login_when_password_expired`
  - ✅ `rejects expired passwords`
  - ❌ `test_login_1`, `test_user_service`
- The test name alone should tell you what broke when CI fails.

### Structure (Arrange-Act-Assert)
```python
def test_should_apply_discount_for_premium_users():
    # Arrange
    user = make_user(tier="premium")
    cart = make_cart(items=[make_item(price=100)])

    # Act
    total = checkout(cart, user)

    # Assert
    assert total == 90  # 10% premium discount
```
Blank lines separate the phases. One logical assertion per test (or one logical group).

### Fixtures vs factories
- **Fixtures** for static, shared setup (DB schema, test client). pytest fixtures, `beforeAll`.
- **Factories** for varying instances (`make_user(tier="premium")`). Use `factory_boy` (Python) or `fishery`/custom builders (TS).
- Avoid inline setup duplication — extract to a factory after the third repeat.

### Determinism
- No `Date.now()`, `time.time()`, `Math.random()`, real network.
- Inject a clock: `now: () => Date` — mock to a fixed timestamp in tests.
- Inject a random source with a fixed seed.
- Use `nock`/`responses` for HTTP, `fake-indexeddb` for browser storage, in-memory adapters for filesystems.

### Mocking discipline
- **Mock at the system boundary:** HTTP clients, DB drivers, message queues, time, FS.
- **Within your own codebase, prefer real implementations** within the same architectural layer. Mock your own modules only at explicit boundaries (port/adapter, hexagonal seam) or when the real dependency is non-deterministic, slow, or operationally expensive. Mocking everywhere tests the test, not the code.
- **Don't mock value objects** — use real instances.
- Verify behavior over interactions (avoid `expect(mock).toHaveBeenCalledWith(...)` when an output assertion would do).

## Flakiness policy

A flaky test is a broken test. Treat it as a P2 bug.

1. **Quarantine is a tracked, time-boxed exception — not a skip-to-green.** A quarantine is legitimate ONLY with all of: an approved tracking ticket, the test still **running in a non-blocking quarantine lane** (so it keeps producing signal), and a removal deadline. It never means deleting, `xit`/`@skip`-ing, or silencing the test to make a required gate pass — CLAUDE.md §2/§10 forbid weakening tests to reach green, and this is the same rule. If you cannot stand up a non-blocking lane, leave the test in the gate and fix it.
2. **Fix within one sprint** or delete. Never let it sit.
3. **Never retry to pass.** Retries hide real bugs (race conditions, timing assumptions, shared state).
4. **Track flake rate** as a team metric. >1% flakiness on a test suite is a fire.

Common flakiness sources:
- Timing assumptions (`sleep(1)` and hope).
- Test ordering dependencies (shared state in DB or globals).
- Real time (`Date.now()`), real network, real filesystem.
- Insufficient cleanup between tests.
- Async without proper `await` — promises resolved after assertions.

## Coverage philosophy

- **Coverage is a signal, not a goal.** 100% with weak assertions is worse than 70% with strong ones.
- Set a floor (e.g., 70%) and require new code to meet it.
- **Mutation score is a stronger quality metric** than line coverage for critical paths.
- Coverage drops on a PR are a smell — investigate before merging.

## E2E and visual

- **E2E:** Playwright (preferred 2026), Cypress as alternative. Test happy-path user journeys, not exhaustive logic.
  - Use stable selectors: `data-testid`, ARIA roles. Never CSS class names.
  - Run against a real-but-isolated environment with seeded data.
  - Keep <30 E2E tests; budget execution time, not count.
- **Visual regression:** Playwright `toHaveScreenshot()` or Chromatic for component libraries. Mask volatile regions (timestamps, animations).

## Performance & load

- Critical paths get a benchmark with a CI-tracked baseline (k6, Artillery, autocannon, or framework-specific benchmark suites).
- Regress >10% on a tracked metric = fail the build.
- Load tests live separately from unit/integration; run on a schedule, not per PR.

## Done criteria (in addition to CLAUDE.md §14)

- [ ] New tests follow Arrange-Act-Assert structure with descriptive names.
- [ ] Mocks placed at boundaries (HTTP, DB, time, FS) or at explicit architectural seams; not scattered across own modules.
- [ ] No timing assumptions (`sleep`, real `Date.now()`); time/random injected.
- [ ] No flaky behavior across 10 consecutive local runs.
- [ ] Boundary cases (empty, max, error) covered, not just happy path.
- [ ] If critical logic changed: mutation score still >80% on touched modules.
- [ ] If service boundary touched: contract tests updated.
- [ ] Coverage on touched files >= prior coverage.
