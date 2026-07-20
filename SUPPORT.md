# Support & Compatibility

## Compatibility window

| Component | Supported | Why this floor |
|---|---|---|
| Claude Code | **≥ 2.1.196** | First version with the settings/skill features this template's profiles rely on (`disable-model-invocation` interactions, `${CLAUDE_PROJECT_DIR}` in skill permission rules, `/context` listing accuracy). Validated on 2.1.214–2.1.215. |
| bash | **≥ 4.0** | Arrays, `mapfile`, `${var,,}` case folding used throughout hooks and tests. macOS ships 3.2 — install bash via Homebrew or use the default zsh only for your shell, not for the hooks. |
| jq | **≥ 1.6** | All hook JSON emission and installer profile transforms. |
| git | ≥ 2.30 | Worktree-aware `rev-parse` used by the Stop hook. |
| Python (tests only) | ≥ 3.10 local, 3.12 in CI | Test tooling only; the hooks themselves never require Python. |
| ShellCheck (dev only) | v0.10.0 pinned | The exact version CI validates against. |

## Platform matrix (measured, not aspirational)

| Platform | Status | Evidence |
|---|---|---|
| Linux (ubuntu-24.04) | **Supported** | Full CI suite on every push |
| Windows 11 + Git Bash | **Supported** | Hook suite, corpus, installer tests, and latency benchmarks run on it throughout the v7 cycle |
| WSL2 | Expected to work, **not measured** | Same toolchain as Linux; no dedicated run recorded yet |
| macOS | Expected to work, **not measured** | Requires Homebrew bash ≥ 4; no dedicated run recorded yet |

"Expected to work" is a prediction, not a claim — the first measured run on
those platforms should be recorded here.

## Getting help

1. [HOW-TO.md](HOW-TO.md) — installation, WSL setup, team distribution.
2. [.claude/hooks/README.md](.claude/hooks/README.md) — hook behavior, the
   bounded guarantee, override mechanism, tuning.
3. GitHub issues — bugs and feature requests (see
   [CONTRIBUTING.md](CONTRIBUTING.md) for what a good report carries).
4. Security reports go through private vulnerability reporting, never public
   issues — see [SECURITY.md](SECURITY.md).

## Release process (draft — owner-gated)

No releases are tagged yet. The intended process, pending owner approval:

1. Semantic versioning; first public tag decided by the owner.
2. A release candidate must pass the full validation battery (hook suite,
   corpus gate, installer tests, ShellCheck, catalog, routing consistency,
   link check) on the exact candidate commit in CI.
3. The live routing evaluation and a session evaluation are attached to the
   release notes with their provenance metadata (commit, digests, model,
   Claude Code version).
4. Breaking changes to hook policy (a tier change: allow→ask, ask→deny, or
   any relaxation) get a **major** version bump and a CHANGELOG entry naming
   the old and new behavior; pattern *coverage* additions within an existing
   tier are **minor**.
5. Tagging and publishing are owner actions — never performed by automation
   or by Claude.
