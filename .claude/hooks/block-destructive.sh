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
# A recursive rm in ANY spelling: clustered (-rf, -fr, -Rf), split (-r -f),
# or long (--recursive [--force]), with other flags interleaved — anchored at a
# command position so substrings of other words (confirm, npm) can never match.
# The dangerous-target patterns below append what the recursion aims at.
RM_FLAG='-{1,2}[a-zA-Z][a-zA-Z-]*'
# Command-word spellings, two alternatives:
#  1. bare `rm` — the char before it may be start-of-string, a shell separator,
#     `/` (path prefix: /bin/rm) or `\` (alias escape: \rm); an optional
#     closing quote directly AFTER it catches quoted paths (`"/bin/rm" -rf`).
#  2. fully-quoted bare name (`'rm' -rf`, `"rm" -rf`) — quotes required on
#     BOTH sides of rm, so prose like `echo 'rm -rf /'` (no quote directly
#     after rm) still cannot match. A letter before `rm` (confirm) never matches.
RM_WORD="((^|[[:space:];|&/\\])rm[\"']?|(^|[[:space:];|&])[\"']rm[\"'])"
# A trailing `(--[[:space:]]+)?` lets the idiomatic end-of-options marker sit
# between the flags and the target (`rm -rf -- /`).
RM_REC="${RM_WORD}[[:space:]]+(${RM_FLAG}[[:space:]]+)*(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]+${RM_FLAG})*[[:space:]]+(--[[:space:]]+)?"

# shellcheck disable=SC2016  # single quotes are intentional: these are regexes,
# the literal '\$HOME' must NOT be shell-expanded.
# Matched case-INSENSITIVELY (grep -i): SQL keywords arrive in any case, and a
# lowercase 'drop table' is exactly as destructive as 'DROP TABLE'.
DESTRUCTIVE_PATTERNS=(
  # Filesystem
  "${RM_REC}/"                                            # rm -rf /abs/path (any flag spelling)
  "${RM_REC}\\*"                                          # rm -rf *
  "${RM_REC}[\"']?\\\$\\{?HOME\\}?"                       # rm -rf $HOME / ${HOME} (quoted or not)
  "${RM_REC}~"                                            # rm -rf ~
  # Current-directory destruction (v6). The GLOB forms really delete
  # (`rm -rf ./*` wipes every visible entry — equivalent to the already-denied
  # bare `*`); the dot targets (`.`, `./`, `..`) are refused by GNU rm itself
  # (POSIX), but the intent is destructive and there is zero legitimate use, so
  # they are denied as defense-in-depth. NAMED relative cleanup (rm -rf
  # ./build, rm -rf ../tmp-build) deliberately stays allowed: after the
  # optional quote/dot prefix these patterns require end-of-target or a glob,
  # so a name character breaks the match.
  "${RM_REC}[\"']?\\.\\.?/?[\"']?([[:space:]]|$)"         # rm -rf . | ./ | ..
  "${RM_REC}[\"']?\\./?[\"']?\\*"                         # rm -rf ./* | "./"* | .*
  "${RM_REC}[\"']?(\\./)?[\"']?\\.\\?\\?\\*"              # rm -rf ./.??* | .??*
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
  # force via +refspec, incl. a quoted refspec: git push origin +main / "+main"
  "git[[:space:]]+push[[:space:]]+.*[[:space:]][\"']?\\+[A-Za-z0-9_/]"
  'git[[:space:]]+reset[[:space:]]+--hard'                # hard reset
  # clean needs BOTH -f and -d, in either order, same cluster or split
  'git[[:space:]]+clean([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-[a-zA-Z]*(f[a-zA-Z]*d|d[a-zA-Z]*f)'
  'git[[:space:]]+clean([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-[a-zA-Z]*d'
  'git[[:space:]]+clean([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-[a-zA-Z]*d[a-zA-Z]*([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-[a-zA-Z]*f'
  'git[[:space:]]+filter-branch'                          # history rewrite
  'git[[:space:]]+update-ref[[:space:]]+-d'               # delete ref

  # Database. DELETE table-name class includes . [ ] so schema-qualified and
  # bracketed forms (dbo.Users, [dbo].[Users]) are covered; a WHERE clause still
  # breaks the match (the name is not immediately followed by ';' or line end).
  'DROP[[:space:]]+(TABLE|DATABASE|SCHEMA|VIEW|PROC|PROCEDURE|INDEX|FUNCTION|TRIGGER)' # DROP object
  'TRUNCATE[[:space:]]+TABLE'                             # TRUNCATE
  'DELETE[[:space:]]+FROM[[:space:]]+[][a-zA-Z0-9_.]+[[:space:]]*;' # DELETE without WHERE, ;-terminated
  # DELETE without WHERE that simply ENDS the command (no semicolon). The line
  # must end right after the table name — a closing quote is deliberately NOT
  # matched, so documentation text (echo "DELETE FROM users", a commit message)
  # stays allowed; quote-wrapped client strings without ';' remain uncovered
  # (documented residual, see hooks README).
  'DELETE[[:space:]]+FROM[[:space:]]+[][a-zA-Z0-9_.]+[[:space:]]*$' # DELETE without WHERE, end-of-command
  # Client-wrapped unguarded DELETE with NO ';' (v6): `psql -c "DELETE FROM
  # users"` executes a full-table delete, but the closing quote defeats both
  # anchors above (by design — that boundary is what keeps prose allowed). So
  # match the CLIENT invocation shape explicitly: psql/mysql/sqlcmd, any
  # intervening options/values, the SQL-carrying flag (-c/-e/-Q, any case via
  # grep -i), a quote, then DELETE FROM <name> with only ;/spaces before the
  # closing quote — a WHERE clause still breaks the match. Prose controls
  # (echo/printf/commit messages) carry no client token and stay allowed.
  # Other clients (e.g. sqlite3's positional SQL) remain a documented residual.
  "(psql|mysql|sqlcmd)[[:space:]]+((-{1,2})?[A-Za-z0-9_./=@:-]+[[:space:]]+)*-[ceq][[:space:]]*[\"']DELETE[[:space:]]+FROM[[:space:]]+[][a-zA-Z0-9_.]+[[:space:]]*;?[[:space:]]*[\"']"

  # Cluster / cloud
  'kubectl[[:space:]]+delete[[:space:]]+(namespace|ns)[[:space:]]'
  'kubectl[[:space:]]+.*--all-namespaces.*--all'
  'helm[[:space:]]+uninstall'
  'terraform[[:space:]]+(destroy|apply)'                  # any apply needs human
  'aws[[:space:]]+s3[[:space:]]+rb[[:space:]]+.*--force'  # delete S3 bucket
  'gcloud[[:space:]]+.*delete[[:space:]]'                 # gcloud delete

)

# Package managers (per CLAUDE.md §2: install, upgrade, or remove — propose,
# the user approves). These get an interactive ASK
# (hookSpecificOutput.permissionDecision) instead of a hard deny — mutating the
# dependency set is a legitimate action that needs the user's yes, not a
# blocked one. RESTORE commands (npm ci / bare install, pip install -r,
# uv sync, poetry/bundle/composer install) deliberately do NOT ask: they
# reinstall an already-committed manifest/lockfile, which is not a new
# supply-chain decision. Modern npm 5+ saves by default — match any
# `npm install <pkg>`, not just --save.
ASK_PATTERNS=(
  # -- add / install a new package --
  # Options may come FIRST (npm install --save-dev lodash, npm i -D x,
  # npm install -g tsc): skip any option words, then require a package name.
  # A bare/options-only `npm install` (lockfile restore) still has no package
  # token after the options, so it stays allowed.
  "npm[[:space:]]+(install|i)[[:space:]]+(-{1,2}[A-Za-z][A-Za-z-]*[[:space:]]+)*[@a-zA-Z]"
  'yarn[[:space:]]+add[[:space:]]'
  'pnpm[[:space:]]+add[[:space:]]'
  'bun[[:space:]]+add[[:space:]]'                         # Bun (growing)
  'pip3?[[:space:]]+install[[:space:]]+[^-]'              # pip install <pkg> (allows -e/-r)
  # pip option-first install into the user site (a new-package decision, not a
  # restore; -r/-e/-c restores don't carry --user in this template's flows).
  'pip3?[[:space:]]+install[[:space:]]+.*--user([[:space:]]|$)'
  # Env-redirected installs (v6): a value-taking option (--prefix /tmp,
  # --target /tmp) or --no-deps defeats the option-skip idioms above, but these
  # commands still fetch and install NEW code — a supply-chain decision. A
  # non-default --index-url is one too (dependency-confusion surface), even on
  # a -r restore; that over-ask is deliberate and documented. npm --prefix asks
  # only when a package token follows (a bare `npm install --prefix DIR`
  # lockfile restore stays allowed).
  "npm[[:space:]]+(install|i)[[:space:]]+.*--prefix([[:space:]]|=).*[[:space:]][@a-zA-Z]"
  'pip3?[[:space:]]+install[[:space:]]+.*--target([[:space:]]|=|$)'
  'pip3?[[:space:]]+install[[:space:]]+.*--no-deps([[:space:]]|$)'
  'pip3?[[:space:]]+install[[:space:]]+.*--index-url([[:space:]]|=|$)'
  'pip3?[[:space:]]+install[[:space:]]+.*--prefix([[:space:]]|=|$)'
  'poetry[[:space:]]+add[[:space:]]'
  'uv[[:space:]]+add[[:space:]]'                          # uv (modern Python)
  'cargo[[:space:]]+add[[:space:]]'
  'gem[[:space:]]+install[[:space:]]'                     # Ruby
  'composer[[:space:]]+require[[:space:]]'                # PHP
  'go[[:space:]]+install[[:space:]]'                      # Go binaries
  'go[[:space:]]+get[[:space:]]'                          # mutates go.mod
  # -- remove / uninstall (mutates the manifest) --
  'npm[[:space:]]+(uninstall|remove|rm|un)([[:space:]]|$)'
  'pnpm[[:space:]]+(remove|rm|uninstall|un)([[:space:]]|$)'
  'yarn[[:space:]]+remove([[:space:]]|$)'
  'bun[[:space:]]+(remove|rm|uninstall)([[:space:]]|$)'
  'pip3?[[:space:]]+uninstall([[:space:]]|$)'
  'uv[[:space:]]+remove([[:space:]]|$)'
  'poetry[[:space:]]+remove([[:space:]]|$)'
  'cargo[[:space:]]+remove([[:space:]]|$)'
  'gem[[:space:]]+uninstall([[:space:]]|$)'
  'composer[[:space:]]+remove([[:space:]]|$)'
  # -- update / upgrade (pulls new code: a supply-chain decision) --
  'npm[[:space:]]+(update|upgrade)([[:space:]]|$)'
  'pnpm[[:space:]]+(update|up|upgrade)([[:space:]]|$)'
  'yarn[[:space:]]+(upgrade|up)([[:space:]]|$)'
  'bun[[:space:]]+update([[:space:]]|$)'
  'pip3?[[:space:]]+install[[:space:]]+(-U([[:space:]]|$)|--upgrade)'
  'poetry[[:space:]]+update([[:space:]]|$)'
  'cargo[[:space:]]+update([[:space:]]|$)'
  'gem[[:space:]]+update([[:space:]]|$)'
  'bundle[[:space:]]+update([[:space:]]|$)'
  'composer[[:space:]]+(update|upgrade)([[:space:]]|$)'
)

for pattern in "${DESTRUCTIVE_PATTERNS[@]}"; do
  if echo "$CMD" | grep -qiE "$pattern"; then
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
    log_event "ASK" "dependency-change" "Command matches '$pattern' — asking the user"
    # Built with jq, never printf-interpolated: the reason must stay valid JSON
    # no matter what characters a future pattern contains.
    jq -cn --arg pattern "$pattern" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:("Dependency change (CLAUDE.md §2 — install/upgrade/remove needs the user'\''s approval; lockfile restores are allowed). Matched pattern: " + $pattern)}}'
    exit 0
  fi
done

# CLAUDE.md §2 forbids direct commits to protected branches. Enforced as a
# low-noise ASK (not deny): a solo main-branch flow stays possible with one
# in-chat approval, and feature-branch commits are untouched. Plain `git push`
# deliberately stays in Claude Code's normal permission flow (hooks README
# tier table) — an ask here would just duplicate that prompt.
if echo "$CMD" | grep -qE '(^|[[:space:];|&])git[[:space:]]+commit([[:space:]]|$)'; then
  BRANCH=$(git -C "${CLAUDE_PROJECT_DIR:-.}" branch --show-current 2>/dev/null || true)
  case "$BRANCH" in
    main|master|production|release/*)
      if check_override "block-destructive"; then
        exit 0  # Override active; allowed but logged.
      fi
      log_event "ASK" "protected-branch-commit" "git commit while on '$BRANCH'"
      jq -cn --arg branch "$BRANCH" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:("You are on protected branch '\''" + $branch + "'\'' (CLAUDE.md §2: no direct commits to protected branches). Approve to commit here anyway, or switch to a feature branch.")}}'
      exit 0
      ;;
  esac
fi

exit 0
