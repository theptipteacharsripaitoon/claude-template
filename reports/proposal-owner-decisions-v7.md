# Owner decisions — v7 proposals

Every item here needs an explicit owner action; none has been performed by
this cycle. Items 2–4 are the only ones blocking a 9.5 claim.

## 1. License — RESOLVED this cycle

Apache-2.0 was authorized and applied: verbatim official text at `/LICENSE`
(11,358 bytes, sha256 `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`),
README section added, docs updated. Prerequisites verified: all four git
identities resolve to the owner; no third-party notices exist, so no NOTICE
file is warranted.

**One residual owner confirmation (1a):** the sole-authorship conclusion is
inferred from name/email shape (`tham <theptip.t@gmail.com>`,
`theptip <53976532+…@users.noreply.github.com>`, `tham <theptip.t@srisawadpower.com>`,
`theptip <theptip.t@gmail.com>`). If any of these is a different person, say so
and the licensing analysis must be redone.

## 2. Repository-level secret scanning — blocks 9.5

**Proposal (unchanged from `proposal-secret-scanner.md`, still recommended):**
enable GitHub **secret scanning + push protection** on the repository
(Settings → Code security). Zero maintenance, no CI time, catches real
credentials the template's regex layer cannot (the hooks scan only content
written through Claude's file tools).

This is a second *detection* layer; the hooks stay the prevention layer. The
v7 cycle did **not** enable it — it changes repository settings, which is
yours.

## 3. Release version + tag — blocks 9.5

Proposal: first public tag `v0.9.0` (signals "productized, pre-1.0 contract"),
tagged only after (a) this cycle's PR merges, (b) CI is green on the merge
commit, (c) you re-run `bash tests/hooks/run-tests.sh` and
`bash tests/installer/run-tests.sh` locally on the merge commit. Draft release
process is in [SUPPORT.md](../SUPPORT.md); the versioning rule proposed there:
hook-policy tier changes are **major**, coverage additions are **minor**.

Tagging is explicitly out of this cycle's authorization.

## 4. `template-repository` GitHub setting

Proposal: enable (Settings → General → Template repository). Lets consumers
click "Use this template" instead of cloning; complements, not replaces,
`claude-init` (which also stamps the version/manifest). No downside identified.

## 5. Global-tool-install hook policy — decided provisionally, revert is one line

The v7 cycle made `cargo install` / `pipx install` / `uv tool install` **ask**,
matching the existing `gem install` / `go install` behavior (plan §10
decision 4; previously `pipx`/`uv tool` were allowed outright and `cargo`
asked only by regex accident). If you prefer global tool installs silent,
delete the three patterns marked "global tool installs" in
`.claude/hooks/block-destructive.sh` and the corpus rows DP-022/023 flip back.

## 6. Compatibility window — sign-off requested

[SUPPORT.md](../SUPPORT.md) declares: Claude Code ≥ 2.1.196, bash ≥ 4,
jq ≥ 1.6, git ≥ 2.30; Linux CI + Windows Git Bash measured, WSL/macOS
"expected, not measured". If you want a different floor (e.g. support macOS
system bash 3.2), that is a rewrite of several hooks — say so before 1.0.
