#!/usr/bin/env bash
# Fires when Claude tries to end its turn. Reminds about §16 Definition of Done
# if code was changed without verification.
#
# Default: reminder only (non-blocking). Set CLAUDE_VERIFY_BLOCK=1 to
# enforce blocking — this runs typecheck/lint/test on every Stop, which is
# powerful but heavy. Most teams should start with reminder mode.

source "$(dirname "$0")/lib.sh"

# Re-entry guard: when Claude already continued once because of this hook,
# the Stop input carries stop_hook_active=true. Never nag (or block) twice —
# without this guard, blocking mode can loop a session forever.
STOP_INPUT=$(cat 2>/dev/null || true)
if command -v jq >/dev/null 2>&1 && [[ -n "$STOP_INPUT" ]]; then
  if [[ "$(echo "$STOP_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || true)" == "true" ]]; then
    exit 0
  fi
fi

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

# Detect uncommitted code changes that look "real" (not just docs/whitespace).
# Use `git rev-parse`, NOT `[[ -d .git ]]`: in a linked worktree `.git` is a
# FILE (a gitdir pointer), so the directory test wrongly exits here and disables
# the hook — and Claude Code runs sessions inside .claude/worktrees/, so that is
# the common case, not an edge case.
if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0  # Not a git work tree, nothing to check.
fi

# --untracked-files=all so an untracked code file inside a NEW directory is
# listed individually (`newdir/mod.py`), not collapsed to `newdir/` (which ends
# in `/` and would slip past the extension filter below).
# grep -c exits 1 when nothing matches; without `|| true`, lib.sh's
# `set -euo pipefail` kills the hook with exit 1 on every CLEAN stop.
CHANGED=$(git status --porcelain --untracked-files=all 2>/dev/null | grep -cE '\.(ts|tsx|js|jsx|py|go|rs|java|rb|php|cs|cpp|c|h|sql|sh)$' || true)

if [[ "$CHANGED" == "0" ]]; then
  exit 0  # No code changes; stopping is fine.
fi

# Reminder mode (default).
if [[ "${CLAUDE_VERIFY_BLOCK:-0}" != "1" ]]; then
  echo "" >&2
  echo "📋 Definition of Done check (CLAUDE.md §16):" >&2
  # "uncommitted", not "changed in this session": this reads the working tree,
  # so it counts pre-existing dirty files too and cannot see changes already
  # committed during the session. True session attribution needs a SessionStart
  # baseline, which this hook deliberately does not maintain.
  echo "   $CHANGED code file(s) with uncommitted changes." >&2
  echo "   Before declaring done, confirm:" >&2
  echo "     [ ] tests run and observed passing" >&2
  echo "     [ ] linter, formatter, type-checker pass" >&2
  echo "     [ ] code path actually executed" >&2
  echo "     [ ] verification matrix (§14) for change type satisfied" >&2
  echo "" >&2
  exit 0
fi

# Blocking mode — actually run verification.
# Customize commands per project. These are conservative defaults that try
# common conventions; missing commands are skipped silently.

# Per-check AND aggregate wall-clock budgets (v9). A blocking-mode Stop hook
# that runs an undetected watcher (`vitest --watch`, `next dev`, nodemon) — or a
# genuinely slow suite — would otherwise wedge the session. We detect obvious
# watchers up front (script_is_watch) and, as a backstop, bound every check with
# a timeout AND cap the TOTAL so N ecosystems cannot multiply into N×per-check.
VERIFY_TIMEOUT_S=${CLAUDE_VERIFY_TIMEOUT_S:-300}              # per check
VERIFY_TOTAL_TIMEOUT_S=${CLAUDE_VERIFY_TOTAL_TIMEOUT_S:-600}  # aggregate, all checks
VERIFY_KILL_AFTER_S=${CLAUDE_VERIFY_KILL_AFTER_S:-10}         # TERM->KILL grace

# Portable bounding tool: GNU coreutils `timeout` (Linux / Git Bash) or
# `gtimeout` (macOS via `brew install coreutils`).
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT_BIN=timeout
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN=gtimeout
fi

# We are past the reminder-mode early return, so this is BLOCKING mode. Strict
# verification must be able to bound every check; without a timeout tool a
# watch/serve script we failed to detect would hang forever. "Cannot verify
# safely" is not "verified" — fail closed rather than run unbounded.
if [[ -z "$TIMEOUT_BIN" ]]; then
  echo "" >&2
  echo "🛑 Definition of Done: cannot bound verification — no 'timeout' or" >&2
  echo "   'gtimeout' is available, so a hung check could wedge the session." >&2
  echo "   Refusing to certify in blocking mode. Install coreutils, or run the" >&2
  echo "   project's checks manually (CLAUDE.md §14/§16)." >&2
  exit 2
fi

START_EPOCH=$(date +%s 2>/dev/null || echo 0)

run_check() {
  # Executes the remaining args DIRECTLY as an argument vector — never eval
  # (CLAUDE.md §7). Bounded by the SMALLER of the per-check limit and the
  # remaining aggregate budget; a check that would begin past the deadline is
  # skipped and counted as a failure. TERM first, then KILL after a grace
  # period, so a child that ignores TERM cannot linger.
  local name="$1"; shift
  local rc=0 now elapsed remaining budget
  now=$(date +%s 2>/dev/null || echo "$START_EPOCH")
  elapsed=$(( now - START_EPOCH ))
  remaining=$(( VERIFY_TOTAL_TIMEOUT_S - elapsed ))
  if (( remaining <= 0 )); then
    echo "   ✗ $name SKIPPED — aggregate verification budget (${VERIFY_TOTAL_TIMEOUT_S}s) exhausted" >&2
    return 1
  fi
  budget=$VERIFY_TIMEOUT_S
  (( remaining < budget )) && budget=$remaining
  "$TIMEOUT_BIN" -k "${VERIFY_KILL_AFTER_S}s" "${budget}s" "$@" >/dev/null 2>&1 || rc=$?
  if (( rc == 0 )); then
    echo "   ✓ $name" >&2
    return 0
  elif (( rc == 124 )); then
    echo "   ✗ $name TIMED OUT after ${budget}s — likely a watch/serve script; run '$*' manually or set CLAUDE_VERIFY_TIMEOUT_S" >&2
    return 1
  else
    echo "   ✗ $name FAILED — run '$*' to see details" >&2
    return 1
  fi
}

# True when a package.json script starts a long-running watcher/server that
# never exits. Such a script must be SKIPPED (with a note), not run — running
# it would burn the whole timeout budget and then report a misleading failure.
script_is_watch() {
  local key="$1" body
  body=$(jq -r --arg k "$key" '.scripts[$k] // ""' package.json 2>/dev/null)
  # Neutralise FINITE forms a broad watcher regex would wrongly catch, BEFORE
  # the test below: `--watch=false` / `--watchAll=false` explicitly disable
  # watch, and `vite build` is a finite build (only bare `vite` and
  # `vite dev|serve|preview` watch). Without this, `vitest --watch=false` and a
  # `vite build` step were skipped as "watchers" and never verified.
  body=$(printf '%s' "$body" | sed -E 's/--watch(All)?[[:space:]=]+(false|0)//g')
  body=$(printf '%s' "$body" | sed -E 's/(^|[[:space:]])vite[[:space:]]+build([[:space:]]|$)/ /g')
  printf '%s' "$body" | grep -qE -- '(--watch|--watchAll|--serve|(^| )-w( |$)|nodemon|(^| )watch( |$)|next[[:space:]]+dev|vite([[:space:]]|$))'
}

echo "🔍 Running Definition of Done verification..." >&2
FAILED=0
RAN=0  # how many checks actually executed — distinguishes "passed" from "none ran"

# Detect Node package manager from lockfile so we use the right one.
detect_node_pm() {
  if [[ -f pnpm-lock.yaml ]]; then echo "pnpm"
  elif [[ -f yarn.lock ]]; then echo "yarn"
  # bun.lock is the TEXT lockfile Bun >= 1.2 writes by default; bun.lockb is
  # the older binary format. Either one is Bun-exclusive.
  elif [[ -f bun.lock || -f bun.lockb ]]; then echo "bun"
  elif [[ -f package-lock.json ]]; then echo "npm"
  else echo "npm"; fi
}

# Independent `if`s (not if/elif): a polyglot repo runs EVERY ecosystem present,
# not just the first one detected.
# Counters use POSIX assignment (RAN=$((RAN+1))), never bare ((RAN++)) — the
# arithmetic command returns status 1 when the expression evaluates to 0, so
# under lib.sh's set -e the first increment from 0 would kill the hook before
# any check runs.
# Ecosystems whose toolchain is missing are SKIPPED with a note, not counted
# as failed — "cannot verify" must never masquerade as "verification failed".
if [[ -f package.json ]]; then
  PM=$(detect_node_pm)
  if ! command -v "$PM" >/dev/null 2>&1; then
    echo "   ⚠ package.json present but '$PM' is not installed — Node checks skipped" >&2
  else
    if jq -e '.scripts.typecheck' package.json >/dev/null 2>&1; then
      if script_is_watch typecheck; then
        echo "   ⚠ 'typecheck' script looks like watch/serve mode — skipped (would not exit); run it manually" >&2
      else
        RAN=$((RAN+1)); run_check "typecheck" "$PM" run typecheck || FAILED=$((FAILED+1))
      fi
    fi
    if jq -e '.scripts.lint' package.json >/dev/null 2>&1; then
      if script_is_watch lint; then
        echo "   ⚠ 'lint' script looks like watch/serve mode — skipped (would not exit); run it manually" >&2
      else
        RAN=$((RAN+1)); run_check "lint" "$PM" run lint || FAILED=$((FAILED+1))
      fi
    fi
    if jq -e '.scripts.test' package.json >/dev/null 2>&1; then
      if script_is_watch test; then
        echo "   ⚠ 'test' script looks like watch mode — skipped (would not exit); run it manually" >&2
      else
        # `run test`, never bare `test`: identical for npm/pnpm/yarn, and for Bun
        # it is the only correct form — `bun test` invokes Bun's NATIVE runner,
        # which ignores the package.json script this check is gated on (on a
        # script-only project real Bun exits 1 "No tests found").
        RAN=$((RAN+1)); run_check "test" "$PM" run test || FAILED=$((FAILED+1))
      fi
    fi
  fi
fi
if [[ -f pyproject.toml ]]; then
  if command -v ruff >/dev/null; then
    RAN=$((RAN+1)); run_check "ruff" ruff check . || FAILED=$((FAILED+1))
  fi
  if command -v mypy >/dev/null; then
    RAN=$((RAN+1)); run_check "mypy" mypy . || FAILED=$((FAILED+1))
  fi
  if command -v pytest >/dev/null; then
    RAN=$((RAN+1)); run_check "pytest" pytest -q || FAILED=$((FAILED+1))
  fi
fi
if [[ -f Cargo.toml ]]; then
  if ! command -v cargo >/dev/null 2>&1; then
    echo "   ⚠ Cargo.toml present but 'cargo' is not installed — Rust checks skipped" >&2
  else
    RAN=$((RAN+1)); run_check "cargo check" cargo check || FAILED=$((FAILED+1))
    RAN=$((RAN+1)); run_check "cargo test" cargo test --quiet || FAILED=$((FAILED+1))
  fi
fi
if [[ -f go.mod ]]; then
  if ! command -v go >/dev/null 2>&1; then
    echo "   ⚠ go.mod present but 'go' is not installed — Go checks skipped" >&2
  else
    RAN=$((RAN+1)); run_check "go vet" go vet ./... || FAILED=$((FAILED+1))
    RAN=$((RAN+1)); run_check "go test" go test ./... || FAILED=$((FAILED+1))
  fi
fi

if (( FAILED > 0 )); then
  echo "" >&2
  echo "🛑 Definition of Done unmet: $FAILED of $RAN check(s) failed." >&2
  echo "   Per CLAUDE.md §16, do not declare success." >&2
  exit 2
fi

if (( RAN == 0 )); then
  # Code changed but NO checker could run (none discovered, or its toolchain is
  # absent). This is BLOCKING mode (reminder mode returned earlier), so "cannot
  # verify" must not be certified as "verified" — fail closed. The user can run
  # the checks manually, configure a checker, or override for the session.
  echo "" >&2
  echo "🛑 Definition of Done: code changed but no verification command could run" >&2
  echo "   (no ecosystem checker was found, or its toolchain is not installed here)." >&2
  echo "   Run the project's checks manually, add a checker, or override for this" >&2
  echo "   session (CLAUDE.md §14/§16). Refusing to certify." >&2
  exit 2
fi

echo "✓ All $RAN verification check(s) passed." >&2
exit 0
