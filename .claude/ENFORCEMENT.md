# Enforcement Layer

`CLAUDE.md` defines policy. This file defines **enforcement** — the deterministic guards that make sure policy actually holds when prose alone fails.

## The reliability gap

Prose-based instructions (CLAUDE.md, skills, system prompts) achieve roughly **70–90% compliance.** The agent usually follows them, but on a long session with full context, under conflicting priorities, or after compaction, it skips. By session 47 of a complex project, "always run the linter" becomes "usually runs the linter."

Hooks execute outside the LLM's reasoning chain. They achieve **100% compliance for the specific patterns they cover** — and 0% for what they don't. A hook that blocks `rm -rf` does not block `python -c "shutil.rmtree(...)"`. Pattern-based enforcement is deterministic, not omniscient.

> Prompts suggest. Hooks enforce. Use both. Never rely on prompts alone for non-negotiable constraints.

This document is the second layer.

---

## Enforcement layers (defense in depth)

Layer them top to bottom; each catches what the layer above missed.

| Layer | What | Catches | Where |
|---|---|---|---|
| 1 | **Claude Code hooks** | Bad actions before they execute | `.claude/settings.json` |
| 2 | **Pre-commit hooks** | Bad commits before they enter git | `.husky/`, `.pre-commit-config.yaml` |
| 3 | **CI gates** | Bad code before it merges | `.github/workflows/`, etc. |
| 4 | **Policy-as-code** | Bad config before it deploys | Conftest, Kyverno, OPA Gatekeeper |
| 5 | **Diff analyzers** | Bad patterns reviewers should see | Danger.js, Reviewdog |

You do not need all five on day one. Start with Layer 1 (Claude Code hooks) — it covers the most damaging AI failure modes — then add the rest as the project matures.

---

## Layer 1: Claude Code hooks (start here)

Hooks fire at lifecycle events. The most important is `PreToolUse`: it can **deny** an action before Claude executes it. A `PreToolUse` hook returning deny blocks even in `--dangerously-skip-permissions` mode — the user cannot accidentally bypass it.

Configure in `.claude/settings.json`. Project-level hooks ship with the repo and apply to every team member.

### Recipe 1: Block destructive shell commands

Drop into `.claude/hooks/block-destructive.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Block patterns from CLAUDE.md §2 AI Action Boundaries
BLOCKED='rm -rf /|rm -rf \*|git push --force|git reset --hard|kubectl apply.*prod|terraform apply|helm upgrade.*prod|DROP TABLE|TRUNCATE'

if [[ "$CMD" =~ $BLOCKED ]]; then
  echo "Blocked by enforcement: command matches dangerous pattern. See CLAUDE.md §2." >&2
  exit 2
fi
exit 0
```

Wire it up in `.claude/settings.json`:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-destructive.sh" }
        ]
      }
    ]
  }
}
```

### Recipe 2: Protect sensitive files from edits

`.claude/hooks/protect-files.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

PROTECTED=(
  ".env" ".env.local" ".env.production"
  ".git/" "package-lock.json" "pnpm-lock.yaml" "uv.lock"
  ".github/workflows/" "Dockerfile" "docker-compose.production.yml"
  "k8s/prod/" "infra/" "terraform/"
  "migrations/"
)

for p in "${PROTECTED[@]}"; do
  if [[ "$FILE" == *"$p"* ]]; then
    echo "Blocked: $FILE is protected (matches '$p'). Ask the user before modifying." >&2
    exit 2
  fi
done
exit 0
```

Settings:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-files.sh" }
        ]
      }
    ]
  }
}
```

### Recipe 3: Auto-format after every edit

Lint and format run no matter what — no "the agent forgot" failure mode.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path' | xargs -r npx prettier --write"
          },
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path' | xargs -r npx eslint --fix --no-error-on-unmatched-pattern"
          }
        ]
      }
    ]
  }
}
```

### Recipe 4: Block secrets in any write

`.claude/hooks/scan-secrets.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty')

# Naive but effective patterns
PATTERNS=(
  'AKIA[0-9A-Z]{16}'              # AWS access key
  'sk-[a-zA-Z0-9]{20,}'           # OpenAI/Anthropic-style
  'ghp_[a-zA-Z0-9]{36}'           # GitHub PAT
  'xox[baprs]-[0-9a-zA-Z-]{10,}'  # Slack token
  '-----BEGIN .*PRIVATE KEY-----' # Private key
)

for pat in "${PATTERNS[@]}"; do
  if echo "$CONTENT" | grep -qE "$pat"; then
    echo "Blocked: write contains a secret-shaped string. Rotate the secret and use env vars." >&2
    exit 2
  fi
done
exit 0
```

### Recipe 5: Stop hook — verify Definition of Done

The `Stop` event fires when the agent thinks it's finished. Use it to verify §16 DoD before declaring victory.

`.claude/hooks/verify-done.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Run the project's verification commands
pnpm typecheck && pnpm lint && pnpm test --run || {
  echo "Definition of Done failed: typecheck/lint/test did not all pass. See CLAUDE.md §16." >&2
  exit 2
}
```

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/verify-done.sh" }] }
    ]
  }
}
```

### Recipe 6 (optional): Prompt-based semantic check

For things regex can't catch — e.g., "does this edit touch authentication logic?" — use a prompt-handler hook that asks a fast model:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Given this tool input, does the change touch authentication, payment, or PII handling? Reply only with {\"sensitive\": true|false, \"reason\": \"...\"}.\n\nINPUT: $ARGUMENTS"
          }
        ]
      }
    ]
  }
}
```

A `sensitive: true` response can prompt the user before allowing the edit. Use sparingly — every prompt-handler hook costs latency and tokens.

---

## Layer 2: Pre-commit hooks

Catch policy violations before commits land. Use `pre-commit` (Python) or `husky + lint-staged` (Node).

Minimum hooks every project should have:
- **Secret scanning:** `gitleaks`, `detect-secrets`, or `trufflehog`.
- **Formatter:** Prettier, Black, ruff format, gofmt.
- **Linter:** ESLint, ruff, golangci-lint.
- **Type-checker:** tsc, mypy, pyright.
- **Forbidden file check:** block `.env*`, large binaries.

Example `.pre-commit-config.yaml`:
```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.0
    hooks: [{ id: gitleaks }]
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-added-large-files
        args: ['--maxkb=1024']
      - id: detect-private-key
```

---

## Layer 3: CI gates (block merge)

Every PR must pass before merging. Configure in `.github/workflows/ci.yml` (or equivalent). Required checks:

- Type-check, lint, format-check (no auto-fix in CI — fail loud).
- Unit + integration tests.
- Security scan: `npm audit --audit-level=high`, `pip-audit`, or `trivy fs`.
- Container scan: `trivy image` if Dockerfile changed.
- Coverage floor: do not let it drop on touched files.
- Schema diff: for OpenAPI/GraphQL changes, fail on undocumented breaking changes (`oasdiff`, `graphql-inspector`).
- IaC scan: `tfsec`, `checkov`, or `trivy config` for infra changes.
- DAG integrity: `pytest tests/dags/` for Airflow changes.

Branch protection: require these checks **and** code review **and** linear history before merge.

---

## Layer 4: Policy-as-code

For Kubernetes / IaC, prose policy in CLAUDE.md is necessary but not sufficient. Use admission controllers:

- **Kubernetes:** Kyverno or OPA Gatekeeper. Enforce: `runAsNonRoot`, `readOnlyRootFilesystem`, dropped capabilities, no `privileged`, no `hostNetwork`, image pinned by digest. (See `.claude/skills/kubernetes/SKILL.md`.)
- **Terraform / Helm / k8s manifests:** Conftest with Rego policies in CI before apply.
- **Container images:** Cosign signature verification at admission.

Policies live in `policies/` at repo root and are tested with their own unit tests.

---

## Layer 5: Diff analyzers (review augmentation)

Catch the soft stuff at PR-review time:

- **Danger.js / Danger Python:** comments on PRs that change too many files, modify migrations + code in one PR, lack a changelog entry, etc.
- **Reviewdog:** posts linter findings as inline PR comments.
- **Required reviewers via CODEOWNERS:** auth, billing, infra paths require domain owners' review.

---

## Mapping CLAUDE.md rules to enforcement

| CLAUDE.md rule | Best enforcement layer |
|---|---|
| §2: No `rm -rf`, force push, etc. | Layer 1 (PreToolUse hook) |
| §2: No edits to protected paths | Layer 1 (PreToolUse hook) |
| §2: No installing dependencies | Layer 1 (PreToolUse hook on Bash matching `npm install\|pip install`) |
| §3: No commits with secrets | Layer 1 + Layer 2 (gitleaks) |
| §6: No `console.log` in commits | Layer 2 (linter) + Layer 3 (CI lint) |
| §6: No `any` without justification | Layer 3 (eslint rule + CI fail) |
| §7: No high-CVE deps | Layer 3 (CI audit) |
| §11: Conventional Commits format | Layer 2 (commitlint) |
| §12: No silent error swallowing | Layer 5 (Danger comment) — hard to enforce deterministically |
| §16: Definition of Done | Layer 1 (Stop hook) + Layer 3 (CI) |

The unenforceable ones (judgment calls, anti-hallucination) are why CLAUDE.md still matters. But the enforceable ones should not be left to prose alone.

---

## Starting recipe (minimum viable enforcement)

If you do nothing else this week, do these. They cover the most damaging AI failure modes:

1. **Layer 1, Recipe 1** — block destructive shell commands.
2. **Layer 1, Recipe 2** — protect `.env`, lockfiles, CI configs, infra paths.
3. **Layer 1, Recipe 4** — block secret-shaped strings in writes.
4. **Layer 2** — pre-commit with gitleaks + linter + formatter.
5. **Layer 3** — CI gate that fails on test/lint/typecheck failures.

Add layers 4 and 5 as the project's risk profile grows.

---

## Maintenance

- **Audit hooks quarterly.** Hooks that have not fired in 90 days might be misconfigured (matcher wrong) or genuinely unneeded.
- **Track hook denials** — false positive rate above ~5% means the hook is too aggressive and the team will start bypassing it.
- **Version hook scripts** in git alongside the rest of the repo. Treat them as code: review changes, add tests for the script logic when non-trivial.
- **Document the why.** When you add a hook, add a comment with the CLAUDE.md section it enforces and the incident or decision that motivated it.
