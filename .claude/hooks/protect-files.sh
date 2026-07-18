#!/usr/bin/env bash
# Guards sensitive files. Per CLAUDE.md §2 AI Action Boundaries and the
# per-project "Protected Paths" config.
# Hook event: PreToolUse, matcher: Edit|Write|NotebookEdit
#
# Two tiers:
#   DENY (exit 2)  — secrets and git internals. Never silently edited; unblock
#                    only via manual edit or CLAUDE_HOOK_OVERRIDE (logged).
#   ASK  (exit 0 + permissionDecision:"ask") — CI/infra/migrations/lockfiles/
#                    settings/hooks. Legitimate WITH the user's approval, so the
#                    user can approve in-chat instead of restarting (§2 "confirm").
#
# Matching is on normalized PATH COMPONENTS / exact basenames — never raw
# substrings — so `config.environment.ts` is not mistaken for `.env`.

export CLAUDE_HOOK_NAME="protect-files"
source "$(dirname "$0")/lib.sh"
require_jq

INPUT=$(read_input)
# NotebookEdit sends notebook_path instead of file_path.
FILE=$(json_get "$INPUT" '.tool_input.file_path // .tool_input.notebook_path')

if [[ -z "$FILE" ]]; then
  exit 0
fi

# Normalize: backslashes -> forward slashes; wrap in slashes so directory
# components can be matched as exact, slash-bounded segments (`/infra/` will
# not match `infrastructure`).
FILE_N="${FILE//\\//}"
BASE="${FILE_N##*/}"
SEG="/${FILE_N#/}/"

# --- Allowlist: committed env templates are editable documentation ------------
ALLOWLIST_BASE=(
  ".env.example"
  ".env.sample"
  ".env.template"
  ".env.dist"
  ".env.test.example"
)
for allowed in "${ALLOWLIST_BASE[@]}"; do
  if [[ "$BASE" == "$allowed" ]]; then
    exit 0  # explicit template/sample; editable
  fi
done

# --- Helpers ------------------------------------------------------------------
# True if the path contains an exact directory segment (or adjacent segments).
has_segment() { [[ "$SEG" == *"/$1/"* ]]; }
# True if the basename equals one of the given names.
base_is() {
  local b
  for b in "$@"; do [[ "$BASE" == "$b" ]] && return 0; done
  return 1
}

# --- DENY: secrets and git internals (hard block) -----------------------------
DENY=false
# .env and any .env.<suffix> (allowlisted templates already returned above).
if [[ "$BASE" == ".env" || "$BASE" == .env.* ]]; then DENY=true; fi
base_is "secrets.yaml" "secrets.yml" "credentials.json" "credentials.yaml" && DENY=true
has_segment ".secrets" && DENY=true
has_segment ".git" && DENY=true

if [[ "$DENY" == "true" ]]; then
  if check_override "protect-files"; then
    exit 0
  fi
  log_block \
    "protected secret/internal file" \
    "$FILE is a secret or git-internal file (never edited automatically)." \
    "CLAUDE.md §2 + §7 Secrets"
  echo "" >&2
  echo "Options:" >&2
  echo "  - The user edits the file directly, OR" >&2
  echo "  - Set CLAUDE_HOOK_OVERRIDE=protect-files for one session (logged)." >&2
  exit 2
fi

# --- ASK: legitimate with the user's approval ---------------------------------
ASK=false
# Lockfiles (regenerated, not hand-edited)
base_is "package-lock.json" "pnpm-lock.yaml" "yarn.lock" "uv.lock" "poetry.lock" \
        "Pipfile.lock" "Cargo.lock" "go.sum" "Gemfile.lock" "composer.lock" && ASK=true
# CI/CD
has_segment ".github" && has_segment "workflows" && ASK=true
base_is ".gitlab-ci.yml" "Jenkinsfile" "azure-pipelines.yml" ".drone.yml" && ASK=true
has_segment ".circleci" && ASK=true
has_segment "buildkite" && ASK=true
# Infrastructure
has_segment "infra" && ASK=true
has_segment "terraform" && ASK=true
has_segment "pulumi" && ASK=true
has_segment "cdk" && ASK=true
# Kubernetes / Helm (production)
{ has_segment "k8s" || has_segment "manifests" || has_segment "charts"; } &&
  { has_segment "prod" || has_segment "production"; } && ASK=true
# Containers (production-impacting)
base_is "docker-compose.production.yml" "docker-compose.prod.yml" && ASK=true
# Migrations (often auto-run)
has_segment "migrations" && ASK=true
{ has_segment "alembic" && has_segment "versions"; } && ASK=true
{ has_segment "db" && has_segment "migrate"; } && ASK=true
{ has_segment "prisma" && has_segment "migrations"; } && ASK=true
# Ownership / policy / enforcement layer
base_is "CODEOWNERS" ".gitattributes" && ASK=true
[[ "$FILE_N" == *".claude/settings.json" ]] && ASK=true
has_segment ".claude" && has_segment "hooks" && ASK=true

if [[ "$ASK" == "true" ]]; then
  if check_override "protect-files"; then
    exit 0
  fi
  log_event "ASK" "protected-file" "$FILE needs approval before editing"
  # Built with jq, never printf-interpolated: the basename is user-controlled,
  # and a quote/tab/newline in it must not be able to corrupt the JSON (which
  # would silently drop the ask).
  jq -cn --arg base "$BASE" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:("Protected path (CLAUDE.md §2 — confirm before editing): " + $base + ". Approve to proceed, or edit it yourself.")}}'
  exit 0
fi

exit 0
