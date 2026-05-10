#!/usr/bin/env bash
# Blocks writes containing secret-shaped strings.
# Per CLAUDE.md §7 Security Foundations > Secrets & Credentials.
# Hook event: PreToolUse, matcher: Edit|Write|MultiEdit

export CLAUDE_HOOK_NAME="scan-secrets"
source "$(dirname "$0")/lib.sh"
require_jq

INPUT=$(read_input)

# Different tools put content in different fields:
#   Write: tool_input.content
#   Edit:  tool_input.new_string
#   MultiEdit: tool_input.edits[].new_string (array)
CONTENT=$(echo "$INPUT" | jq -r '
  (.tool_input.content // "") +
  "\n" +
  (.tool_input.new_string // "") +
  "\n" +
  ((.tool_input.edits // []) | map(.new_string // "") | join("\n"))
')

if [[ -z "$CONTENT" || "$CONTENT" == $'\n\n' ]]; then
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
# Patterns that mean "this is fake" — if the content matches one of these in
# context, the secret-shaped string is probably a fixture.
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

for pattern in "${SECRET_PATTERNS[@]}"; do
  MATCH=$(echo "$CONTENT" | grep -oE -e "$pattern" | head -1 || true)
  if [[ -n "$MATCH" ]]; then
    # Check if a fake marker is on the same line.
    LINE=$(echo "$CONTENT" | grep -E -e "$pattern" | head -1 || true)
    IS_FAKE=false
    for marker in "${FAKE_MARKERS[@]}"; do
      if echo "$LINE" | grep -qE -e "$marker"; then
        IS_FAKE=true
        break
      fi
    done

    if [[ "$IS_FAKE" == "true" ]]; then
      # Don't include preview in log_warn — even fake previews go to disk
      # via log_event. Keep stderr-only for any matched content.
      log_warn "Skipping secret-shaped string that looks like a test fixture (matched pattern '$pattern')."
      continue
    fi

    if check_override "scan-secrets"; then
      log_warn "Override: allowing secret-shaped string (this MUST be reviewed)" "scan-secrets-override"
      continue
    fi

    # IMPORTANT: do not put the matched preview into log_block's detail —
    # that goes to .claude/logs/hooks.log on disk. Show preview only in
    # ephemeral stderr (which Claude sees once, then it's gone).
    log_block \
      "secret-shaped string" \
      "Content contains a string matching pattern '$pattern'." \
      "CLAUDE.md §7 Security Foundations"
    echo "   Match preview (not persisted to log): ${MATCH:0:8}..." >&2
    echo "" >&2
    echo "If this is real:  ROTATE the secret immediately and use env vars / a secret manager." >&2
    echo "If this is fake:  add a marker like 'EXAMPLE', 'fake-', or 'test-' to the value." >&2
    exit 2
  fi
done

exit 0
