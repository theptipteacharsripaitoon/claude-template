#!/usr/bin/env bash
# Table-driven tests for claude-init.sh: success, failure, dry-run, profiles,
# version stamp/manifest, and drift status. Portable: bash + jq + git only.
# Run: bash tests/installer/run-tests.sh
#
# shellcheck disable=SC2015
# The `<check> && ok … || bad …` table idiom is used file-wide. SC2015 warns
# that `bad` would also run if `ok` failed — here `ok` is a printf+counter that
# cannot fail, so the idiom is exact and keeps each case on one line.

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf 'PASS %-8s %s\n' "$1" "$2"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %-8s %s\n' "$1" "$2"; }

# Run claude-init in a THROWAWAY bash so its success-path `cd` and sourced
# function definitions never touch this test shell.
ci() { # ci <projects-dir> <template-dir> <args...>
  local pd="$1" td="$2"; shift 2
  local q=""
  local a
  for a in "$@"; do q+=" $(printf '%q' "$a")"; done
  bash -c "source '$REPO/claude-init.sh' && CLAUDE_PROJECTS_DIR='$pd' CLAUDE_TEMPLATE_DIR='$td' claude-init$q"
}

TPL="$REPO"   # the real template checkout is the fixture

echo "== success path =="
PD="$SCRATCH/p1"
if out=$(ci "$PD" "$TPL" proj1 2>&1); then ok S1 "exit 0"; else bad S1 "exit $? :: $(tail -1 <<<"$out")"; fi
[[ -f "$PD/proj1/CLAUDE.md" ]]                       && ok S2 "CLAUDE.md copied"        || bad S2 "CLAUDE.md missing"
[[ -d "$PD/proj1/.claude/hooks" ]]                   && ok S3 "hooks copied"            || bad S3 "hooks missing"
[[ -d "$PD/proj1/.claude/skills" ]]                  && ok S4 "skills copied"           || bad S4 "skills missing"
[[ ! -d "$PD/proj1/.claude/worktrees" ]]             && ok S5 "no worktrees leaked"     || bad S5 "worktrees leaked"
[[ ! -d "$PD/proj1/.claude/logs" ]]                  && ok S6 "no logs leaked"          || bad S6 "logs leaked"
[[ -f "$PD/proj1/.claude/.template-version" ]]       && ok S7 "version stamp written"   || bad S7 "no version stamp"
[[ -s "$PD/proj1/.claude/.template-manifest" ]]      && ok S8 "manifest written"        || bad S8 "no manifest"
grep -q "profile=standard" "$PD/proj1/.claude/.template-version" && ok S9 "profile recorded" || bad S9 "profile not recorded"
# Manifest hashes must verify against the generated tree.
if (cd "$PD/proj1" && sha256sum --check --quiet .claude/.template-manifest 2>/dev/null); then
  ok S10 "manifest hashes verify"
else
  bad S10 "manifest hashes do not verify"
fi

echo "== failure paths =="
if ci "$PD" "$TPL" proj1 >/dev/null 2>&1; then bad F1 "existing dest accepted"; else ok F1 "existing dest refused"; fi
if ci "$PD" "$TPL" "../escape" >/dev/null 2>&1; then bad F2 "path escape accepted"; else ok F2 "path escape refused"; fi
if ci "$PD" "$TPL" "-flag" >/dev/null 2>&1; then bad F3 "leading dash accepted"; else ok F3 "leading dash refused"; fi
if ci "$PD" "$TPL" --profile bogus x >/dev/null 2>&1; then bad F4 "bogus profile accepted"; else ok F4 "bogus profile refused"; fi
[[ ! -e "$PD/x" ]] && ok F5 "failed run left nothing" || bad F5 "failed run left $PD/x"
# Incomplete template: missing settings.json must fail up front, create nothing.
BROKEN="$SCRATCH/broken-tpl"; mkdir -p "$BROKEN/.claude/hooks"
cp "$TPL/CLAUDE.md" "$TPL/.gitignore" "$TPL/.gitattributes" "$BROKEN/"
cp "$TPL/.claude/hooks/install.sh" "$BROKEN/.claude/hooks/"
if ci "$PD" "$BROKEN" p2 >/dev/null 2>&1; then bad F6 "incomplete template accepted"; else ok F6 "incomplete template refused"; fi
# Unknown .claude entry: must fail loudly, not skip silently (v7 allowlist rule).
UNK="$SCRATCH/unk-tpl"; cp -r "$TPL/CLAUDE.md" "$TPL/.gitignore" "$TPL/.gitattributes" "$UNK" 2>/dev/null
mkdir -p "$UNK"; cp "$TPL/CLAUDE.md" "$TPL/.gitignore" "$TPL/.gitattributes" "$UNK/"
mkdir -p "$UNK/.claude"
cp -r "$TPL/.claude/hooks" "$UNK/.claude/"; cp -r "$TPL/.claude/skills" "$UNK/.claude/"
cp "$TPL/.claude/settings.json" "$UNK/.claude/"; cp "$TPL/.claude/ENFORCEMENT.md" "$UNK/.claude/"
mkdir -p "$UNK/.claude/future-feature"
if out=$(ci "$PD" "$UNK" p3 2>&1); then
  bad F7 "unknown .claude entry accepted"
else
  grep -q "future-feature" <<<"$out" && ok F7 "unknown entry refused and named" || bad F7 "refused but did not name the entry"
fi

echo "== dry run =="
PD2="$SCRATCH/p2"
if out=$(ci "$PD2" "$TPL" --dry-run proj-dry 2>&1); then ok D1 "exit 0"; else bad D1 "exit $?"; fi
[[ ! -e "$PD2" ]] && ok D2 "wrote nothing (dest root not even created)" || bad D2 "dry run created $PD2"
grep -q "DRY RUN" <<<"$out"        && ok D3 "labelled as dry run"       || bad D3 "no DRY RUN label"
grep -q "Profile:       standard" <<<"$out" && ok D4 "profile reported" || bad D4 "profile not reported"
grep -q ".claude/hooks" <<<"$out"  && ok D5 "copy list reported"        || bad D5 "no copy list"
out=$(ci "$PD2" "$TPL" --dry-run --profile minimal proj-dry 2>&1)
grep -q "SAFETY REDUCED" <<<"$out" && ok D6 "minimal names its safety reduction" || bad D6 "minimal silent about safety"

echo "== profiles =="
PD3="$SCRATCH/p3"
ci "$PD3" "$TPL" --profile minimal m1 >/dev/null 2>&1
N=$(jq '[.hooks.PreToolUse[] | select(.matcher=="Edit|Write|NotebookEdit") | .hooks[]] | length' "$PD3/m1/.claude/settings.json")
[[ "$N" == "1" ]] && ok P1 "minimal: file hooks reduced to protect-files" || bad P1 "minimal: file hooks = $N"
jq -e '.hooks.Stop' "$PD3/m1/.claude/settings.json" >/dev/null 2>&1 && bad P2 "minimal: Stop still present" || ok P2 "minimal: Stop removed"
jq -e '.hooks.PreToolUse[] | select(.matcher=="Bash")' "$PD3/m1/.claude/settings.json" >/dev/null && ok P3 "minimal: block-destructive kept" || bad P3 "minimal: block-destructive lost"

ci "$PD3" "$TPL" --profile strict s1 >/dev/null 2>&1
[[ "$(jq -r '.env.CLAUDE_VERIFY_BLOCK' "$PD3/s1/.claude/settings.json")" == "1" ]] && ok P4 "strict: Stop blocking env set" || bad P4 "strict: env missing"
N=$(jq '[.hooks.PreToolUse[] | select(.matcher=="Edit|Write|NotebookEdit") | .hooks[]] | length' "$PD3/s1/.claude/settings.json")
[[ "$N" == "3" ]] && ok P5 "strict: all file hooks kept" || bad P5 "strict: file hooks = $N"

ci "$PD3" "$TPL" --profile security-sensitive ss1 >/dev/null 2>&1
[[ "$(jq -r '.env.CLAUDE_DIFF_BLOCK_LINES' "$PD3/ss1/.claude/settings.json")" == "500" ]] && ok P6 "security-sensitive: diff block tightened" || bad P6 "security-sensitive: diff env missing"

ci "$PD3" "$TPL" --profile team t1 >/dev/null 2>&1
grep -q "disable-model-invocation: true" "$PD3/t1/.claude/skills/repository-cleanup/SKILL.md" \
  && ok P7 "team: repository-cleanup manual-only" || bad P7 "team: repository-cleanup not flipped"
grep -q "disable-model-invocation: true" "$PD3/t1/.claude/skills/release-readiness/SKILL.md" \
  && ok P8 "team: release-readiness manual-only" || bad P8 "team: release-readiness not flipped"
grep -q "disable-model-invocation" "$PD3/t1/.claude/skills/airflow/SKILL.md" \
  && bad P9 "team: unrelated skill flipped" || ok P9 "team: unrelated skills untouched"
[[ ! -f "$TPL/.claude/skills/repository-cleanup/SKILL.md.bak" ]] \
  && ok P10 "team: template source untouched" || bad P10 "team: template source modified"

echo "== drift status =="
ST="$PD3/s1"
if (cd "$ST" && source "$REPO/claude-init.sh" && claude-template-status) | grep -q "locally-modified=0"; then
  ok T1 "fresh project reports zero drift"
else
  bad T1 "fresh project reports drift"
fi
printf '\n# local tweak\n' >> "$ST/CLAUDE.md"
if (cd "$ST" && source "$REPO/claude-init.sh" && claude-template-status) | grep -q "LOCALLY MODIFIED   CLAUDE.md"; then
  ok T2 "local modification detected and named"
else
  bad T2 "modification not detected"
fi
rm "$ST/.claude/ENFORCEMENT.md"
if (cd "$ST" && source "$REPO/claude-init.sh" && claude-template-status) | grep -q "MISSING            .claude/ENFORCEMENT.md"; then
  ok T3 "missing managed file detected"
else
  bad T3 "missing file not detected"
fi
if (cd "$SCRATCH" && source "$REPO/claude-init.sh" && claude-template-status) >/dev/null 2>&1; then
  bad T4 "non-project dir accepted"
else
  ok T4 "non-project dir refused"
fi

echo ""
echo "RESULT: pass=$PASS fail=$FAIL"
[[ "$FAIL" == 0 ]] || exit 1
