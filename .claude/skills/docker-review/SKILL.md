---
name: docker-review
description: Use when reviewing a container change before merge — Dockerfile edits, docker-compose changes, base-image bumps, image-size regressions. Trigger on phrases like "review the Dockerfile", "is this image safe", "check the compose change", "image got bigger", "base image update". The docker skill owns the standards; this skill owns the review process and required evidence. Do NOT use for writing/authoring Dockerfiles (docker) or cluster manifests (kubernetes).
---

# Docker Review

Extends `CLAUDE.md`. The [docker](../docker/SKILL.md) skill owns ALL container standards (multi-stage, non-root, pinning, size budgets, compose rules, smells) — this skill owns the review PROCESS: what evidence a container change shows before it merges.

## Purpose

Container regressions are silent: an image that doubled, a dropped `USER`, a new CVE in a bumped base. Review means demanding the evidence, not trusting the diff.

## When to use

- Reviewing any PR touching `Dockerfile*`, `docker-compose*`, `.dockerignore`, or base-image versions.

## When NOT to use

- Authoring/fixing container files → [docker](../docker/SKILL.md). Kubernetes manifests → kubernetes skill.

## Review checklist (each item needs evidence)

1. **Standards walk** — check the diff against the [docker](../docker/SKILL.md) rules and Done criteria (canonical there): multi-stage intact, non-root user, no `:latest`, no `COPY . .` without tight `.dockerignore`, healthcheck present.
2. **It actually builds and runs** — build output + container start attached or in CI; `docker compose config` validates on compose changes (commands and blocking policy: [verification](../verification/SKILL.md); matrix row: `CLAUDE.md` §14 Dockerfile).
3. **Scan evidence** — trivy/grype output on the built image; zero new high/critical CVEs (standard: docker skill). A base-image bump without a scan is unreviewed.
4. **Size delta stated** — before/after image size; over budget needs the justification the docker skill requires.
5. **Secrets check** — no build args/ENV carrying real secrets, no secret files in layers (standard: docker skill; anything found: [security-review](../security-review/SKILL.md) response — rotate, don't just delete the layer).
6. **Runtime posture on compose changes** — limits, restart policy, healthchecks, named volumes per docker skill's compose rules.
7. **Pin discipline** — new/changed base images pinned by digest or exact tag (canonical: docker skill).

## Cross-references

- [docker](../docker/SKILL.md) — canonical standards and Done criteria this review checks
- [verification](../verification/SKILL.md) — build/config checks, blocking policy
- [security-review](../security-review/SKILL.md) — response to secrets found in images/args
- `CLAUDE.md` §14 — Dockerfile verification row

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Build + run + scan evidence attached; zero new high/critical CVEs.
- [ ] Size delta stated and within budget (or justified per docker skill).
- [ ] No secrets in args/env/layers; pins by digest or exact tag.
