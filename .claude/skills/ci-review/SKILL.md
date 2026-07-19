---
name: ci-review
description: >-
  Use when reviewing CI/CD pipeline changes — GitHub Actions, GitLab CI, Azure
  Pipelines — for security, determinism, gate completeness. Trigger: "review
  the CI workflow", "check the pipeline change", "CI is flaky", "action
  version bump". Review only; Claude never edits CI configs without approval
  (CLAUDE.md §2). Do NOT use for app tests (testing) or deploy manifests
  (kubernetes).

---

# CI/CD Review

Extends `CLAUDE.md`. REVIEW-only by design: editing CI configs requires explicit user approval and hook override (canonical: `CLAUDE.md` §2; `.github/workflows/` is hook-protected). CI is enforcement Layer 3 — gates catch what prose cannot ([ENFORCEMENT.md](../../ENFORCEMENT.md)).

## Purpose

CI changes have root-like power: they run arbitrary code with repo secrets on every push. A workflow diff deserves the same suspicion as a production deploy.

## When to use

- Reviewing any PR touching `.github/workflows/`, `.gitlab-ci.yml`, `azure-pipelines.yml`, `Jenkinsfile`; diagnosing flaky or slow pipelines; auditing what the pipeline can access.

## When NOT to use

- Authoring app tests → [testing](../testing/SKILL.md). Container build content → docker/docker-review. Cluster deploys → kubernetes skill.

## Review checklist (each item needs evidence)

1. **Actions pinned by commit SHA** for third-party actions (`uses: org/action@<sha>`), not floating tags — a retagged action is a supply-chain injection (supply-chain canon: `CLAUDE.md` §7). First-party/official actions may use major tags if the repo accepts that risk explicitly.
2. **Least-privilege token** — an explicit `permissions:` block per workflow/job, defaulting to `contents: read`; write scopes justified line-by-line. No `permissions: write-all`.
3. **Secrets hygiene** — secrets only via the platform's secret store; never echoed, never passed to untrusted actions, never in URLs; forks must not receive secrets (`pull_request_target` with checkout of fork code is a finding). Anything leaked: [security-review](../security-review/SKILL.md) response.
4. **Untrusted input isolation** — PR titles/bodies/branch names never interpolated into `run:` scripts unquoted (script injection); use env indirection.
5. **Gates complete** — lint, type-check, tests actually run and BLOCK the merge (`CLAUDE.md` §16); a gate that continues-on-error is decoration. No `--no-verify`-style bypasses (§2).
6. **Determinism** — pinned runner images/tool versions, lockfile-based installs (`npm ci`, frozen lockfiles); caches keyed on lockfile hashes so a cache hit can't mask a dependency change.
7. **Bounded jobs** — `timeout-minutes` on every job (`CLAUDE.md` §19); concurrency groups to cancel superseded runs.
8. **Flakiness policy** — no blanket retries to green (canonical: [testing](../testing/SKILL.md) flakiness policy); a retried step needs the flake tracked.
9. **Branch protection alignment** — required checks match what the workflow actually names; direct-to-main still impossible (`CLAUDE.md` §11).

## Cross-references

- [ENFORCEMENT.md](../../ENFORCEMENT.md) — CI as enforcement Layer 3
- [testing](../testing/SKILL.md) — what the gates run; flakiness policy
- [security-review](../security-review/SKILL.md) — leaked-secret response
- [verification](../verification/SKILL.md) — blocking posture
- `CLAUDE.md` §2 (edit boundary), §7 (supply chain), §16 (gates), §19 (timeouts)

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Third-party actions SHA-pinned; permissions explicit and minimal.
- [ ] No secret reaches logs, forks, or untrusted actions; no unquoted untrusted interpolation.
- [ ] All quality gates blocking; jobs time-bounded; no retry-to-green.
