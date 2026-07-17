#!/usr/bin/env bash
# Shared helpers for Claude Code hooks.
# Source this from each hook script: source "$(dirname "$0")/lib.sh"

set -euo pipefail

# Auto-derive hook name from caller's filename if not set explicitly.
# This means a new hook script Just Works even if the author forgets to
# `export CLAUDE_HOOK_NAME`.
if [[ -z "${CLAUDE_HOOK_NAME:-}" ]]; then
  # ${BASH_SOURCE[1]} is the file that sourced this lib.
  CLAUDE_HOOK_NAME="$(basename "${BASH_SOURCE[1]:-unknown}" .sh)"
  export CLAUDE_HOOK_NAME
fi

# --- Output helpers ----------------------------------------------------------
# stderr text becomes feedback Claude sees; stdout is generally ignored for
# command hooks. Exit codes are the control mechanism:
#   0 = allow / no opinion
#   2 = deny / block (Claude sees stderr as the reason)

log_block() {
  # Block message — Claude sees this and adapts.
  echo "🛑 BLOCKED by enforcement: $1" >&2
  echo "   Reason: $2" >&2
  echo "   See: $3" >&2
  log_event "BLOCK" "$1" "$2"
}

log_warn() {
  # Warning — does not block, but Claude sees it.
  echo "⚠️  $1" >&2
  log_event "WARN" "${2:-warn}" "$1"
}

# --- Audit log ---------------------------------------------------------------
# Lightweight observability: every hook decision appended to .claude/logs/hooks.log
# This enables tuning (which patterns fire most? which never fire?) without
# requiring an external system. Logs are local-only; gitignore them.

log_event() {
  local kind="$1"      # BLOCK | WARN | OVERRIDE
  local category="$2"  # short label
  local detail="$3"    # human-readable detail
  local logdir="${CLAUDE_PROJECT_DIR:-.}/.claude/logs"
  local logfile="$logdir/hooks.log"

  mkdir -p "$logdir" 2>/dev/null || return 0
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "?")
  local hook="${CLAUDE_HOOK_NAME:-unknown}"
  # JSON-ish line for easy grepping; not strict JSON to keep deps minimal.
  printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$kind" "$hook" "$category" "$detail" >> "$logfile" 2>/dev/null || true
}

# --- Override mechanism ------------------------------------------------------
# When a user genuinely needs to bypass a hook for a single action, they can
# set an override env var. Overrides are LOGGED so they're auditable — the
# point is not to defeat the hook silently, but to make bypass a deliberate,
# reviewable action.
#
# Usage (in shell):
#   CLAUDE_HOOK_OVERRIDE=block-destructive claude ...
# Or for all hooks (use sparingly):
#   CLAUDE_HOOK_OVERRIDE=all claude ...
#
# A hook checks: if check_override "name"; then exit 0; fi  (allow when override active)

check_override() {
  local hook_name="$1"
  local override="${CLAUDE_HOOK_OVERRIDE:-}"
  if [[ "$override" == "$hook_name" || "$override" == "all" ]]; then
    log_event "OVERRIDE" "$hook_name" "explicit user override via CLAUDE_HOOK_OVERRIDE=$override"
    echo "⚠️  Override active for $hook_name (CLAUDE_HOOK_OVERRIDE=$override). This is logged." >&2
    return 0  # override active — caller should allow
  fi
  return 1  # no override — caller should enforce
}

# --- JSON helpers ------------------------------------------------------------

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "Hook misconfiguration: jq not installed. Install with 'brew install jq' / 'apt-get install jq'." >&2
    # Exit 0 (allow) on misconfig — fail open is safer than fail closed for hooks.
    # The user will see the message and can fix it.
    exit 0
  fi
}

# Read full stdin into a variable (hooks receive JSON on stdin).
read_input() {
  cat
}

# Extract a JSON field; print empty string if missing OR if the input is not
# valid JSON. Guardrail hooks must fail OPEN on malformed input (same policy
# as require_jq) — without the guard, jq's parse error aborts the sourcing
# hook via set -euo pipefail with a confusing non-0/non-2 exit code.
json_get() {
  local input="$1"
  local field="$2"
  echo "$input" | jq -r "$field // empty" 2>/dev/null || true
}
