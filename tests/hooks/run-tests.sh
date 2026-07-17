#!/usr/bin/env bash
# Table-driven regression suite for the enforcement hooks.
# Portable: needs bash + jq + git only (no bats). Run: bash tests/hooks/run-tests.sh
# Expectations encode CORRECT behavior; a failing case is a live defect.
# Secret-shaped fixtures are CONSTRUCTED at runtime so this file never contains
# a contiguous secret pattern (keeps scanners, including our own hook, quiet).

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS="$REPO/.claude/hooks"
SCRATCH="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$SCRATCH"
PASS=0; FAIL=0

AWS_FAKE="AKIA""ABCDEFGHIJKLMNOP"
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

t_ask() { # exit 0 AND stdout carries a permissionDecision ask
  local id="$1" hook="$2" payload="$3" got=0
  printf '%s' "$payload" | bash "$HOOKS/$hook" >"$SCRATCH/out.txt" 2>/dev/null || got=$?
  if [[ "$got" == "0" ]] && grep -qF '"permissionDecision":"ask"' "$SCRATCH/out.txt"; then
    PASS=$((PASS+1)); printf 'PASS %-6s ask-json emitted\n' "$id"
  else
    FAIL=$((FAIL+1)); printf 'FAIL %-6s want exit 0 + ask JSON, got exit %s stdout: %s\n' "$id" "$got" "$(head -c 80 "$SCRATCH/out.txt")"
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

echo "== protect-files =="
t PF1 2 protect-files.sh "$(fp '/repo/.env')"
t PF2 0 protect-files.sh "$(fp '/repo/.env.example')"
t PF4 2 protect-files.sh "$(fp '/repo/package-lock.json')"
t PF5 0 protect-files.sh "$(fp '/repo/src/main.py')"
t PF6 0 protect-files.sh "$(fp '/c/repo/docs/แผนงาน.md')"
t PF7 2 protect-files.sh "$(fp '/repo/migrations/0001_init.sql')"
t PF8 2 protect-files.sh "$(fp '/repo/my docs/.env.local')"
t PF9 0 protect-files.sh 'not json'
echo "== protect-files: NotebookEdit coverage =="
t NB1 2 protect-files.sh '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/repo/migrations/x.ipynb"}}'

echo "== scan-secrets =="
t SS1 2 scan-secrets.sh "$(wc_ "key = \"$AWS_FAKE\"")"
t SS2 0 scan-secrets.sh "$(wc_ "key = \"${AWS_FAKE}\"  # EXAMPLE fixture")"
t SS3 2 scan-secrets.sh "$(wc_ "$PEM_FAKE")"
t SS4 2 scan-secrets.sh "$(wc_ "$(printf 'a = "%s"\nb = "%s"' "$AWS_FAKE" "$GH_FAKE")")"
t SS5 2 scan-secrets.sh "$(wc_ "$PW_KEY = \"abcdefghijklmnopqrstuvwx\"")"
t SS6 0 scan-secrets.sh "$(wc_ 'const K = 42')"
t SS7 2 scan-secrets.sh "$(printf '{"tool_name":"Edit","tool_input":{"file_path":"/x","new_string":%s}}' "$(printf 'token = "%s"' "$GH_FAKE" | jq -Rs .)")"
t SS8 0 scan-secrets.sh 'not json'
echo "== scan-secrets: NotebookEdit coverage =="
t NB2 2 scan-secrets.sh "$(printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/x.ipynb","new_source":%s}}' "$(printf 'k = "%s"' "$AWS_FAKE" | jq -Rs .)")"

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

echo "== install.sh: counter must survive set -e =="
if grep -q '((FAIL++))' "$HOOKS/install.sh"; then FAIL=$((FAIL+1)); echo "FAIL INST1  install.sh still uses ((FAIL++)) — dies under set -e on first failing test"; else PASS=$((PASS+1)); echo "PASS INST1  no set -e-fatal increments"; fi

echo "== settings.json: matcher covers current editing tools =="
if grep -q 'MultiEdit' "$REPO/.claude/settings.json"; then FAIL=$((FAIL+1)); echo "FAIL SET1   matcher still lists MultiEdit (tool removed in current Claude Code)"; else PASS=$((PASS+1)); echo "PASS SET1   no stale MultiEdit matcher"; fi
if grep -q 'NotebookEdit' "$REPO/.claude/settings.json"; then PASS=$((PASS+1)); echo "PASS SET2   NotebookEdit matched"; else FAIL=$((FAIL+1)); echo "FAIL SET2   NotebookEdit not matched — notebook edits bypass file hooks"; fi

echo ""
echo "RESULT: pass=$PASS fail=$FAIL"
[[ "$FAIL" == 0 ]] || exit 1
