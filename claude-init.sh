#!/usr/bin/env bash
# Claude project bootstrap — sources from main_template
# Usage:
#   claude-init <project-name>            # creates $HOME/projects/<name>
#   CLAUDE_PROJECTS_DIR=/foo claude-init <name>   # custom destination root
#   CLAUDE_TEMPLATE_DIR=/bar claude-init <name>   # template cloned elsewhere
#
# Failure-atomic: the project is assembled and validated in a temporary
# sibling directory and only renamed to <name> after every copy AND the hook
# installer succeed. A failed bootstrap leaves no destination, no temp dir, and
# the caller's working directory untouched (all cd's happen in a subshell).
# Limitation: a process KILLED mid-bootstrap (SIGINT/SIGKILL) can leave a
# `.claude-init.XXXXXX` directory under the destination root — safe to delete.
# (No trap is installed: this function is *sourced*, so a trap here would
# mutate the caller's shell.)

claude-init() {
  local TEMPLATE="${CLAUDE_TEMPLATE_DIR:-$HOME/Claude_Project/main_template}"
  local DEST_ROOT="${CLAUDE_PROJECTS_DIR:-$HOME/projects}"
  local name="${1:-}"

  if [[ -z "$name" ]]; then
    echo "Usage: claude-init <project-name>"
    echo "Creates: $DEST_ROOT/<project-name> from $TEMPLATE"
    echo "Override destination root: CLAUDE_PROJECTS_DIR=/some/path claude-init <name>"
    return 1
  fi

  # The name must be a single safe path component — a separator or a relative
  # special name could escape DEST_ROOT (e.g. '../escape').
  case "$name" in
    */* | *\\* | . | .. | -*)
      echo "✗ Invalid project name '$name' — use a single folder name (no / or \\, not . or .., no leading -)."
      return 1
      ;;
  esac

  # Validate EVERY required template source before creating anything: a
  # template missing CLAUDE.md or the root protections must fail up front,
  # not produce a half-usable project that reports success.
  local missing=()
  [[ -f "$TEMPLATE/CLAUDE.md" ]]                 || missing+=("CLAUDE.md")
  [[ -d "$TEMPLATE/.claude" ]]                   || missing+=(".claude/")
  [[ -f "$TEMPLATE/.claude/hooks/install.sh" ]]  || missing+=(".claude/hooks/install.sh")
  [[ -f "$TEMPLATE/.gitignore" ]]                || missing+=(".gitignore")
  [[ -f "$TEMPLATE/.gitattributes" ]]            || missing+=(".gitattributes")
  if (( ${#missing[@]} > 0 )); then
    echo "✗ Template at $TEMPLATE is incomplete — missing: ${missing[*]}"
    echo "  Set up the template first (see HOW-TO.md Phase 2)."
    return 1
  fi

  local dest="$DEST_ROOT/$name"
  if [[ -e "$dest" ]]; then
    echo "✗ $dest already exists. Remove or pick a different name."
    return 1
  fi

  mkdir -p "$DEST_ROOT" || return 1

  # Build in a temp SIBLING (same filesystem) so the final rename is atomic.
  local tmp
  tmp=$(mktemp -d "$DEST_ROOT/.claude-init.XXXXXX") || return 1

  # .gitignore/.gitattributes are required root protections: without them,
  # `git add -A` below would stage .env / machine-local state, and .sh hooks
  # could be checked out CRLF on Windows and break bash.
  # The steps are `&&`-chained, NOT `set -e`: this subshell is the operand of
  # `if !`, a context where bash ignores `-e` entirely (even a `set -e` issued
  # inside it) — so with plain command sequencing, a failed `cp CLAUDE.md`
  # would be masked by a later `install.sh` exit 0 and an incomplete project
  # would publish with a success message. `&&` short-circuits regardless of
  # `set -e` context, so the first failure is the subshell's status.
  if ! (
    cp "$TEMPLATE/CLAUDE.md" "$tmp/" \
      && cp -r "$TEMPLATE/.claude" "$tmp/" \
      && cp "$TEMPLATE/.gitignore" "$tmp/" \
      && cp "$TEMPLATE/.gitattributes" "$tmp/" \
      && cd "$tmp" \
      && bash .claude/hooks/install.sh
  ); then
    rm -rf "$tmp"
    echo "✗ Bootstrap failed — cleaned up; nothing was created at $dest."
    return 1
  fi

  # Belt-and-braces: never publish a staged tree that is missing a required
  # artifact, no matter how a future edit re-sequences the block above.
  local req
  local missing_req=()
  for req in CLAUDE.md .claude/hooks/install.sh .gitignore .gitattributes; do
    [[ -e "$tmp/$req" ]] || missing_req+=("$req")
  done
  if (( ${#missing_req[@]} > 0 )); then
    rm -rf "$tmp"
    echo "✗ Bootstrap failed — staged project missing: ${missing_req[*]}; nothing was created at $dest."
    return 1
  fi

  # Strip machine-local Claude state that a `cp -r .claude` would otherwise
  # carry over from the template checkout (another dev's logs, a session's
  # worktrees, local settings, cleanup planning artifacts). Done on the success
  # path, before publishing, so a failed bootstrap's cleanup is unaffected. These
  # are the same paths .gitignore excludes; seed-repo.sh prunes worktrees/logs too.
  # install.sh's functional self-tests write .claude/logs/, so prune after it ran.
  rm -rf "$tmp/.claude/worktrees" \
         "$tmp/.claude/logs" \
         "$tmp/.claude/settings.local.json" \
         "$tmp/.claude/CLEANUP_PLAN.md" \
         "$tmp/.claude/CLEANUP_EXECUTION.md"

  if ! mv "$tmp" "$dest"; then
    rm -rf "$tmp"
    echo "✗ Could not move the finished project into $dest."
    return 1
  fi

  cd "$dest" || return 1

  echo ""
  echo "✅ Project '$name' bootstrapped at $dest"
  echo ""
  echo "Next steps:"
  echo "  1. Fill 'Project Configuration' section in CLAUDE.md"
  echo "     \$EDITOR CLAUDE.md   # or:  code ."
  echo "  2. git init && git add -A && git commit -m 'chore: bootstrap'"
  echo "  3. Restart Claude Code in this directory"
  echo ""
  echo "Currently at: $(pwd)"
}
