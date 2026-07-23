#!/usr/bin/env bash
# Table-driven regression suite for the enforcement hooks.
# Portable: needs bash + jq + git only (no bats). Run: bash tests/hooks/run-tests.sh
# Expectations encode CORRECT behavior; a failing case is a live defect.
# Secret-shaped fixtures are CONSTRUCTED at runtime so this file never contains
# a contiguous secret pattern (keeps scanners, including our own hook, quiet).

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS="$REPO/.claude/hooks"
SCRATCH="$(mktemp -d)"
# Clean the scratch tree on exit (even on failure) so repeated runs do not
# accumulate temp directories.
trap 'rm -rf "$SCRATCH"' EXIT
export CLAUDE_PROJECT_DIR="$SCRATCH"
PASS=0; FAIL=0

AWS_FAKE="AKIA""ABCDEFGHIJKLMNOP"
AWS_FAKE_MARKED="AKIA""EXAMPLE012345678"   # fake marker embedded IN the value
AWS_REAL="AKIA""1234567890QRSTUV"
GH_FAKE="ghp_""abcdefghijklmnopqrstuvwxyz0123456789"
PEM_FAKE="-----BEGIN RSA ""PRIVATE"" KEY-----"
PW_KEY="pass""word"

t() { # t <id> <expected_exit> <hook> <payload> [envvar]
  local id="$1" want="$2" hook="$3" payload="$4" envvar="${5:-}" got=0
  if [[ -n "$envvar" ]]; then
    printf '%s' "$payload" | env "$envvar" bash "$HOOKS/$hook" >"$SCRATCH/out.txt" 2>"$SCRATCH/err.txt" || got=$?
  else
    printf '%s' "$payload" | bash "$HOOKS/$hook" >"$SCRATCH/out.txt" 2>"$SCRATCH/err.txt" || got=$?
  fi
  if [[ "$got" == "$want" ]]; then PASS=$((PASS+1)); printf 'PASS %-6s exit %s\n' "$id" "$got"
  else FAIL=$((FAIL+1)); printf 'FAIL %-6s want exit %s got %s\n' "$id" "$want" "$got"; fi
}

t_ask() { # t_ask <id> <hook> <payload> [envvar] — exit 0 AND jq-valid PreToolUse ask
  local id="$1" hook="$2" payload="$3" envvar="${4:-}" got=0
  if [[ -n "$envvar" ]]; then
    printf '%s' "$payload" | env "$envvar" bash "$HOOKS/$hook" >"$SCRATCH/out.txt" 2>/dev/null || got=$?
  else
    printf '%s' "$payload" | bash "$HOOKS/$hook" >"$SCRATCH/out.txt" 2>/dev/null || got=$?
  fi
  # -s guard: some jq builds (msys 1.6) exit 0, not 4, on EMPTY input with -e,
  # which would let a silent allow masquerade as a valid ask.
  if [[ "$got" == "0" ]] && [[ -s "$SCRATCH/out.txt" ]] \
     && jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"
               and .hookSpecificOutput.permissionDecision == "ask"
               and (.hookSpecificOutput.permissionDecisionReason | type) == "string"' \
          "$SCRATCH/out.txt" >/dev/null 2>&1; then
    PASS=$((PASS+1)); printf 'PASS %-6s valid ask-json emitted\n' "$id"
  else
    FAIL=$((FAIL+1)); printf 'FAIL %-6s want exit 0 + jq-valid ask JSON, got exit %s stdout: %s\n' "$id" "$got" "$(head -c 100 "$SCRATCH/out.txt" | tr -d '\n')"
  fi
}

t_noask() { # t_noask <id> <hook> <payload> [envvar] — exit 0, NO permission decision
  local id="$1" hook="$2" payload="$3" envvar="${4:-}" got=0
  if [[ -n "$envvar" ]]; then
    printf '%s' "$payload" | env "$envvar" bash "$HOOKS/$hook" >"$SCRATCH/out.txt" 2>/dev/null || got=$?
  else
    printf '%s' "$payload" | bash "$HOOKS/$hook" >"$SCRATCH/out.txt" 2>/dev/null || got=$?
  fi
  if [[ "$got" == "0" ]] && ! grep -q 'permissionDecision' "$SCRATCH/out.txt"; then
    PASS=$((PASS+1)); printf 'PASS %-6s allowed without ask\n' "$id"
  else
    FAIL=$((FAIL+1)); printf 'FAIL %-6s want plain allow (exit 0, no ask), got exit %s stdout: %s\n' "$id" "$got" "$(head -c 100 "$SCRATCH/out.txt" | tr -d '\n')"
  fi
}

cmd() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)"; }
fp()  { printf '{"tool_name":"Write","tool_input":{"file_path":%s}}' "$(printf '%s' "$1" | jq -Rs .)"; }
wc_() { printf '{"tool_name":"Write","tool_input":{"file_path":"/x/a.py","content":%s}}' "$(printf '%s' "$1" | jq -Rs .)"; }

echo "== block-destructive: hard denials stay hard =="
t BD1 2 block-destructive.sh "$(cmd 'git push --force origin main')"
t BD2 0 block-destructive.sh "$(cmd 'git status')"
t BD6 2 block-destructive.sh "$(cmd 'rm -rf /tmp/x')"
t BD7 0 block-destructive.sh "$(cmd 'rm -rf build/')"
t BD9 0 block-destructive.sh '{"tool_input":{}}'
t BD10 0 block-destructive.sh "$(cmd 'git push --force origin main')" 'CLAUDE_HOOK_OVERRIDE=block-destructive'
echo "== block-destructive: dependency installs ASK instead of deny =="
t_ask ASK1 block-destructive.sh "$(cmd 'npm install lodash')"
t_ask ASK2 block-destructive.sh "$(cmd 'pip install requests')"
t_ask ASK3 block-destructive.sh "$(cmd 'cargo add serde')"
echo "== block-destructive: malformed JSON fails open =="
t BD11 0 block-destructive.sh 'this is not json'
echo "== block-destructive: rm/clean/SQL variants (threat-matrix v3) =="
t BD20 2 block-destructive.sh "$(cmd 'rm -fr /tmp/x')"
t BD21 2 block-destructive.sh "$(cmd 'rm -r -f /tmp/x')"
t BD22 2 block-destructive.sh "$(cmd 'rm --recursive --force /tmp/x')"
echo "== block-destructive: git global options do not hide the subcommand (H1) =="
t BDG1 2 block-destructive.sh "$(cmd 'git -C /repo reset --hard HEAD')"
t BDG2 2 block-destructive.sh "$(cmd 'git -c gc.auto=0 clean -fd')"
t BDG3 2 block-destructive.sh "$(cmd 'git --git-dir=/r/.git push --force origin main')"
t BDG4 2 block-destructive.sh "$(cmd 'git --work-tree /r reset --hard')"
t BDG5 2 block-destructive.sh "$(cmd 'git -C . push -f origin feat')"
t BDG6 0 block-destructive.sh "$(cmd 'git -C . status')"
t BDG7 0 block-destructive.sh "$(cmd 'git --no-pager diff')"
echo "== block-destructive: rm value-bearing options do not hide -rf (H2) =="
t BDRM1 2 block-destructive.sh "$(cmd 'rm --interactive=never -rf /')"
t BDRM2 2 block-destructive.sh "$(cmd 'rm --interactive=once -Rf /srv/data')"
t BDRM3 0 block-destructive.sh "$(cmd 'rm --interactive=never -rf ./build')"
# shellcheck disable=SC2016  # deliberate: the payload must carry a LITERAL $HOME
t BD23 2 block-destructive.sh "$(cmd 'rm -rf "$HOME"')"
t BD24 2 block-destructive.sh "$(cmd 'git clean -df')"
t BD25 2 block-destructive.sh "$(cmd "psql -c 'drop table users'")"
t BD26 2 block-destructive.sh "$(cmd "mysql -e 'truncate table events'")"
t BD27 2 block-destructive.sh "$(cmd 'sqlcmd -Q "delete from users;"')"
t BD28 2 block-destructive.sh "$(cmd 'psql -c "Drop Table users"')"
t BD34 2 block-destructive.sh "$(cmd 'git clean -fd')"
t BD35 2 block-destructive.sh "$(cmd 'git clean -f -d')"
echo "== block-destructive: local cleanup / WHERE-guarded SQL / lookalikes stay allowed =="
t BD30 0 block-destructive.sh "$(cmd 'rm -r -f build/')"
t BD31 0 block-destructive.sh "$(cmd 'psql -c "delete from users where id = 1;"')"
t BD32 0 block-destructive.sh "$(cmd 'git clean -n')"
t BD33 0 block-destructive.sh "$(cmd 'grep -rf patterns.txt src/')"
echo "== block-destructive: dependency remove/upgrade ASK (CLAUDE.md §2) =="
t_ask ASK4 block-destructive.sh "$(cmd 'npm uninstall lodash')"
t_ask ASK5 block-destructive.sh "$(cmd 'npm update')"
t_ask ASK6 block-destructive.sh "$(cmd 'yarn remove lodash')"
t_ask ASK7 block-destructive.sh "$(cmd 'pnpm update')"
t_ask ASK8 block-destructive.sh "$(cmd 'pip uninstall requests')"
t_ask ASK9 block-destructive.sh "$(cmd 'pip install --upgrade requests')"
t_ask ASK10 block-destructive.sh "$(cmd 'poetry remove requests')"
t_ask ASK11 block-destructive.sh "$(cmd 'cargo update')"
t_ask ASK12 block-destructive.sh "$(cmd 'composer remove vendor/pkg')"
t_ask ASK13 block-destructive.sh "$(cmd 'bundle update')"
t_ask ASK14 block-destructive.sh "$(cmd 'go get example.com/tool')"
t_ask ASK15 block-destructive.sh "$(cmd 'bun remove lodash')"
t_ask ASK16 block-destructive.sh "$(cmd 'gem uninstall rails')"
t_ask ASK17 block-destructive.sh "$(cmd 'cargo remove serde')"
echo "== block-destructive: lockfile/manifest RESTORE stays allowed (no ask) =="
t_noask AL1 block-destructive.sh "$(cmd 'npm ci')"
t_ask   AL2 block-destructive.sh "$(cmd 'npm install')"   # v9: bare install can rewrite the lockfile → ask
t_noask AL3 block-destructive.sh "$(cmd 'pnpm install')"
t_noask AL4 block-destructive.sh "$(cmd 'yarn install')"
t_noask AL5 block-destructive.sh "$(cmd 'pip install -r requirements.txt')"
t_noask AL6 block-destructive.sh "$(cmd 'uv sync')"
t_noask AL7 block-destructive.sh "$(cmd 'poetry install')"
t_noask AL8 block-destructive.sh "$(cmd 'bundle install')"
t_noask AL9 block-destructive.sh "$(cmd 'composer install')"
t_noask AL10 block-destructive.sh "$(cmd 'bun install')"
t_noask AL11 block-destructive.sh "$(cmd 'pip install -e .')"

echo "== protect-files: secrets stay a HARD deny (exit 2) =="
t PF1 2 protect-files.sh "$(fp '/repo/.env')"
t PF2 0 protect-files.sh "$(fp '/repo/.env.example')"
t PF5 0 protect-files.sh "$(fp '/repo/src/main.py')"
t PF6 0 protect-files.sh "$(fp '/c/repo/docs/แผนงาน.md')"
t PF8 2 protect-files.sh "$(fp '/repo/my docs/.env.local')"
t PF9 0 protect-files.sh 'not json'
t PF11 2 protect-files.sh "$(fp '/repo/.env.example.secret')"
echo "== protect-files: exact-component matching, no substring false positives =="
t PF10 0 protect-files.sh "$(fp '/repo/src/config.environment.ts')"
t PF13 0 protect-files.sh "$(fp '/repo/src/infrastructure/service.ts')"
echo "== protect-files: approvable paths ASK instead of hard-deny =="
t_ask PFA1 protect-files.sh "$(fp '/repo/package-lock.json')"
t_ask PFA2 protect-files.sh "$(fp '/repo/migrations/0001_init.sql')"
t_ask PFA3 protect-files.sh "$(fp '/repo/.github/workflows/ci.yml')"
t_ask PFA4 protect-files.sh "$(fp '/repo/.claude/hooks/x.sh')"
echo "== protect-files: instruction/policy/eval sources ASK (H3) =="
t_ask PFPOL1 protect-files.sh "$(fp '/repo/CLAUDE.md')"
t_ask PFPOL2 protect-files.sh "$(fp '/repo/.claude/ENFORCEMENT.md')"
t_ask PFPOL3 protect-files.sh "$(fp '/repo/.claude/skills/docker/SKILL.md')"
t_ask PFPOL4 protect-files.sh "$(fp '/repo/tests/hooks/corpus.jsonl')"
t_ask PFPOL5 protect-files.sh "$(fp '/repo/tests/skills/trigger-cases.yaml')"
t_ask PFPOL7 protect-files.sh "$(fp '/repo/policy/action-matrix.yaml')"
t_ask PFPOL8 protect-files.sh "$(fp '/repo/tests/policy_matrix.py')"
t_ask PFPOL9 protect-files.sh "$(fp '/repo/tests/skills/check_coverage.py')"
t_noask PFPOL6 protect-files.sh "$(fp '/repo/docs/guide.md')"
echo "== protect-files: symlink alias resolves, not bypasses (H4) =="
# Skip where the platform has no real symlinks (Git Bash without
# MSYS=winsymlinks:nativestrict): `ln -s` there makes a copy, not a link, so
# these tests are meaningless. The hook's readlink -f resolution is a Unix path.
if ln -sf "$SCRATCH/.env" "$SCRATCH/env-alias" 2>/dev/null && [[ -L "$SCRATCH/env-alias" ]]; then
  : > "$SCRATCH/.env"
  t PFSYM1 2 protect-files.sh "$(fp "$SCRATCH/env-alias")"
  : > "$SCRATCH/plain.py"; ln -sf "$SCRATCH/plain.py" "$SCRATCH/safe-alias"
  t PFSYM2 0 protect-files.sh "$(fp "$SCRATCH/safe-alias")"
else
  echo "SKIP   PFSYM1/2 — no real symlink support on this platform"
fi
echo "== protect-files: NotebookEdit coverage (migrations ask) =="
t_ask NB1 protect-files.sh '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/repo/migrations/x.ipynb"}}'
echo "== protect-files: ask JSON stays valid on hostile basenames =="
t_ask PFH1 protect-files.sh "$(fp '/repo/.github/workflows/build"prod.yml')"
t_ask PFH2 protect-files.sh "$(fp $'/repo/migrations/a\tb.sql')"
t_ask PFH3 protect-files.sh "$(fp $'/repo/migrations/a\nb.sql')"
t_ask PFH4 protect-files.sh "$(fp "/repo/migrations/weird\\")"
t_ask PFH5 protect-files.sh "$(fp '/repo/migrations/แผน งาน v2.sql')"
LONGB=$(printf 'a%.0s' {1..300})
t_ask PFH6 protect-files.sh "$(fp "/repo/migrations/$LONGB.sql")"

echo "== scan-secrets =="
t SS1 2 scan-secrets.sh "$(wc_ "key = \"$AWS_FAKE\"")"
t SS2 0 scan-secrets.sh "$(wc_ "key = \"${AWS_FAKE_MARKED}\"  # fixture")"
t SS3 2 scan-secrets.sh "$(wc_ "$PEM_FAKE")"
t SS4 2 scan-secrets.sh "$(wc_ "$(printf 'a = "%s"\nb = "%s"' "$AWS_FAKE" "$GH_FAKE")")"
t SS5 2 scan-secrets.sh "$(wc_ "$PW_KEY = \"abcdefghijklmnopqrstuvwx\"")"
t SS6 0 scan-secrets.sh "$(wc_ 'const K = 42')"
t SS7 2 scan-secrets.sh "$(printf '{"tool_name":"Edit","tool_input":{"file_path":"/x","new_string":%s}}' "$(printf 'token = "%s"' "$GH_FAKE" | jq -Rs .)")"
t SS8 0 scan-secrets.sh 'not json'
echo "== scan-secrets: NotebookEdit coverage =="
t NB2 2 scan-secrets.sh "$(printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/x.ipynb","new_source":%s}}' "$(printf 'k = "%s"' "$AWS_FAKE" | jq -Rs .)")"
echo "== scan-secrets: same-pattern fake-then-real must NOT bypass =="
# Line 1 is a fake fixture (EXAMPLE marker); line 2 is a real-shaped AWS key with
# no marker. The scanner must inspect the SECOND match, not stop at the first.
t SS9 2 scan-secrets.sh "$(wc_ "$(printf 'k1 = "%s"  # EXAMPLE\nk2 = "%s"' "$AWS_FAKE" "$AWS_REAL")")"
echo "== scan-secrets: real secret with fake word elsewhere on the line must NOT bypass =="
t SS10 2 scan-secrets.sh "$(wc_ "$(printf 'api_key = "%s"  # see config.example' "$AWS_REAL")")"

echo "== check-diff-size =="
BIG=$(for i in $(seq 1 1100); do echo "line $i"; done)
MED=$(for i in $(seq 1 400); do echo "line $i"; done)
t CD1 2 check-diff-size.sh "$(printf '{"tool_name":"Write","tool_input":{"file_path":"/x/big.py","content":%s}}' "$(printf '%s' "$BIG" | jq -Rs .)")"
t CD2 0 check-diff-size.sh "$(wc_ 'short file')"
t CD3 0 check-diff-size.sh "$(printf '{"tool_name":"Write","tool_input":{"file_path":"/x/med.py","content":%s}}' "$(printf '%s' "$MED" | jq -Rs .)")"
echo "== check-diff-size: NotebookEdit coverage =="
t NB3 2 check-diff-size.sh "$(printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/x.ipynb","new_source":%s}}' "$(printf '%s' "$BIG" | jq -Rs .)")"

echo "== verify-done (Stop hook) =="
mkdir -p "$SCRATCH/dirtyrepo" && ( cd "$SCRATCH/dirtyrepo" && git init -q . && echo "x=1" > a.py && git add a.py && git -c user.email=t@t -c user.name=t commit -qm init && echo "x=2" > a.py )
VD_ENV="CLAUDE_PROJECT_DIR=$SCRATCH/dirtyrepo"
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "$VD_ENV" bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd1.txt" || got=$?
if [[ "$got" == 0 ]] && grep -q 'Definition of Done' "$SCRATCH/vd1.txt"; then PASS=$((PASS+1)); echo "PASS VD1    dirty tree -> reminder, exit 0"; else FAIL=$((FAIL+1)); echo "FAIL VD1    want exit 0 + reminder (got exit $got)"; fi
got=0; printf '%s' '{"hook_event_name":"Stop","stop_hook_active":true}' | env "$VD_ENV" bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd4.txt" || got=$?
if [[ "$got" == 0 ]] && ! grep -q 'Definition of Done' "$SCRATCH/vd4.txt"; then PASS=$((PASS+1)); echo "PASS VD4    stop_hook_active honored (no re-entry nag)"; else FAIL=$((FAIL+1)); echo "FAIL VD4    want exit 0 + NO reminder when stop_hook_active (got exit $got)"; fi
git -C "$SCRATCH/dirtyrepo" checkout -q -- a.py
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "$VD_ENV" bash "$HOOKS/verify-done.sh" >/dev/null 2>&1 || got=$?
if [[ "$got" == 0 ]]; then PASS=$((PASS+1)); echo "PASS VD2    clean tree -> exit 0"; else FAIL=$((FAIL+1)); echo "FAIL VD2    clean tree want exit 0 got $got"; fi
mkdir -p "$SCRATCH/nogit"
got=0; printf '%s' '{}' | env "CLAUDE_PROJECT_DIR=$SCRATCH/nogit" bash "$HOOKS/verify-done.sh" >/dev/null 2>&1 || got=$?
if [[ "$got" == 0 ]]; then PASS=$((PASS+1)); echo "PASS VD3    no git -> exit 0"; else FAIL=$((FAIL+1)); echo "FAIL VD3    no git want exit 0 got $got"; fi
# VD5: blocking mode with NO discoverable checker must NOT claim "passed".
mkdir -p "$SCRATCH/nochecks" && ( cd "$SCRATCH/nochecks" && git init -q . && echo "x=1" > a.py && git add a.py && git -c user.email=t@t -c user.name=t commit -qm init && echo "x=2" > a.py )
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "CLAUDE_PROJECT_DIR=$SCRATCH/nochecks" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd5.txt" || got=$?
if [[ "$got" == 2 ]] && ! grep -q 'checks passed' "$SCRATCH/vd5.txt" && grep -qi 'no verification command could run' "$SCRATCH/vd5.txt"; then PASS=$((PASS+1)); echo "PASS VD5    strict: no checker discovered -> fail closed (exit 2)"; else FAIL=$((FAIL+1)); echo "FAIL VD5    want exit 2 + block (not 'checks passed'); got exit $got"; fi
# VD6: blocking mode with a real PASSING checker must run it and exit 0.
# (Regression: bare ((RAN++)) under set -e aborted the hook before any check.)
# Script is `node -e process.exit(0)`, NOT `exit 0`: v8 portability — a bare
# `exit 0` npm script runs through cmd.exe on default Windows npm and fails,
# so 289/291 vs 291/291 depended on the host's npm script-shell. node is
# cross-platform and always available where npm is.
mkdir -p "$SCRATCH/nodeok" && ( cd "$SCRATCH/nodeok" && git init -q . \
  && printf '{"name":"x","version":"1.0.0","scripts":{"test":"node -e \\"process.exit(0)\\""}}\n' > package.json \
  && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'x=1\n' > a.py )
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "CLAUDE_PROJECT_DIR=$SCRATCH/nodeok" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd6.txt" || got=$?
if [[ "$got" == 0 ]] && grep -q 'check(s) passed' "$SCRATCH/vd6.txt"; then PASS=$((PASS+1)); echo "PASS VD6    blocking + passing checker -> ran, exit 0"; else FAIL=$((FAIL+1)); echo "FAIL VD6    want exit 0 + 'check(s) passed'; got exit $got: $(head -c 120 "$SCRATCH/vd6.txt" | tr -d '\n')"; fi
# VD7: blocking mode with a real FAILING checker must report it and exit 2.
mkdir -p "$SCRATCH/nodebad" && ( cd "$SCRATCH/nodebad" && git init -q . \
  && printf '{"name":"x","version":"1.0.0","scripts":{"test":"node -e \\"process.exit(1)\\""}}\n' > package.json \
  && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'x=1\n' > a.py )
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "CLAUDE_PROJECT_DIR=$SCRATCH/nodebad" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd7.txt" || got=$?
if [[ "$got" == 2 ]] && grep -q 'Definition of Done unmet' "$SCRATCH/vd7.txt"; then PASS=$((PASS+1)); echo "PASS VD7    blocking + failing checker -> exit 2"; else FAIL=$((FAIL+1)); echo "FAIL VD7    want exit 2 + 'unmet'; got exit $got: $(head -c 120 "$SCRATCH/vd7.txt" | tr -d '\n')"; fi
# VD8: polyglot repo runs EVERY ecosystem (Node + Rust via a stub cargo on PATH).
mkdir -p "$SCRATCH/stubbin"
printf '#!/bin/sh\nexit 0\n' > "$SCRATCH/stubbin/cargo" && chmod +x "$SCRATCH/stubbin/cargo"
mkdir -p "$SCRATCH/polyglot" && ( cd "$SCRATCH/polyglot" && git init -q . \
  && printf '{"name":"x","version":"1.0.0","scripts":{"test":"node -e \\"process.exit(0)\\""}}\n' > package.json \
  && printf '[package]\nname = "x"\nversion = "0.1.0"\n' > Cargo.toml \
  && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'x=1\n' > a.py )
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "PATH=$SCRATCH/stubbin:$PATH" "CLAUDE_PROJECT_DIR=$SCRATCH/polyglot" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd8.txt" || got=$?
if [[ "$got" == 0 ]] && grep -q 'All 3' "$SCRATCH/vd8.txt"; then PASS=$((PASS+1)); echo "PASS VD8    polyglot ran Node + both cargo checks (3 total)"; else FAIL=$((FAIL+1)); echo "FAIL VD8    want exit 0 + 'All 3'; got exit $got: $(head -c 120 "$SCRATCH/vd8.txt" | tr -d '\n')"; fi
# VD9: checker binary MISSING (bun.lockb selects bun): must honestly report
# nothing verified, not crash and not claim failure. v6: deterministic on ANY
# host — the hook runs on a RESTRICTED PATH containing wrappers for exactly the
# tools it needs, so bun stays absent even on bun-equipped machines.
RBIN="$SCRATCH/rbin"; mkdir -p "$RBIN"
for vd_tool in bash git jq grep mkdir date cat tr basename dirname sed timeout gtimeout; do
  vd_path="$(command -v "$vd_tool")" \
    && printf '#!/bin/sh\nexec "%s" "$@"\n' "$vd_path" > "$RBIN/$vd_tool" \
    && chmod +x "$RBIN/$vd_tool"
done
mkdir -p "$SCRATCH/nodebun" && ( cd "$SCRATCH/nodebun" && git init -q . \
  && printf '{"name":"x","version":"1.0.0","scripts":{"test":"exit 0"}}\n' > package.json \
  && : > bun.lockb \
  && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'x=1\n' > a.py )
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "PATH=$RBIN" "CLAUDE_PROJECT_DIR=$SCRATCH/nodebun" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd9.txt" || got=$?
if [[ "$got" == 2 ]] && grep -qi 'no verification command could run' "$SCRATCH/vd9.txt"; then PASS=$((PASS+1)); echo "PASS VD9    strict: missing checker binary -> fail closed (exit 2, restricted PATH)"; else FAIL=$((FAIL+1)); echo "FAIL VD9    want exit 2 + block; got exit $got: $(head -c 120 "$SCRATCH/vd9.txt" | tr -d '\n')"; fi
# VD9b: same fixture with a stub bun PREPENDED to the restricted PATH — presence
# is controlled too, and the hook must run the package.json test SCRIPT through
# it (`bun run test`), never Bun's native runner (`bun test` exits 1 "No tests
# found" on script-only projects — real Bun 1.3.14 behavior).
BUNSTUB="$SCRATCH/bunstub"; mkdir -p "$BUNSTUB"
printf '#!/bin/sh\necho "bun $*" >> "%s"\nexit 0\n' "$SCRATCH/bun-argv.txt" > "$BUNSTUB/bun"
chmod +x "$BUNSTUB/bun"
: > "$SCRATCH/bun-argv.txt"
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "PATH=$BUNSTUB:$RBIN" "CLAUDE_PROJECT_DIR=$SCRATCH/nodebun" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd9b.txt" || got=$?
if [[ "$got" == 0 ]] && grep -q 'check(s) passed' "$SCRATCH/vd9b.txt" && grep -qx 'bun run test' "$SCRATCH/bun-argv.txt"; then PASS=$((PASS+1)); echo "PASS VD9b   stub bun present -> runs 'bun run test' (package script), exit 0"; else FAIL=$((FAIL+1)); echo "FAIL VD9b   want exit 0 + 'bun run test' argv; got exit $got argv: $(tr '\n' ';' < "$SCRATCH/bun-argv.txt")"; fi
# VD12: modern TEXT lockfile `bun.lock` (Bun >= 1.2 default) must also select
# bun. Pre-v6 it fell through to npm — absent from the restricted PATH, so this
# case fails deterministically before the fix on any host.
mkdir -p "$SCRATCH/nodebunlock" && ( cd "$SCRATCH/nodebunlock" && git init -q . \
  && printf '{"name":"x","version":"1.0.0","scripts":{"test":"exit 0"}}\n' > package.json \
  && printf '{"lockfileVersion": 1}\n' > bun.lock \
  && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'x=1\n' > a.py )
: > "$SCRATCH/bun-argv.txt"
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "PATH=$BUNSTUB:$RBIN" "CLAUDE_PROJECT_DIR=$SCRATCH/nodebunlock" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd12.txt" || got=$?
if [[ "$got" == 0 ]] && grep -q 'check(s) passed' "$SCRATCH/vd12.txt" && grep -qx 'bun run test' "$SCRATCH/bun-argv.txt"; then PASS=$((PASS+1)); echo "PASS VD12   bun.lock (text) selects bun and runs the package script"; else FAIL=$((FAIL+1)); echo "FAIL VD12   want bun selected + 'bun run test' argv; got exit $got: $(head -c 100 "$SCRATCH/vd12.txt" | tr -d '\n') argv: $(tr '\n' ';' < "$SCRATCH/bun-argv.txt")"; fi

# --- S1/S2/S3/S5: bounded, fail-closed Stop verification ---------------------
# Own isolated fixture ($SCRATCH/nodewf) and stub argv file — VD13 below uses
# its own $SCRATCH/nodewatch, and sharing a dir would leave one test's committed
# a.py making the other's tree clean (verify-done would exit early). The
# restricted PATH ($RBIN) now carries a real `timeout`, so these are
# deterministic on any host. The stub npm records argv and exits 0.
WFSTUB="$SCRATCH/npmstub-wf"; mkdir -p "$WFSTUB"
printf '#!/bin/sh\necho "npm $*" >> "%s"\nexit 0\n' "$SCRATCH/npmwf-argv.txt" > "$WFSTUB/npm"; chmod +x "$WFSTUB/npm"
mkdir -p "$SCRATCH/nodewf" && ( cd "$SCRATCH/nodewf" && git init -q . \
  && printf '{"name":"x","version":"1.0.0","scripts":{"test":"vitest --watch=false"}}\n' > package.json \
  && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'y=2\n' > b.py )

# VDW1 (S3) — `--watch=false` is a FINITE run, not a watcher: must be executed.
: > "$SCRATCH/npmwf-argv.txt"
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "PATH=$WFSTUB:$RBIN" "CLAUDE_PROJECT_DIR=$SCRATCH/nodewf" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vdw.txt" || got=$?
if [[ "$got" == 0 ]] && grep -q 'check(s) passed' "$SCRATCH/vdw.txt" && grep -qx 'npm run test' "$SCRATCH/npmwf-argv.txt"; then PASS=$((PASS+1)); echo "PASS VDW1   --watch=false is run, not skipped as a watcher"; else FAIL=$((FAIL+1)); echo "FAIL VDW1   want 'check(s) passed' + 'npm run test'; got exit $got: $(head -c 100 "$SCRATCH/vdw.txt" | tr -d '\n')"; fi

# VDD1 (S1) — the aggregate budget bounds TOTAL verification (0 => immediate).
: > "$SCRATCH/npmwf-argv.txt"
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "PATH=$WFSTUB:$RBIN" "CLAUDE_PROJECT_DIR=$SCRATCH/nodewf" CLAUDE_VERIFY_BLOCK=1 CLAUDE_VERIFY_TOTAL_TIMEOUT_S=0 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vdd.txt" || got=$?
if [[ "$got" == 2 ]] && grep -qi 'budget' "$SCRATCH/vdd.txt"; then PASS=$((PASS+1)); echo "PASS VDD1   aggregate budget exhausted -> check skipped, blocked"; else FAIL=$((FAIL+1)); echo "FAIL VDD1   want exit 2 + 'budget'; got exit $got: $(head -c 100 "$SCRATCH/vdd.txt" | tr -d '\n')"; fi

# VDNT1 (S2) — blocking mode with NO timeout tool must fail closed, not run
# unbounded. Restricted PATH built WITHOUT timeout/gtimeout.
RBIN_NT="$SCRATCH/rbin-nt"; mkdir -p "$RBIN_NT"
for vd_tool in bash git jq grep mkdir date cat tr basename dirname sed; do
  vd_path="$(command -v "$vd_tool")" && printf '#!/bin/sh\nexec "%s" "$@"\n' "$vd_path" > "$RBIN_NT/$vd_tool" && chmod +x "$RBIN_NT/$vd_tool"
done
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "PATH=$WFSTUB:$RBIN_NT" "CLAUDE_PROJECT_DIR=$SCRATCH/nodewf" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vdnt.txt" || got=$?
if [[ "$got" == 2 ]] && grep -qi 'cannot bound' "$SCRATCH/vdnt.txt"; then PASS=$((PASS+1)); echo "PASS VDNT1  blocking + no timeout tool -> fail closed (exit 2)"; else FAIL=$((FAIL+1)); echo "FAIL VDNT1  want exit 2 + 'cannot bound'; got exit $got: $(head -c 100 "$SCRATCH/vdnt.txt" | tr -d '\n')"; fi

# VDST1 (S1) — the Stop hook carries an explicit outer timeout in settings.json.
if jq -e '.hooks.Stop[0].hooks[0].timeout' "$REPO/.claude/settings.json" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "PASS VDST1  Stop hook has explicit settings timeout"; else FAIL=$((FAIL+1)); echo "FAIL VDST1  Stop hook missing explicit timeout in settings.json"; fi
# VD10: multiple failing checks are all counted.
mkdir -p "$SCRATCH/nodebad2" && ( cd "$SCRATCH/nodebad2" && git init -q . \
  && printf '{"name":"x","version":"1.0.0","scripts":{"lint":"node -e \\"process.exit(1)\\"","test":"node -e \\"process.exit(1)\\""}}\n' > package.json \
  && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'x=1\n' > a.py )
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "CLAUDE_PROJECT_DIR=$SCRATCH/nodebad2" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd10.txt" || got=$?
if [[ "$got" == 2 ]] && grep -q '2 of 2' "$SCRATCH/vd10.txt"; then PASS=$((PASS+1)); echo "PASS VD10   both failing checks counted (2 of 2), exit 2"; else FAIL=$((FAIL+1)); echo "FAIL VD10   want exit 2 + '2 of 2'; got exit $got: $(head -c 120 "$SCRATCH/vd10.txt" | tr -d '\n')"; fi
# VD13 (v8 A5): a watch-mode test SCRIPT must be SKIPPED, not run — otherwise
# blocking Stop hangs until the timeout. Must finish fast, exit 0, say
# "no verification" (nothing else ran), and NEVER invoke the package manager
# for the watch script. A stub npm records any invocation so we can assert it
# was not called; a real npm on PATH would also work but the stub makes the
# "skipped, not run" guarantee deterministic on any host.
NPMSTUB="$SCRATCH/npmstub"; mkdir -p "$NPMSTUB"
printf '#!/bin/sh\necho "npm $*" >> "%s"\nexit 0\n' "$SCRATCH/npm-argv.txt" > "$NPMSTUB/npm"
chmod +x "$NPMSTUB/npm"
: > "$SCRATCH/npm-argv.txt"
mkdir -p "$SCRATCH/nodewatch" && ( cd "$SCRATCH/nodewatch" && git init -q . \
  && printf '{"name":"x","version":"1.0.0","scripts":{"test":"vitest --watch"}}\n' > package.json \
  && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'x=1\n' > a.py )
vd13_start=$(date +%s); got=0
printf '%s' '{"hook_event_name":"Stop"}' | env "PATH=$NPMSTUB:$RBIN" "CLAUDE_PROJECT_DIR=$SCRATCH/nodewatch" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd13.txt" || got=$?
vd13_wall=$(( $(date +%s) - vd13_start ))
if [[ "$got" == 2 ]] && grep -qi 'watch' "$SCRATCH/vd13.txt" && grep -qi 'no verification' "$SCRATCH/vd13.txt" \
   && [[ ! -s "$SCRATCH/npm-argv.txt" ]] && (( vd13_wall < 30 )); then
  PASS=$((PASS+1)); echo "PASS VD13   watch-mode script skipped fast (npm never invoked); strict -> fail closed"
else
  FAIL=$((FAIL+1)); echo "FAIL VD13   want fast exit 2 + 'watch' + 'no verification' + npm-not-called; got exit $got wall=${vd13_wall}s npm-argv='$(tr '\n' ';' < "$SCRATCH/npm-argv.txt")': $(head -c 120 "$SCRATCH/vd13.txt" | tr -d '\n')"
fi
# VD14 (v8 A5 backstop): a non-obvious long runner is bounded by
# CLAUDE_VERIFY_TIMEOUT_S and reported as a timeout failure, not a hang.
if command -v timeout >/dev/null 2>&1; then
  mkdir -p "$SCRATCH/nodeslow" && ( cd "$SCRATCH/nodeslow" && git init -q . \
    && printf '{"name":"x","version":"1.0.0","scripts":{"test":"sleep 60"}}\n' > package.json \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
    && printf 'x=1\n' > a.py )
  vd14_start=$(date +%s); got=0
  printf '%s' '{"hook_event_name":"Stop"}' | env "CLAUDE_PROJECT_DIR=$SCRATCH/nodeslow" CLAUDE_VERIFY_BLOCK=1 CLAUDE_VERIFY_TIMEOUT_S=3 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd14.txt" || got=$?
  vd14_wall=$(( $(date +%s) - vd14_start ))
  if [[ "$got" == 2 ]] && grep -qi 'timed out' "$SCRATCH/vd14.txt" && (( vd14_wall < 30 )); then
    PASS=$((PASS+1)); echo "PASS VD14   slow check bounded by CLAUDE_VERIFY_TIMEOUT_S, reported as timeout"
  else
    FAIL=$((FAIL+1)); echo "FAIL VD14   want exit 2 + 'timed out' under budget; got exit $got wall=${vd14_wall}s: $(head -c 120 "$SCRATCH/vd14.txt" | tr -d '\n')"
  fi
else
  echo "SKIP VD14   'timeout' not available on this host — timeout backstop unverified here"
fi

echo "== install.sh: counter must survive set -e =="
if grep -q '((FAIL++))' "$HOOKS/install.sh"; then FAIL=$((FAIL+1)); echo "FAIL INST1  install.sh still uses ((FAIL++)) — dies under set -e on first failing test"; else PASS=$((PASS+1)); echo "PASS INST1  no set -e-fatal increments"; fi

echo "== claude-init: generated projects inherit root protections =="
# Bootstrap a project from THIS repo as the template and assert the protection
# files are copied and would ignore machine-local/secret files.
BOOT="$SCRATCH/boot"; mkdir -p "$BOOT"
( set +e
  # shellcheck disable=SC1090,SC1091  # sourced path is a runtime variable
  source "$REPO/claude-init.sh"
  CLAUDE_TEMPLATE_DIR="$REPO" CLAUDE_PROJECTS_DIR="$BOOT" claude-init gen >/dev/null 2>&1
)
GENP="$BOOT/gen"
if [[ -f "$GENP/.gitignore" && -f "$GENP/.gitattributes" ]]; then PASS=$((PASS+1)); echo "PASS BOOT1  .gitignore + .gitattributes copied"; else FAIL=$((FAIL+1)); echo "FAIL BOOT1  generated project missing .gitignore/.gitattributes"; fi
( cd "$GENP" 2>/dev/null && git init -q 2>/dev/null && printf 'SECRET=x\n' > .env && git add -A 2>/dev/null
  if git status --porcelain .env 2>/dev/null | grep -q .; then echo STAGED; else echo IGNORED; fi ) > "$SCRATCH/boot_env.txt" 2>/dev/null
if grep -q IGNORED "$SCRATCH/boot_env.txt"; then PASS=$((PASS+1)); echo "PASS BOOT2  .env is ignored in generated project"; else FAIL=$((FAIL+1)); echo "FAIL BOOT2  .env would be staged in generated project"; fi
if [[ ! -e "$GENP/reports" && ! -e "$GENP/external-review-v2.md" ]]; then PASS=$((PASS+1)); echo "PASS BOOT3  audit reports/external reviews not copied"; else FAIL=$((FAIL+1)); echo "FAIL BOOT3  template audit artifacts leaked into generated project"; fi

echo "== claude-init: unsafe names, missing sources, failure atomicity =="
# BOOT4: a traversal name must be refused and must not create anything outside DEST_ROOT.
rc=0
( set +e
  # shellcheck disable=SC1090,SC1091
  source "$REPO/claude-init.sh"
  CLAUDE_TEMPLATE_DIR="$REPO" CLAUDE_PROJECTS_DIR="$BOOT" claude-init '../esc' >/dev/null 2>&1
) || rc=$?
if [[ "$rc" != 0 && ! -e "$SCRATCH/esc" ]]; then PASS=$((PASS+1)); echo "PASS BOOT4  traversal name refused, nothing escaped the root"; else FAIL=$((FAIL+1)); echo "FAIL BOOT4  '../esc' must fail and create nothing (rc=$rc, exists=$([[ -e "$SCRATCH/esc" ]] && echo yes || echo no))"; fi
# BOOT5: a name containing a separator must be refused.
rc=0
( set +e
  # shellcheck disable=SC1090,SC1091
  source "$REPO/claude-init.sh"
  CLAUDE_TEMPLATE_DIR="$REPO" CLAUDE_PROJECTS_DIR="$BOOT" claude-init 'a/b' >/dev/null 2>&1
) || rc=$?
if [[ "$rc" != 0 && ! -e "$BOOT/a" ]]; then PASS=$((PASS+1)); echo "PASS BOOT5  separator name refused"; else FAIL=$((FAIL+1)); echo "FAIL BOOT5  'a/b' must fail and create nothing"; fi
# BOOT6: a template missing CLAUDE.md must fail up front — no destination created.
TNOCM="$SCRATCH/tmpl-nocm"; mkdir -p "$TNOCM/.claude/hooks"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TNOCM/.claude/hooks/install.sh"
: > "$TNOCM/.gitignore"; : > "$TNOCM/.gitattributes"
rc=0
( set +e
  # shellcheck disable=SC1090,SC1091
  source "$REPO/claude-init.sh"
  CLAUDE_TEMPLATE_DIR="$TNOCM" CLAUDE_PROJECTS_DIR="$BOOT" claude-init nocm >/dev/null 2>&1
) || rc=$?
if [[ "$rc" != 0 && ! -e "$BOOT/nocm" ]]; then PASS=$((PASS+1)); echo "PASS BOOT6  incomplete template refused before creating anything"; else FAIL=$((FAIL+1)); echo "FAIL BOOT6  missing CLAUDE.md must fail with no destination (rc=$rc)"; fi
# BOOT7: installer failure must leave NO destination, NO temp dirs, and the
# caller's cwd untouched.
TBAD="$SCRATCH/tmpl-bad"; mkdir -p "$TBAD/.claude/hooks"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TBAD/.claude/hooks/install.sh"
printf '# t\n' > "$TBAD/CLAUDE.md"; : > "$TBAD/.gitignore"; : > "$TBAD/.gitattributes"
( set +e
  # shellcheck disable=SC1090,SC1091
  source "$REPO/claude-init.sh"
  cd "$SCRATCH" || exit 9
  before="$(pwd)"
  CLAUDE_TEMPLATE_DIR="$TBAD" CLAUDE_PROJECTS_DIR="$BOOT" claude-init bad >/dev/null 2>&1
  rc=$?
  after="$(pwd)"
  printf 'rc=%s\nsamecwd=%s\n' "$rc" "$([[ "$before" == "$after" ]] && echo yes || echo no)" > "$SCRATCH/boot7.txt"
)
LEFTOVER="$(find "$BOOT" -maxdepth 1 -name '.claude-init*' -print -quit 2>/dev/null)"
if grep -q 'rc=1' "$SCRATCH/boot7.txt" && grep -q 'samecwd=yes' "$SCRATCH/boot7.txt" && [[ ! -e "$BOOT/bad" && -z "$LEFTOVER" ]]; then
  PASS=$((PASS+1)); echo "PASS BOOT7  installer failure is atomic (no dest, no temp, cwd preserved)"
else
  FAIL=$((FAIL+1)); echo "FAIL BOOT7  $(tr '\n' ' ' < "$SCRATCH/boot7.txt") dest=$([[ -e "$BOOT/bad" ]] && echo left || echo none) temp=${LEFTOVER:-none}"
fi
# BOOT8: names with spaces still bootstrap successfully.
rc=0
( set +e
  # shellcheck disable=SC1090,SC1091
  source "$REPO/claude-init.sh"
  CLAUDE_TEMPLATE_DIR="$REPO" CLAUDE_PROJECTS_DIR="$BOOT" claude-init 'my proj' >/dev/null 2>&1
) || rc=$?
if [[ "$rc" == 0 && -f "$BOOT/my proj/CLAUDE.md" && -d "$BOOT/my proj/.claude" ]]; then PASS=$((PASS+1)); echo "PASS BOOT8  space-containing name bootstraps"; else FAIL=$((FAIL+1)); echo "FAIL BOOT8  'my proj' should bootstrap cleanly (rc=$rc)"; fi
# BOOT9: machine-local Claude state in the template must NOT leak into the
# generated project (D6). Build a template that mirrors the repo but carries
# local state, bootstrap from it, assert none of the local paths came across.
TLOCAL="$SCRATCH/tmpl-local"; mkdir -p "$TLOCAL"
cp "$REPO/CLAUDE.md" "$TLOCAL/"; cp "$REPO/.gitignore" "$TLOCAL/"; cp "$REPO/.gitattributes" "$TLOCAL/"
cp -r "$REPO/.claude" "$TLOCAL/.claude"
printf '{"local":true}\n' > "$TLOCAL/.claude/settings.local.json"
mkdir -p "$TLOCAL/.claude/logs" && printf 'log\n' > "$TLOCAL/.claude/logs/hooks.log"
mkdir -p "$TLOCAL/.claude/worktrees/br" && printf 'stray\n' > "$TLOCAL/.claude/worktrees/br/f.txt"
printf '# plan\n' > "$TLOCAL/.claude/CLEANUP_PLAN.md"
printf '# exec\n' > "$TLOCAL/.claude/CLEANUP_EXECUTION.md"
( set +e
  # shellcheck disable=SC1090,SC1091
  source "$REPO/claude-init.sh"
  CLAUDE_TEMPLATE_DIR="$TLOCAL" CLAUDE_PROJECTS_DIR="$BOOT" claude-init genlocal >/dev/null 2>&1
)
GL="$BOOT/genlocal"; leak9=""
for lp in .claude/settings.local.json .claude/logs .claude/worktrees .claude/CLEANUP_PLAN.md .claude/CLEANUP_EXECUTION.md; do
  [[ -e "$GL/$lp" ]] && leak9="$leak9 $lp"
done
if [[ -f "$GL/CLAUDE.md" && -z "$leak9" ]]; then PASS=$((PASS+1)); echo "PASS BOOT9  machine-local state excluded from generated project"; else FAIL=$((FAIL+1)); echo "FAIL BOOT9  local state leaked:$leak9 (project built=$([[ -f "$GL/CLAUDE.md" ]] && echo yes || echo no))"; fi

echo "== settings.json: matcher covers current editing tools =="
if grep -q 'MultiEdit' "$REPO/.claude/settings.json"; then FAIL=$((FAIL+1)); echo "FAIL SET1   matcher still lists MultiEdit (tool removed in current Claude Code)"; else PASS=$((PASS+1)); echo "PASS SET1   no stale MultiEdit matcher"; fi
if grep -q 'NotebookEdit' "$REPO/.claude/settings.json"; then PASS=$((PASS+1)); echo "PASS SET2   NotebookEdit matched"; else FAIL=$((FAIL+1)); echo "FAIL SET2   NotebookEdit not matched — notebook edits bypass file hooks"; fi
# Fast PreToolUse validators declare a short explicit timeout; the Stop hook is
# deliberately exempt (blocking mode legitimately runs full test suites).
if jq -e '[.hooks.PreToolUse[].hooks[] | select((.timeout // null) == null)] | length == 0' "$REPO/.claude/settings.json" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS SET3   every PreToolUse validator declares a timeout"
else
  FAIL=$((FAIL+1)); echo "FAIL SET3   PreToolUse validator(s) missing an explicit timeout"
fi

echo "== verify-done: real linked worktree (.git is a FILE) =="
# D1 regression: a linked worktree's .git is a file, not a dir. The Stop hook
# must still detect uncommitted code and emit the reminder — not silently exit.
WTMAIN="$SCRATCH/wt-main"; mkdir -p "$WTMAIN"
( cd "$WTMAIN" && git init -q . && git config core.longpaths true \
  && printf 'x=1\n' > a.py && git add a.py \
  && git -c user.email=t@t -c user.name=t commit -qm init \
  && git worktree add -q "$SCRATCH/wt-linked" -b feature >/dev/null 2>&1 )
# Sanity: confirm .git really is a file in the linked worktree.
if [[ -f "$SCRATCH/wt-linked/.git" ]]; then PASS=$((PASS+1)); echo "PASS WT0    linked worktree .git is a file"; else FAIL=$((FAIL+1)); echo "FAIL WT0    expected .git file in linked worktree"; fi
printf 'x=2\n' > "$SCRATCH/wt-linked/a.py"
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "CLAUDE_PROJECT_DIR=$SCRATCH/wt-linked" bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/wt.txt" || got=$?
if [[ "$got" == 0 ]] && grep -q 'Definition of Done' "$SCRATCH/wt.txt"; then PASS=$((PASS+1)); echo "PASS WT1    dirty linked worktree -> reminder (exit 0)"; else FAIL=$((FAIL+1)); echo "FAIL WT1    linked worktree Stop must remind (got exit $got, reminder=$(grep -c 'Definition of Done' "$SCRATCH/wt.txt"))"; fi
# Clean the worktree -> no reminder.
( cd "$SCRATCH/wt-linked" && git checkout -q -- a.py )
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "CLAUDE_PROJECT_DIR=$SCRATCH/wt-linked" bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/wt2.txt" || got=$?
if [[ "$got" == 0 ]] && ! grep -q 'Definition of Done' "$SCRATCH/wt2.txt"; then PASS=$((PASS+1)); echo "PASS WT2    clean linked worktree -> no reminder"; else FAIL=$((FAIL+1)); echo "FAIL WT2    clean worktree must not remind (got exit $got)"; fi

echo "== verify-done: untracked code file inside a NEW untracked dir is counted =="
# D2 regression: default porcelain collapses new dirs to '?? newdir/', missing
# the .py inside. --untracked-files=all must surface it.
UNT="$SCRATCH/untdir"; mkdir -p "$UNT"
( cd "$UNT" && git init -q . && printf 'x=1\n' > seed.py && git add seed.py \
  && git -c user.email=t@t -c user.name=t commit -qm init \
  && mkdir -p brandnew && printf 'y=1\n' > brandnew/mod.py )
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "CLAUDE_PROJECT_DIR=$UNT" bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/unt.txt" || got=$?
if [[ "$got" == 0 ]] && grep -q 'Definition of Done' "$SCRATCH/unt.txt"; then PASS=$((PASS+1)); echo "PASS VD11   untracked .py in new dir triggers reminder"; else FAIL=$((FAIL+1)); echo "FAIL VD11   untracked .py in new dir must be counted (got exit $got)"; fi

echo "== scan-secrets: NO secret substring in stdout/stderr/log =="
# D4 regression: the hook must not print any prefix/preview of the matched value.
export CLAUDE_PROJECT_DIR="$SCRATCH/ss-out"; mkdir -p "$SCRATCH/ss-out"
SEC_AWS="AKIA""ZZ34567890QRSTUV"   # real-shape, no marker, constructed at runtime
printf '{"tool_name":"Write","tool_input":{"content":%s}}' "$(printf 'k = "%s"' "$SEC_AWS" | jq -Rs .)" \
  | bash "$HOOKS/scan-secrets.sh" >"$SCRATCH/ss_out.txt" 2>"$SCRATCH/ss_err.txt" || true
LOGF="$SCRATCH/ss-out/.claude/logs/hooks.log"
# Probe the SECRET material (the 16 random chars), not the public 'AKIA' scheme
# prefix — that prefix legitimately appears inside the regex pattern name.
leak=0
for probe in "$SEC_AWS" "${SEC_AWS:0:8}" "${SEC_AWS:4:8}" "${SEC_AWS: -8}"; do
  grep -qF "$probe" "$SCRATCH/ss_out.txt" 2>/dev/null && leak=1
  grep -qF "$probe" "$SCRATCH/ss_err.txt" 2>/dev/null && leak=1
  [[ -f "$LOGF" ]] && grep -qF "$probe" "$LOGF" 2>/dev/null && leak=1
done
if [[ "$leak" == 0 ]]; then PASS=$((PASS+1)); echo "PASS SS11   no secret substring in stdout/stderr/log"; else FAIL=$((FAIL+1)); echo "FAIL SS11   secret substring leaked to output/log"; fi
export CLAUDE_PROJECT_DIR="$SCRATCH"

echo "== logging: hostile field cannot inject a second log record =="
# D5 regression: a file path with an embedded newline must not forge a log line.
export CLAUDE_PROJECT_DIR="$SCRATCH/loginj"; mkdir -p "$SCRATCH/loginj"
EVILP=$'/repo/migrations/a\n2099-01-01T00:00:00Z\tBLOCK\tfake\tfake\tinjected\t.sql'
printf '{"tool_name":"Write","tool_input":{"file_path":%s}}' "$(printf '%s' "$EVILP" | jq -Rs .)" \
  | bash "$HOOKS/protect-files.sh" >/dev/null 2>&1 || true
LOGI="$SCRATCH/loginj/.claude/logs/hooks.log"
lines=$(wc -l < "$LOGI" 2>/dev/null | tr -d ' ')
inj=$(grep -c '^2099-01-01' "$LOGI" 2>/dev/null || true)
if [[ "$lines" == 1 && "$inj" == 0 ]]; then PASS=$((PASS+1)); echo "PASS LOG1   hostile path logged as one escaped record"; else FAIL=$((FAIL+1)); echo "FAIL LOG1   log record injection (lines=$lines injected=$inj)"; fi
export CLAUDE_PROJECT_DIR="$SCRATCH"

echo "== block-destructive: prefix / end-of-options rm bypasses now blocked =="
t BD40 2 block-destructive.sh "$(cmd '/bin/rm -rf /')"
t BD41 2 block-destructive.sh "$(cmd '\rm -rf /')"
t BD42 2 block-destructive.sh "$(cmd 'rm -rf -- /')"
t BD43 2 block-destructive.sh "$(cmd 'rm --recursive --force -- /')"
t BD44 0 block-destructive.sh "$(cmd 'rm -rf build/')"          # still allowed (safe target)
t BD45 0 block-destructive.sh "$(cmd 'confirm the release')"    # 'rm' inside a word must not match
echo "== block-destructive: schema-qualified / bracketed DELETE, DROP object variants =="
t BD46 2 block-destructive.sh "$(cmd 'DELETE FROM dbo.Users;')"
t BD47 2 block-destructive.sh "$(cmd 'DELETE FROM [dbo].[Users];')"
t BD48 0 block-destructive.sh "$(cmd 'DELETE FROM dbo.Users WHERE id = 1;')"   # WHERE-guarded stays allowed
t BD49 2 block-destructive.sh "$(cmd 'DROP VIEW dbo.v_users')"
t BD50 2 block-destructive.sh "$(cmd 'DROP PROCEDURE dbo.p')"
t BD51 2 block-destructive.sh "$(cmd 'DROP INDEX IX_x ON dbo.t')"
echo "== block-destructive: force-push via +refspec =="
t BD52 2 block-destructive.sh "$(cmd 'git push origin +main')"
t BD53 2 block-destructive.sh "$(cmd 'git push origin +refs/heads/main')"
t BD54 0 block-destructive.sh "$(cmd 'git push origin main')"   # plain push still allowed (normal perm flow)

echo "== protect-files: private-key / credential files gated =="
t PFK1 2 protect-files.sh "$(fp '/repo/id_rsa')"
# v5: generic *.pem is ASK, not deny — PEM containers are often PUBLIC cert
# chains; private-key CONTENT is still hard-blocked by scan-secrets.
t_ask PFK2 protect-files.sh "$(fp '/repo/certs/server.pem')"
t PFK3 2 protect-files.sh "$(fp '/repo/tls.key')"
t_ask PFK4 protect-files.sh "$(fp '/repo/.netrc')"
t_ask PFK5 protect-files.sh "$(fp '/repo/.npmrc')"
t_ask PFK6 protect-files.sh "$(fp '/repo/.pypirc')"
echo "== protect-files: .env case-insensitive (same file on Windows/macOS) =="
t PFC1 2 protect-files.sh "$(fp '/repo/.ENV')"
t PFC2 2 protect-files.sh "$(fp '/repo/.Env.Local')"
echo "== protect-files: composite actions, submodules, root infra =="
t_ask PFI1 protect-files.sh "$(fp '/repo/.github/actions/build/action.yml')"
t_ask PFI2 protect-files.sh "$(fp '/repo/.gitmodules')"
t_ask PFI3 protect-files.sh "$(fp '/repo/main.tf')"
t_ask PFI4 protect-files.sh "$(fp '/repo/modules/vpc/network.tf')"
echo "== protect-files: still no substring false positives after additions =="
t PFC3 0 protect-files.sh "$(fp '/repo/src/keyboard.ts')"       # '.key' substring must not match
t PFC4 0 protect-files.sh "$(fp '/repo/src/environment.ts')"    # 'env' substring must not match

echo "== block-destructive: v5 quoted / braced / fully-quoted rm spellings =="
t BD60 2 block-destructive.sh "$(cmd '"/bin/rm" -rf /')"
t BD61 2 block-destructive.sh "$(cmd "'/bin/rm' -rf /")"
# shellcheck disable=SC2016  # deliberate: payloads must carry a LITERAL ${HOME}
t BD62 2 block-destructive.sh "$(cmd 'rm -rf ${HOME}')"
# shellcheck disable=SC2016
t BD63 2 block-destructive.sh "$(cmd 'rm -rf "${HOME}"')"
t BD64 2 block-destructive.sh "$(cmd "'rm' -rf /")"
echo "== block-destructive: quoted rm PROSE stays allowed (safe controls) =="
t BD65 0 block-destructive.sh "$(cmd "echo 'rm -rf /'")"
t BD66 0 block-destructive.sh "$(cmd 'echo "rm -rf /"')"
echo "== block-destructive: quoted force-refspec =="
t BD67 2 block-destructive.sh "$(cmd 'git push origin "+main"')"
t BD68 2 block-destructive.sh "$(cmd "git push origin '+main'")"
echo "== block-destructive: semicolon-less unguarded DELETE at end-of-command =="
t BD70 2 block-destructive.sh "$(cmd 'DELETE FROM users')"
t BD71 2 block-destructive.sh "$(cmd 'DELETE FROM dbo.Users')"
t BD72 2 block-destructive.sh "$(cmd 'DELETE FROM [dbo].[Users]')"
t BD73 0 block-destructive.sh "$(cmd 'DELETE FROM users WHERE id = 1')"     # WHERE-guarded
t BD74 0 block-destructive.sh "$(cmd 'echo "DELETE FROM users"')"           # docs text
t BD75 0 block-destructive.sh "$(cmd 'git commit -m "document DELETE FROM users"')"  # docs text
echo "== block-destructive: option-first installs ASK; option-only restores stay allowed =="
t_ask ASK18 block-destructive.sh "$(cmd 'npm install --save-dev lodash')"
t_ask ASK19 block-destructive.sh "$(cmd 'npm i -D lodash')"
t_ask ASK20 block-destructive.sh "$(cmd 'npm install -g typescript')"
t_ask ASK21 block-destructive.sh "$(cmd 'pip install --user requests')"
t_ask   AL12 block-destructive.sh "$(cmd 'npm install --legacy-peer-deps')"   # v9: options-only install still re-resolves → ask

echo "== block-destructive: git commit on a protected branch ASKs (CLAUDE.md §2) =="
PBMAIN="$SCRATCH/pb-main"; mkdir -p "$PBMAIN"
( cd "$PBMAIN" && git init -q -b main . && printf 'x\n' > f.txt && git add f.txt \
  && git -c user.email=t@t -c user.name=t commit -qm init )
PBFEAT="$SCRATCH/pb-feat"; mkdir -p "$PBFEAT"
( cd "$PBFEAT" && git init -q -b feat/x . && printf 'x\n' > f.txt && git add f.txt \
  && git -c user.email=t@t -c user.name=t commit -qm init )
t_ask  PBC1 block-destructive.sh "$(cmd 'git commit -am wip')" "CLAUDE_PROJECT_DIR=$PBMAIN"
t_noask PBC2 block-destructive.sh "$(cmd 'git commit -am wip')" "CLAUDE_PROJECT_DIR=$PBFEAT"
t_noask PBC3 block-destructive.sh "$(cmd 'git commit -am wip')" "CLAUDE_PROJECT_DIR=$SCRATCH"
# deny still beats the branch ask when both would apply
t PBC4 2 block-destructive.sh "$(cmd 'git commit -am wip && git push --force')" "CLAUDE_PROJECT_DIR=$PBMAIN"

echo "== protect-files: v5 case-folded sensitive basenames (same file on Windows/macOS) =="
t PFF1 2 protect-files.sh "$(fp '/repo/ID_RSA')"
t PFF2 2 protect-files.sh "$(fp '/repo/Id_Rsa')"
t PFF3 2 protect-files.sh "$(fp '/repo/Secrets.yaml')"
t PFF4 2 protect-files.sh "$(fp '/repo/Credentials.json')"
t_ask PFF5 protect-files.sh "$(fp '/repo/.NPMRC')"
t_ask PFF6 protect-files.sh "$(fp '/repo/.PYPIRC')"
t_ask PFF7 protect-files.sh "$(fp '/repo/.NETRC')"
t PFF8 0 protect-files.sh "$(fp '/repo/src/KeyBoard.ts')"   # mixed-case substring still no match

echo "== protect-files: BOTH settings layers ask (local allow rules skip workspace trust) =="
t_ask PFS1 protect-files.sh "$(fp '/repo/.claude/settings.local.json')"
t_ask PFS2 protect-files.sh '{"tool_name":"Edit","tool_input":{"file_path":"/repo/.claude/settings.local.json"}}'
t_ask PFS3 protect-files.sh '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/repo/.claude/settings.local.json"}}'
t_ask PFS4 protect-files.sh "$(fp '/repo/.claude/settings.json')"

echo "== protect-files: whole .github/actions/ subtree asks (scripts run with CI trust) =="
t_ask PFI5 protect-files.sh "$(fp '/repo/.github/actions/example/script.sh')"
t_ask PFI6 protect-files.sh "$(fp '/repo/.github/actions/example/index.js')"
t PFI7 0 protect-files.sh "$(fp '/repo/.github/ISSUE_TEMPLATE.md')"   # docs outside actions/ stay editable

echo "== claude-init: single masked copy failures (v5 P1 regression) =="
# PATH-stub cp fails on exactly ONE source basename; everything later would
# succeed. Pre-fix, CLAUDE.md/.gitignore/.gitattributes copy failures were
# masked (set -e is inert inside `if ! ( ... )`) and an incomplete project
# published with a success message.
STUBCP="$SCRATCH/stubcp"; mkdir -p "$STUBCP"
REAL_CP="$(command -v cp)"
cat > "$STUBCP/cp" <<STUB
#!/usr/bin/env bash
if [[ -n "\${FAIL_CP_BASE:-}" ]]; then
  for a in "\$@"; do
    if [[ "\$(basename "\$a")" == "\$FAIL_CP_BASE" ]]; then
      echo "stub-cp: injected failure on \$a" >&2
      exit 1
    fi
  done
fi
exec "$REAL_CP" "\$@"
STUB
chmod +x "$STUBCP/cp"
bootfail() { # bootfail <id> <basename-to-fail>
  local id="$1" failbase="$2"
  local root="$SCRATCH/bf-$id"
  mkdir -p "$root"
  ( set +e
    cd "$SCRATCH" || exit 9
    before="$(pwd)"
    # shellcheck disable=SC1090,SC1091  # sourced path is a runtime variable
    source "$REPO/claude-init.sh"
    PATH="$STUBCP:$PATH" FAIL_CP_BASE="$failbase" \
      CLAUDE_TEMPLATE_DIR="$REPO" CLAUDE_PROJECTS_DIR="$root" \
      claude-init proj > "$SCRATCH/bf-$id.out" 2>&1
    rc=$?
    printf 'rc=%s samecwd=%s\n' "$rc" "$([[ "$(pwd)" == "$before" ]] && echo yes || echo no)" > "$SCRATCH/bf-$id.txt"
  )
  local leftover
  leftover="$(find "$root" -maxdepth 1 -name '.claude-init*' -print -quit 2>/dev/null)"
  if grep -q 'rc=1' "$SCRATCH/bf-$id.txt" && grep -q 'samecwd=yes' "$SCRATCH/bf-$id.txt" \
     && [[ ! -e "$root/proj" && -z "$leftover" ]] \
     && ! grep -q 'bootstrapped at' "$SCRATCH/bf-$id.out"; then
    PASS=$((PASS+1)); echo "PASS $id failed '$failbase' copy -> exit 1, no dest, no temp, no success msg, cwd kept"
  else
    FAIL=$((FAIL+1)); echo "FAIL $id $(tr '\n' ' ' < "$SCRATCH/bf-$id.txt") dest=$([[ -e "$root/proj" ]] && echo LEFT || echo none) temp=${leftover:-none} msg=$(grep -c 'bootstrapped at' "$SCRATCH/bf-$id.out")"
  fi
}
bootfail BOOT10 "CLAUDE.md"
bootfail BOOT11 ".claude"
bootfail BOOT12 ".gitignore"
bootfail BOOT13 ".gitattributes"

echo "== gitignore: every hook-allowlisted env template is committable =="
GI="$SCRATCH/gi"; mkdir -p "$GI"
( cd "$GI" && git init -q . && "$REAL_CP" "$REPO/.gitignore" . \
  && for f in .env.example .env.sample .env.template .env.dist .env.test.example; do printf 'X=1\n' > "$f"; done \
  && printf 'SECRET=a\n' > .env && printf 'SECRET=b\n' > .env.local \
  && git add -A 2>/dev/null )
gi_ok=1
for f in .env.example .env.sample .env.template .env.dist .env.test.example; do
  git -C "$GI" ls-files --cached | grep -qxF "$f" || gi_ok=0
done
git -C "$GI" ls-files --cached | grep -qxF ".env" && gi_ok=0
git -C "$GI" ls-files --cached | grep -qxF ".env.local" && gi_ok=0
if [[ "$gi_ok" == 1 ]]; then PASS=$((PASS+1)); echo "PASS GI1    5 templates stage; .env/.env.local stay ignored"; else FAIL=$((FAIL+1)); echo "FAIL GI1    template/gitignore policy disagreement: $(git -C "$GI" ls-files --cached | tr '\n' ' ')"; fi

echo "== block-destructive: v6 current-directory destruction (globs really delete; dot forms are inert but intent-denied) =="
t BD80 2 block-destructive.sh "$(cmd 'rm -rf ./*')"
t BD81 2 block-destructive.sh "$(cmd 'rm -rf -- ./*')"
t BD82 2 block-destructive.sh "$(cmd 'rm -rf ./.??*')"
t BD83 2 block-destructive.sh "$(cmd 'rm -rf ./* ./.??*')"
t BD84 2 block-destructive.sh "$(cmd 'rm -rf "./"*')"
t BD85 2 block-destructive.sh "$(cmd 'rm -rf .')"
t BD86 2 block-destructive.sh "$(cmd 'rm -rf ..')"
t BD87 2 block-destructive.sh "$(cmd 'rm -rf ./')"
t BD88 2 block-destructive.sh "$(cmd 'rm -rf .??*')"
echo "== block-destructive: v6 named relative cleanup stays allowed =="
t BD89 0 block-destructive.sh "$(cmd 'rm -rf ./build')"
t BD90 0 block-destructive.sh "$(cmd 'rm -rf ../temporary-build')"
t BD91 0 block-destructive.sh "$(cmd 'rm -rf ./dist')"
echo "== block-destructive: v8 multiline bypass closed (A1) =="
# The command string carries a REAL newline; jq -Rs in cmd() encodes it as \n.
t BD_ML1 2 block-destructive.sh "$(cmd "$(printf 'rm -rf \\\n/')")"    # backslash line-continuation
t BD_ML2 2 block-destructive.sh "$(cmd "$(printf 'rm -rf\n/')")"       # bare LF, no space
t BD_ML3 2 block-destructive.sh "$(cmd "$(printf 'rm -rf \n/')")"      # bare LF, trailing space
t BD_ML4 2 block-destructive.sh "$(cmd "$(printf 'rm -r\n-f /')")"     # LF inside flag cluster
t BD_ML5 2 block-destructive.sh "$(cmd "$(printf 'echo hi\nrm -rf /')")" # dangerous rm on a later line
echo "== block-destructive: v8 harmless multiline still allowed =="
t BD_ML6 0 block-destructive.sh "$(cmd "$(printf 'ls -la\nsrc/')")"    # harmless listing
t BD_ML7 0 block-destructive.sh "$(cmd "$(printf 'rm -rf ./build\nnpm run build')")" # named cleanup then cmd
echo "== block-destructive: v6 client-wrapped unguarded DELETE without ';' =="
t BD92 2 block-destructive.sh "$(cmd 'psql -c "DELETE FROM users"')"
t BD93 2 block-destructive.sh "$(cmd "psql -c 'DELETE FROM users'")"
t BD94 2 block-destructive.sh "$(cmd 'mysql -e "DELETE FROM users"')"
t BD95 2 block-destructive.sh "$(cmd 'sqlcmd -Q "DELETE FROM dbo.Users"')"
t BD96 2 block-destructive.sh "$(cmd 'psql -U admin -d prod -c "DELETE FROM users"')"
echo "== block-destructive: v6 WHERE-guarded client DELETE and prose stay allowed =="
t BD97 0 block-destructive.sh "$(cmd 'psql -c "DELETE FROM users WHERE id = 1"')"
t BD98 0 block-destructive.sh "$(cmd "printf '%s\\n' 'DELETE FROM users'")"
echo "== block-destructive: v6 env-redirected installs ASK (still fetch+install new code) =="
t_ask ASK22 block-destructive.sh "$(cmd 'npm install --prefix /tmp lodash')"
t_ask ASK23 block-destructive.sh "$(cmd 'pip install --target /tmp requests')"
t_ask ASK24 block-destructive.sh "$(cmd 'pip install --no-deps requests')"
t_ask ASK25 block-destructive.sh "$(cmd 'pip install --index-url https://example.invalid/simple requests')"
t_ask ASK26 block-destructive.sh "$(cmd 'npm install --workspace app lodash')"
t_ask   AL13 block-destructive.sh "$(cmd 'npm install --prefix /tmp')"   # v9: any npm install form asks

echo "== protect-files: v6 directory-segment case variants (same file on Windows/macOS) =="
t PFD1 2 protect-files.sh "$(fp '/repo/.GIT/config')"
t PFD2 2 protect-files.sh "$(fp '/repo/.Secrets/token.txt')"
t PFD3 2 protect-files.sh "$(fp 'C:\repo\.GIT\config')"
t_ask PFD4 protect-files.sh "$(fp '/repo/.CLAUDE/settings.local.json')"
t_ask PFD5 protect-files.sh "$(fp '/repo/.Claude/settings.json')"
t_ask PFD6 protect-files.sh "$(fp '/repo/.GITHUB/actions/example/script.sh')"
t_ask PFD7 protect-files.sh "$(fp '/repo/.github/ACTIONS/example/script.sh')"
t_ask PFD8 protect-files.sh "$(fp '/repo/MIGRATIONS/0001.sql')"
t_ask PFD9 protect-files.sh '{"tool_name":"Edit","tool_input":{"file_path":"/repo/Migrations/0001.sql"}}'
t_ask PFD10 protect-files.sh '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/repo/.GITHUB/Workflows/x.ipynb"}}'
t PFD11 0 protect-files.sh "$(fp '/repo/SRC/App.py')"   # uppercase ordinary dirs still allowed

echo "== check-diff-size: v6 documented override actually unblocks (hooks README) =="
DSC="$(seq 1 1100)"
t DS1 0 check-diff-size.sh "$(wc_ "$DSC")" 'CLAUDE_HOOK_OVERRIDE=check-diff-size'
t DS2 2 check-diff-size.sh "$(wc_ "$DSC")"
DSW="$(seq 1 400)"
t DS3 0 check-diff-size.sh "$(wc_ "$DSW")"   # warn tier stays non-blocking

echo "== v7 V7-01: env-template basename must not bypass unrelated path policy =="
# The allowlist exists to keep committed templates editable. It must suppress
# ONLY the .env* filename deny — never the directory rules that follow.
t V701a 0 protect-files.sh "$(fp '/repo/.env.example')"              # root template: still editable
t V701b 0 protect-files.sh "$(fp '/repo/config/.env.sample')"        # nested ordinary dir: editable
t V701c 2 protect-files.sh "$(fp '/repo/.git/.env.example')"         # .git segment: hard deny
t V701d 2 protect-files.sh "$(fp '/repo/.secrets/.env.example')"     # .secrets segment: hard deny
t_ask V701e protect-files.sh "$(fp '/repo/.github/workflows/.env.example')"
t_ask V701f protect-files.sh "$(fp '/repo/.claude/hooks/.env.example')"
t_ask V701g protect-files.sh '{"tool_name":"Edit","tool_input":{"file_path":"/repo/.github/actions/example/.env.example"}}'
t_ask V701h protect-files.sh '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/repo/migrations/.env.example"}}'
t V701i 2 protect-files.sh "$(fp '/repo/.env')"                      # real secret still denied
t V701j 2 protect-files.sh "$(fp '/repo/.env.local')"                # non-template suffix still denied

echo "== v7 V7-04/05/06/07: recursive-rm target families (bounded guarantee) =="
t V704a 2 block-destructive.sh "$(cmd "rm -rf '/srv/data'")"          # quoted absolute target
t V704b 2 block-destructive.sh "$(cmd 'rm -rf "/srv/data"')"
# shellcheck disable=SC2016  # single quotes are REQUIRED here: the literal
# $PWD / ${PWD} / $(pwd) must reach the hook UNEXPANDED — an expanded path is a
# different test (it would become a plain absolute path, already covered above).
{
  t V705a 2 block-destructive.sh "$(cmd 'rm -rf -- "$PWD"')"
  t V705b 2 block-destructive.sh "$(cmd 'rm -rf -- "${PWD}"')"
  t V705c 2 block-destructive.sh "$(cmd 'rm -rf -- "$(pwd)"')"
  t V705d 2 block-destructive.sh "$(cmd 'rm -rf $PWD')"
}
t V706a 2 block-destructive.sh "$(cmd 'rm -rf -- .[!.]*')"
t V706b 2 block-destructive.sh "$(cmd 'rm -rf -- ./.[!.]*')"
t V706c 2 block-destructive.sh "$(cmd 'rm -rf -- .[^.]*')"
t V707a 2 block-destructive.sh "$(cmd 'rm -rf -- {*,.[!.]*,..?*}')"
# Intended-allow controls: named relative cleanup must survive every widening.
t V70Xa 0 block-destructive.sh "$(cmd 'rm -rf ./build')"
t V70Xb 0 block-destructive.sh "$(cmd 'rm -rf ../tmp-build')"
t V70Xc 0 block-destructive.sh "$(cmd 'rm -rf node_modules')"
t V70Xd 0 block-destructive.sh "$(cmd 'rm -rf dist/assets')"

echo "== v7 V7-03: SQL client long options (short forms already covered) =="
t V703a 2 block-destructive.sh "$(cmd 'psql --command="DELETE FROM users"')"
t V703b 2 block-destructive.sh "$(cmd 'psql --command "DELETE FROM users"')"
t V703c 2 block-destructive.sh "$(cmd 'mysql --execute="DELETE FROM users"')"
t V703d 2 block-destructive.sh "$(cmd 'mysql --execute "DELETE FROM users"')"
t V703e 2 block-destructive.sh "$(cmd 'sqlcmd --query "DELETE FROM dbo.Users"')"
# The quote boundary that keeps documentation allowed is load-bearing.
t V703f 0 block-destructive.sh "$(cmd 'echo "DELETE FROM users"')"
t V703g 0 block-destructive.sh "$(cmd 'psql -c "DELETE FROM users WHERE id = 1"')"
t V703h 0 block-destructive.sh "$(cmd 'printf "%s" "DELETE FROM audit"')"

echo "== v7 V7-08: git global options must not hide the commit subcommand =="
mkdir -p "$SCRATCH/pbmain" && ( cd "$SCRATCH/pbmain" && git init -q -b main . \
  && printf 'x\n' > f.txt && git add f.txt \
  && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
mkdir -p "$SCRATCH/pbfeat" && ( cd "$SCRATCH/pbfeat" && git init -q -b feat/x . \
  && printf 'x\n' > f.txt && git add f.txt \
  && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
PB_MAIN="CLAUDE_PROJECT_DIR=$SCRATCH/pbmain"
PB_FEAT="CLAUDE_PROJECT_DIR=$SCRATCH/pbfeat"
t_ask V708a block-destructive.sh "$(cmd 'git commit -am wip')" "$PB_MAIN"
t_ask V708b block-destructive.sh "$(cmd 'git -C . commit -am wip')" "$PB_MAIN"
t_ask V708c block-destructive.sh "$(cmd '/usr/bin/git commit -am wip')" "$PB_MAIN"
t_ask V708d block-destructive.sh "$(cmd 'git -c user.name=x commit -am wip')" "$PB_MAIN"
t_ask V708e block-destructive.sh "$(cmd 'git --no-pager commit -am wip')" "$PB_MAIN"
t_ask V708f block-destructive.sh "$(cmd 'git --git-dir=.git --work-tree=. commit -am wip')" "$PB_MAIN"
t_ask V708g block-destructive.sh "$(cmd 'env git commit -am wip')" "$PB_MAIN"
# Feature branches stay silent, and a word that merely starts with "commit" is not one.
t_noask V708h block-destructive.sh "$(cmd 'git commit -am wip')" "$PB_FEAT"
t_noask V708i block-destructive.sh "$(cmd 'git -C . commit -am wip')" "$PB_FEAT"
t_noask V708j block-destructive.sh "$(cmd 'git commitizen --help')" "$PB_MAIN"

echo "== v7 V7-09: dependency patterns anchored at a command position =="
# `cargo install` previously matched the GO pattern via the trailing "go" of
# car-go — right answer, wrong reason. Anchoring fixes the accident; the global
# tool installs are then asked for DELIBERATELY (plan §10 decision 4).
t_ask V709a block-destructive.sh "$(cmd 'cargo install ripgrep')"
t_ask V709b block-destructive.sh "$(cmd 'pipx install black')"
t_ask V709c block-destructive.sh "$(cmd 'uv tool install ruff')"
t_ask V709d block-destructive.sh "$(cmd 'gem install bundler')"
t_ask V709e block-destructive.sh "$(cmd 'go install ./cmd/x')"
# Words that merely CONTAIN a package-manager name must not match.
t_noask V709f block-destructive.sh "$(cmd 'mongo install-check --dry-run')"
t_noask V709g block-destructive.sh "$(cmd 'django-admin get sitemap')"
t_noask V709h block-destructive.sh "$(cmd './cargo-helper add serde')"

echo "== v7 V7-02: option-first dependency installs (README claims these ask) =="
t_ask V702a block-destructive.sh "$(cmd 'pip install -q requests')"
t_ask V702b block-destructive.sh "$(cmd 'pip install -c constraints.txt requests')"
t_ask V702c block-destructive.sh "$(cmd 'pip install --constraint constraints.txt requests')"
t_ask V702d block-destructive.sh "$(cmd 'npm --prefix /tmp install lodash')"
t_ask V702e block-destructive.sh "$(cmd 'pip install --quiet --no-cache-dir flask')"
t_ask V702k block-destructive.sh "$(cmd 'npm install ./local-package')"
t_ask V702l block-destructive.sh "$(cmd 'npm install ../shared/pkg')"
# Restores are NOT a new supply-chain decision and must stay silent — including
# a restore redirected by an option VALUE that happens to be a local path.
t_ask   V702m block-destructive.sh "$(cmd 'npm install --prefix ./out')"   # v9: any npm install form asks
t_noask V702f block-destructive.sh "$(cmd 'npm ci')"                       # npm ci = the only allowed npm restore
t_ask   V702g block-destructive.sh "$(cmd 'npm install')"                  # v9: bare install can rewrite the lockfile → ask
t_noask V702h block-destructive.sh "$(cmd 'pip install -r requirements.txt')"
t_noask V702i block-destructive.sh "$(cmd 'pip install -q -r requirements.txt')"
t_noask V702j block-destructive.sh "$(cmd 'uv sync')"

echo "== v9 A4: CRITICAL hooks fail CLOSED (ask) when they cannot inspect input =="
# block-destructive and protect-files are critical guardrails: given unparseable
# input they must ASK (a static, dependency-free permission prompt), never
# silently allow. Advisory hooks (scan-secrets, below) still fail OPEN. FC1/FC2:
# exit 0 with a jq-valid ask. FC3: the fail-closed decision is logged and the
# payload never leaks to stdout or the log.
mkdir -p "$SCRATCH/logs"; : > "$SCRATCH/logs/hooks.log"
mkdir -p "$SCRATCH/.claude/logs"; : > "$SCRATCH/.claude/logs/hooks.log"
t_ask FC1 block-destructive.sh 'THIS IS NOT JSON'
t_ask FC2 protect-files.sh 'THIS IS NOT JSON'
: > "$SCRATCH/.claude/logs/hooks.log"
fcout=$(printf '%s' 'SENTINEL_NOT_JSON_zzz' | bash "$HOOKS/block-destructive.sh" 2>/dev/null)
if printf '%s' "$fcout" | grep -q '"permissionDecision":"ask"' \
   && grep -q 'fail-closed' "$SCRATCH/.claude/logs/hooks.log" 2>/dev/null \
   && ! grep -q 'SENTINEL_NOT_JSON_zzz' "$SCRATCH/.claude/logs/hooks.log" 2>/dev/null \
   && ! printf '%s' "$fcout" | grep -q 'SENTINEL_NOT_JSON_zzz'; then
  PASS=$((PASS+1)); printf 'PASS %-6s fail-closed logged, payload not leaked\n' FC3
else
  FAIL=$((FAIL+1)); printf 'FAIL %-6s expected a fail-closed ask+log with no payload leak\n' FC3
fi
# FO3: valid JSON must NOT trigger a fail-open (the empty-object smoke input
# used by install.sh must stay silent).
: > "$SCRATCH/.claude/logs/hooks.log"
got=0; printf '%s' '{"tool_input":{}}' | bash "$HOOKS/block-destructive.sh" >/dev/null 2>&1 || got=$?
if [[ "$got" == 0 ]] && ! grep -q 'FAIL_OPEN' "$SCRATCH/.claude/logs/hooks.log" 2>/dev/null; then
  PASS=$((PASS+1)); printf 'PASS %-6s valid empty JSON does not trip fail-open\n' FO3
else
  FAIL=$((FAIL+1)); printf 'FAIL %-6s valid JSON should not log FAIL_OPEN (exit %s)\n' FO3 "$got"
fi
# FO4/FO5: scan-secrets reads several fields at once and used a raw `jq … ||
# true`, so malformed input failed open SILENTLY (no FAIL_OPEN row). It must now
# record the bypass like the other hooks, and stay silent on valid JSON.
: > "$SCRATCH/.claude/logs/hooks.log"
got=0; printf '%s' 'THIS IS NOT JSON' | bash "$HOOKS/scan-secrets.sh" >/dev/null 2>&1 || got=$?
if [[ "$got" == 0 ]] && grep -q 'FAIL_OPEN' "$SCRATCH/.claude/logs/hooks.log" 2>/dev/null \
   && ! grep -qi 'THIS IS NOT JSON' "$SCRATCH/.claude/logs/hooks.log" 2>/dev/null; then
  PASS=$((PASS+1)); printf 'PASS %-6s scan-secrets malformed input fails open + logged\n' FO4
else
  FAIL=$((FAIL+1)); printf 'FAIL %-6s scan-secrets should log FAIL_OPEN on malformed input (exit %s)\n' FO4 "$got"
fi
: > "$SCRATCH/.claude/logs/hooks.log"
got=0; printf '%s' '{"tool_input":{"content":"ok"}}' | bash "$HOOKS/scan-secrets.sh" >/dev/null 2>&1 || got=$?
if [[ "$got" == 0 ]] && ! grep -q 'FAIL_OPEN' "$SCRATCH/.claude/logs/hooks.log" 2>/dev/null; then
  PASS=$((PASS+1)); printf 'PASS %-6s scan-secrets valid JSON does not trip fail-open\n' FO5
else
  FAIL=$((FAIL+1)); printf 'FAIL %-6s scan-secrets valid JSON should not log FAIL_OPEN (exit %s)\n' FO5 "$got"
fi

echo ""
echo "RESULT: pass=$PASS fail=$FAIL"
[[ "$FAIL" == 0 ]] || exit 1
