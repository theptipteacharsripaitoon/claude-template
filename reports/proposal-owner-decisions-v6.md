# Owner-Decision Proposals — v6 (prepared, NOT activated)

Consolidates the public-template decisions only the repository owner can make.
Nothing in this file has been applied: no license chosen, no scanner installed,
no tag created, no repository settings changed. Each item lists options and a
recommendation; activation is one explicit owner instruction away.

## 1. License (blocks public reuse today)

Without a license file, default copyright applies and third parties have no
legal right to reuse the template — the single biggest gap for a public
template.

| Option | Effect | Fit |
|---|---|---|
| MIT | shortest, maximally permissive | best fit for a config/docs template meant to be copied into private repos |
| Apache-2.0 | permissive + explicit patent grant + NOTICE mechanics | fine, slightly heavier ceremony for a no-code-library repo |
| CC-BY-4.0 | built for documents | uncommon for repos consumed as code; tooling (SPDX scanners) handles MIT/Apache better |

**Recommendation:** MIT, license year/holder = owner's choice. **Awaiting owner.**

## 2. Release / version policy (blocks reproducible adoption)

CHANGELOG.md says "Versions are git tags"; no tag exists. Proposal:
- Tag `v0.6.0` at the merge of the v6 cycle (0.x signals evolving policy);
  move the `[Unreleased]` cycle sections under it.
- SemVer mapping: MAJOR = breaking hook/policy contract (a previously-allowed
  command class becomes deny, settings schema changes), MINOR = new coverage or
  skills, PATCH = docs/test-only.
- Release gate = the CI suite green on the tagged commit + the §16 checklist;
  the `release-readiness` skill already encodes the checklist.
**Awaiting owner** (tag creation is explicitly out of scope for this cycle).

## 3. Community / security documents

- `SECURITY.md`: private-report contact (GitHub private vulnerability
  reporting), scope note (hooks are guardrails, not a sandbox — README
  wording already exists to link), no bounty.
- `CONTRIBUTING.md`: run `bash tests/hooks/run-tests.sh` + the offline checks
  before a PR; failing-first regression policy for hook changes; Conventional
  Commits (CLAUDE.md §11 is the source of truth).
**Recommendation:** both are low-risk to add next cycle. **Awaiting owner.**

## 4. GitHub "template repository" setting + update mechanism

- Enabling the template-repo toggle gives consumers "Use this template"
  (clean history) — complements, not replaces, `claude-init` (which targets
  local, non-GitHub project creation).
- Updates for generated projects: recommend documenting a plain
  `git remote add template … && git fetch template && git merge --squash`
  recipe in HOW-TO.md rather than building tooling; revisit if consumers ask.
**Awaiting owner** (repository setting; only the owner can toggle it).

## 5. Claude Code compatibility policy

The repo pins knowledge of specific behaviors (hooks schema, `stop_hook_active`,
permission semantics) verified on Claude Code 2.1.214/2.1.215. Proposal: state
in README "verified against Claude Code X.Y.Z (see routing results metadata
`cc_version` for the last live-verified version)" and re-verify on major
upgrades. **Awaiting owner** preference on wording prominence.

## 6. Installation profiles

Deferred: current consumers copy everything. If demand appears, a "minimal"
profile (hooks + CLAUDE.md, no skills) is the only split with a clear user;
implementing it now adds a matrix nobody has asked for. **Recommend: no.**

## 7. Repository/history secret scanner

Unchanged from `reports/proposal-secret-scanner.md` (v5): gitleaks in CI +
pre-commit, pinned version, plus a one-time full-history scan before any
visibility widening. Still **not installed** — requires owner approval per the
standing constraint.
