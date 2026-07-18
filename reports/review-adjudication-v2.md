# External-Review Adjudication v2

Adjudicates `external-review-v2.md` (OpenAI GPT-5.6 Thinking, reviewing merge `3127a65`)
against the independent audit in [claude-independent-audit-v2.md](claude-independent-audit-v2.md)
and executable evidence. Produced **after** the independent audit was committed (`3ccf897`).

Verdicts: **Confirmed** / **Partly confirmed** / **Rejected** / **Not reproducible** / **Obsolete** / **Subjective**.
A finding is not accepted because GPT-5.6 reported it, nor rejected because it criticizes Claude's work.

## Adjudication table

| # | External finding | Verdict | Evidence |
|---|---|---|---|
| 1 | CI workflow failing; couldn't get log | **Confirmed (root cause established)** | All 3 runs failed with **zero steps**; check-run annotation: "account is locked due to a billing issue". Independently, on committed LF blobs the ShellCheck step also fails (SC2155+SC2016) → latent failure even after billing. |
| 1a | No explicit `permissions:` | **Confirmed** | `test.yml` has none; `ci-review` skill item 2 requires `contents: read`. |
| 1b | No `timeout-minutes` | **Confirmed** | Absent; `ci-review` item 7. |
| 1c | PyYAML unpinned | **Confirmed** | `pip install --quiet pyyaml`; `ci-review` item 6. |
| 2 | Secret-scanner same-pattern bypass (fake-then-real) | **Confirmed** | Reproduced: fake `AKIA…MNOP # EXAMPLE` then real `AKIA1B2C…` → **exit 0**. Root cause: `head -1` on both match and marker-line; later matches never inspected. |
| 2a | Real secret skipped due to marker on same line | **Confirmed** | Reproduced: `api_key="AKIA1B2C…" # see config.example` → **exit 0**. |
| 2b | Tests miss fake-first/real-second same pattern | **Confirmed** | SS1–SS8 cover fake-alone and two *different* patterns; not this case. |
| 3 | Protected-file approval non-functional (hard deny, no ask) | **Confirmed** | protect-files always `exit 2`; only unblock is `CLAUDE_HOOK_OVERRIDE` (restart) or manual edit. In-chat approval cannot unblock. |
| 3a | `.env` substring blocks unrelated filenames | **Confirmed** | Reproduced: `/repo/src/config.environment.ts` → **exit 2** (contains `.env`). |
| 3b | Allowlist substring lets `.env.example.secret` through | **Rejected (with evidence)** | Reproduced: `.env.example.secret` → **exit 2** (blocked). Allowlist uses suffix `*"$allowed"` match, so `.env.example.secret` is not allowlisted; the `.env` rule then catches it. Not a bypass. |
| 4 | Generated projects miss `.gitignore`/`.gitattributes` | **Confirmed** | `claude-init.sh` copies only `CLAUDE.md`+`.claude/`. Simulated generated project + `git add -A` → **`A .env`** staged; no `.gitattributes` ⇒ CRLF risk for `*.sh` on Windows. |
| 5 | Stop hook attributes unrelated dirty files | **Confirmed (inspection)** | `git status --porcelain` counts all dirty files. Reminder-only by default; low severity. |
| 5a | Polyglot `if/elif` runs one ecosystem | **Confirmed (inspection)** | Blocking mode only (off by default). |
| 5b | Prints "All checks passed" when none ran | **Confirmed** | Reproduced: `.py`-only repo, no `pyproject.toml`, `CLAUDE_VERIFY_BLOCK=1` → "✓ All verification checks passed." with zero checks run. |
| 6 | Universal DoD contradictory | **Confirmed** | §16 "Always required" (compile, tests, new tests, lint/format/typecheck, Conventional Commit, execute path) contradicts §13 LOW / §14 proportionality and is impossible for review/docs/investigation tasks; mandates a commit with no user intent. See applicability matrix in the audit. |
| 6a | Policy forbids referencing unopened symbols → context expansion | **Partly confirmed** | §3 requires *verifying existence before reference*, not opening every referenced file. Real context-cost tension exists, but the rule as written is a correctness guard, not a "read everything" mandate. Minor wording clarification at most. |
| 7 | Trigger fixtures never executed; `evaluated_runs` empty | **Confirmed** | Executed a 9-case live sample (sonnet-5, CC 2.1.214); results in the audit. Full 19-case precision/recall not claimed (empty-template confound). |
| 8 | Workflow skills better as manual-only | **Partly confirmed → preserve auto** | Measured: `repository-cleanup` loaded only on "clean up this repo…", `release-readiness` only on "get this repo ready to release"; neither over-fired. Evidence does **not** support blanket `disable-model-invocation`. External review agrees "decide each independently." Keep auto-invoked. |
| 9-docker-1 | Docker Done requires multi-stage unconditionally vs stated exception | **Confirmed** | Body line 13 permits justified single-stage; Done line 80 unconditional. |
| 9-docker-2 | Docker description claims review ownership | **Confirmed (measured)** | Description says "…or **reviewing** Dockerfile"; no `docker-review` disclaimer. "Review the Dockerfile before we merge" loaded **both** docker-review and docker. |
| 9-k8s | HPA presented as general requirement; readiness fails on dep too broadly | **Rejected (HPA) / Subjective (readiness)** | HPA is a body "consider", **not** a Done checkbox — not over-required. Readiness "must reflect dependency readiness" is a debatable default; optional nuance, not a defect. |
| 9-migrations | Requires universal reversibility + up→down→up even when destructive | **Partly confirmed** | Done already says "reversible, **or** `down` unsafety is documented"; body "Every migration is reversible" overstates. Wording alignment only. |
| 10a | Docs describe dependency installs as hard-denied | **Confirmed** | hooks README table lists "package installs" under "Hard block (exit 2)"; they actually `ask`. |
| 10b | Docs omit NotebookEdit | **Confirmed** | hooks README: 0 occurrences; matcher is `Edit|Write|NotebookEdit`. |
| 10c | Docs use `claude code` | **Confirmed** | hooks README lines 33, 36. |
| 10d | Hook headers mention stale MultiEdit | **Confirmed** | protect-files/scan-secrets/check-diff-size headers say `Edit|Write|MultiEdit`. |
| 10e | README test counts don't match suite | **Rejected (with evidence)** | README/CHANGELOG say "39-case"; suite reports `pass=39`. Accurate. |
| 10f | Reports don't reflect current CI status honestly | **Confirmed** | v1 `reports/` imply validation; CI never executed (billing). v2 reports correct this. |
| Lic | No license; all rights reserved | **Confirmed (owner action)** | No `LICENSE` file. Owner must choose. |

## Phase 3 — Improvement decisions

**Implement (evidence-backed net improvements):**

| Change | Reason (of the 12 valid) |
|---|---|
| scan-secrets: inspect **all** matches per pattern; marker check per-matching-line, not first-line-only | 3 (reduce false negative) — closes both confirmed bypasses |
| ShellCheck: fix SC2155 in install.sh; scoped `# shellcheck disable=SC2016` on the regex array | 9 (CI enforces intended standard) |
| `claude-init.sh`: also copy `.gitignore` + `.gitattributes`; never copy `reports/`/`external-review*` | 6 (generated projects inherit protections) |
| protect-files: exact-basename + path-component matching; structured `ask` for the approvable set (CI/infra/migrations/lockfiles/settings/hooks/.gitattributes), hard **deny** kept for secrets (`.env*`, secrets/credentials, `.git/`) | 1, 2, 3 (fix FP; make approval honor policy) |
| verify-done: distinguish passed / failed / **none discovered** / unavailable | 1 (fix reproducible defect) |
| CLAUDE.md §16 DoD: task-type applicability gate; keep strictness for behavioral/high-risk; no mandatory commit without user intent; require explicit reporting of skipped/unavailable checks | 7 (make requirements conditional) |
| CI workflow: add `permissions: contents: read`, `timeout-minutes`, pin pyyaml; keep SHA-pinned actions | 9 (CI enforces intended standards) |
| docker skill: drop "reviewing" from description, add docker-review disclaimer; make Done multi-stage conditional | 8 (reduce measured conflict), 12 (doc/impl agreement) |
| database-migrations: align body "every migration reversible" with the conditional Done | 12 (internal consistency) |
| Doc drift: `claude`→ not `claude code`; NotebookEdit in README; package-install "ask" in README table; hook headers `NotebookEdit` | 12 (doc matches implementation) |
| Add `LICENSE` — **owner decision**, not auto-selected | — (surface to owner) |

**Preserve (reject change, current behavior better or claim wrong):**

- Allowlist "bypass" (3b) — already blocks correctly.
- Kubernetes HPA requirement (9-k8s) — not actually a Done gate.
- Workflow skills manual-only (8) — measured routing supports keeping them auto-invoked.
- README test count (10e) — already accurate.
- shfmt enforcing gate — would strip intentional comment alignment (large no-behavior diff, worse readability); not added.
- Fail-open on missing `jq` — intentional, documented; unchanged.
- Stop-hook attribution / polyglot (5, 5a) — blocking mode is off by default; the "none discovered" fix (5b) is the high-value part. Attribution is documented as a known limitation rather than reworked (would require session-baseline tracking the hook can't reliably get from a single Stop payload).

**Owner decisions required:** resolve GitHub billing lock (only way to a green CI run); choose a `LICENSE`.

## Remaining unresolved trade-offs

- **verify-done session attribution:** a Stop hook cannot reliably distinguish this session's edits
  from pre-existing dirty files without a session-start baseline the payload doesn't carry. Documented
  as a limitation; not reworked.
- **CI cannot be turned green from the repo** until the billing lock is cleared; the repo-side
  ShellCheck/permissions/timeout fixes are necessary-but-not-sufficient.
