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

echo "== failure injection (post-first-stage stages must fail closed) =="
# Each FI case shadows one binary invoked in the post-staging phase (profile
# transform / version stamp / manifest generation / final publish). The
# bootstrap MUST return non-zero, publish nothing, and print no success line.
# Shims live in $SCRATCH so they never leak to the harness's own PATH.

# ci_shim <projects-dir> <template-dir> <shim-dir> <args...>
# Runs claude-init in a throwaway bash with the shim directory PREPENDED to
# PATH in the environment (so binaries invoked from the sourced function
# resolve to the shim first). The env-form is required: inline `PATH=x source`
# only sets PATH for the source BUILTIN itself; later external command
# lookups from inside the function would ignore it.
ci_shim() {
  local pd="$1" td="$2" shim="$3"; shift 3
  local q="" a
  for a in "$@"; do q+=" $(printf '%q' "$a")"; done
  env "PATH=$shim:$PATH" bash -c "source '$REPO/claude-init.sh' && CLAUDE_PROJECTS_DIR='$pd' CLAUDE_TEMPLATE_DIR='$td' claude-init$q"
}

# make_shim <cmd> <fail-substring>  →  prints shim dir on stdout
# Empty fail-substring = fail every invocation. Non-empty = fail only when
# joined argv contains the substring; pass through to real binary otherwise.
make_shim() {
  local cmd="$1" match="$2"
  local dir; dir=$(mktemp -d "$SCRATCH/shim-${cmd}-XXXX")
  local real; real="$(command -v "$cmd")"
  {
    printf '#!/usr/bin/env bash\n'
    if [[ -n "$match" ]]; then
      # These printf format strings are the SHIM's source, emitted literally —
      # $args/$@ must NOT expand here (they expand when the shim runs). SC2016.
      # shellcheck disable=SC2016
      printf 'args="$*"\n'
      # shellcheck disable=SC2016
      printf 'case "$args" in *%s*) exit 77 ;; esac\n' "$match"
      printf 'exec %q "$@"\n' "$real"
    else
      printf 'exit 77\n'
    fi
  } > "$dir/$cmd"
  chmod +x "$dir/$cmd"
  echo "$dir"
}

# assert_failure_closed <label> <projects-dir> <output-str>
# Fails the bootstrap must have: exit != 0, no destination dir, no success line.
assert_failure_closed() {
  local label="$1" pd="$2" out="$3" name="$4"
  local ok_dest=0 ok_msg=0
  # (Caller already invoked ci_shim and asserted its non-zero exit; here we
  # only assert on the published-state outputs it produced.)
  # Ensure dest not published
  [[ ! -e "$pd/$name" ]] && ok_dest=1
  # Success line must not have been printed
  if ! grep -qE "^✅ Project '$name' bootstrapped" <<<"$out"; then ok_msg=1; fi
  if (( ok_dest == 1 && ok_msg == 1 )); then
    ok "$label" "failed closed: no dest, no success line"
  else
    local why=""
    (( ok_dest == 0 )) && why+="dest exists; "
    (( ok_msg == 0 ))  && why+="success line printed; "
    bad "$label" "${why%; }"
  fi
}

PDI="$SCRATCH/pinj"

# FI1 — strict-profile jq failure (P1 external review reproduction).
SHIM=$(make_shim jq "CLAUDE_VERIFY_BLOCK")
out=$(ci_shim "$PDI" "$TPL" "$SHIM" --profile strict fi1 2>&1); rc=$?
if (( rc != 0 )); then
  assert_failure_closed FI1 "$PDI" "$out" fi1
else
  bad FI1 "expected non-zero exit for strict-jq failure; got 0"
fi

# FI2 — security-sensitive-profile jq failure.
SHIM=$(make_shim jq "CLAUDE_DIFF_BLOCK_LINES")
out=$(ci_shim "$PDI" "$TPL" "$SHIM" --profile security-sensitive fi2 2>&1); rc=$?
if (( rc != 0 )); then
  assert_failure_closed FI2 "$PDI" "$out" fi2
else
  bad FI2 "expected non-zero exit for security-sensitive jq failure; got 0"
fi

# FI3 — minimal-profile jq failure.
SHIM=$(make_shim jq "protect-files")
out=$(ci_shim "$PDI" "$TPL" "$SHIM" --profile minimal fi3 2>&1); rc=$?
if (( rc != 0 )); then
  assert_failure_closed FI3 "$PDI" "$out" fi3
else
  bad FI3 "expected non-zero exit for minimal jq failure; got 0"
fi

# FI4 — team-profile sed failure (only path where sed is called in phase 2).
SHIM=$(make_shim sed "disable-model-invocation")
out=$(ci_shim "$PDI" "$TPL" "$SHIM" --profile team fi4 2>&1); rc=$?
if (( rc != 0 )); then
  assert_failure_closed FI4 "$PDI" "$out" fi4
else
  bad FI4 "expected non-zero exit for team sed failure; got 0"
fi

# FI5 — manifest sha256sum failure (P1 external review reproduction).
SHIM=$(make_shim sha256sum "")   # sha256sum is only used in phase 2 manifest gen
out=$(ci_shim "$PDI" "$TPL" "$SHIM" fi5 2>&1); rc=$?
if (( rc != 0 )); then
  assert_failure_closed FI5 "$PDI" "$out" fi5
else
  bad FI5 "expected non-zero exit for manifest sha256sum failure; got 0"
fi

# FI6 — manifest find failure (find is used with -type f for the manifest).
SHIM=$(make_shim find "-type f")
out=$(ci_shim "$PDI" "$TPL" "$SHIM" fi6 2>&1); rc=$?
if (( rc != 0 )); then
  assert_failure_closed FI6 "$PDI" "$out" fi6
else
  bad FI6 "expected non-zero exit for manifest find failure; got 0"
fi

# FI7 — final publish mv failure. mv is used for two purposes: profile
# transforms (settings.json.new -> settings.json) and the FINAL publish
# (tmp -> dest). The shim exits 77 only when neither .new nor settings.json
# appears in the argv — i.e., the final publish.
SHIM=$(mktemp -d "$SCRATCH/shim-mv-XXXX")
REAL_MV="$(command -v mv)"
{
  printf '#!/usr/bin/env bash\n'
  # Shim source emitted literally — $args/$@ expand when the shim RUNS. SC2016.
  # shellcheck disable=SC2016
  printf 'args="$*"\n'
  # shellcheck disable=SC2016
  printf 'case "$args" in *.new*|*settings.json*) exec %q "$@" ;; esac\n' "$REAL_MV"
  printf 'exit 77\n'
} > "$SHIM/mv"
chmod +x "$SHIM/mv"
out=$(ci_shim "$PDI" "$TPL" "$SHIM" fi7 2>&1); rc=$?
if (( rc != 0 )); then
  assert_failure_closed FI7 "$PDI" "$out" fi7
else
  bad FI7 "expected non-zero exit for final mv failure; got 0"
fi

# FI8 — drift report must NOT validate a manifest with blank hashes
# (compounding harm: sha256sum broken later gives all "" == "" comparisons).
# Set up a valid manifest-generated project, then poison the manifest to
# blank-hash rows and confirm claude-template-status flags it, not silently
# reports "unchanged".
PDG="$SCRATCH/pfg"
ci "$PDG" "$TPL" fi8 >/dev/null 2>&1
if [[ -f "$PDG/fi8/.claude/.template-manifest" ]]; then
  # Blank every hash on the left side of the two-space separator.
  # Use awk (not sed) to be portable across BSD/GNU sed on Windows Git Bash.
  awk 'BEGIN{FS="  "; OFS="  "} { $1=""; print }' \
    "$PDG/fi8/.claude/.template-manifest" > "$PDG/fi8/.claude/.template-manifest.new" \
    && mv "$PDG/fi8/.claude/.template-manifest.new" "$PDG/fi8/.claude/.template-manifest"
  status_out=$(cd "$PDG/fi8" && source "$REPO/claude-init.sh" && claude-template-status 2>&1)
  # Success = the drift report REFUSES to validate: it should not report
  # "unchanged=53" (or any positive unchanged count) for a poisoned manifest.
  if grep -qE 'unchanged=[1-9]' <<<"$status_out" && ! grep -q 'blank\|invalid\|poison' <<<"$status_out"; then
    bad FI8 "drift report validates blank-hash manifest: $(head -c 200 <<<"$status_out" | tr '\n' ' ')"
  else
    ok FI8 "drift report refuses to validate blank-hash manifest"
  fi
else
  bad FI8 "prep failed: no manifest to poison"
fi

# FI9 — version-stamp `date` failure must fail closed. Before the fix,
# `generated_utc=$(date …)` sat inside an `echo` whose enclosing block still
# exited 0, so a broken `date` published a project with an EMPTY timestamp.
SHIM=$(make_shim date "T%H:%M:%SZ")
out=$(ci_shim "$PDI" "$TPL" "$SHIM" fi9 2>&1); rc=$?
if (( rc != 0 )); then
  assert_failure_closed FI9 "$PDI" "$out" fi9
else
  bad FI9 "expected non-zero exit for version-stamp date failure; got 0"
fi

# FI10 — partial manifest via `find`: emit a SUBSET then exit nonzero. The
# manifest enumeration ran behind process substitution, so a truncated list that
# exited nonzero was invisible; the short manifest verified against itself and
# published. Only the manifest call (`… -type f`) is hijacked.
SHIM=$(mktemp -d "$SCRATCH/shim-findp-XXXX")
REAL_FIND="$(command -v find)"
{
  printf '#!/usr/bin/env bash\n'
  # Shim source emitted literally — $*/$@ expand when the shim RUNS. SC2016.
  # shellcheck disable=SC2016
  printf 'case "$*" in *"-type f"*) echo CLAUDE.md; exit 1 ;; esac\n'
  printf 'exec %q "$@"\n' "$REAL_FIND"
} > "$SHIM/find"
chmod +x "$SHIM/find"
out=$(ci_shim "$PDI" "$TPL" "$SHIM" fi10 2>&1); rc=$?
if (( rc != 0 )); then
  assert_failure_closed FI10 "$PDI" "$out" fi10
else
  bad FI10 "expected non-zero exit for partial-find manifest; got 0"
fi

# FI11 — partial manifest via `sort`: emit a subset then exit nonzero. Same
# process-substitution blind spot on the consuming side of the pipe.
SHIM=$(mktemp -d "$SCRATCH/shim-sortp-XXXX")
{
  printf '#!/usr/bin/env bash\n'
  printf 'head -n1; exit 1\n'
} > "$SHIM/sort"
chmod +x "$SHIM/sort"
out=$(ci_shim "$PDI" "$TPL" "$SHIM" fi11 2>&1); rc=$?
if (( rc != 0 )); then
  assert_failure_closed FI11 "$PDI" "$out" fi11
else
  bad FI11 "expected non-zero exit for partial-sort manifest; got 0"
fi

# FI12 — partial manifest that even exits 0: a `find` that drops files but
# succeeds must still fail closed, because the manifest omits required anchors
# (here .claude/settings.json). Guards the exit-0 truncation the status checks
# above cannot see.
SHIM=$(mktemp -d "$SCRATCH/shim-find0-XXXX")
REAL_FIND="$(command -v find)"
{
  printf '#!/usr/bin/env bash\n'
  # shellcheck disable=SC2016
  printf 'case "$*" in *"-type f"*) echo CLAUDE.md; exit 0 ;; esac\n'
  printf 'exec %q "$@"\n' "$REAL_FIND"
} > "$SHIM/find"
chmod +x "$SHIM/find"
out=$(ci_shim "$PDI" "$TPL" "$SHIM" fi12 2>&1); rc=$?
if (( rc != 0 )); then
  assert_failure_closed FI12 "$PDI" "$out" fi12
else
  bad FI12 "expected non-zero exit for anchor-incomplete manifest; got 0"
fi

# --- B3/B4: no-clobber, ownership-aware publish ------------------------------
# A destination that appears AFTER the up-front existence check (a concurrent
# actor) must never cause a nested publish or deletion of data we do not own.

# FI13 — concurrent DIRECTORY at dest, created during manifest generation
# (before the rename). Publish must refuse; the pre-existing dir must survive
# and must not contain our tree at its root.
SHIM=$(mktemp -d "$SCRATCH/shim-cdir-XXXX"); REAL_SHA="$(command -v sha256sum)"
{
  printf '#!/usr/bin/env bash\n'
  printf 'mkdir -p %q 2>/dev/null\n' "$PDI/fi13"
  printf 'exec %q "$@"\n' "$REAL_SHA"
} > "$SHIM/sha256sum"; chmod +x "$SHIM/sha256sum"
out=$(ci_shim "$PDI" "$TPL" "$SHIM" fi13 2>&1); rc=$?
if (( rc != 0 )) && [[ -d "$PDI/fi13" && ! -f "$PDI/fi13/CLAUDE.md" ]] \
   && ! grep -qE "^✅ Project 'fi13'" <<<"$out"; then
  ok FI13 "concurrent dir: refused, no nested publish, dir preserved"
else
  bad FI13 "concurrent dir mishandled (rc=$rc)"
fi

# FI14 — tight race: dest is created (as a dir) at the instant of the final
# rename, so mv nests our tree inside it. The post-publish root check must
# detect the nesting and back out ONLY our nested subdir.
SHIM=$(mktemp -d "$SCRATCH/shim-nest-XXXX"); REAL_MV="$(command -v mv)"
{
  printf '#!/usr/bin/env bash\n'
  # Shim source emitted literally; $*/$@ expand when the shim RUNS. SC2016.
  # shellcheck disable=SC2016
  printf 'case "$*" in *.new*|*settings.json*) exec %q "$@" ;; esac\n' "$REAL_MV"
  printf 'mkdir -p %q 2>/dev/null\n' "$PDI/fi14"
  printf 'exec %q "$@"\n' "$REAL_MV"
} > "$SHIM/mv"; chmod +x "$SHIM/mv"
out=$(ci_shim "$PDI" "$TPL" "$SHIM" fi14 2>&1); rc=$?
if (( rc != 0 )) && [[ ! -f "$PDI/fi14/CLAUDE.md" ]] \
   && ! grep -qE "^✅ Project 'fi14'" <<<"$out"; then
  ok FI14 "tight-race nest detected and backed out"
else
  bad FI14 "nested publish not detected (rc=$rc)"
fi

# FI15 — concurrent FILE at dest at rename time: mv fails. Cleanup must NOT
# delete the file (we do not own it) — the pre-fix cleanup rm -rf'd any $dest.
SHIM=$(mktemp -d "$SCRATCH/shim-cfile-XXXX"); REAL_MV="$(command -v mv)"
{
  printf '#!/usr/bin/env bash\n'
  # shellcheck disable=SC2016
  printf 'case "$*" in *.new*|*settings.json*) exec %q "$@" ;; esac\n' "$REAL_MV"
  printf 'touch %q 2>/dev/null\n' "$PDI/fi15"
  printf 'exec %q "$@"\n' "$REAL_MV"
} > "$SHIM/mv"; chmod +x "$SHIM/mv"
out=$(ci_shim "$PDI" "$TPL" "$SHIM" fi15 2>&1); rc=$?
if (( rc != 0 )) && [[ -f "$PDI/fi15" ]] \
   && ! grep -qE "^✅ Project 'fi15'" <<<"$out"; then
  ok FI15 "concurrent file preserved (not owned, not deleted)"
else
  bad FI15 "concurrent file mishandled (rc=$rc)"
fi

# FI16 — concurrent SYMLINK at dest (created before the rename). The pre-rename
# guard rejects a symlinked destination rather than following it into its target.
SHIM=$(mktemp -d "$SCRATCH/shim-clink-XXXX"); REAL_SHA="$(command -v sha256sum)"
mkdir -p "$SCRATCH/fi16-target"
{
  printf '#!/usr/bin/env bash\n'
  printf 'ln -s %q %q 2>/dev/null\n' "$SCRATCH/fi16-target" "$PDI/fi16"
  printf 'exec %q "$@"\n' "$REAL_SHA"
} > "$SHIM/sha256sum"; chmod +x "$SHIM/sha256sum"
out=$(ci_shim "$PDI" "$TPL" "$SHIM" fi16 2>&1); rc=$?
if (( rc != 0 )) && [[ -L "$PDI/fi16" && ! -f "$SCRATCH/fi16-target/CLAUDE.md" ]] \
   && ! grep -qE "^✅ Project 'fi16'" <<<"$out"; then
  ok FI16 "concurrent symlink refused, not followed"
else
  bad FI16 "concurrent symlink mishandled (rc=$rc)"
fi

echo ""
echo "RESULT: pass=$PASS fail=$FAIL"
[[ "$FAIL" == 0 ]] || exit 1
