---
name: python-review
description: >-
  Use when reviewing Python code changes before they ship — correctness, error
  handling, typing, resource safety, async discipline. Trigger: "review this
  Python code", "is this function safe", "check my Python changes". Do NOT use
  for restructuring (python-refactor), performance (python-performance), or
  writing tests (testing).

---

# Python Review

Extends `CLAUDE.md`. The base standards are owned elsewhere and only CHECKED here: code quality §6 (type hints, `logging` not `print`, context managers), errors §12, reliability §19, security §7, tests → [testing](../testing/SKILL.md), dependencies → [dependency-review](../dependency-review/SKILL.md). This skill owns the Python-specific review checklist.

## Purpose

Python fails quietly: a broad `except`, a mutable default, a blocking call inside async — all invisible until production. The checklist makes a reviewer look at each known trap on every change.

## When to use

- Reviewing a Python PR/diff; hardening a script before it gets scheduled; second-opinion on a module you inherited.

## When NOT to use

- Project structure → [python-layout](../python-layout/SKILL.md). Refactor mechanics → python-refactor. Optimization → python-performance. Authoring tests → [testing](../testing/SKILL.md).

## Review checklist

**Baseline compliance (canonical sources, verify not restate):**
1. Signatures typed; no unexplained `# type: ignore`; `logging` not `print`; `with` for every I/O resource (`CLAUDE.md` §6).
2. Errors: nothing swallowed, context preserved (`raise ... from e`), no exceptions as control flow (`CLAUDE.md` §12).
3. Reliability: timeouts on every outbound call, bounded retries, explicit encoding on file I/O (`CLAUDE.md` §19).
4. Security: input validated at the boundary, no secrets in code/logs (`CLAUDE.md` §7).

**Python-specific traps (owned here):**
5. **Mutable default arguments** (`def f(items=[])`) — shared state across calls; use `None` + assign inside.
6. **`except` breadth** — a bare `except:` or `except Exception` needs a written justification and must re-raise or fully handle; catching to log-and-continue is a silent failure (§12).
7. **Blocking in async** — `time.sleep`, sync HTTP/DB clients, heavy CPU inside `async def`: move to async clients or a thread/process pool.
8. **Late-binding closures in loops** (`lambda: x` inside `for x in ...`) — bind with a default arg.
9. **Logging calls build strings lazily** — `logger.info("x=%s", x)`, not f-strings, so disabled levels cost nothing and args aren't formatted on the hot path.
10. **`pathlib.Path` over string concatenation** for paths; no os.path/string mixing in new code.
11. **Truthiness traps** — `if x:` where `0`/`""`/`[]` are valid values; compare explicitly (`if x is None`).
12. **`datetime` correctness** — timezone-aware for real timestamps; no naive `utcnow()` in new code (`datetime.now(timezone.utc)`).
13. **Resource lifetime in generators** — a generator holding a file/connection open must be closed deterministically (context manager around consumption).

## Workflow

Walk the diff against items 1–13 → every finding cites the line and the rule → verify fixes per [verification](../verification/SKILL.md) (focused tests first, §15).

## Cross-references

- [python-layout](../python-layout/SKILL.md) — placement/structure questions found during review
- [dependency-review](../dependency-review/SKILL.md) — new/changed imports and manifests
- [verification](../verification/SKILL.md) — running the checks; blocking policy
- [testing](../testing/SKILL.md) — test quality for the change
- `CLAUDE.md` §6, §7, §12, §19 — canonical baseline standards

## Done criteria (in addition to CLAUDE.md §14)

- [ ] All 13 checklist items answered against the diff, findings cited by line.
- [ ] No unjustified broad excepts, mutable defaults, or blocking-in-async left.
- [ ] Baseline (§6/§7/§12/§19) verified, not assumed.
