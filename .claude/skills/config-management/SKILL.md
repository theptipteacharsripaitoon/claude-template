---
name: config-management
description: Use when deciding where configuration lives and how code loads it — env hierarchy, config files vs env vars, Pydantic Settings, per-environment overrides, config for scheduler-run scripts. Trigger on phrases like "where should this setting live", "move this to config", "add an environment variable", "settings class", "dev vs prod config". Covers the precedence hierarchy and typed loading. Do NOT use for the env-var baseline rules (CLAUDE.md §7 owns validate-at-startup and .env.example), secret handling (security-review), or writing .env.example docs (documentation).
---

# Config Management

Extends `CLAUDE.md` §7 Environment Variables — canonical there: read config once at startup into a typed object, validate presence and fail loud, document every var in `.env.example`, group by prefix. This skill owns WHERE configuration lives and the loading pattern.

## Purpose

Config scattered across hardcoded constants, ad-hoc `os.environ` reads, and per-machine files is why "works on my machine" exists. One hierarchy, one typed loader.

## When to use

- Introducing a new setting; consolidating duplicated constants (the cleanup Phase-3 module sends target-location decisions here); making a script deployable across environments.

## When NOT to use

- Secret discovery/rotation → [security-review](../security-review/SKILL.md). `.env.example` content standards → [documentation](../documentation/SKILL.md). Universal env-var rules → `CLAUDE.md` §7.

## Core rules

- **Precedence hierarchy, lowest to highest:** defaults in code → config file (committed, non-secret) → environment variables / `.env` → explicit overrides (CLI flags). Every project documents this order; a value settable in two layers without documented precedence is a finding.
- **What goes where:**
  - *Code defaults* — safe, environment-independent values only.
  - *Config files* (`config/` dir; e.g. `base.yaml` + `prod.yaml` overlays) — non-secret, environment-shaped values (batch sizes, feature flags, paths).
  - *Env vars / `.env`* — deployment-specific values and ALL secrets (canonical: `CLAUDE.md` §7; never in config files, never committed).
- **Typed loader at the boundary** — Python: Pydantic `BaseSettings` (env prefix, `.env` support, `SecretStr` for secrets); one `Settings` object constructed at startup, passed explicitly — no `os.environ` reads scattered through business logic (canonical: §7).
- **No environment conditionals in code** — `if env == "prod"` logic is config expressed as code; the overlay file carries the difference instead (same principle airflow-layout applies to DAGs).
- **Scheduler-run scripts load config by explicit absolute path,** never CWD-relative — SQL Agent, Task Scheduler, and cron start processes with surprising working directories. (Extraction INTO shared config for such scripts has its own safety rule — canonical: repository-cleanup's config-consolidation module.)
- **Changing a config value must not require a code change** in the same commit — if it does, it wasn't config.

## Cross-references

- [security-review](../security-review/SKILL.md) — secrets found in configs; rotation
- [documentation](../documentation/SKILL.md) — `.env.example` structure
- `CLAUDE.md` §7 Environment Variables — canonical baseline rules

## Done criteria (in addition to CLAUDE.md §14)

- [ ] New settings placed per the hierarchy; precedence documented.
- [ ] Loaded through the typed settings object; zero new scattered `os.environ` reads.
- [ ] No secrets in config files; `.env.example` updated (per §7/documentation).
- [ ] Scheduler-run entry points resolve config by explicit path.
