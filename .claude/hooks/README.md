# Hooks — Operational Guide

Phase 1 enforcement layer for `CLAUDE.md`. These scripts close the gap between **prose policy (~70-90% compliance)** and **deterministic enforcement of specific patterns (100% on those patterns, 0% on what's not patterned)**.

See `.claude/ENFORCEMENT.md` for design and rationale; this file is for operations.

## Installation

```bash
bash .claude/hooks/install.sh
```

That's it. The script makes hooks executable, verifies `jq` is installed, validates `settings.json`, and smoke-tests each hook.

Restart Claude Code after install. Test by asking it to run `rm -rf /tmp/anything` — should be blocked.

## What's installed

| Hook | Event | Purpose | Behavior |
|---|---|---|---|
| `block-destructive.sh` | PreToolUse: Bash | Blocks `rm -rf` (any flag spelling, incl. `/bin/rm`, quoted `"/bin/rm"`/`'rm'`, `\rm`, `-- /` — the target may be quoted too (`rm -rf '/srv/data'`, v7), `$HOME`/`${HOME}`/`$PWD`/`${PWD}`/`$(pwd)` targets (v7), brace sweeps `{…}` (v7), and current-directory destruction: `./*`, `"./"*`, `./.??*`, `.[!.]*`/`.[^.]*` (v7), `.`, `..` — named cleanup like `./build` stays allowed), force-push (incl. quoted `+refspec`), `terraform apply`, SQL destruction (case-insensitive, schema-qualified, with or without a trailing `;` at end-of-command, incl. client-wrapped in **short or long** flag form: `psql -c`/`--command`, `mysql -e`/`--execute`, `sqlcmd -Q`/`--query`, `=` or space before the quote — v7), etc.; **asks** for dependency install/upgrade/remove — option-first spellings included (`npm install --save-dev x`, `pip install -q x`, `pip install -c constraints.txt x` — pip is decided by explicit restore-vs-install logic, not one regex, v7), env-redirected installs (`npm --prefix D install pkg` global-option-first too, `pip install --target D pkg`, `--no-deps`, `--index-url`), local-path installs (`npm install ./pkg`, v7), and global tool installs (`cargo install`, `pipx install`, `uv tool install` — deliberate v7 policy, matching `gem`/`go`); all dependency asks are anchored at a command position so `mongo install`/`django get`/prose cannot match (v7); lockfile *restores* like `npm ci`, `pip install -r`, `uv sync` stay allowed — and asks for `git commit` while on a protected branch (`main`/`master`/`production`/`release/*`), **including** with global options between `git` and `commit` (`git -C . commit`, `git -c k=v commit`, `git --no-pager commit`) and path/env invocations (`/usr/bin/git`, `env git`) (v7) | Hard block (exit 2) / ask |
| `protect-files.sh` | PreToolUse: Edit/Write/NotebookEdit | Secrets and private keys (`.env*`, credentials, `id_rsa`, `*.key`/`*.p12`/`*.pfx`, `.git/`) → hard block — **all basenames case-folded** (`ID_RSA` gates like `id_rsa`; Windows/macOS treat them as the same file); CI/infra/migrations/lockfiles/**both** settings layers (`settings.json` **and** `settings.local.json`)/hooks/`*.tf`/`*.pem`/`.netrc`/the whole `.github/actions/` subtree/`.gitmodules` → **ask**. The `.env.example`/`.sample`/`.template`/`.dist` allowlist suppresses **only the `.env*` filename deny** — the same basename inside `.git/`, `.secrets/`, workflows, actions or hooks still hits that directory's rule (v7; previously the basename bypassed the whole hook) | Deny / ask |
| `scan-secrets.sh` | PreToolUse: Edit/Write/NotebookEdit | Blocks writes containing AWS/GitHub/Stripe/etc. token shapes | Hard block (exit 2) |
| `check-diff-size.sh` | PreToolUse: Edit/Write/NotebookEdit | Warns at 300+ line changes, blocks at 1000+ | Warn / block |
| `verify-done.sh` | Stop | Reminds about Definition of Done if code changed | Reminder / block |

The PreToolUse validators declare a 10 s `timeout` in `settings.json` (they finish in milliseconds; the docs default is 600 s). The Stop hook deliberately has **no** short timeout — blocking mode runs real test suites. Both `ask` decisions are emitted as jq-built JSON, so hostile filenames or future pattern edits cannot corrupt the payload.

### Command-policy tiers (how `block-destructive.sh` maps to CLAUDE.md §2)

CLAUDE.md §2 says several classes of command "require explicit user confirmation." The hook implements that as **four tiers**, so policy and enforcement agree:

| Tier | Behavior | Examples |
|---|---|---|
| **deny** (exit 2) | hard block; unblock only by running it yourself or `CLAUDE_HOOK_OVERRIDE` | `rm -rf /` (incl. `/bin/rm`, quoted `"/bin/rm"`/`'rm'`, `\rm`, `rm -rf -- /`, a quoted target `'/srv/data'`, `$HOME`/`${HOME}`/`$PWD`/`${PWD}`/`$(pwd)`, brace sweeps `{…}`), current-directory destruction (`rm -rf ./*`, `"./"*`, `./.??*`, `.[!.]*`, `.[^.]*`, `.`, `..` — named cleanup `rm -rf ./build` stays allowed), force-push (incl. quoted `+refspec`), `git reset --hard`, `git clean -fd`, `DROP TABLE`/`TRUNCATE`/unguarded `DELETE` (schema-qualified; `;`-terminated, ending the command, **or** client-wrapped without `;` in short or long flag form: `psql -c`/`--command`, `mysql -e`/`--execute`, `sqlcmd -Q`/`--query`), `terraform apply`, `kubectl delete namespace`, `curl … \| sh` |
| **ask** (permission JSON) | approve in-chat instead of restarting | dependency install/upgrade/remove incl. option-first spellings (`pip install -q x` — pip uses explicit restore-vs-install logic), env-redirected installs (`--prefix`/`--target`/`--no-deps`/`--index-url` — a non-default index is a supply-chain decision even for a restore), local-path installs (`npm install ./pkg`) and global tool installs (`cargo install`, `pipx install`, `uv tool install`, `gem install`, `go install`); all anchored at a command position so prose and near-miss names (`mongo install`) never match; lockfile *restores* like `npm ci` are allowed; `git commit` while on `main`/`master`/`production`/`release/*` incl. global options between `git` and `commit` and path/env invocations (CLAUDE.md §2) |
| **normal permission flow** | no hook opinion → Claude Code's usual per-command prompt | `git push`, `kubectl apply`, `helm upgrade` — mutating but not caught here. Surfaced by Claude Code's own permission prompt **unless the user has pre-allowlisted the command** in their permission settings; the hook layer adds no second gate for these |
| **not covered (semantic equivalents)** | regex cannot catch these; rely on prose + the other enforcement layers | `python -c "shutil.rmtree(...)"`, base64-encoded payloads, a downloaded script that contains the destructive call; SQL through clients whose statement is a positional argument (`sqlite3 db "DELETE FROM x"`) — the psql/mysql/sqlcmd flag forms are covered, and the quote boundary still keeps documentation text (`echo "DELETE FROM users"`, a commit message) allowed |

The hook is deliberately conservative: a documentation string that merely *mentions* `DROP TABLE` (an `echo` or a commit message) is blocked too. False positives are cheaper than a real disaster; override or reword.

**Four confirmation levels, kept distinct.** CLAUDE.md §2's "explicit user
confirmation in the current message" is a *prose norm for Claude*, and it is
enforced to different degrees:
1. **Deterministic hook deny/ask** (tiers 1–2 above) — enforced regardless of
   what Claude decides.
2. **Claude Code's permission prompt** (tier 3) — enforced by the app, *per
   your permission settings*.
3. **User pre-allowlists** (`permissions.allow` in settings) — a pre-allowlisted
   `git push` runs with **no prompt at all**; hooks here deliberately do not
   duplicate that gate.
4. **The §2 in-chat confirmation norm** — prose-level (~70–90% compliance),
   deterministically enforced **only** where a tier-1/2 pattern exists.
None of these guarantees another; if you allowlist a mutating command, only
tiers 1–2 still stand between you and it.

### When hooks disagree on one edit

An Edit/Write to a protected path that is also an oversized rewrite triggers both `protect-files` (**ask**) and `check-diff-size` (**deny**). Claude Code applies **deny before ask**, so approving the protected path does **not** authorize the oversized write — split it, or raise `CLAUDE_DIFF_BLOCK_LINES` / set `CLAUDE_HOOK_OVERRIDE`. This is intentional: an oversized rewrite should be reconsidered regardless of which path it targets.

## Override (when you genuinely need to bypass)

A blocked action is sometimes the correct one (a real `rm -rf` to clean a temp dir, an intentional commit to a lockfile, etc.). The override mechanism makes bypass **deliberate and logged**, not silent.

```bash
# Bypass one specific hook for the next Claude session
CLAUDE_HOOK_OVERRIDE=block-destructive  claude

# Bypass any hook (use only when you understand the risk)
CLAUDE_HOOK_OVERRIDE=all                claude
```

Every override is recorded to `.claude/logs/hooks.log` with timestamp and which hook was bypassed. If the team starts setting `CLAUDE_HOOK_OVERRIDE=all` in their shell rc, the hooks are dead — review override frequency periodically.

## Logs and observability

Each hook decision is appended to `.claude/logs/hooks.log` (tab-separated). The
`category` and `detail` columns can contain user-controlled data (e.g. a file
path), so `log_event` collapses tab/newline/other control characters to spaces
before writing — one event is always exactly one line with a fixed column count,
so a crafted path cannot forge an extra record.

```
2026-05-10T10:52:26Z   BLOCK     block-destructive   destructive command pattern   Command matches 'rm -rf /...'
2026-05-10T10:52:26Z   OVERRIDE  block-destructive   block-destructive             explicit user override via CLAUDE_HOOK_OVERRIDE=block-destructive
```

Useful queries:
```bash
# Most-blocked patterns this week
awk -F'\t' '$2=="BLOCK"' .claude/logs/hooks.log | sort | uniq -c | sort -rn | head

# Override rate (sign of an over-tight pattern or a bypass culture)
grep -c OVERRIDE .claude/logs/hooks.log

# Patterns that have never blocked anything (candidates for removal)
# — by inspection, compare BLOCK lines vs your pattern lists
```

The log is **local to each developer's machine.** This is fine for tuning but is not a centralized audit trail. For team-wide visibility, route hooks through HTTP to a central collector (see `ENFORCEMENT.md` Layer 1 Recipe 6).

**Log security.** What gets logged:
- ✅ Pattern that matched (regex form, e.g., `AKIA[0-9A-Z]{16}`).
- ✅ Hook name, timestamp, decision (BLOCK / WARN / OVERRIDE).
- ✅ File paths (for protect-files / check-diff-size).
- ❌ **Not** the matched secret value or its prefix — **anywhere**: the log
  records only the pattern name, and stderr says only "value withheld" (Claude
  already holds the content it tried to write; repeating any part of the value
  would be a partial exposure with zero information gain).
- ❌ **Not** the full shell command — only the regex pattern that matched.

This separation is intentional: stderr is for Claude to adapt right now; the log is for humans to tune over time. If you add new hooks, follow the same rule — actionable *context* (paths, pattern names) goes to stderr, the log gets only the pattern name, and the secret **value** goes to *neither* destination. Treat `.claude/logs/` as you would any local debug artifact: still don't paste it into bug reports without redaction.

**Log rotation.** These logs grow unboundedly. If they get large (>50 MB), rotate them (`mv hooks.log hooks.log.$(date +%Y%m)`) or truncate (`: > hooks.log`). The `.gitignore` in `.claude/logs/` excludes them from version control.

## Testing your patterns

When you change a pattern in any hook, verify both directions:

```bash
# Should BLOCK (exit 2)
echo '{"tool_input":{"command":"rm -rf /tmp/x"}}' | bash .claude/hooks/block-destructive.sh
echo "exit=$?"  # expect 2

# Should ALLOW (exit 0)
echo '{"tool_input":{"command":"ls -la"}}' | bash .claude/hooks/block-destructive.sh
echo "exit=$?"  # expect 0

# Should be logged
tail -3 .claude/logs/hooks.log
```

A change that breaks the smoke test in `install.sh` will fail loudly. A change that flips a previously-blocked case to allowed (or vice versa) without you intending it is the dangerous case — re-run the table of test cases above whenever you tune.

## Tuning

Most teams want to tune over the first 2–4 weeks. Common tweaks:

### Add or remove protected paths
Edit `protect-files.sh`. Matching is on exact basenames (`base_is`) and slash-bounded path segments (`has_segment`) — never raw substrings — so `config.environment.ts` is not mistaken for `.env` and `infrastructure/` is not mistaken for `infra/`. Add DENY rules for never-edit files, ASK rules for approve-in-chat files.

### Change diff-size thresholds
Set in your shell (or CI):
```bash
export CLAUDE_DIFF_WARN_LINES=500     # default 300
export CLAUDE_DIFF_BLOCK_LINES=2000   # default 1000
```

### Make the Stop hook actually run tests
The `verify-done.sh` hook is reminder-only by default. To make it block on failed checks:
```bash
export CLAUDE_VERIFY_BLOCK=1
```
This runs typecheck/lint/test on every Stop event. Heavy but catches "I'm done" claims that aren't.
Exit semantics: 0 = all discovered checks passed (or none could run — reported honestly, never
as "passed"), 2 = at least one check failed. An ecosystem whose toolchain is missing (e.g.
`Cargo.toml` with no `cargo` installed) is skipped with a note, not reported as a failure.

Blocking mode enforces *"the checks that exist pass"*, **not** *"checks must exist."* When code
changed but no checker is discoverable, the hook exits 0 with an explicit "nothing was verified"
warning rather than exit 2 — blocking there would only force a no-op continuation (the re-entry
guard lets the next Stop through anyway) without verifying anything. It detects the git work tree
with `git rev-parse`, so this holds in linked worktrees too.

### Whitelist a fake-looking secret
If `scan-secrets.sh` blocks a legitimate test fixture, embed a fake marker **inside the value**:
```ts
const TEST_API_KEY = "sk-EXAMPLE-fake-test-1234567890abcdef";  // marker is in the value
```
The scanner skips a match only when the **matched value itself** contains `EXAMPLE`, `fake-`,
`test-`, `dummy-`, `placeholder`, `XXXX`, etc. A marker in a nearby comment does **not** suppress
a real secret (that was a bypass) — put the marker in the value.

Two boundaries to know:
- **Marker skips are a deliberate false-negative path.** Every skipped fixture is logged as a
  `WARN` line in `.claude/logs/hooks.log` — review those occasionally. If a *real* secret ever
  contains a marker string, this hook alone will not catch it; that is one reason §7 also
  requires a pre-commit/CI scanner (gitleaks, detect-secrets) as a second layer.
- **The hook scans the content each edit inserts, not the reconstructed final file.** A secret
  assembled across two separate edits is invisible to it; the pre-commit layer catches that.

### Disable a hook temporarily
Comment it out in `.claude/settings.json` rather than deleting — easier to reinstate.

## Debugging

### A hook isn't firing
1. Run `/hooks` in Claude Code to confirm it's loaded.
2. Check the matcher pattern — it's case-sensitive.
3. Verify the script is executable: `ls -la .claude/hooks/*.sh`
4. Run the hook manually with a sample payload:
   ```bash
   echo '{"tool_input":{"command":"rm -rf /"}}' | .claude/hooks/block-destructive.sh
   ```
   Should print a block message and exit 2.

### A hook fires when it shouldn't (false positive)
Check stderr — every block lists the matched pattern. Adjust the pattern in the relevant script. Treat hook scripts like any other code: `git diff` and review changes.

### Block rate too high
If hooks block more than ~5% of legitimate actions, the team will start bypassing them (or asking the user to do every blocked action manually). Tune the patterns. False positives erode trust faster than false negatives.

## Maintenance

Quarterly:
- Review block stats (if you wire up logging via HTTP hooks, see `ENFORCEMENT.md` Layer 1 Recipe 6).
- Remove patterns that have not blocked anything legitimate in 90 days.
- Add patterns from incidents that slipped through.

## Bounded guarantee (what the hooks DO promise)

Falsifiable statements, each pinned by regression tests and the policy corpus
(`tests/hooks/corpus.jsonl`). Anything not listed here is not promised.

1. **Recursive deletion.** `block-destructive` denies a recursive-`rm` whose
   target token — after an optional `--`, an optional quote, and an optional
   `./` — begins with `/`, `~`, a `$HOME`/`$PWD` expansion, `$(pwd)`, `*`, `{`,
   or a dot-target/dot-glob form (`.`, `..`, `.*`, `.??*`, `.[!.]*`, `.[^.]*`).
   It does **not** parse shell: a variable holding a path, command substitution
   other than `$(pwd)`, an alias, or any non-`rm` deletion is out of scope.
2. **Protected-branch commits.** The ask fires for `git commit` on
   `main`/`master`/`production`/`release/*`, including global options between
   `git` and `commit` and path/env invocations. The branch is always read from
   `CLAUDE_PROJECT_DIR`; **`git -C <other>`/`--git-dir` targets are not
   resolved** — a commit aimed at a different repository is evaluated against
   the project's branch, not the target's.
3. **SQL.** Unguarded `DELETE`/`DROP`/`TRUNCATE` is denied when `;`-terminated,
   at end of command, or carried by a `psql`/`mysql`/`sqlcmd` flag in short
   (`-c`/`-e`/`-Q`) or long (`--command`/`--execute`/`--query`) form. Clients
   taking SQL positionally (`sqlite3 db "…"`) are not covered. Documentation
   text mentioning a statement stays allowed — that boundary is deliberate.
4. **Strict Stop.** With `CLAUDE_VERIFY_BLOCK=1` the Stop hook exits 2 **only**
   when a checker is discovered, executes, and fails, on the first Stop of a
   turn. No checker found / toolchain missing → exit 0 with an honest "nothing
   was verified". It blocks **at most once** per turn, and reads the working
   tree — changes already committed during the session are invisible. This is
   **best-effort verification, not a hard Definition-of-Done gate**.
5. **Universally:** these hooks are a prevention layer built on regex over the
   literal command string — effective against a *careless* agent, **not** a
   security boundary against an adversarial one.

## Limitations (what these hooks do NOT do)

Things they do *not* catch:

**Semantic equivalents of blocked patterns.** A `rm -rf /` block does not catch:
- `python -c "import shutil; shutil.rmtree('/')"`
- `find / -delete` (covered) but `python -c "...os.walk and os.remove..."` (not)
- A bash script downloaded from the internet that contains the destructive call
- Encoded or escaped versions

**Indirect secret leaks.**
- `echo $SECRET | base64` writing the encoded form
- Logging that includes a secret in a structured object
- A secret committed in a file the agent did not directly write

**Behavioral correctness.**
- Bad business logic (the function compiles, lints, types — and is wrong)
- Missing edge cases
- Race conditions
- Architecture-level mistakes (split a service that should be one, etc.)
- Unsafe SQL that's parameterized but logically wrong (deletes too much)

**Governance lifecycle gaps.** The full governance loop is `prevention → detection → response → recovery → audit → policy evolution`. These hooks cover **prevention** strongly. They do not provide:
- Observability (denial counts, false-positive rate, override rate over time)
- Audit trail (who overrode what, when, why)
- Override workflow (escalation, approvals, signed exemptions)
- Cross-environment enforcement (local vs CI vs staging vs prod)
- Sandboxing (these hooks run with your user's privileges)

If you need those, the next layers are: HTTP-based hooks posting to a central log, a separate review/approval app, runtime sandboxing (gVisor, Firecracker), and policy-as-code engines (OPA, Kyverno). For most single-project teams, those are overkill; for an enterprise platform, they are minimum bar.

**Bypass-resistance is asymmetric.**
- Strong against: an LLM that respects its tool boundary and tries to do the literal thing.
- Weak against: an adversary who deliberately constructs equivalents.
- Hooks raise the bar; they do not seal it.

## What this does NOT replace

These hooks complement, not replace:
- **Pre-commit hooks** (gitleaks, lint-staged) — catches what reaches git.
- **CI gates** — catches what reaches the PR.
- **Policy-as-code** (Kyverno, Conftest) — catches what reaches deploy.

Layer them. See `ENFORCEMENT.md` for the full picture.

## Compatibility

- Designed for **Claude Code** (settings.json schema). Cursor and GitHub Copilot have similar but not identical hook systems; manual translation needed.
- Requires `bash`, `jq`, `grep`. On Windows, use WSL — these scripts are not PowerShell.
- `verify-done.sh` auto-detects Node, Python, Rust, Go projects via their config files.

## Philosophy

> Prompts suggest. Hooks enforce. Use both. Never rely on prompts alone for non-negotiable constraints.

If a rule appears in CLAUDE.md and the cost of violation is high (data loss, security breach, deploy outage), it should also have a hook. Prose alone is ~70-90% compliance.
