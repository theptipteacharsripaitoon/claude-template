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
| `block-destructive.sh` | PreToolUse: Bash | Blocks `rm -rf`, force-push, `terraform apply`, package installs, etc. | Hard block (exit 2) |
| `protect-files.sh` | PreToolUse: Edit/Write | Blocks edits to `.env*`, lockfiles, CI configs, infra, migrations | Hard block (exit 2) |
| `scan-secrets.sh` | PreToolUse: Edit/Write | Blocks writes containing AWS/GitHub/Stripe/etc. token shapes | Hard block (exit 2) |
| `check-diff-size.sh` | PreToolUse: Edit/Write | Warns at 300+ line changes, blocks at 1000+ | Warn / block |
| `verify-done.sh` | Stop | Reminds about Definition of Done if code changed | Reminder / block |

## Override (when you genuinely need to bypass)

A blocked action is sometimes the correct one (a real `rm -rf` to clean a temp dir, an intentional commit to a lockfile, etc.). The override mechanism makes bypass **deliberate and logged**, not silent.

```bash
# Bypass one specific hook for the next Claude session
CLAUDE_HOOK_OVERRIDE=block-destructive  claude code

# Bypass any hook (use only when you understand the risk)
CLAUDE_HOOK_OVERRIDE=all                claude code
```

Every override is recorded to `.claude/logs/hooks.log` with timestamp and which hook was bypassed. If the team starts setting `CLAUDE_HOOK_OVERRIDE=all` in their shell rc, the hooks are dead — review override frequency periodically.

## Logs and observability

Each hook decision is appended to `.claude/logs/hooks.log` (tab-separated):

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
- ❌ **Not** the matched secret value or its prefix — that goes only to Claude's stderr (one-time, ephemeral).
- ❌ **Not** the full shell command — only the regex pattern that matched.

This separation is intentional: stderr is for Claude to adapt right now; the log is for humans to tune over time. If you add new hooks, follow the same rule — sensitive content stays in stderr, not in the log. Treat `.claude/logs/` as you would any local debug artifact: still don't paste it into bug reports without redaction.

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
Edit `protect-files.sh`. The `PROTECTED_PATTERNS` array uses substring match against the full file path.

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

### Whitelist a fake-looking secret
If `scan-secrets.sh` blocks a legitimate test fixture, add a fake marker to the value:
```ts
const TEST_API_KEY = "sk-EXAMPLE-fake-test-1234567890abcdef";  // contains EXAMPLE
```
The scanner skips strings on lines containing `EXAMPLE`, `fake-`, `test-`, `dummy-`, `placeholder`, `XXXX`, etc.

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

## Limitations (what these hooks do NOT do)

Be honest about the bar. These hooks are a **prevention layer with regex pattern-matching**, not a complete governance system. Things they do *not* catch:

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
