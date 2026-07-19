# Proposal: repository-level secret scanner (owner approval required)

Status: **PROPOSAL ONLY — nothing installed, nothing selected.** Adding a
scanner is a dependency/tooling decision reserved to the owner (CLAUDE.md §2,
audit v5 §12, adjudication v5 #13). This document records a ready-to-review
configuration so the decision needs a yes/no, not research.

## Why a second layer

`scan-secrets.sh` inspects only content inserted through Claude's Edit/Write/
NotebookEdit tools (its documented boundary). It cannot see: secrets composed
across multiple edits, files written by Bash (`echo $TOKEN > cfg`), files
added outside Claude, or anything already in Git history. A repository-state
scanner closes exactly that gap; both layers stay.

## Recommended tool

**gitleaks** — single static binary, no runtime deps (fits this repo's
bash+jq-only posture), active maintenance, wide ruleset, JSON reports.
Alternative considered: `detect-secrets` (Python; heavier fit here since the
repo's only Python surface is the test harness — viable if the owner prefers
a Python toolchain).

## Pinning (fill exact values at adoption)

- Pin an exact release tag (v8.x line) **and** record the release asset's
  SHA-256 next to it, same pattern as the workflow's ShellCheck pin
  (`.github/workflows/test.yml` `SHELLCHECK_VERSION`/`SHELLCHECK_SHA256`).
  Verify the checksum from the official release page at adoption time; do not
  trust a number written down in advance (this proposal deliberately records
  none).

## Integration points (either or both)

1. **CI job step** (recommended first — zero developer-machine setup):

   ```yaml
   - name: Secret scan (gitleaks, pinned)
     run: |
       curl -fsSL -o /tmp/gitleaks.tar.gz \
         "https://github.com/gitleaks/gitleaks/releases/download/${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION#v}_linux_x64.tar.gz"
       echo "${GITLEAKS_SHA256}  /tmp/gitleaks.tar.gz" | sha256sum -c -
       tar -xzf /tmp/gitleaks.tar.gz -C /tmp gitleaks
       /tmp/gitleaks detect --source . --no-banner --redact --exit-code 1
   ```

2. **pre-commit hook** (catches secrets before they reach git): a
   `.pre-commit-config.yaml` with the official `gitleaks` hook at the same
   pinned rev — adds a `pre-commit` framework dependency for every
   contributor, so CI-first is the lower-friction start.

3. **One-time history scan** before any visibility widening:
   `gitleaks detect --source . --log-opts="--all" --redact`.

## Expected false positives in THIS repo (verified against the tree)

| Location | Why it trips | Mitigation |
|---|---|---|
| `tests/hooks/run-tests.sh` | runtime-CONSTRUCTED secret-shaped fixtures (`AKIA…`, `ghp_…` built from concatenation) — mostly invisible to a static scanner by design, but marker variants may still match generic rules | `.gitleaks.toml` allowlist scoped to this path |
| `.claude/hooks/scan-secrets.sh` | the detection REGEXES themselves (`AKIA[0-9A-Z]{16}`, `ghp_…`) match generic token rules | allowlist scoped to the pattern-list lines |
| `.claude/hooks/README.md`, reports | pattern names quoted in docs | allowlist by path or inline `gitleaks:allow` comments |

Always run with `--redact` so even true positives never print values into CI
logs (mirrors the Write/Edit scanner's no-value rule).

## Decision needed from the owner

1. Adopt gitleaks (or name a preferred alternative)?
2. CI-only, pre-commit-only, or both?
3. Approve the exact pinned version + checksum at adoption time.

Until then: no scanner runs, and `scan-secrets.sh` + §7's prose rules remain
the active layers.
