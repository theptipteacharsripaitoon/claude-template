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

run_check() {
  # Executes the remaining args DIRECTLY as an argument vector — never eval
  # (CLAUDE.md §7: no eval, even on internally-built strings; word-splitting
  # surprises are a maintenance hazard the vector form cannot have).
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "   ✓ $name" >&2
    return 0
  else
    echo "   ✗ $name FAILED — run '$*' to see details" >&2
    return 1
  fi
}

echo "🔍 Running Definition of Done verification..." >&2
FAILED=0
RAN=0  # how many checks actually executed — distinguishes "passed" from "none ran"

# Detect Node package manager from lockfile so we use the right one.
detect_node_pm() {
  if [[ -f pnpm-lock.yaml ]]; then echo "pnpm"
  elif [[ -f yarn.lock ]]; then echo "yarn"
  elif [[ -f bun.lockb ]]; then echo "bun"
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
      RAN=$((RAN+1)); run_check "typecheck" "$PM" run typecheck || FAILED=$((FAILED+1))
    fi
    if jq -e '.scripts.lint' package.json >/dev/null 2>&1; then
      RAN=$((RAN+1)); run_check "lint" "$PM" run lint || FAILED=$((FAILED+1))
    fi
    if jq -e '.scripts.test' package.json >/dev/null 2>&1; then
      RAN=$((RAN+1)); run_check "test" "$PM" test || FAILED=$((FAILED+1))
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
  # Code changed but no checker was discovered/installed. This is NOT success —
  # report it honestly so "no checks ran" is never mistaken for "checks passed".
  echo "" >&2
  echo "⚠️  No verification commands could be run for this repo (no ecosystem" >&2
  echo "   checker was found, or its toolchain is not installed here)." >&2
  echo "   Code changed but nothing was verified — run the project's checks manually" >&2
  echo "   before declaring done (CLAUDE.md §14/§16)." >&2
  exit 0
fi

echo "✓ All $RAN verification check(s) passed." >&2
exit 0
