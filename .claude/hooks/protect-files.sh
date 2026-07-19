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
# Matching is on slash-bounded PATH SEGMENTS / exact basenames (case-folded for
# the .env check) — never raw substrings — so `config.environment.ts` is not
# mistaken for `.env`. Limitation: `..` is NOT resolved, so a path like
# `infra/../src/app.py` still matches the `infra` segment and errs toward ASK
# (over-cautious, never a dangerous allow). Symlinks are likewise not resolved.

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
# Case-normalization strategy (one rule, applied everywhere): EVERY comparison
# in this hook — basenames, extensions, AND directory segments — is
# case-folded, because on this repo's primary platforms (Windows/macOS) case
# variants address the SAME file: `.GIT/config` reaches the real `.git/config`
# exactly as `ID_RSA` reaches `id_rsa` (v6; segments were case-sensitive
# before, a deny/ask bypass on case-insensitive filesystems). On case-sensitive
# Linux a genuinely distinct `.GIT/` directory now errs toward ask/deny —
# over-cautious, never a dangerous allow, per the limitation note above.
# User-facing reasons always print $FILE in its original casing.
FILE_N="${FILE//\\//}"
FILE_LC="${FILE_N,,}"
BASE="${FILE_N##*/}"
BASE_LC="${BASE,,}"
SEG_LC="/${FILE_LC#/}/"

# --- Allowlist: committed env templates are editable documentation ------------
# This is an exception to the `.env*` FILENAME deny (below) and to nothing else.
# It deliberately does NOT short-circuit the hook: a file named `.env.example`
# sitting inside .git/, .secrets/, .github/workflows/ or .claude/hooks/ is still
# governed by that directory's rule. Exiting here (as this did before v7) let
# any protected path be reached by giving the file a template basename.
ALLOWLIST_BASE=(
  ".env.example"
  ".env.sample"
  ".env.template"
  ".env.dist"
  ".env.test.example"
)
IS_ENV_TEMPLATE=false
for allowed in "${ALLOWLIST_BASE[@]}"; do
  if [[ "$BASE_LC" == "$allowed" ]]; then
    IS_ENV_TEMPLATE=true
    break
  fi
done

# --- Helpers ------------------------------------------------------------------
# True if the path contains an exact directory segment (or adjacent segments).
# Both sides case-folded (see strategy note above).
has_segment() { [[ "$SEG_LC" == *"/${1,,}/"* ]]; }
# True if the basename equals one of the given names (case-folded; the names
# passed in are written lowercase except proper-noun files, which are folded).
base_is() {
  local b
  for b in "$@"; do [[ "$BASE_LC" == "${b,,}" ]] && return 0; done
  return 1
}

# --- DENY: secrets and git internals (hard block) -----------------------------
DENY=false
# .env and any .env.<suffix>, unless the basename is an explicit template.
if [[ "$IS_ENV_TEMPLATE" == "false" ]] \
   && [[ "$BASE_LC" == ".env" || "$BASE_LC" == .env.* ]]; then DENY=true; fi
base_is "secrets.yaml" "secrets.yml" "credentials.json" "credentials.yaml" && DENY=true
# Private-key material is a hard deny by name even when the scanner cannot see
# the (binary) contents. Generic `*.pem` moved to ASK below: a PEM container is
# often a PUBLIC certificate chain, and private-key CONTENT written through
# tools is still hard-blocked by scan-secrets regardless of filename.
case "$BASE_LC" in
  *.key|*.p12|*.pfx|*.keystore|*.jks) DENY=true ;;
esac
base_is "id_rsa" "id_dsa" "id_ecdsa" "id_ed25519" && DENY=true
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
# Composite/custom action definitions run in CI just like workflows do —
# and so do the scripts they invoke, so the WHOLE .github/actions/ subtree
# (action.yml, script.sh, index.js, …) needs approval, not just the manifest.
{ has_segment ".github" && has_segment "actions"; } && ASK=true
{ has_segment ".github" && base_is "action.yml" "action.yaml"; } && ASK=true
# Certificate containers (often public chains): approve rather than hard-deny.
case "$BASE_LC" in *.pem) ASK=true ;; esac
base_is ".gitlab-ci.yml" "Jenkinsfile" "azure-pipelines.yml" ".drone.yml" && ASK=true
has_segment ".circleci" && ASK=true
has_segment "buildkite" && ASK=true
# Credential/registry config that commonly carries tokens or passwords.
base_is ".netrc" ".npmrc" ".pypirc" && ASK=true
# Submodule source pointers (a changed URL can repoint a submodule).
base_is ".gitmodules" && ASK=true
# Infrastructure
has_segment "infra" && ASK=true
has_segment "terraform" && ASK=true
has_segment "pulumi" && ASK=true
has_segment "cdk" && ASK=true
# Terraform sources anywhere (infra is sensitive regardless of folder).
case "$BASE_LC" in *.tf|*.tfvars) ASK=true ;; esac
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
# Both Claude Code settings layers. settings.local.json is NOT less sensitive
# than settings.json: per the official settings docs, local scope OVERRIDES
# project settings, its permission `allow` rules take effect without the
# workspace-trust step, and it accepts `disableAllHooks` — i.e. an ungated
# write here is a path to weaken hooks/permissions without approval.
[[ "$FILE_LC" == *".claude/settings.json" || "$FILE_LC" == *".claude/settings.local.json" ]] && ASK=true
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
