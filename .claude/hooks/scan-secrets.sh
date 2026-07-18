#!/usr/bin/env bash
# Blocks writes containing secret-shaped strings.
# Per CLAUDE.md §7 Security Foundations > Secrets & Credentials.
# Hook event: PreToolUse, matcher: Edit|Write|NotebookEdit

export CLAUDE_HOOK_NAME="scan-secrets"
source "$(dirname "$0")/lib.sh"
require_jq

INPUT=$(read_input)

# Different tools put content in different fields:
#   Write: tool_input.content
#   Edit:  tool_input.new_string
#   NotebookEdit: tool_input.new_source
#   (legacy MultiEdit: tool_input.edits[].new_string)
# `|| true`: malformed JSON fails open (same policy as require_jq).
CONTENT=$(echo "$INPUT" | jq -r '
  (.tool_input.content // "") +
  "\n" +
  (.tool_input.new_string // "") +
  "\n" +
  (.tool_input.new_source // "") +
  "\n" +
  ((.tool_input.edits // []) | map(.new_string // "") | join("\n"))
' 2>/dev/null || true)

if [[ -z "${CONTENT//$'\n'/}" ]]; then
  exit 0
fi

# Secret-shaped patterns. False positive is acceptable; false negative is not.
# Tune if a real value gets blocked (e.g., a fixture using a fake-but-formatted key).
SECRET_PATTERNS=(
  # AWS
  'AKIA[0-9A-Z]{16}'                              # AWS access key
  'aws_secret_access_key[[:space:]]*=[[:space:]]*[A-Za-z0-9/+=]{40}'

  # GitHub
  'ghp_[A-Za-z0-9]{36,}'                          # personal access token
  'gho_[A-Za-z0-9]{36,}'                          # OAuth token
  'ghs_[A-Za-z0-9]{36,}'                          # server-to-server
  'github_pat_[A-Za-z0-9_]{82}'                   # fine-grained PAT

  # OpenAI / Anthropic / similar
  'sk-[A-Za-z0-9]{32,}'                           # OpenAI/Anthropic-style
  'sk-ant-[A-Za-z0-9_-]{32,}'                     # Anthropic explicit

  # Slack
  'xox[baprs]-[A-Za-z0-9-]{10,}'

  # Stripe
  'sk_live_[A-Za-z0-9]{24,}'
  'rk_live_[A-Za-z0-9]{24,}'

  # Google
  'AIza[0-9A-Za-z_-]{35}'                         # Google API key

  # Generic high-entropy
  '-----BEGIN[[:space:]]+(RSA[[:space:]]+|EC[[:space:]]+|OPENSSH[[:space:]]+|DSA[[:space:]]+)?PRIVATE[[:space:]]+KEY-----'

  # Heuristic: assignment of a long base64-like string to a sensitive name
  '(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token)[[:space:]]*[:=][[:space:]]*[\"'"'"']?[A-Za-z0-9+/=_-]{20,}'
)

# Allow obviously-fake test fixtures so legitimate test data does not block.
# A marker suppresses a match ONLY when it appears INSIDE the matched value —
# not merely somewhere on the line. Line-scoped marking let a real secret slip
# through whenever the line also contained a word like "example" (and let a real
# second match hide behind a fake first match). Value-scoped marking matches the
# hook's own guidance below ("add a marker ... to the value").
FAKE_MARKERS=(
  'EXAMPLE'
  'example'
  'fake[_-]'
  'test[_-]'
  'dummy[_-]'
  'placeholder'
  'XXXX'
  'xxxxxxxx'
  '0000000000'
  'abcdef0123'
)

# Returns 0 (true) when the matched value itself carries a fake marker.
value_is_fixture() {
  local value="$1" marker
  for marker in "${FAKE_MARKERS[@]}"; do
    if printf '%s' "$value" | grep -qE -e "$marker"; then
      return 0
    fi
  done
  return 1
}

for pattern in "${SECRET_PATTERNS[@]}"; do
  # Inspect EVERY match of this pattern, not just the first. A real secret must
  # not be able to hide behind a fixture that matched earlier in the content.
  while IFS= read -r MATCH; do
    [[ -z "$MATCH" ]] && continue

    if value_is_fixture "$MATCH"; then
      # Marker is inside the value — treat this occurrence as a fixture and keep
      # scanning later matches. No preview to disk (log_event persists detail).
      log_warn "Skipping secret-shaped fixture value (matched pattern '$pattern')."
      continue
    fi

    if check_override "scan-secrets"; then
      log_warn "Override: allowing secret-shaped string (this MUST be reviewed)" "scan-secrets-override"
      continue
    fi

    # NEVER print the matched value — not in full, not a prefix, not a preview.
    # stderr is fed back to Claude and may be captured by wrapping tooling, so
    # even 8 characters of a token is a partial exposure (and Claude already
    # holds the full content it tried to write, so a preview tells it nothing).
    # Only the pattern NAME and the non-secret location go anywhere.
    log_block \
      "secret-shaped string" \
      "Content contains a string matching pattern '$pattern'." \
      "CLAUDE.md §7 Security Foundations"
    echo "   Matched secret-shaped pattern '$pattern' — value withheld." >&2
    echo "" >&2
    echo "If this is real:  ROTATE the secret immediately and use env vars / a secret manager." >&2
    echo "If this is fake:  add a marker like 'EXAMPLE', 'fake-', or 'test-' to the value." >&2
    exit 2
  done < <(printf '%s\n' "$CONTENT" | grep -oE -e "$pattern" || true)
done

exit 0
