---
name: python-performance
description: Use when Python code is measurably too slow or memory-hungry and needs optimization — profiling, choosing what to fix, verifying the win. Trigger on phrases like "this script is slow", "speed this up", "optimize this function", "memory error on big file", "profile this". Covers measure-first discipline, the optimization order, and chunked processing for large data. Do NOT use for general code review (python-review), refactoring without a measured goal (python-refactor), or SQL query tuning (database-review).
---

# Python Performance

Extends `CLAUDE.md` (especially §14 performance verification, §19 batching). Owns the optimization DISCIPLINE for Python. Cleanup work never optimizes (canonical: [repository-cleanup](../repository-cleanup/SKILL.md) objective) — this skill is for explicit, measured performance goals.

## Purpose

Unmeasured optimization trades readability for imaginary wins. Every change here starts with a profile and ends with a benchmark.

## When to use

- A concrete slowness/memory complaint with a reproducible case; capacity planning for growing data volumes.

## When NOT to use

- No measurement exists yet and none is planned — measure first or decline.
- The slow part is SQL → [database-review](../database-review/SKILL.md) (execution plans). Style/correctness → python-review.

## Core rules

- **Profile before touching anything.** `cProfile`/`profile` for call costs, `py-spy` for live processes, `tracemalloc` for memory. The hotspot is where the profile says — not where intuition points.
- **Benchmark before/after on the same data;** the win is stated with numbers (canonical: `CLAUDE.md` §14 performance-sensitive row). No number, no merge.
- **Optimize in this order** (stop at the first sufficient win):
  1. **Algorithm/data structure** — O(n²) membership tests on lists → sets/dicts; repeated work → compute once.
  2. **I/O batching** — fewer round-trips beats faster loops (canonical: `CLAUDE.md` §19 bulk-over-loops); batch DB writes, reuse HTTP sessions/connections.
  3. **Vectorization** — pandas/numpy column operations instead of Python-level row loops; `itertuples` over `iterrows` when looping is unavoidable.
  4. **Caching** — `functools.lru_cache`/explicit cache WITH a stated invalidation story; an unbounded cache is a memory leak with good PR.
  5. **Concurrency last** — threads/`asyncio` for I/O-bound, processes for CPU-bound (the GIL limits threads to I/O wins); concurrency multiplies failure modes, so it comes after 1–4.
- **Large files stream in chunks** — generators, `pandas.read_*(chunksize=...)`, openpyxl `read_only=True`; loading a multi-hundred-MB file whole is a finding, not a necessity.
- **Readability survives.** If the optimized version needs a comment to be believed, keep the clear version unless the number justifies it (`CLAUDE.md` §0: correctness and architecture beat style — and style beats vanity wins).

## Workflow

Reproduce slow case → profile → name the hotspot with data → apply the lowest rung of the order that fixes it → benchmark before/after → keep the profile + numbers in the PR → verify behavior unchanged ([verification](../verification/SKILL.md), [testing](../testing/SKILL.md) for regression tests).

## Cross-references

- [database-review](../database-review/SKILL.md) — when the hotspot is the query, not the Python
- [verification](../verification/SKILL.md), [testing](../testing/SKILL.md) — proving behavior unchanged
- `CLAUDE.md` §14 (benchmark requirement), §19 (batching)

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Profile evidence names the hotspot; fix targets it.
- [ ] Before/after benchmark on identical data recorded in the PR.
- [ ] Behavior unchanged (tests green); no unbounded caches introduced.
