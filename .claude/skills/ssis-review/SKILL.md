---
name: ssis-review
description: >-
  Use when reviewing or hardening SSIS packages (.dtsx) — Data Flows, Derived
  Columns, connection managers — especially Thai data into SQL Server.
  Trigger: "review the dtsx", "Derived Column", "Thai characters look wrong",
  "dates are 543 years off". Do NOT use for pure T-SQL review
  (database-review) or Airflow pipelines (airflow-review).

---

# SSIS Package Review

Extends `CLAUDE.md`. Owns SSIS (`.dtsx`) review standards and the Thai-data production lessons. T-SQL inside packages is reviewed per [database-review](../database-review/SKILL.md); end-to-end pipeline questions per [etl-review](../etl-review/SKILL.md).

## Purpose

SSIS failures are usually invisible in the designer — expression quirks, encoding damage, calendar mix-ups, and packages that fight each other over locks. These are the review rules production taught.

## When to use

- Reviewing a new or changed `.dtsx`; debugging garbled Thai text or shifted dates after a load; hardening packages for scheduled production runs.

## When NOT to use

- Stand-alone T-SQL procs/queries → [database-review](../database-review/SKILL.md).
- Airflow-orchestrated pipelines → [airflow-review](../airflow-review/SKILL.md).

## Production lessons (canonical here unless marked)

- **Single-line Derived Column expressions.** Multi-line or deeply nested expressions in Derived Column transforms are unreviewable in the designer, break diffs, and hide precedence bugs. One derivation per column, single line; anything more complex moves to upstream SQL or a Script Component where it gets real code review.
- **Invisible-Unicode cleanup for Thai data.** Strip zero-width and invisible characters BEFORE trim/compare/join on Thai text — at minimum: ZWSP (U+200B), ZWNJ (U+200C), ZWJ (U+200D), BOM/ZWNBSP (U+FEFF), NBSP (U+00A0). Two visually identical strings that refuse to join means this. Keep Thai text `DT_WSTR` (Unicode) end to end — a `DT_STR` round-trip through a mismatched codepage silently destroys characters.
- **Buddhist Era date conversion.** Thai sources commonly store พ.ศ. (BE = CE + 543). Convert exactly once, at the ingestion boundary, and validate ranges after conversion — a year ≥ 2500 in a CE column is an unconverted BE value; a birth year before 1900 may be a double conversion. Never mix calendars in one column; record per source which calendar it uses.
- **Swap-table publish** — load staging, verify, publish by atomic swap (canonical: [database-review](../database-review/SKILL.md)).
- **Single-UPDATE deadlock avoidance** — parallel Data Flow paths or Execute SQL Tasks must not issue overlapping UPDATEs against the same table; consolidate into one set-based UPDATE or serialize with precedence constraints (canonical: [database-review](../database-review/SKILL.md)).

## Package hygiene

- **Connections via project parameters/environments** — no hardcoded server, database, or file path inside the package.
- **`ProtectionLevel = DontSaveSensitive`;** secrets supplied at runtime by environment/config, never saved into the `.dtsx` (canonical: `CLAUDE.md` §7).
- **OnError event handling and logging enabled;** every Data Flow error output routed somewhere reviewable (error table/file with the row and the reason). Silent row redirection is a finding (`CLAUDE.md` §12 — fail visibly).
- **One package = one unit of work;** package name says what it loads (file-naming spirit: [sql-layout](../sql-layout/SKILL.md)).
- **`.dtsx` in version control:** the XML diffs are noisy, so the commit message must say what functionally changed; keep layout-only designer saves out of logic commits (`CLAUDE.md` §9).

## Workflow

1. Connections and parameters — nothing hardcoded, nothing sensitive saved.
2. Walk each Data Flow: Derived Column expressions (single-line), data types on Thai text (`DT_WSTR` throughout), error outputs routed.
3. Cross-package lock interaction — apply the deadlock lesson to anything else writing the same tables.
4. T-SQL inside Execute SQL Tasks / sources → [database-review](../database-review/SKILL.md).
5. Run against sample Thai data; verify text and dates survive the round-trip unchanged. Blocking rules: [verification](../verification/SKILL.md).

## Cross-references

- [database-review](../database-review/SKILL.md) — swap-table publish, deadlock avoidance, T-SQL review
- [sql-layout](../sql-layout/SKILL.md) — SQL file and naming conventions around the packages
- [verification](../verification/SKILL.md) — verifying fixes; blocking policy
- `CLAUDE.md` §7 (secrets), §12 (fail visibly)

## Done criteria (in addition to CLAUDE.md §14)

- [ ] All five production lessons checked against the package.
- [ ] No hardcoded connections; `DontSaveSensitive` set; no secrets in the dtsx.
- [ ] Every error output routed and reviewable; OnError logging on.
- [ ] Thai sample data round-trips with text and dates intact.
