---
name: python-refactor
description: Use when restructuring existing Python code without changing behavior — renames, extract function/module, moving code between modules, untangling imports. Trigger on phrases like "refactor this", "extract this into a module", "rename this function everywhere", "split this file", "restructure this module". Behavior preservation is mandatory and test-proven. Do NOT use for architecture rewrites or module redesign (out of scope by policy), new features, bug fixes (fix first, refactor separately), or performance work (python-performance).
---

# Python Refactor

Extends `CLAUDE.md` §9 (Refactoring, Scope & Diff Discipline) — the canonical rules: preserve behavior, surgical edits, prove preservation with tests passing before AND after. The architecture boundary is canonical in [repository-cleanup](../repository-cleanup/SKILL.md): no architecture rewrites, no splitting/merging business modules, no framework swaps — restated here as the hard scope line for any refactor.

## Purpose

A refactor that changes behavior is a bug with good intentions. This workflow makes each step mechanical, reviewable, and provably behavior-preserving.

## When to use

- Renames, extract-function/extract-module, moving code to its right home, deduplicating copies, untangling import knots.

## When NOT to use

- Architecture redesign, layer introduction, framework replacement — out of scope (canonical: [repository-cleanup](../repository-cleanup/SKILL.md) architecture boundary).
- Bug fixing (fix on its own commit first — `CLAUDE.md` §9: mention, don't silently fix), features, performance (→ python-performance).

## Workflow

1. **Characterize first.** The code to be refactored has tests proving current behavior. None exist → write characterization tests BEFORE touching anything (pin current outputs, even odd ones — behavior, not ideals; authoring: [testing](../testing/SKILL.md)). For a trivial tool-assisted rename with existing passing tests, running those tests is sufficient characterization.
2. **One mechanical transform per commit** — a rename, an extract, a move. Never mixed, never combined with logic edits. (Move first, rename later — same discipline git-hygiene applies to files.)
3. **Update every reference in the same commit** as the transform — imports, `__all__`, entry points, string references (task names, dynamic imports, config values pointing at dotted paths).
4. **Keep old import paths working during multi-step moves** — a re-export shim at the old location (`from new.home import thing`) until all callers migrate, then remove the shim as its own commit.
5. **Verify after every commit** — same assertions pass before and after, plus the applicable command set ([verification](../verification/SKILL.md)). A changed assertion means it wasn't a refactor.
6. **Watch the dynamic edges** — `getattr` chains, scheduler entries (SQL Agent, Task Scheduler, cron) calling `python path/to/script.py`, Airflow callables, pickled objects: these break on rename/move without any import error. Search for the OLD dotted path and file path as strings before declaring done.

## Core rules

- Behavior preservation over structure — always (`CLAUDE.md` §0, §9).
- Smallest step that compiles and passes — no "while I'm here" edits (§9).
- Public API of the package unchanged unless the refactor's explicit goal says otherwise; then it is an api-design/deprecation question, not a refactor.

## Cross-references

- [repository-cleanup](../repository-cleanup/SKILL.md) — architecture boundary (canonical), file-level moves in cleanups
- [testing](../testing/SKILL.md) — characterization tests
- [verification](../verification/SKILL.md) — per-commit verification and failure protocol
- `CLAUDE.md` §9 — canonical refactoring discipline

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Tests existed (or were written) before the first transform; same assertions green before and after.
- [ ] One transform per commit; references (incl. string/dynamic ones) updated in the same commit.
- [ ] No behavior, API, or architecture change smuggled in.
