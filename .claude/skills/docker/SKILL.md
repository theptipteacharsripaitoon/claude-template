---
name: docker
description: Use when creating, modifying, building, or reviewing Dockerfile, .dockerignore, docker-compose.yml, container images, or any container-related task. Trigger on phrases like "build the image", "fix the Dockerfile", "containerize this", "update docker-compose", "image is too big", "container won't start", or any file path matching Dockerfile* or docker-compose*. Covers multi-stage builds, image security, runtime hardening, and image size optimization.
---

# Docker & Containers

Extends `CLAUDE.md`. When this skill loads, its rules and Done criteria apply on top of the universal baseline.

## Dockerfile rules

**Structure:**
- **Multi-stage builds always.** Build deps stay in a builder stage; final image carries only runtime artifacts.
- **Pin base images by digest** in production: `FROM node:22-alpine@sha256:...`. Tag drift breaks reproducibility.
- **No `:latest` tag** — neither base image nor produced image.
- **Order layers by change frequency.** Least-changing first (system deps → package manifests → install → app source).
- **`COPY` specific files**, not `COPY . .`. Untracked junk leaks into images.
- **Set `WORKDIR`** explicitly. Never rely on default.
- **Use `ENTRYPOINT` for the main process, `CMD` for default args.** Use exec form (`["cmd", "arg"]`), not shell form — signals must reach PID 1.
- **Set `HEALTHCHECK`** for long-running services. The check must reflect dependency readiness, not just process up.
- **Cache mounts** for package managers: `RUN --mount=type=cache,target=/root/.npm npm ci`.

**Security in build:**
- **Run as non-root.** Create a user with UID >10000: `RUN adduser -D -u 10001 app && USER app`. Default root is forbidden in final images.
- **No secrets in images, ever.** Use BuildKit secrets (`RUN --mount=type=secret,id=npmrc ...`) or runtime injection. Never `ENV TOKEN=...` for real secrets.
- **Drop build tools** in the final stage — no `gcc`, `apt-get`, package manager caches.
- **`.dockerignore` is mandatory.** Must exclude at minimum: `.git`, `node_modules`, `.env*`, `dist/`, `build/`, `coverage/`, `*.md` (unless needed), `.vscode/`, `.idea/`, `Dockerfile*`, `docker-compose*`.

**Base image choice (best to worst):**
1. `gcr.io/distroless/*` — minimal attack surface, no shell.
2. `chainguard/*` — minimal, signed, daily CVE rebuilds.
3. `alpine` — small, but musl libc can break some native modules.
4. Language-official slim variants (e.g., `python:3.12-slim`).
5. Avoid: `ubuntu:latest`, `debian:latest`, full distro images for runtime.

## Image hygiene

- **Size budgets** (justify excess in PR description):
  - Backend service: <300 MB
  - Frontend asset bundle: <50 MB
  - CLI tool: <100 MB
- **Scan every image** with `trivy` or `grype` in CI. Fail build on high/critical CVEs.
- **Sign production images** with `cosign`. Verify signatures at deploy time.
- **SBOM generation** with `syft` for production images.
- **Label images** with OCI metadata: `org.opencontainers.image.source`, `revision`, `version`, `created`.

## Runtime hardening

When running containers (compose, k8s, ECS, etc.):

- `--read-only` root filesystem; mount writable `tmpfs` only where needed (`/tmp`, app cache).
- Drop all Linux capabilities; add only what's required: `--cap-drop=ALL --cap-add=NET_BIND_SERVICE` (only if binding ports <1024).
- `--no-new-privileges` always.
- Set memory and CPU limits; never run unbounded.
- One process per container. Use compose/k8s to orchestrate multiple processes — no `supervisord` shoehorning.
- Mount Docker socket (`/var/run/docker.sock`) into a container only when absolutely required, and treat that container as privileged.

## docker-compose.yml rules

- Pin every image by digest or specific tag. No `latest`.
- Define `healthcheck` for every service.
- Define `depends_on` with `condition: service_healthy` for ordering.
- Use named volumes, not bind mounts to host paths, for persistent data.
- Set `restart: unless-stopped` (or `on-failure` with limit) for long-running services.
- Networks: define explicit networks; don't share the default bridge across unrelated stacks.
- Pass secrets via Docker Swarm secrets or compose `secrets:` block, never `environment:` for production-grade compose.
- Set resource limits per service (`deploy.resources.limits` and `reservations`).

## Common smells to fix on sight

- `RUN apt-get update && apt-get install -y X` without `--no-install-recommends` and `rm -rf /var/lib/apt/lists/*` in the same `RUN`.
- `ADD` for local files (use `COPY`); `ADD` only for remote URLs or auto-extraction.
- Multiple `RUN` commands that could be a single layer.
- `pip install` without `--no-cache-dir`.
- `npm install` instead of `npm ci` in CI/build paths.
- Missing `.dockerignore` (or one that does not exclude `.git`).

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Dockerfile uses multi-stage build.
- [ ] Final image runs as non-root (UID >10000).
- [ ] No secrets, no `:latest`, no `COPY . .` without `.dockerignore`.
- [ ] Image scan (trivy/grype) passes with zero high/critical CVEs.
- [ ] `HEALTHCHECK` defined.
- [ ] Image size within budget (or excess justified in PR).
- [ ] `.dockerignore` excludes `.git`, `.env*`, build artifacts, IDE configs.
- [ ] `docker-compose.yml` (if present) has healthchecks and resource limits.
