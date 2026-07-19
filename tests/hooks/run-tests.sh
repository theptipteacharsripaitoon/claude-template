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
t_noask AL2 block-destructive.sh "$(cmd 'npm install')"
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
if [[ "$got" == 0 ]] && ! grep -q 'checks passed' "$SCRATCH/vd5.txt" && grep -qi 'no verification' "$SCRATCH/vd5.txt"; then PASS=$((PASS+1)); echo "PASS VD5    no checks discovered -> not reported as passed"; else FAIL=$((FAIL+1)); echo "FAIL VD5    want exit 0 + 'no verification' (not 'checks passed'); got exit $got"; fi
# VD6: blocking mode with a real PASSING checker must run it and exit 0.
# (Regression: bare ((RAN++)) under set -e aborted the hook before any check.)
mkdir -p "$SCRATCH/nodeok" && ( cd "$SCRATCH/nodeok" && git init -q . \
  && printf '{"name":"x","version":"1.0.0","scripts":{"test":"exit 0"}}\n' > package.json \
  && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'x=1\n' > a.py )
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "CLAUDE_PROJECT_DIR=$SCRATCH/nodeok" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd6.txt" || got=$?
if [[ "$got" == 0 ]] && grep -q 'check(s) passed' "$SCRATCH/vd6.txt"; then PASS=$((PASS+1)); echo "PASS VD6    blocking + passing checker -> ran, exit 0"; else FAIL=$((FAIL+1)); echo "FAIL VD6    want exit 0 + 'check(s) passed'; got exit $got: $(head -c 120 "$SCRATCH/vd6.txt" | tr -d '\n')"; fi
# VD7: blocking mode with a real FAILING checker must report it and exit 2.
mkdir -p "$SCRATCH/nodebad" && ( cd "$SCRATCH/nodebad" && git init -q . \
  && printf '{"name":"x","version":"1.0.0","scripts":{"test":"exit 1"}}\n' > package.json \
  && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'x=1\n' > a.py )
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "CLAUDE_PROJECT_DIR=$SCRATCH/nodebad" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd7.txt" || got=$?
if [[ "$got" == 2 ]] && grep -q 'Definition of Done unmet' "$SCRATCH/vd7.txt"; then PASS=$((PASS+1)); echo "PASS VD7    blocking + failing checker -> exit 2"; else FAIL=$((FAIL+1)); echo "FAIL VD7    want exit 2 + 'unmet'; got exit $got: $(head -c 120 "$SCRATCH/vd7.txt" | tr -d '\n')"; fi
# VD8: polyglot repo runs EVERY ecosystem (Node + Rust via a stub cargo on PATH).
mkdir -p "$SCRATCH/stubbin"
printf '#!/bin/sh\nexit 0\n' > "$SCRATCH/stubbin/cargo" && chmod +x "$SCRATCH/stubbin/cargo"
mkdir -p "$SCRATCH/polyglot" && ( cd "$SCRATCH/polyglot" && git init -q . \
  && printf '{"name":"x","version":"1.0.0","scripts":{"test":"exit 0"}}\n' > package.json \
  && printf '[package]\nname = "x"\nversion = "0.1.0"\n' > Cargo.toml \
  && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'x=1\n' > a.py )
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "PATH=$SCRATCH/stubbin:$PATH" "CLAUDE_PROJECT_DIR=$SCRATCH/polyglot" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd8.txt" || got=$?
if [[ "$got" == 0 ]] && grep -q 'All 3' "$SCRATCH/vd8.txt"; then PASS=$((PASS+1)); echo "PASS VD8    polyglot ran Node + both cargo checks (3 total)"; else FAIL=$((FAIL+1)); echo "FAIL VD8    want exit 0 + 'All 3'; got exit $got: $(head -c 120 "$SCRATCH/vd8.txt" | tr -d '\n')"; fi
# VD9: checker binary MISSING (bun.lockb selects bun, which is not installed):
# must honestly report nothing verified, not crash and not claim failure.
mkdir -p "$SCRATCH/nodebun" && ( cd "$SCRATCH/nodebun" && git init -q . \
  && printf '{"name":"x","version":"1.0.0","scripts":{"test":"exit 0"}}\n' > package.json \
  && : > bun.lockb \
  && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'x=1\n' > a.py )
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "CLAUDE_PROJECT_DIR=$SCRATCH/nodebun" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd9.txt" || got=$?
if [[ "$got" == 0 ]] && grep -qi 'no verification' "$SCRATCH/vd9.txt"; then PASS=$((PASS+1)); echo "PASS VD9    missing checker binary -> honest 'no verification', exit 0"; else FAIL=$((FAIL+1)); echo "FAIL VD9    want exit 0 + 'no verification'; got exit $got: $(head -c 120 "$SCRATCH/vd9.txt" | tr -d '\n')"; fi
# VD10: multiple failing checks are all counted.
mkdir -p "$SCRATCH/nodebad2" && ( cd "$SCRATCH/nodebad2" && git init -q . \
  && printf '{"name":"x","version":"1.0.0","scripts":{"lint":"exit 1","test":"exit 1"}}\n' > package.json \
  && git add -A && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'x=1\n' > a.py )
got=0; printf '%s' '{"hook_event_name":"Stop"}' | env "CLAUDE_PROJECT_DIR=$SCRATCH/nodebad2" CLAUDE_VERIFY_BLOCK=1 bash "$HOOKS/verify-done.sh" >/dev/null 2>"$SCRATCH/vd10.txt" || got=$?
if [[ "$got" == 2 ]] && grep -q '2 of 2' "$SCRATCH/vd10.txt"; then PASS=$((PASS+1)); echo "PASS VD10   both failing checks counted (2 of 2), exit 2"; else FAIL=$((FAIL+1)); echo "FAIL VD10   want exit 2 + '2 of 2'; got exit $got: $(head -c 120 "$SCRATCH/vd10.txt" | tr -d '\n')"; fi

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
t_noask AL12 block-destructive.sh "$(cmd 'npm install --legacy-peer-deps')"

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

echo ""
echo "RESULT: pass=$PASS fail=$FAIL"
[[ "$FAIL" == 0 ]] || exit 1
