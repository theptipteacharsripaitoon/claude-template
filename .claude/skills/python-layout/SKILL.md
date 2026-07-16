---
name: python-layout
description: Use when structuring a Python project — package vs flat modules, where pyproject.toml settings live, __init__.py discipline, entry points, shared-library placement. Trigger on phrases like "structure this Python project", "where should this module go", "package layout", "organize the Python code", "make this importable". Covers Python-specific placement on top of the general project-layout skill. Do NOT use for general repo structure (project-layout), naming and import-order rules (CLAUDE.md §8), or reviewing code (python-review).
---

# Python Project Layout

Extends `CLAUDE.md`. General structure and project-type layouts are owned by [project-layout](../project-layout/SKILL.md); naming defaults, import grouping, and test co-location by `CLAUDE.md` §8. This skill owns only the Python-specific placement decisions.

## Purpose

Python projects drift into "a folder of scripts that import each other by accident." These rules make imports intentional and the project installable.

## When to use

- Turning loose scripts into a package; deciding package vs flat layout; placing shared utilities; wiring entry points; choosing where tool config lives.

## When NOT to use

- General repository structure or monorepo questions → [project-layout](../project-layout/SKILL.md).
- Reviewing Python code → python-review. Refactoring module boundaries → python-refactor.

## Core rules

- **`pyproject.toml` is the single config home** — project metadata, dependencies, and tool sections (`[tool.ruff]`, `[tool.mypy]`, `[tool.pytest.ini_options]`) live there, not in a constellation of `setup.cfg`/`.flake8`/`pytest.ini` files (one legacy file kept only if a tool cannot read pyproject).
- **Package directory = import name.** `mis_lib/` imports as `mis_lib`. Match `[project] name` to it (dashes in the dist name map to underscores in the import).
- **Respect the existing layout style** — keep flat layout if the project is flat; keep `src/` if it already uses `src/` (never force either — canonical: [project-layout](../project-layout/SKILL.md)).
- **`__init__.py` is a table of contents, not a program:** explicit re-exports (`__all__`) only; no I/O, no config loading, no heavy imports at package import time.
- **One module = one concern,** grouped by domain, not by type (`billing.py`, not `helpers2.py`). Unclear names (`utils.py` catch-alls, `new.py`, `test2.py`) are findings — naming review: [project-layout](../project-layout/SKILL.md).
- **Entry points over loose scripts:** runnable things are `[project.scripts]` console entries or `python -m package.module` — a script that is also imported by other code is two things and should be split.
- **Shared code is a real package** (installable or on an explicit `PYTHONPATH`), never reached by `sys.path.append("../somewhere")`.
- **Environment junk stays ignored:** `.venv/`, `__pycache__/`, `.pytest_cache/`, build artifacts — ignore-list mechanics: git-hygiene (add `.venv/` there if missing).

## Cross-references

- [project-layout](../project-layout/SKILL.md) — general structure, project types, migration strategy
- `CLAUDE.md` §8 — naming, import grouping, test co-location

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Tool config consolidated in `pyproject.toml` (or documented why not).
- [ ] No `sys.path` hacks; imports resolve from the package root.
- [ ] `__init__.py` files contain exports only — no side effects.
- [ ] Runnable scripts exposed as entry points or `-m` modules.
