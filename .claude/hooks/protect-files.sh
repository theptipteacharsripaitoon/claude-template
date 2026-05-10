#!/usr/bin/env bash
# Blocks edits to sensitive files. Per CLAUDE.md §2 AI Action Boundaries
# and the per-project "Protected Paths" config.
# Hook event: PreToolUse, matcher: Edit|Write|MultiEdit

export CLAUDE_HOOK_NAME="protect-files"
source "$(dirname "$0")/lib.sh"
require_jq

INPUT=$(read_input)
FILE=$(json_get "$INPUT" '.tool_input.file_path')

if [[ -z "$FILE" ]]; then
  exit 0
fi

# Files that LOOK like protected env files but are conventionally committed
# templates/samples meant for documentation. Allow these explicitly so the
# .env substring match doesn't false-positive on them.
ALLOWLIST=(
  ".env.example"
  ".env.sample"
  ".env.template"
  ".env.dist"
  ".env.test.example"
)

for allowed in "${ALLOWLIST[@]}"; do
  if [[ "$FILE" == *"$allowed" ]]; then
    exit 0  # explicitly allowed; documentation/template file
  fi
done

# Patterns that should never be silently edited.
# Each entry is a substring match against the full file path.
PROTECTED_PATTERNS=(
  # Secrets / env
  ".env"
  ".env.local"
  ".env.production"
  ".env.staging"
  "secrets.yaml"
  "secrets.yml"
  ".secrets/"
  "credentials.json"
  "credentials.yaml"

  # Lockfiles (only the user/CI should regenerate)
  "package-lock.json"
  "pnpm-lock.yaml"
  "yarn.lock"
  "uv.lock"
  "poetry.lock"
  "Pipfile.lock"
  "Cargo.lock"
  "go.sum"
  "Gemfile.lock"
  "composer.lock"

  # CI/CD
  ".github/workflows/"
  ".gitlab-ci.yml"
  "Jenkinsfile"
  ".circleci/config.yml"
  "azure-pipelines.yml"
  "buildkite/"
  ".drone.yml"

  # Infrastructure
  "infra/"
  "terraform/"
  "pulumi/"
  "cdk/"

  # Kubernetes / Helm
  "k8s/prod/"
  "k8s/production/"
  "manifests/prod/"
  "charts/prod/"

  # Containers (production-impacting)
  "docker-compose.production.yml"
  "docker-compose.prod.yml"

  # Migrations (often run automatically)
  "migrations/"
  "alembic/versions/"
  "db/migrate/"
  "prisma/migrations/"

  # Git internals
  ".git/"
  ".gitattributes"

  # Code owners and policy
  "CODEOWNERS"
  ".github/CODEOWNERS"
  ".claude/settings.json"
  ".claude/hooks/"
)

for pattern in "${PROTECTED_PATTERNS[@]}"; do
  if [[ "$FILE" == *"$pattern"* ]]; then
    if check_override "protect-files"; then
      exit 0
    fi
    log_block \
      "protected file" \
      "$FILE matches protected pattern '$pattern'." \
      "CLAUDE.md §2 + Project Configuration > Protected Paths"
    echo "" >&2
    echo "Options:" >&2
    echo "  - Ask the user to confirm and edit the file directly, OR" >&2
    echo "  - Set CLAUDE_HOOK_OVERRIDE=protect-files for one session (logged), OR" >&2
    echo "  - Remove the pattern from .claude/hooks/protect-files.sh if it's no longer protected." >&2
    exit 2
  fi
done

exit 0
