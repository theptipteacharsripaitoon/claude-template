# Config Consolidation (Cleanup Phase 3 — optional, opt-in)

Module of [repository-cleanup](../SKILL.md). This is the ONLY permitted exception to the cleanup Architecture boundary, and only within the rules below.

## Preconditions (ALL must be true)

1. Cleanup Phase 2 is fully complete and all verification passed.
2. The user EXPLICITLY requests Phase 3.
3. The Phase 3 plan below has been separately approved.

## Planning (read-only first)

From the duplicate analysis in `CLEANUP_PLAN.md`, build the table:

`Constant/Variable | Files & Values Found | Identical? | Proposed Config Location | Risk`

STOP and wait for approval of this table before touching any code.

## Extraction rules

- Extract a duplicated constant into a shared config ONLY when its value is byte-identical across ALL occurrences.
- If values differ between files: DO NOT merge. Report the difference and let the user decide the canonical value. Never choose a value yourself.
- Never extract from standalone scripts invoked by external schedulers (SQL Agent, Windows Task Scheduler, cron, UiPath) unless the config import path is verified to work in that execution context.
- Never create import cycles. If extraction would create one, skip and report.
- Secrets discovered during extraction go to `.env` (with `.env.example` updated — format: [documentation](../../documentation/SKILL.md)), NEVER into config files. Never print their values (canonical: [security-review](../../security-review/SKILL.md)).
- Do not change types, formats, or evaluation timing of any value.
- Target config locations follow the repository's existing convention. (A dedicated `config-management` skill is planned; until it exists, decide per repo convention and record the decision in `CLEANUP_PLAN.md`.)

## Execution rules

- One constant group per commit.
- Run applicable verification after EVERY commit ([verification](../../verification/SKILL.md)); failures follow the same BLOCKING rules as Phase 2.
- Log every extraction in `.claude/CLEANUP_EXECUTION.md`.
