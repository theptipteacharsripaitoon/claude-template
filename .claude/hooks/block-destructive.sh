#!/usr/bin/env bash
# Blocks destructive shell commands per CLAUDE.md §2 AI Action Boundaries.
# Hook event: PreToolUse, matcher: Bash

export CLAUDE_HOOK_NAME="block-destructive"
source "$(dirname "$0")/lib.sh"
require_jq

INPUT=$(read_input)
CMD=$(json_get "$INPUT" '.tool_input.command')

if [[ -z "$CMD" ]]; then
  exit 0  # No command to inspect; allow.
fi

# Patterns that should ALWAYS be blocked.
# Each line is a separate regex. Be conservative — false positives are better
# than missing a real disaster. Claude will surface a normal request to the
# user when blocked, who can override by running the command themselves.
DESTRUCTIVE_PATTERNS=(
  # Filesystem
  'rm[[:space:]]+-rf?[[:space:]]+/'                       # rm -rf /
  'rm[[:space:]]+-rf?[[:space:]]+\*'                      # rm -rf *
  'rm[[:space:]]+-rf?[[:space:]]+\$HOME'                  # rm -rf $HOME
  'rm[[:space:]]+-rf?[[:space:]]+~'                       # rm -rf ~
  'rm[[:space:]]+--no-preserve-root'                      # explicit override
  'find[[:space:]].*-delete'                              # find ... -delete
  'shred[[:space:]]'                                      # shred
  'mkfs\.'                                                # filesystem create
  'dd[[:space:]]+if=.*of=/dev/'                           # dd to device
  ':\(\)\{.*:\|:.*\}'                                     # fork bomb
  'chmod[[:space:]]+-R[[:space:]]+777'                    # disastrous permissions
  'chmod[[:space:]]+777[[:space:]]'                       # chmod 777 anywhere

  # Untrusted-input executor patterns (famous attack vector)
  'curl[[:space:]]+.*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh'  # curl ... | sh
  'wget[[:space:]]+.*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh'  # wget ... | sh

  # Git destructive
  'git[[:space:]]+push[[:space:]]+.*--force'              # force push
  'git[[:space:]]+push[[:space:]]+.*-f([[:space:]]|$)'    # short -f
  'git[[:space:]]+reset[[:space:]]+--hard'                # hard reset
  'git[[:space:]]+clean[[:space:]]+-[a-z]*f[a-z]*d'       # clean -fd
  'git[[:space:]]+filter-branch'                          # history rewrite
  'git[[:space:]]+update-ref[[:space:]]+-d'               # delete ref

  # Database
  'DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)'               # DROP TABLE/DB
  'TRUNCATE[[:space:]]+TABLE'                             # TRUNCATE
  'DELETE[[:space:]]+FROM[[:space:]]+[a-zA-Z_]+[[:space:]]*;' # DELETE without WHERE

  # Cluster / cloud
  'kubectl[[:space:]]+delete[[:space:]]+(namespace|ns)[[:space:]]'
  'kubectl[[:space:]]+.*--all-namespaces.*--all'
  'helm[[:space:]]+uninstall'
  'terraform[[:space:]]+(destroy|apply)'                  # any apply needs human
  'aws[[:space:]]+s3[[:space:]]+rb[[:space:]]+.*--force'  # delete S3 bucket
  'gcloud[[:space:]]+.*delete[[:space:]]'                 # gcloud delete

)

# Package managers (per CLAUDE.md §2: propose, don't install). These get an
# interactive ASK (hookSpecificOutput.permissionDecision) instead of a hard
# deny — installing a dependency is a legitimate action that needs the user's
# yes, not a blocked one. Modern npm 5+ saves by default — match any
# `npm install <pkg>`, not just --save.
ASK_PATTERNS=(
  'npm[[:space:]]+install[[:space:]]+[@a-zA-Z]'           # npm install <pkg> or @scope
  'npm[[:space:]]+i[[:space:]]+[@a-zA-Z]'                 # npm i <pkg> shorthand
  'yarn[[:space:]]+add[[:space:]]'
  'pnpm[[:space:]]+add[[:space:]]'
  'bun[[:space:]]+add[[:space:]]'                         # Bun (growing)
  'pip[[:space:]]+install[[:space:]]+[^-]'                # pip install <pkg> (allows -e)
  'pip3[[:space:]]+install[[:space:]]+[^-]'
  'poetry[[:space:]]+add[[:space:]]'
  'uv[[:space:]]+add[[:space:]]'                          # uv (modern Python)
  'cargo[[:space:]]+add[[:space:]]'
  'gem[[:space:]]+install[[:space:]]'                     # Ruby
  'composer[[:space:]]+require[[:space:]]'                # PHP
  'go[[:space:]]+install[[:space:]]'                      # Go binaries
)

for pattern in "${DESTRUCTIVE_PATTERNS[@]}"; do
  if echo "$CMD" | grep -qE "$pattern"; then
    if check_override "block-destructive"; then
      exit 0  # Override active; allowed but logged.
    fi
    log_block \
      "destructive command pattern" \
      "Command matches '$pattern'. Per CLAUDE.md §2, this requires explicit user confirmation." \
      "CLAUDE.md §2 AI Action Boundaries"
    echo "" >&2
    echo "If this is genuinely needed:" >&2
    echo "  - The user runs it themselves, OR" >&2
    echo "  - Set CLAUDE_HOOK_OVERRIDE=block-destructive for one session (logged to .claude/logs/hooks.log)" >&2
    exit 2
  fi
done

for pattern in "${ASK_PATTERNS[@]}"; do
  if echo "$CMD" | grep -qE "$pattern"; then
    if check_override "block-destructive"; then
      exit 0  # Override active; allowed but logged.
    fi
    log_event "ASK" "dependency-install" "Command matches '$pattern' — asking the user"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Dependency install (CLAUDE.md §2 — propose, user approves). Matched pattern: %s"}}\n' "$pattern"
    exit 0
  fi
done

exit 0
