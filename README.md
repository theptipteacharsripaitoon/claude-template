# claude-template

A Claude Code project template with baked-in guardrails: a universal
engineering policy (`CLAUDE.md`), **37 domain skills** that load on demand,
and **5 enforcement hooks** that block destructive actions before they run —
plus the regression tests that keep the enforcement honest.

## What you get

| Piece | Where | What it does |
|---|---|---|
| Engineering policy | [CLAUDE.md](CLAUDE.md) | Priorities, AI action boundaries, security, testing, git discipline (§0–§20) |
| Skill library | [.claude/skills/](.claude/skills/INDEX.md) | 37 single-responsibility skills — cleanup, data engineering (SQL Server/SSIS/Airflow), Python/backend, AI/LLM, CI, frontend. Full catalog + dependency graph in [INDEX.md](.claude/skills/INDEX.md) |
| Enforcement hooks | [.claude/hooks/](.claude/hooks/README.md) | Block destructive commands, protect sensitive files, scan secrets, warn on oversized diffs, remind on Definition of Done. Dependency installs prompt for approval instead of hard-failing |
| Tests | [tests/](tests/) | 39-case hook regression suite + skill-catalog consistency checks + trigger-case evaluation fixtures |
| Enforcement design | [.claude/ENFORCEMENT.md](.claude/ENFORCEMENT.md) | The 5-layer defense model: prompts suggest, hooks enforce |

## Quick start

Full walkthrough (prerequisites, WSL setup, team distribution): **[HOW-TO.md](HOW-TO.md)**.

```bash
git clone <this-repo> ~/Claude_Project/main_template
bash ~/Claude_Project/main_template/.claude/hooks/install.sh   # verifies deps + runs hook tests
echo 'source ~/Claude_Project/main_template/claude-init.sh' >> ~/.bashrc   # ~/.zshrc on macOS
source ~/.bashrc
claude-init my-project    # bootstraps a new project from the template
```

Requirements: bash + jq + git (Windows: use WSL2 or Git Bash). Run the test
suite any time with `bash tests/hooks/run-tests.sh`.

## License

Not yet licensed — until the owner adds a LICENSE file, all rights reserved.
