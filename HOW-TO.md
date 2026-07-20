# Claude Code Stack — Setup Guide

Complete guide for setting up the CLAUDE.md + skills + hooks template stack on a new machine, then bootstrapping new projects from it.

**Time:** 15 minutes first machine, 5 minutes per subsequent project.

---

## What this stack provides

- **CLAUDE.md** — universal engineering policy (boundaries, code quality, security, testing, git, DoD, etc.)
- **`.claude/skills/`** — domain skills (docker, k8s, airflow, testing, web-security, db-migrations, api-design, observability, repository-cleanup, and more — full list in `.claude/skills/INDEX.md`) that load on-demand
- **`.claude/hooks/`** — 5 deterministic enforcement hooks (block destructive commands, protect sensitive files, scan secrets, check diff size, verify Definition of Done)
- **`.claude/ENFORCEMENT.md`** — design doc explaining the 5-layer defense model

After setup: every Claude Code session in the project loads policy automatically; hooks block dangerous actions before execution.

---

## Quick start (TL;DR for repeat installs)

If template is already in a git repo:

```bash
# One-time per machine
sudo apt-get install -y jq dos2unix git
git clone <template-repo-url> ~/Claude_Project/main_template
echo 'source ~/Claude_Project/main_template/claude-init.sh' >> ~/.bashrc && source ~/.bashrc

# Per new project
claude-init my-app
cd ~/projects/my-app
$EDITOR CLAUDE.md  # fill Project Configuration
```

Detailed steps below.

---

## Phase 1: Machine prerequisites (one-time per computer)

### A. Windows users — install WSL2

1. Open PowerShell as Administrator and run:
   ```powershell
   wsl --install -d Ubuntu
   ```
2. Reboot when prompted.
3. After reboot, set your WSL username/password.
4. Open Windows Terminal → select "Ubuntu" tab. All subsequent commands run here.

### B. Linux/macOS users

You're ready. Use your native terminal.

### C. Install required tools

In your shell (WSL Ubuntu / Linux / macOS):

```bash
# Ubuntu/Debian/WSL
sudo apt-get update && sudo apt-get install -y jq dos2unix git

# macOS
brew install jq dos2unix git

# Verify
jq --version
dos2unix --version
git --version
```

### D. Install Claude Code

Follow Anthropic's official instructions for your platform. Verify:

```bash
claude --version
```

---

## Phase 2: Get the template

You have two options:

### Option A: Clone from git (recommended once you have the template in a repo)

```bash
mkdir -p ~/Claude_Project
git clone <your-template-repo-url> ~/Claude_Project/main_template
cd ~/Claude_Project/main_template
```

### Option B: Copy from existing files (Windows desktop, USB, etc.)

If you have the files on Windows desktop at `C:\Users\<you>\Desktop\Claude\`:

```bash
mkdir -p ~/Claude_Project/main_template
cd ~/Claude_Project/main_template

# Adjust path to where your files actually are
SRC="/mnt/c/Users/<your-windows-username>/Desktop/Claude"

cp "$SRC/CLAUDE.md" ./
cp -r "$SRC/.claude" ./
# .gitignore and .gitattributes are REQUIRED root files — claude-init.sh refuses
# to bootstrap a template that is missing either (and without them, `git add -A`
# would stage .env / machine-local state, and .sh hooks can be checked out CRLF
# on Windows and break bash).
cp "$SRC/.gitignore" ./
cp "$SRC/.gitattributes" ./

# Create logs folder if missing
mkdir -p .claude/logs
[ ! -f .claude/logs/.gitignore ] && echo '*.log' > .claude/logs/.gitignore
```

### Required template structure

After getting the template, you should have:

```
~/Claude_Project/main_template/
├── CLAUDE.md
├── .gitignore          # required — claude-init refuses to bootstrap without it
├── .gitattributes      # required — forces LF on *.sh so hooks run on Linux/WSL
└── .claude/
    ├── settings.json
    ├── ENFORCEMENT.md
    ├── hooks/
    │   ├── README.md
    │   ├── install.sh
    │   ├── lib.sh
    │   ├── block-destructive.sh
    │   ├── protect-files.sh
    │   ├── scan-secrets.sh
    │   ├── check-diff-size.sh
    │   └── verify-done.sh
    ├── logs/
    │   └── .gitignore
    └── skills/
        ├── README.md
        ├── INDEX.md
        └── <one folder per skill, each with SKILL.md — full list in INDEX.md>
```

Verify:

```bash
cd ~/Claude_Project/main_template

# Should show all skill folders + README + INDEX.md (full list in INDEX.md)
ls .claude/skills/

# Should show README.md + 7 .sh files (5 enforcement hooks + lib.sh + install.sh)
ls .claude/hooks/

# Each skill folder must have SKILL.md
for d in .claude/skills/*/; do
  [ -f "$d/SKILL.md" ] && echo "✓ $d" || echo "✗ MISSING: $d"
done
```

---

## Phase 3: Fix Windows-side issues (skip if not from Windows)

If you copied files from Windows, line endings and permissions need fixing:

```bash
cd ~/Claude_Project/main_template

# Convert CRLF (Windows) to LF (Linux) in all shell scripts
find .claude -name "*.sh" -exec dos2unix {} \;

# Make hook scripts executable
chmod +x .claude/hooks/*.sh

# Lowercase any folder names (Windows is case-insensitive, Linux isn't)
cd .claude/skills
for d in */; do
  lower=$(echo "$d" | tr '[:upper:]' '[:lower:]')
  if [[ "$d" != "$lower" ]]; then
    mv "$d" "$lower"
    echo "Renamed: $d → $lower"
  fi
done
cd ~/Claude_Project/main_template
```

### Test the template

```bash
cd ~/Claude_Project/main_template
bash .claude/hooks/install.sh
```

Should end with:
```
✓ Hooks installed and functional. Restart Claude Code to pick up the configuration.
```

If you see ✗ anywhere, jump to **Troubleshooting** below.

---

## Phase 4: Install the `claude-init` command

This creates a shell function that bootstraps a new project from the template in one command.

### The init script ships with the template

`claude-init.sh` is already at the repository root — the Phase 2 clone put it at
`~/Claude_Project/main_template/claude-init.sh`. There is nothing to create;
you only wire it into your shell below. (To bootstrap from a template kept
elsewhere, set `CLAUDE_TEMPLATE_DIR=/path/to/template`.)

### Wire it into your shell

```bash
# Add to .bashrc so it loads in every new terminal
echo '' >> ~/.bashrc
echo '# Claude template bootstrap' >> ~/.bashrc
echo 'source ~/Claude_Project/main_template/claude-init.sh' >> ~/.bashrc

# Load into current session
source ~/.bashrc

# Verify
type claude-init
```

> **macOS note:** the default shell is zsh — append the `source` line to
> `~/.zshrc` instead of `~/.bashrc` (same command, different file).

Should show: `claude-init is a function`.

---

## Phase 5: Daily use — bootstrap a new project

From any directory:

```bash
claude-init my-new-app                       # standard profile
claude-init --dry-run my-new-app             # show the plan; writes nothing
claude-init --profile strict my-new-app      # pick a profile
```

### Profiles

Every profile except `standard` changes the **generated project only** — the
template source is never modified. A profile that reduces safety says so in
its own output; nothing is weakened silently.

| Profile | Hooks | Stop hook | Skills | For |
|---|---|---|---|---|
| `minimal` | block-destructive + protect-files only — **prints a SAFETY REDUCED warning** (no secret scan, no diff guard) | off | all 37 | scratch work you fully supervise |
| `standard` *(default)* | all five | reminder | all 37 | normal development |
| `strict` | all five | **blocking** (`CLAUDE_VERIFY_BLOCK=1`) | all 37 | pre-merge / CI-adjacent work |
| `team` | all five | reminder | all 37; `repository-cleanup` and `release-readiness` become **manual-only** (`/repository-cleanup`, `/release-readiness`) | shared repos where whole-repo workflows should be deliberate |
| `security-sensitive` | all five, diff hard-block tightened to 500 lines | blocking | all 37 | regulated / auditable work |

`--dry-run` prints the template commit, destination, profile, exact copy
list, excluded machine-local state, and expected git changes — and creates
nothing (not even the destination root).

### Updates: version stamp + drift status

Each generated project carries `.claude/.template-version` (template commit,
profile, timestamp) and `.claude/.template-manifest` (sha256 of every
template-owned file at generation time). From inside a project:

```bash
claude-template-status
```

reports every managed file as unchanged / **LOCALLY MODIFIED** / MISSING and
never writes anything. There is deliberately **no auto-update**: update by
generating a fresh project from the newer template and diffing, or by copying
individual files after review — your local customizations are never silently
overwritten.

Output:
```
Installing Claude Code hooks...
  ✓ Made hook scripts executable
  ✓ Dependencies present (jq, grep)
  ✓ settings.json is valid JSON
  ✓ block-destructive.sh runs cleanly on empty input
  ✓ protect-files.sh runs cleanly on empty input
  ✓ scan-secrets.sh runs cleanly on empty input
  ✓ check-diff-size.sh runs cleanly on empty input
  ✓ block-destructive: rm -rf / correctly blocked
  ... (more functional tests)
✓ Hooks installed and functional.

✅ Project 'my-new-app' bootstrapped at /home/<you>/projects/my-new-app

Next steps:
  1. Fill 'Project Configuration' section in CLAUDE.md
  2. git init && git add -A && git commit -m 'chore: bootstrap'
  3. Restart Claude Code in this directory

Currently at: /home/<you>/projects/my-new-app
```

### Fill in Project Configuration

Open the project's `CLAUDE.md` and find the section at the bottom titled "Project Configuration". Replace the `_e.g., ..._` placeholders with your actual stack:

```markdown
### Tech Stack
- **Language(s):** TypeScript 5.6
- **Framework(s):** Next.js 15
- **Database:** PostgreSQL 16
- **Test runner:** Vitest
- **Package manager:** pnpm
- **Runtime / Hosting:** Node 22 on Vercel

### Commands
- **Install:** `pnpm install`
- **Dev:** `pnpm dev`
- **Test:** `pnpm test`
- **Lint:** `pnpm lint`
- **Type-check:** `pnpm typecheck`
- **Build:** `pnpm build`

### Project Structure
Source in `src/`, tests co-located as `*.test.ts`, configs at root.

### Project-Specific Quirks
None.

### Protected Paths (Claude must not modify without explicit instruction)

Two layers of protection:
- **Hook-enforced** ... (leave as-is — list of defaults)
- **Advisory** ... (add project-specific paths here)
```

### Initialize git and start working

```bash
cd ~/projects/my-new-app
git init
git add -A
git commit -m "chore: bootstrap claude template"
claude
```

---

## Phase 6: Setting up on additional machines

### Recommended: keep template in a git repo

On the **first** machine (after template is set up):

```bash
cd ~/Claude_Project/main_template
git init
git add -A
git commit -m "chore: initial Claude template stack"

# Push to a private repo (GitHub example):
gh repo create claude-template --private --source=. --push
# Or use GitLab/Bitbucket; just get a remote URL.
```

On **subsequent** machines:

```bash
# 1. Install dependencies (Phase 1.C above)
sudo apt-get install -y jq dos2unix git

# 2. Clone the template
mkdir -p ~/Claude_Project
git clone <your-template-repo-url> ~/Claude_Project/main_template

# 3. Wire up claude-init (Phase 4 wire-up step)
echo 'source ~/Claude_Project/main_template/claude-init.sh' >> ~/.bashrc
source ~/.bashrc

# 4. Verify
type claude-init
```

Done. Now `claude-init <name>` works on this machine too.

### Updating the template

When you improve the template (add a skill, fix a hook, etc.):

1. Make changes in `~/Claude_Project/main_template/` on one machine.
2. `git commit && git push`.
3. On other machines: `cd ~/Claude_Project/main_template && git pull`.
4. **Existing projects don't auto-update.** They use the snapshot taken at `claude-init` time. To update an existing project, either:
   - Manually copy specific changed files from template to project, or
   - Re-run `claude-init` to a new directory and migrate your work.

---

## Configuration — environment variables

These can be set in your shell to tune behavior:

| Variable | Default | Effect |
|---|---|---|
| `CLAUDE_PROJECTS_DIR` | `~/projects` | Where `claude-init` creates new projects |
| `CLAUDE_HOOK_OVERRIDE` | unset | `<hook-name>` or `all` — bypass hook(s) for one session (logged) |
| `CLAUDE_VERIFY_BLOCK` | `0` | `1` = Stop hook actually runs typecheck/lint/test (heavy but strict) |
| `CLAUDE_VERIFY_TIMEOUT_S` | `300` | Per-check wall-clock budget in blocking Stop mode. A checker exceeding it is reported as a timeout failure (not a hang). Watch/serve scripts (`--watch`, `next dev`, nodemon…) are detected and skipped before running. |
| `CLAUDE_DIFF_WARN_LINES` | `300` | Warn when a single Edit/Write changes ≥ this many lines |
| `CLAUDE_DIFF_BLOCK_LINES` | `1000` | Block when a single Edit/Write changes ≥ this many lines |

Example:
```bash
# Bypass destructive command block for this Claude session only
CLAUDE_HOOK_OVERRIDE=block-destructive claude

# Strict mode: Stop hook fully runs verification
CLAUDE_VERIFY_BLOCK=1 claude
```

---

## Troubleshooting

### `claude-init: command not found`
The function isn't loaded. Run:
```bash
source ~/.bashrc
type claude-init    # should show: claude-init is a function
```
If still missing, re-add the line to `.bashrc`:
```bash
echo 'source ~/Claude_Project/main_template/claude-init.sh' >> ~/.bashrc
source ~/.bashrc
```

### `bash: jq: command not found`
```bash
sudo apt-get install -y jq
```

### Hooks don't run / "permission denied"
```bash
chmod +x ~/Claude_Project/main_template/.claude/hooks/*.sh
# Re-run claude-init for affected projects, or chmod each project's hooks too:
chmod +x ~/projects/<your-project>/.claude/hooks/*.sh
```

### Hooks fail with weird "syntax error" or "$'\r': command not found"
Line endings are CRLF (Windows). Fix:
```bash
cd ~/Claude_Project/main_template
find .claude -name "*.sh" -exec dos2unix {} \;
chmod +x .claude/hooks/*.sh
```

### Skill isn't loading when expected
1. Check folder name is **lowercase** and matches the `name:` field in the skill's frontmatter:
   ```bash
   ls -d ~/Claude_Project/main_template/.claude/skills/*/
   # All names should be lowercase (docker not Docker)
   ```
2. Check the `description` in `SKILL.md` includes phrases similar to what you actually type to Claude.
3. Run `/hooks` and `/skills` (if available) inside Claude Code to see what's loaded.

### Hook blocked something it shouldn't (false positive)
Two options:
- **One-time bypass** (recommended for genuine cases):
  ```bash
  CLAUDE_HOOK_OVERRIDE=<hook-name> claude
  # The override is logged to .claude/logs/hooks.log
  ```
- **Permanent fix:** Edit the pattern in `.claude/hooks/<hook>.sh` and remove or refine the offending pattern.

### Hook never blocked anything in 90 days
Probably OK, but check:
```bash
grep -c BLOCK ~/projects/<project>/.claude/logs/hooks.log
```
If zero blocks AND you've worked on risky stuff, the hook may be misconfigured. Test manually:
```bash
echo '{"tool_input":{"command":"rm -rf /"}}' | bash .claude/hooks/block-destructive.sh
echo "exit=$?"   # should be 2
```

### Template missing files (e.g., a SKILL.md)
Restore from git:
```bash
cd ~/Claude_Project/main_template
git status         # see what's deleted
git checkout HEAD -- .claude/skills/<missing-skill>/SKILL.md
```
Or copy from another machine that has it.

### `claude-init` says "already exists"
The destination directory exists. Either pick a new name or remove the old one:
```bash
rm -rf ~/projects/<old-name>
claude-init <name>
```

### CLAUDE.md not loading in Claude Code
- File must be at the **root** of the directory where you run `claude`.
- Restart Claude Code after creating/changing CLAUDE.md.
- Verify: in Claude Code, ask "what's in your system prompt?" — it should reference the policy.

---

## File reference

| File | Purpose | Edit per project? |
|---|---|---|
| `CLAUDE.md` (universal §0-20) | Engineering policy | No (universal) |
| `CLAUDE.md` Project Configuration | Tech stack hints | **Yes — fill before first use** |
| `.claude/settings.json` | Hook wiring | No |
| `.claude/ENFORCEMENT.md` | Design doc | No |
| `.claude/hooks/*.sh` | Enforcement scripts | Tune patterns over time |
| `.claude/hooks/install.sh` | Setup script | Run once per project |
| `.claude/skills/<name>/SKILL.md` | Domain rules | Add new skills as needed |
| `.claude/logs/hooks.log` | Audit log | Local only — not committed |

---

## Maintenance schedule

**Weekly:** none required.

**Monthly:**
- Skim `.claude/logs/hooks.log` for override frequency. High override rate = pattern is too aggressive.

**Quarterly:**
- Audit which hook patterns have actually fired. Remove dead patterns.
- Update Claude Code itself.
- Review skills — any new domain needs its own skill?
- `git pull` template repo on each machine if changes propagated.

---

## Security notes

- `.claude/logs/hooks.log` is **local-only** and `.gitignored`. Never commit it.
- It does NOT contain secret values or full commands — only the regex patterns that matched.
- Hooks run with **your user's privileges**. They are guardrails against AI mistakes, not a sandbox against adversaries.
- For team-wide audit visibility: route hooks through HTTP to a central collector (see `.claude/ENFORCEMENT.md` Layer 1 Recipe 6).

---

## What this stack does NOT do

Be honest about the bar:
- **Does not catch semantic equivalents.** A `rm -rf` block won't catch `python -c "shutil.rmtree(...)"`.
- **Does not enforce behavioral correctness.** Linting passes ≠ logic is right.
- **Does not provide enterprise governance.** No audit trail to a central system, no signed overrides, no sandboxing.
- **Does not replace pre-commit/CI/policy-as-code.** It's the first line, not the only line.

For deeper layers, see `.claude/ENFORCEMENT.md`.

---

## Quick reference card

```
Setup once per machine:
  sudo apt-get install -y jq dos2unix git
  git clone <template-repo> ~/Claude_Project/main_template
  echo 'source ~/Claude_Project/main_template/claude-init.sh' >> ~/.bashrc
  source ~/.bashrc

Per new project:
  claude-init <name>
  cd ~/projects/<name>
  $EDITOR CLAUDE.md           # fill Project Configuration
  git init && git add -A && git commit -m 'chore: bootstrap'
  claude

One-time bypass:
  CLAUDE_HOOK_OVERRIDE=<hook-name> claude

Strict mode:
  CLAUDE_VERIFY_BLOCK=1 claude

Update template across machines:
  cd ~/Claude_Project/main_template
  git pull
```
