#!/usr/bin/env bash
# Warns on suspiciously large file rewrites.
# Per CLAUDE.md §9 Refactoring, Scope & Diff Discipline.
# Hook event: PreToolUse, matcher: Edit|Write|NotebookEdit
#
# Behavior: WARN by default (non-blocking). To make this blocking,
# change `exit 0` at the end of the warn branch to `exit 2`.

source "$(dirname "$0")/lib.sh"
require_jq

INPUT=$(read_input)
TOOL=$(json_get "$INPUT" '.tool_name')
FILE=$(json_get "$INPUT" '.tool_input.file_path')

# Threshold: warn above this many lines added/changed in one tool call.
# Tune to your codebase. 300 catches "rewrote the whole file" without
# blocking large legitimate generations (e.g., adding a new fixture).
THRESHOLD=${CLAUDE_DIFF_WARN_LINES:-300}

# Hard-block threshold — almost always a rewrite, not a real change.
HARD_THRESHOLD=${CLAUDE_DIFF_BLOCK_LINES:-1000}

count_lines() {
  if [[ -z "$1" ]]; then
    echo 0
  else
    echo "$1" | awk 'END { print NR }'
  fi
}

LINES_CHANGED=0

case "$TOOL" in
  Write)
    CONTENT=$(json_get "$INPUT" '.tool_input.content')
    LINES_CHANGED=$(count_lines "$CONTENT")
    ;;
  Edit)
    OLD=$(json_get "$INPUT" '.tool_input.old_string')
    NEW=$(json_get "$INPUT" '.tool_input.new_string')
    OLD_LINES=$(count_lines "$OLD")
    NEW_LINES=$(count_lines "$NEW")
    # Use the larger side as a proxy for change size.
    if (( NEW_LINES > OLD_LINES )); then
      LINES_CHANGED=$NEW_LINES
    else
      LINES_CHANGED=$OLD_LINES
    fi
    ;;
  NotebookEdit)
    CONTENT=$(json_get "$INPUT" '.tool_input.new_source')
    LINES_CHANGED=$(count_lines "$CONTENT")
    ;;
  MultiEdit)
    # Legacy tool (removed in current Claude Code); handling kept for old versions.
    LINES_CHANGED=$(echo "$INPUT" | jq -r '
      [.tool_input.edits[]?
        | (.new_string // "" | split("\n") | length)
      ] | add // 0
    ' 2>/dev/null || echo 0)
    ;;
  *)
    exit 0
    ;;
esac

if (( LINES_CHANGED >= HARD_THRESHOLD )); then
  log_block \
    "very large diff" \
    "$TOOL on $FILE would change ~$LINES_CHANGED lines (>= $HARD_THRESHOLD). This is almost certainly a rewrite, not a focused change." \
    "CLAUDE.md §9 Diff Discipline"
  echo "" >&2
  echo "Split into smaller, focused edits. If this really must be one operation," >&2
  echo "set CLAUDE_DIFF_BLOCK_LINES higher in your shell." >&2
  exit 2
fi

if (( LINES_CHANGED >= THRESHOLD )); then
  log_warn "Large diff: $TOOL on $FILE will change ~$LINES_CHANGED lines (>= $THRESHOLD). Verify this is a focused change, not a full-file rewrite. (Per CLAUDE.md §9.)"
fi

exit 0
