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
if ! command -v git >/dev/null 2>&1 || [[ ! -d .git ]]; then
  exit 0  # No git, nothing to check.
fi

# grep -c exits 1 when nothing matches; without `|| true`, lib.sh's
# `set -euo pipefail` kills the hook with exit 1 on every CLEAN stop.
CHANGED=$(git status --porcelain 2>/dev/null | grep -cE '\.(ts|tsx|js|jsx|py|go|rs|java|rb|php|cs|cpp|c|h|sql|sh)$' || true)

if [[ "$CHANGED" == "0" ]]; then
  exit 0  # No code changes; stopping is fine.
fi

# Reminder mode (default).
if [[ "${CLAUDE_VERIFY_BLOCK:-0}" != "1" ]]; then
  echo "" >&2
  echo "📋 Definition of Done check (CLAUDE.md §16):" >&2
  echo "   $CHANGED code file(s) changed in this session." >&2
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
  local name="$1"; shift
  local cmd="$*"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "   ✓ $name" >&2
    return 0
  else
    echo "   ✗ $name FAILED — run '$cmd' to see details" >&2
    return 1
  fi
}

echo "🔍 Running Definition of Done verification..." >&2
FAILED=0

# Detect Node package manager from lockfile so we use the right one.
detect_node_pm() {
  if [[ -f pnpm-lock.yaml ]]; then echo "pnpm"
  elif [[ -f yarn.lock ]]; then echo "yarn"
  elif [[ -f bun.lockb ]]; then echo "bun"
  elif [[ -f package-lock.json ]]; then echo "npm"
  else echo "npm"; fi
}

# Auto-detect project type and run the right commands.
if [[ -f package.json ]]; then
  PM=$(detect_node_pm)
  if jq -e '.scripts.typecheck' package.json >/dev/null 2>&1; then
    run_check "typecheck" "$PM run typecheck" || ((FAILED++)) || true
  fi
  if jq -e '.scripts.lint' package.json >/dev/null 2>&1; then
    run_check "lint" "$PM run lint" || ((FAILED++)) || true
  fi
  if jq -e '.scripts.test' package.json >/dev/null 2>&1; then
    if [[ "$PM" == "npm" ]]; then
      run_check "test" "npm test" || ((FAILED++)) || true
    else
      run_check "test" "$PM test" || ((FAILED++)) || true
    fi
  fi
elif [[ -f pyproject.toml ]]; then
  # Use { } not ( ) — () creates a subshell, FAILED++ wouldn't propagate.
  if command -v ruff >/dev/null; then
    { run_check "ruff" "ruff check ." || ((FAILED++)); } || true
  fi
  if command -v mypy >/dev/null; then
    { run_check "mypy" "mypy ." || ((FAILED++)); } || true
  fi
  if command -v pytest >/dev/null; then
    { run_check "pytest" "pytest -q" || ((FAILED++)); } || true
  fi
elif [[ -f Cargo.toml ]]; then
  run_check "cargo check" "cargo check" || ((FAILED++)) || true
  run_check "cargo test" "cargo test --quiet" || ((FAILED++)) || true
elif [[ -f go.mod ]]; then
  run_check "go vet" "go vet ./..." || ((FAILED++)) || true
  run_check "go test" "go test ./..." || ((FAILED++)) || true
fi

if (( FAILED > 0 )); then
  echo "" >&2
  echo "🛑 Definition of Done unmet: $FAILED check(s) failed." >&2
  echo "   Per CLAUDE.md §16, do not declare success." >&2
  exit 2
fi

echo "✓ All verification checks passed." >&2
exit 0
