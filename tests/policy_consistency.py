#!/usr/bin/env python3
"""Static consistency gate across CLAUDE.md, skills, and hook README.

Guards the inter-document invariants that prose-only enforcement keeps missing:
  1. No skill authorizes logging even a *prefix* of a secret/auth-header/token
     value. CLAUDE.md §7 says "never log secrets, auth headers, session tokens";
     a domain skill saying "token prefix only" is a per-response conflict.
  2. No skill body recommends automatic `git revert` — the failure protocol
     must PROPOSE, not EXECUTE, so history is not mutated before approval.
  3. No skill body tells the agent to "exclude" a test from the "blocking CI
     gate" — CLAUDE.md §2/§10 forbid weakening tests to reach green.
  4. Hook README's bounded-guarantee for the SQL-prose case must match the
     hook's actual behavior (see hooks/README.md line 40 vs bounded guarantee).

Exit 1 on any failure. This runs offline; no model calls, no network.
"""
import io
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SKILLS = ROOT / ".claude" / "skills"
HOOKS_README = ROOT / ".claude" / "hooks" / "README.md"

failures: list[str] = []


def read(p: pathlib.Path) -> str:
    with io.open(p, encoding="utf-8") as fh:
        return fh.read()


# --- 1. Token-prefix logging ban -------------------------------------------
# The exact phrase "token prefix" or "prefix only" applied to logging is the
# defect. Do not match discussions of tokenizer prefixes, URL prefixes, etc.
TOKEN_PREFIX_RE = re.compile(
    r"(token|auth[-_ ]?header|bearer|api[-_ ]?key)[^.\n]{0,60}?(prefix|first\s+\d+|last\s+\d+)",
    re.IGNORECASE,
)
# Also catch the inverse ordering ("prefix of a token", "mask the token, show N chars").
TOKEN_PREFIX_INV_RE = re.compile(
    r"(prefix|first\s+\d+|last\s+\d+)[^.\n]{0,60}?(token|auth[-_ ]?header|bearer)",
    re.IGNORECASE,
)


def _token_line_ok(line: str) -> bool:
    """Ban only lines that AUTHORIZE the pattern, not lines that FORBID it."""
    lo = line.lower()
    if any(w in lo for w in ("never log", "never mask", "forbid", "not allowed", "must not")):
        return True
    # "hash-derived prefix" phrasings, still forbidden if they hash the raw token.
    return False


def check_token_prefix_ban() -> None:
    hits: list[tuple[pathlib.Path, int, str]] = []
    for skill in sorted(SKILLS.glob("*/SKILL.md")):
        text = read(skill)
        for i, line in enumerate(text.splitlines(), 1):
            if TOKEN_PREFIX_RE.search(line) or TOKEN_PREFIX_INV_RE.search(line):
                if _token_line_ok(line):
                    continue
                hits.append((skill.relative_to(ROOT), i, line.strip()))
    if hits:
        for path, i, line in hits:
            failures.append(f"[token-prefix] {path}:{i}: {line}")


# --- 2. No automatic git revert in skill failure protocols -----------------
# Match a `git revert` recommendation that IS the action, not a discussion.
# Allow "propose a git revert", "we could git revert", "suggest git revert".
GIT_REVERT_ACTION_RE = re.compile(r"\bgit\s+revert\b", re.IGNORECASE)


def check_no_auto_revert() -> None:
    hits: list[tuple[pathlib.Path, int, str]] = []
    allow_context = re.compile(
        r"propose|suggest|recommend|preview|dry[-\s]?run|would|might|could|before[- ]approv|await|require\s+approval|do\s+not\s+auto",
        re.IGNORECASE,
    )
    for skill in sorted(SKILLS.glob("*/SKILL.md")):
        text = read(skill)
        for i, line in enumerate(text.splitlines(), 1):
            if GIT_REVERT_ACTION_RE.search(line) and not allow_context.search(line):
                hits.append((skill.relative_to(ROOT), i, line.strip()))
    if hits:
        for path, i, line in hits:
            failures.append(f"[auto-revert] {path}:{i}: {line}")


# --- 3. No "exclude from blocking CI gate" wording -------------------------
EXCLUDE_GATE_RE = re.compile(
    r"exclude[^.\n]{0,60}?(blocking|required|ci)\s+(gate|check|pipeline)",
    re.IGNORECASE,
)
SKIP_TO_GREEN_RE = re.compile(
    r"(disable|skip|@?skip)[^.\n]{0,40}?(to\s+get|to\s+reach|to\s+make)[^.\n]{0,20}?green",
    re.IGNORECASE,
)


def check_no_skip_to_green() -> None:
    hits: list[tuple[pathlib.Path, int, str]] = []
    for skill in sorted(SKILLS.glob("*/SKILL.md")):
        text = read(skill)
        for i, line in enumerate(text.splitlines(), 1):
            lo = line.lower()
            # Skip lines that FORBID the pattern (e.g. CLAUDE.md-adjacent
            # quoted rules "never disable a test to get green").
            if any(w in lo for w in ("never", "must not", "forbid", "do not")):
                continue
            if EXCLUDE_GATE_RE.search(line) or SKIP_TO_GREEN_RE.search(line):
                hits.append((skill.relative_to(ROOT), i, line.strip()))
    if hits:
        for path, i, line in hits:
            failures.append(f"[skip-to-green] {path}:{i}: {line}")


# --- 4. Hook README SQL-prose bounded-guarantee must match actual behavior --
def check_hook_readme_sql_consistency() -> None:
    if not HOOKS_README.exists():
        failures.append(f"[hook-readme] {HOOKS_README} missing")
        return
    text = read(HOOKS_README)
    # The hook actually BLOCKS `echo 'DROP TABLE ...'` and
    # `git commit -m 'drop the DROP TABLE stmt'` (deliberate, per line 40's
    # admission). Any prose claiming "documentation text mentioning a
    # statement stays allowed" would contradict that. Match across a small
    # newline window so the phrase catches even when it wraps at ~80 cols.
    offending = re.compile(
        r"documentation[\s\n]+text[\s\n]+mentioning[\s\n]+a[\s\n]+statement[\s\n]+stays[\s\n]+allowed",
        re.IGNORECASE,
    )
    m = offending.search(text)
    if m:
        # Line number of the match start.
        line_no = text[: m.start()].count("\n") + 1
        snippet = " ".join(m.group(0).split())
        failures.append(
            f"[hook-readme] {HOOKS_README.relative_to(ROOT)}:{line_no}: "
            f"contradicts hook's actual DENY on prose DROP/TRUNCATE: '{snippet}'"
        )


# --- 5. Version-sensitive skills must scope their guidance ------------------
def check_airflow_version_scoped() -> None:
    """The airflow skill must give Airflow-3-aware guidance: a version scope,
    Task SDK imports (airflow.sdk), get_current_context(), Assets (not only the
    renamed-away Datasets), and the Deadline-Alerts replacement for removed
    SLAs. Guards the P1-7 regression where the skill described only Airflow 2.x
    APIs and would generate version-invalid DAGs on an Airflow 3 project."""
    skill = SKILLS / "airflow" / "SKILL.md"
    if not skill.exists():
        return
    low = read(skill).lower()
    required = ("airflow 3", "airflow.sdk", "get_current_context", "assets", "deadline alert")
    missing = [r for r in required if r not in low]
    if missing:
        failures.append(
            f"[airflow-version] {skill.relative_to(ROOT)}: "
            f"missing Airflow-3 guidance ({', '.join(missing)})"
        )


def check_db_migrations_engine_scoped() -> None:
    """database-migrations gives PostgreSQL lock-safe DDL but is routed schema
    changes for other engines too (SQL Server via database-review). It must be
    engine-aware — name the engines and their differing mechanics — so a SQL
    Server / MySQL user is not handed Postgres-only syntax as universal (P1-7)."""
    skill = SKILLS / "database-migrations" / "SKILL.md"
    if not skill.exists():
        return
    low = read(skill).lower()
    missing = [e for e in ("sql server", "mysql") if e not in low]
    if missing:
        failures.append(
            f"[db-engine] {skill.relative_to(ROOT)}: "
            f"Postgres-centric guidance not engine-scoped (missing: {', '.join(missing)})"
        )


def check_websecurity_ratelimit_complete() -> None:
    """The web-security FastAPI SlowAPI example claimed 'copy-paste safe' but
    created a Limiter with no exception handler and no per-route limit — so it
    rate-limited nothing (P1-7). Require the two enforcing pieces."""
    skill = SKILLS / "web-security" / "SKILL.md"
    if not skill.exists():
        return
    text = read(skill)
    if "slowapi" not in text.lower():
        return
    missing = [n for n in ("add_exception_handler", "limiter.limit") if n not in text]
    if missing:
        failures.append(
            f"[web-ratelimit] {skill.relative_to(ROOT)}: "
            f"SlowAPI example incomplete — enforces no limit (missing: {', '.join(missing)})"
        )


def main() -> int:
    check_token_prefix_ban()
    check_no_auto_revert()
    check_no_skip_to_green()
    check_hook_readme_sql_consistency()
    check_airflow_version_scoped()
    check_db_migrations_engine_scoped()
    check_websecurity_ratelimit_complete()
    if failures:
        print("policy_consistency: FAILURES")
        for f in failures:
            print("  " + f)
        return 1
    print("policy_consistency: ALL CHECKS PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
