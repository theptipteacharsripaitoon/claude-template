#!/usr/bin/env bash
# Claude project bootstrap — sources from main_template
# Usage:
#   claude-init <project-name>            # creates $HOME/projects/<name>
#   CLAUDE_PROJECTS_DIR=/foo claude-init <name>   # custom destination root
#   CLAUDE_TEMPLATE_DIR=/bar claude-init <name>   # template cloned elsewhere

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

  if [[ ! -d "$TEMPLATE/.claude" ]]; then
    echo "✗ Template not found at $TEMPLATE"
    echo "  Set up the template first (see HOW-TO.md Phase 2)."
    return 1
  fi

  local dest="$DEST_ROOT/$name"
  if [[ -e "$dest" ]]; then
    echo "✗ $dest already exists. Remove or pick a different name."
    return 1
  fi

  mkdir -p "$dest" && cd "$dest" || return 1

  cp "$TEMPLATE/CLAUDE.md" ./
  cp -r "$TEMPLATE/.claude" ./

  if ! bash .claude/hooks/install.sh; then
    echo "✗ Hook install failed. Project at $dest may be incomplete."
    return 1
  fi

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
