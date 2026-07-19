#!/usr/bin/env bash
# Claude project bootstrap — sources from main_template
# Usage:
#   claude-init <project-name>                    # creates $HOME/projects/<name>
#   claude-init --profile strict <name>           # minimal|standard|strict|team|security-sensitive
#   claude-init --dry-run [--profile P] <name>    # report what WOULD happen; writes nothing
#   CLAUDE_PROJECTS_DIR=/foo claude-init <name>   # custom destination root
#   CLAUDE_TEMPLATE_DIR=/bar claude-init <name>   # template cloned elsewhere
#
#   claude-template-status                        # in a generated project: drift report
#
# Failure-atomic: the project is assembled and validated in a temporary
# sibling directory and only renamed to <name> after every copy AND the hook
# installer succeed. A failed bootstrap leaves no destination, no temp dir, and
# the caller's working directory untouched (the assembly `cd` runs in a
# subshell; on SUCCESS the function intentionally cd's into the new project
# and prints "Currently at:").
#
# Copy model (v7): an explicit ALLOWLIST of template artifacts is copied —
# hooks, skills, settings.json, ENFORCEMENT.md — instead of `cp -r .claude`
# followed by pruning. Measured on a real checkout, 95% of the bytes the old
# model copied were machine-local worktrees (7.0M of 7.4M) that were then
# deleted again. The allowlist's own risk — a future template adds a new
# top-level `.claude/` entry and generated projects silently miss it — is
# closed by the unknown-entry check below, which FAILS the bootstrap rather
# than skipping silently.
# Limitations:
#   - A process KILLED mid-bootstrap (SIGINT/SIGKILL) can leave a
#     `.claude-init.XXXXXX` directory under the destination root — safe to
#     delete. (No trap is installed: this function is *sourced*, so a trap
#     here would mutate the caller's shell.)

# Template-owned .claude/ entries, copied into every project.
CLAUDE_INIT_ALLOWLIST=("hooks" "skills" "settings.json" "ENFORCEMENT.md")
# Machine-local state, expected in a working checkout, never copied.
CLAUDE_INIT_LOCAL=("worktrees" "logs" "settings.local.json" "CLEANUP_PLAN.md" "CLEANUP_EXECUTION.md" ".template-version" ".template-manifest")

claude-init() {
  local TEMPLATE="${CLAUDE_TEMPLATE_DIR:-$HOME/Claude_Project/main_template}"
  local DEST_ROOT="${CLAUDE_PROJECTS_DIR:-$HOME/projects}"
  local name="" profile="standard" dry_run=0

  while (( $# > 0 )); do
    case "$1" in
      --dry-run) dry_run=1; shift ;;
      --profile) profile="${2:-}"; shift 2 ;;
      --profile=*) profile="${1#--profile=}"; shift ;;
      -*)
        echo "✗ Unknown option '$1'. Usage: claude-init [--dry-run] [--profile P] <name>"
        return 1
        ;;
      *) name="$1"; shift ;;
    esac
  done

  case "$profile" in
    minimal|standard|strict|team|security-sensitive) ;;
    *)
      echo "✗ Unknown profile '$profile' — use minimal|standard|strict|team|security-sensitive."
      return 1
      ;;
  esac

  if [[ -z "$name" ]]; then
    echo "Usage: claude-init [--dry-run] [--profile P] <project-name>"
    echo "Creates: $DEST_ROOT/<project-name> from $TEMPLATE (profile: $profile)"
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
  local item
  for item in "${CLAUDE_INIT_ALLOWLIST[@]}"; do
    [[ -e "$TEMPLATE/.claude/$item" ]] || missing+=(".claude/$item")
  done
  if (( ${#missing[@]} > 0 )); then
    echo "✗ Template at $TEMPLATE is incomplete — missing: ${missing[*]}"
    echo "  Set up the template first (see HOW-TO.md Phase 2)."
    return 1
  fi

  # Unknown-entry check: an allowlist must fail LOUDLY on template content it
  # does not recognise, or new template features silently never reach projects.
  local entry base unknown=()
  for entry in "$TEMPLATE/.claude"/* "$TEMPLATE/.claude"/.[!.]*; do
    [[ -e "$entry" ]] || continue
    base="${entry##*/}"
    local known=1
    for item in "${CLAUDE_INIT_ALLOWLIST[@]}" "${CLAUDE_INIT_LOCAL[@]}"; do
      [[ "$base" == "$item" ]] && { known=0; break; }
    done
    (( known == 0 )) || unknown+=("$base")
  done
  if (( ${#unknown[@]} > 0 )); then
    echo "✗ Template .claude/ contains entries this installer does not know: ${unknown[*]}"
    echo "  Add them to CLAUDE_INIT_ALLOWLIST (copied) or CLAUDE_INIT_LOCAL (machine-local) in claude-init.sh."
    return 1
  fi

  local dest="$DEST_ROOT/$name"
  if [[ -e "$dest" ]]; then
    echo "✗ $dest already exists. Remove or pick a different name."
    return 1
  fi

  local tpl_commit
  tpl_commit=$(git -C "$TEMPLATE" rev-parse HEAD 2>/dev/null || echo "unknown")

  # ---- Dry run: report the exact plan, write nothing --------------------------
  if (( dry_run == 1 )); then
    echo "DRY RUN — nothing will be written."
    echo "  Template:      $TEMPLATE (commit ${tpl_commit:0:12})"
    echo "  Destination:   $dest (new directory; atomic rename from a temp sibling)"
    echo "  Profile:       $profile"
    echo "  Files copied:  CLAUDE.md, .gitignore, .gitattributes,"
    for item in "${CLAUDE_INIT_ALLOWLIST[@]}"; do
      echo "                 .claude/$item"
    done
    echo "  Excluded local state: ${CLAUDE_INIT_LOCAL[*]}"
    echo "  Overwrites:    none ($dest must not pre-exist)"
    case "$profile" in
      minimal)
        echo "  Hooks enabled: block-destructive, protect-files (PreToolUse)"
        echo "  ⚠ SAFETY REDUCED vs standard: scan-secrets and check-diff-size are DISABLED,"
        echo "    and the Stop-hook Definition-of-Done reminder is OFF."
        ;;
      standard) echo "  Hooks enabled: all five (Stop hook in reminder mode)" ;;
      strict)   echo "  Hooks enabled: all five; Stop hook BLOCKING (CLAUDE_VERIFY_BLOCK=1)" ;;
      team)     echo "  Hooks enabled: all five; repository-cleanup and release-readiness become manual-only (/name)" ;;
      security-sensitive)
        echo "  Hooks enabled: all five; Stop BLOCKING; diff hard-block tightened to 500 lines"
        ;;
    esac
    echo "  Version stamp: .claude/.template-version + .claude/.template-manifest (sha256 per managed file)"
    echo "  Required tools: bash, jq, git (verified by install.sh at real run)"
    echo "  Expected git changes: none until you 'git init && git add -A' in the new project"
    return 0
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
      && cp "$TEMPLATE/.gitignore" "$tmp/" \
      && cp "$TEMPLATE/.gitattributes" "$tmp/" \
      && mkdir -p "$tmp/.claude" \
      && cp -r "$TEMPLATE/.claude/hooks" "$tmp/.claude/" \
      && cp -r "$TEMPLATE/.claude/skills" "$tmp/.claude/" \
      && cp "$TEMPLATE/.claude/settings.json" "$tmp/.claude/" \
      && cp "$TEMPLATE/.claude/ENFORCEMENT.md" "$tmp/.claude/" \
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
  for req in CLAUDE.md .claude/hooks/install.sh .claude/skills .claude/settings.json .gitignore .gitattributes; do
    [[ -e "$tmp/$req" ]] || missing_req+=("$req")
  done
  if (( ${#missing_req[@]} > 0 )); then
    rm -rf "$tmp"
    echo "✗ Bootstrap failed — staged project missing: ${missing_req[*]}; nothing was created at $dest."
    return 1
  fi

  # install.sh's functional self-tests write .claude/logs/ inside the staging
  # tree; that is run output, not template content.
  rm -rf "$tmp/.claude/logs"

  # ---- Profile application (documented in HOW-TO.md; never silent) -----------
  # Transforms are jq-based edits of the staged settings.json; the source
  # template is never modified.
  case "$profile" in
    minimal)
      # Deny-tier scan-secrets and the diff guard are REMOVED — this is a
      # documented safety reduction, echoed at the end of the bootstrap.
      jq '
        .hooks.PreToolUse |= map(
          if .matcher == "Edit|Write|NotebookEdit"
          then .hooks |= map(select(.command | test("protect-files")))
          else . end)
        | del(.hooks.Stop)
      ' "$tmp/.claude/settings.json" > "$tmp/.claude/settings.json.new" \
        && mv "$tmp/.claude/settings.json.new" "$tmp/.claude/settings.json"
      ;;
    strict)
      jq '. + {env: ((.env // {}) + {CLAUDE_VERIFY_BLOCK: "1"})}' \
        "$tmp/.claude/settings.json" > "$tmp/.claude/settings.json.new" \
        && mv "$tmp/.claude/settings.json.new" "$tmp/.claude/settings.json"
      ;;
    security-sensitive)
      jq '. + {env: ((.env // {}) + {CLAUDE_VERIFY_BLOCK: "1", CLAUDE_DIFF_BLOCK_LINES: "500"})}' \
        "$tmp/.claude/settings.json" > "$tmp/.claude/settings.json.new" \
        && mv "$tmp/.claude/settings.json.new" "$tmp/.claude/settings.json"
      ;;
    team)
      # Workflow skills become manual-only (/repository-cleanup, /release-readiness):
      # deliberate multi-step efforts a team triggers explicitly. Insert the
      # frontmatter flag right after the name: line.
      local wf
      for wf in repository-cleanup release-readiness; do
        sed -i.bak "0,/^name: $wf$/s//name: $wf\ndisable-model-invocation: true/" \
          "$tmp/.claude/skills/$wf/SKILL.md" && rm -f "$tmp/.claude/skills/$wf/SKILL.md.bak"
      done
      ;;
  esac
  if [[ "$profile" != "standard" ]]; then
    if ! jq empty "$tmp/.claude/settings.json" 2>/dev/null; then
      rm -rf "$tmp"
      echo "✗ Profile '$profile' produced invalid settings.json — aborted; nothing was created."
      return 1
    fi
  fi

  # ---- Version stamp + managed-file manifest (update propagation, v7) --------
  # The manifest records the sha256 of every template-owned file AT GENERATION
  # TIME. claude-template-status compares current hashes against it to classify
  # drift; nothing is ever auto-overwritten.
  {
    echo "template_commit=$tpl_commit"
    echo "profile=$profile"
    echo "generated_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$tmp/.claude/.template-version"
  (
    cd "$tmp" \
      && find CLAUDE.md .gitignore .gitattributes .claude/hooks .claude/skills .claude/settings.json .claude/ENFORCEMENT.md \
           -type f 2>/dev/null | LC_ALL=C sort \
      | while IFS= read -r f; do
          printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$f"
        done
  ) > "$tmp/.claude/.template-manifest"

  if ! mv "$tmp" "$dest"; then
    rm -rf "$tmp"
    echo "✗ Could not move the finished project into $dest."
    return 1
  fi

  cd "$dest" || return 1

  echo ""
  echo "✅ Project '$name' bootstrapped at $dest (profile: $profile, template ${tpl_commit:0:12})"
  if [[ "$profile" == "minimal" ]]; then
    echo "⚠ minimal profile: scan-secrets, check-diff-size and the Stop reminder are DISABLED."
  fi
  echo ""
  echo "Next steps:"
  echo "  1. Fill 'Project Configuration' section in CLAUDE.md"
  echo "     \$EDITOR CLAUDE.md   # or:  code ."
  echo "  2. git init && git add -A && git commit -m 'chore: bootstrap'"
  echo "  3. Restart Claude Code in this directory"
  echo ""
  echo "Currently at: $(pwd)"
}

# Drift report for a generated project. Read-only: classifies every manifest
# entry as unchanged / locally modified / missing, and lists template-side
# updates only when the template checkout is reachable. NEVER writes.
claude-template-status() {
  local manifest=".claude/.template-manifest"
  local version=".claude/.template-version"
  if [[ ! -f "$manifest" || ! -f "$version" ]]; then
    echo "✗ No template manifest here — not a claude-init-generated project (or pre-v7)."
    return 1
  fi
  echo "== $(tr '\n' ' ' < "$version")"
  local unchanged=0 modified=0 miss_count=0
  local hash path current
  while IFS= read -r line; do
    hash="${line%%  *}"; path="${line#*  }"
    if [[ ! -f "$path" ]]; then
      echo "MISSING            $path"
      miss_count=$((miss_count+1))
    else
      current=$(sha256sum "$path" | cut -d' ' -f1)
      if [[ "$current" == "$hash" ]]; then
        unchanged=$((unchanged+1))
      else
        echo "LOCALLY MODIFIED   $path"
        modified=$((modified+1))
      fi
    fi
  done < "$manifest"
  echo "== unchanged=$unchanged locally-modified=$modified missing=$miss_count"
  echo "== policy: nothing is auto-overwritten; update by re-running claude-init into a new directory and diffing, or copy individual files after review."
}
