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

# --- Multiline normalization (v8) --------------------------------------------
# grep matches line by line, so before v8 any newline between `rm -rf` and its
# dangerous target slipped the recursive-rm patterns: `rm -rf \<LF>/` (bash
# line continuation), `rm -rf<LF>/`, a CRLF split, or `rm -r<LF>-f /` all
# matched NOTHING and were allowed. Normalize a MATCH-ONLY copy so the patterns
# see one logical line; $CMD itself is left intact (the block message reports
# the matched pattern, never the command, so logs are unaffected).
#   1. A backslash line-continuation (`\` + optional CR + LF) joins tokens in
#      bash — collapse it to a space.
#   2. Any remaining CR or LF becomes a space, so a target split across
#      physical lines cannot hide a recursive rm. This can flag a heredoc that
#      literally contains a dangerous command (`cat <<EOF … rm -rf / … EOF`),
#      which is consistent with the hook's existing conservative stance (prose
#      merely mentioning a dangerous command is already blocked) — override or
#      reword. Single-line prose protections are untouched: a command with no
#      newline is not modified here.
CMD_MATCH=$CMD
CMD_MATCH=${CMD_MATCH//$'\\\r\n'/ }   # continuation, CRLF
CMD_MATCH=${CMD_MATCH//$'\\\n'/ }     # continuation, LF
CMD_MATCH=${CMD_MATCH//$'\r'/ }       # bare CR
CMD_MATCH=${CMD_MATCH//$'\n'/ }       # bare LF

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
  # The optional quote class is on the TARGET, not just the command: quoting the
  # target (`rm -rf '/srv/data'`) must not defeat the absolute-path rule (v7).
  "${RM_REC}[\"']?/"                                      # rm -rf /abs/path (any flag spelling)
  "${RM_REC}\\*"                                          # rm -rf *
  # $HOME and $PWD are the same class of disaster: one wipes the home tree, the
  # other the current project tree. $PWD/${PWD} were uncovered before v7.
  "${RM_REC}[\"']?\\\$\\{?(HOME|PWD)\\}?"                 # rm -rf $HOME / ${PWD} (quoted or not)
  "${RM_REC}[\"']?\\\$\\(pwd\\)"                          # rm -rf "$(pwd)" (command substitution)
  "${RM_REC}~"                                            # rm -rf ~
  # Brace expansion sweeps everything including dotfiles: rm -rf {*,.[!.]*,..?*}
  "${RM_REC}[\"']?\\{"                                    # rm -rf {…}
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
  # Character-class dotglobs delete every hidden entry INCLUDING .git — measured
  # in the v7 audit, not theoretical. Covers .[!.]* and .[^.]* with or without
  # a ./ prefix. A named target cannot match: `[` must follow the dot.
  "${RM_REC}[\"']?(\\./)?[\"']?\\.\\[[!^]"                # rm -rf .[!.]* | .[^.]*
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
  # Long spellings (--command/--execute/--query) are flag forms too, joined by
  # either `=` or a space. Before v7 only the single-letter forms matched, so
  # `psql --command="DELETE FROM users"` ran unguarded while `psql -c` was denied.
  "(psql|mysql|sqlcmd)[[:space:]]+((-{1,2})?[A-Za-z0-9_./=@:-]+[[:space:]]+)*(-[ceq]|--(command|execute|query))[[:space:]=]*[\"']DELETE[[:space:]]+FROM[[:space:]]+[][a-zA-Z0-9_.]+[[:space:]]*;?[[:space:]]*[\"']"

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
# Every ASK pattern is matched at a COMMAND POSITION (start of string or after a
# shell separator) via $PM at the match site below. Without it the patterns were
# raw substrings: `cargo install ripgrep` matched the *go* pattern through the
# trailing "go" of car-go, so it asked for the wrong reason, and `mongo install`
# / `django get` matched too (v7).
PM='(^|[[:space:];|&(])'

ASK_PATTERNS=(
  # -- add / install a new package --
  # Options may come FIRST (npm install --save-dev lodash, npm i -D x,
  # npm install -g tsc): skip any option words, then require a package name.
  # A bare/options-only `npm install` (lockfile restore) still has no package
  # token after the options, so it stays allowed. GLOBAL options may also come
  # before the subcommand (`npm --prefix /tmp install lodash`), which bypassed
  # this entirely before v7.
  "npm([[:space:]]+-{1,2}[A-Za-z][A-Za-z0-9-]*([[:space:]]+|=)[^-[:space:]]+)*[[:space:]]+(install|i)[[:space:]]+(-{1,2}[A-Za-z][A-Za-z-]*[[:space:]]+)*[@a-zA-Z]"
  # Local-path installs (npm install ./pkg, ../pkg, /abs/pkg) mutate the
  # manifest exactly like a registry install. The path must sit IMMEDIATELY
  # after the subcommand: that keeps `npm install --prefix ./out` (bare
  # restore redirected by an option value) allowed, per the v6 rows.
  # `npm install -D ./pkg` (option before a local path) is a documented residual.
  "npm[[:space:]]+(install|i)[[:space:]]+[\"']?\\.{0,2}/"
  'yarn[[:space:]]+add[[:space:]]'
  'pnpm[[:space:]]+add[[:space:]]'
  'bun[[:space:]]+add[[:space:]]'                         # Bun (growing)
  # pip install is NOT a pattern: its option grammar needs real logic (below).
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
  # -- global tool installs (plan §10 decision 4) --
  # These do not touch the project manifest, but they fetch and EXECUTE new
  # third-party code, which is the same supply-chain decision `gem install` and
  # `go install` already ask about. Asked deliberately here; before v7 `pipx`
  # and `uv tool` were allowed outright and `cargo install` asked by accident.
  'cargo[[:space:]]+install[[:space:]]'
  'pipx[[:space:]]+(install|inject|upgrade)([[:space:]]|$)'
  'uv[[:space:]]+tool[[:space:]]+(install|upgrade)([[:space:]]|$)'
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

# Fast path (v7 latency fix): ONE combined grep decides whether anything
# matched; the per-pattern loop runs only on a hit, to name the pattern in the
# block message. Before this, ~85 patterns each spawned `echo | grep` on EVERY
# Bash call — measured p50 2.18 s on Windows, 6x every other hook. Each pattern
# is parenthesized so its internal alternations cannot leak into the joins.
COMBINED_DESTRUCTIVE=""
for pattern in "${DESTRUCTIVE_PATTERNS[@]}"; do
  COMBINED_DESTRUCTIVE+="|(${pattern})"
done
COMBINED_DESTRUCTIVE="${COMBINED_DESTRUCTIVE#|}"
COMBINED_ASK=""
for pattern in "${ASK_PATTERNS[@]}"; do
  COMBINED_ASK+="|(${PM}${pattern})"
done
COMBINED_ASK="${COMBINED_ASK#|}"

MATCHED_DESTRUCTIVE=false
if echo "$CMD_MATCH" | grep -qiE "$COMBINED_DESTRUCTIVE"; then MATCHED_DESTRUCTIVE=true; fi

[[ "$MATCHED_DESTRUCTIVE" == "true" ]] && for pattern in "${DESTRUCTIVE_PATTERNS[@]}"; do
  if echo "$CMD_MATCH" | grep -qiE "$pattern"; then
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

MATCHED_ASK=false
if echo "$CMD_MATCH" | grep -qE "$COMBINED_ASK"; then MATCHED_ASK=true; fi

[[ "$MATCHED_ASK" == "true" ]] && for pattern in "${ASK_PATTERNS[@]}"; do
  if echo "$CMD_MATCH" | grep -qE "${PM}${pattern}"; then
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

# pip needs policy, not a pattern. `pip install -r reqs.txt` is a RESTORE
# (allowed) but `pip install -c constraints.txt requests` and even
# `pip install -q requests` install a NEW package (ask). A single regex cannot
# express "an option consumed its value UNLESS that option was -r", so the rule
# is written out: a requirement file makes it a restore whatever else is
# present; otherwise a trailing package token makes it an install. Before v7 the
# pattern required a non-dash immediately after `install `, so ANY leading
# option — a bare `-q` — silently downgraded a real install to allow.
if echo "$CMD_MATCH" | grep -qE "${PM}pip3?[[:space:]]+install([[:space:]]|$)" \
   && ! echo "$CMD_MATCH" | grep -qE '[[:space:]](-r|--requirement)([[:space:]]|=)' \
   && echo "$CMD_MATCH" | grep -qE "install([[:space:]]+-{1,2}[A-Za-z][A-Za-z0-9-]*([[:space:]]+|=)[^-[:space:]]+|[[:space:]]+-{1,2}[A-Za-z][A-Za-z0-9-]*)*[[:space:]]+[@a-zA-Z][^[:space:]]*([[:space:]]|$)"; then
  if check_override "block-destructive"; then
    exit 0  # Override active; allowed but logged.
  fi
  log_event "ASK" "dependency-change" "pip install of a new package — asking the user"
  jq -cn '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:"Dependency change (CLAUDE.md §2 — pip install of a new package needs the user'\''s approval; -r/--requirement restores are allowed)."}}'
  exit 0
fi

# CLAUDE.md §2 forbids direct commits to protected branches. Enforced as a
# low-noise ASK (not deny): a solo main-branch flow stays possible with one
# in-chat approval, and feature-branch commits are untouched. Plain `git push`
# deliberately stays in Claude Code's normal permission flow (hooks README
# tier table) — an ask here would just duplicate that prompt.
# Command position includes `/` and `\` so a path-invoked git (/usr/bin/git)
# is recognised — matching RM_WORD, which already did this. Any run of git
# GLOBAL options may sit between `git` and `commit`: before v7 the subcommand
# had to be adjacent, so `-C`, `-c`, `--no-pager`, `--git-dir` and every future
# global option silently hid the commit from this check.
if echo "$CMD_MATCH" | grep -qE '(^|[[:space:];|&/\\])git([[:space:]]+-{1,2}[A-Za-z][A-Za-z0-9-]*(=[^[:space:]]+)?([[:space:]]+[^-[:space:]]+)?)*[[:space:]]+commit([[:space:]]|$)'; then
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
