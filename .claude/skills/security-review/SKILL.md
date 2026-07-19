---
name: security-review
description: >-
  Use when scanning a repository for committed secrets or responding to found
  credentials — keys, passwords, tokens, connection strings — rotation and
  history cleanup. Trigger: "scan for secrets", "leaked API key", "secret in
  git history", "pre-publication scan". Never print secret values. Do NOT use
  for building auth/web security features (web-security) or secure-coding
  defaults (CLAUDE.md §7).

---

# Security Review — Repository Secret Audit

Extends `CLAUDE.md`. Owns repo-level secret scanning and response. Application-layer security (auth, sessions, CSRF, SSRF, headers, crypto) is owned by [web-security](../web-security/SKILL.md); universal secure-coding rules by `CLAUDE.md` §7.

## Purpose

Find committed or hardcoded credentials without ever exposing them, report them safely, and drive the correct response: rotation first, history cleanup second — deleting the file is never enough.

## When to use

- Repository audits and cleanups; before making a repo public or widening access; whenever a credential is discovered in code, configs, logs, or git history.

## When NOT to use

- Implementing security features or fixing web vulnerabilities → [web-security](../web-security/SKILL.md).
- Choosing crypto, hashing, or randomness for new code → `CLAUDE.md` §7 Secure Defaults.

## Core rules

- **Scan targets:** API keys, passwords, tokens, JWT secrets, SSH keys, certificates, database credentials, connection strings, service-account credentials — in tracked files, configs, scripts, notebooks, and git history.
- **NEVER print secret values.** Not in the plan, not in logs, not in chat, not in reports. This rule is canonical here; other skills restate it only as a one-liner pointing back.
- **Report only:** file, line (only if the line itself is safe to show), severity, recommendation.
- **A secret that touched git history is compromised.** Recommend, in order: (1) rotate/invalidate immediately; (2) clean git history (e.g. `git filter-repo`) — the USER runs this, since it rewrites shared history (forbidden for Claude, `CLAUDE.md` §2/§11); (3) remove the tracked file — in a cleanup this lands in the approved hygiene commit (sequence owned by git-hygiene).
- **Full incident steps** (session revocation, access-log audit, leak documentation): `CLAUDE.md` §7 Leak Prevention & Incident Response.

## Workflow

1. Scan tracked files and git history for the target classes (grep patterns; a scanner like `gitleaks` if already available — never install tools without approval).
2. Classify severity: active production credential > stale/expired credential > test/dummy value (verify it is truly fake).
3. Report the findings table, values redacted: `File | Line (if safe) | Type | Severity | Recommendation`.
4. STOP — rotation, history cleanup, and removal are user decisions.

## Cross-references

- [web-security](../web-security/SKILL.md) — application-security depth
- `CLAUDE.md` §7 — Secrets & Credentials; Leak Prevention & Incident Response

## Done criteria (in addition to CLAUDE.md §14)

- [ ] All scan-target classes covered; findings reported as file/severity only — zero secret values printed anywhere.
- [ ] Every committed secret has a rotation recommendation; history cleanup proposed, not executed.
