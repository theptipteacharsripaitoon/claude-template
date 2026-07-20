# Security Policy

## What this project is (and is not)

This template ships **prevention-layer hooks**: deterministic regex checks
that stop a *careless* AI agent from running destructive commands, editing
protected files, or committing secret-shaped strings. Per the bounded
guarantee in [.claude/hooks/README.md](.claude/hooks/README.md), they are
**not a security boundary against an adversarial actor** — semantic
equivalents (`python -c "shutil.rmtree(...)"`), encoded payloads, and
downloaded scripts are documented as out of scope. Please calibrate reports
accordingly:

- **In scope:** a command *within the documented guarantee* that the hooks
  allow (e.g. a covered `rm -rf` spelling that slips through); a protected
  path reachable despite the deny/ask tiers; the secret scanner leaking a
  matched secret's value into logs or hook output; the installer writing
  outside its destination; a profile weakening safety *silently*.
- **Out of scope:** semantic-equivalent bypasses the bounded guarantee
  already names; prompt injection against the model itself; anything
  requiring the local user's own privileges to have been misused first.

## Reporting a vulnerability

Please use **GitHub private vulnerability reporting** (Security → Report a
vulnerability) on this repository. Do not open a public issue for anything
you believe is exploitable.

Include: the exact command/payload, the hook decision you observed (allow /
ask / deny), the decision you expected, and your OS + bash + jq versions. A
corpus-row-shaped reproducer (`tests/hooks/corpus.jsonl` format) is the
fastest path to a fix.

Response target: acknowledgement within 7 days. Fixes land with a regression
test and a corpus row, and are noted in [CHANGELOG.md](CHANGELOG.md).

## Supported versions

Until tagged releases exist, only the latest `main` is supported. The
compatibility window (Claude Code / OS / tool versions) is documented in
[SUPPORT.md](SUPPORT.md).

## Secrets

Never include a real credential in an issue, PR, or reproducer — use the
fixture style in `tests/hooks/run-tests.sh` (constructed strings with fake
markers). If you accidentally commit a secret to a fork, treat it as
compromised and rotate it; deleting the file is not enough
(CLAUDE.md §7).
