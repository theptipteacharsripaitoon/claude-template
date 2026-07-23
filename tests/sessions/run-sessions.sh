#!/usr/bin/env bash
# Realistic-session evaluation (v7 plan §8; v8 assertions; v9 scorer contract):
# scenario repos, one real headless Claude Code session each, scored against
# declared expectations by score_session.py (unit-tested offline at
# test_score_session.py — no model calls there).
#
# v9 change — the driver now feeds the STRICTER scorer contract (review P1-5). A
# scenario PASSES iff every applicable gate holds:
#   * the Claude CLI exited 0                         (--claude-exit)
#   * every non-blank stream line was valid JSON AND a terminal `result` event
#     was present                                     (scorer reads the stream)
#   * the Stop hook replay produced a well-formed decision, not a crash
#                                                     (--stop-outcome-ok)
#   * every must_load skill loaded, no must_not_load skill loaded
#   * the permission tier was exercised: allow = ZERO asks and ZERO denies (a
#     clean run), ask = >=1 ask, ignore = don't-care          (expected_tier)
#   * exact changed-path allowlist: something changed AND nothing outside the
#     scenario's artifact pattern changed (no unrelated edits)
#                                        (--changed-path list vs allowed_paths)
#   * the semantic assertion on the produced tree passed
#
# Two determinism guards on top of the scorer:
#   * PRISTINE-RED: the semantic predicate must FAIL on the untouched seed, or
#     the scenario is vacuous (would pass without the model doing anything) and
#     is failed immediately.
#   * a bare `.` artifact pattern is rejected (it would match any path).
#
# Per scenario it still records sanitized telemetry only: skills loaded (names),
# hook events by tier (from the seeded repo's .claude/logs/hooks.log), asks/
# denials, the Stop end-state decision (verify-done replayed against the final
# tree — headless -p cannot surface the reminder itself), wall-clock, and the
# artifact-level outcome. Nothing from the transcript is stored except skill
# names and counts.
#
# TWO-TURN (s4/s5): the migration and prod-infra scenarios run plan-then-confirm
# to exercise the ASK tier — turn 1 in plan mode (the agent plans and makes NO
# edit; the artifact stays pristine-red after turn 1 or the scenario fails), turn
# 2 with edits accepted (the protected write proceeds and protect-files logs the
# ASK). A scenario opts into this shape by passing a 9th run_scenario argument
# (the confirm-prompt); single arg-8 scenarios stay one-turn. The shell
# orchestration is exercised offline by tests/sessions/test_driver_smoke.sh
# (a stubbed `claude` via CLAUDE_BIN — no model calls); the live model behavior
# is only proven by a real run (tests/EVIDENCE.md).
#
# Usage: bash tests/sessions/run-sessions.sh <out-dir> [only-scenario-id]
# Needs an authenticated Claude Code CLI + jq + python; LOCAL evaluation, not CI.
set -uo pipefail

OUT="${1:?usage: run-sessions.sh <out-dir> [only-id]}"
ONLY="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SEED="$REPO/tests/skills/routing/seed-repo.sh"
SCORER="$HERE/score_session.py"
mkdir -p "$OUT"

# Resolve the Claude CLI portably: `claude` on Linux/mac, `claude.cmd` under
# Windows Git bash (MSYS `command -v` resolves .exe but not .cmd, so a bare
# `claude` is invisible even though `claude.cmd` runs fine). CLAUDE_BIN may be
# pre-set in the environment — the offline stub smoke test injects a fake CLI
# this way — in which case its resolution is skipped.
CLAUDE_BIN="${CLAUDE_BIN:-}"
if [[ -z "$CLAUDE_BIN" ]]; then
  if command -v claude >/dev/null 2>&1; then CLAUDE_BIN=claude
  elif command -v claude.cmd >/dev/null 2>&1; then CLAUDE_BIN=claude.cmd
  else echo "need claude CLI" >&2; exit 1; fi
fi
command -v jq >/dev/null || { echo "need jq" >&2; exit 1; }
command -v python >/dev/null || command -v python3 >/dev/null || { echo "need python" >&2; exit 1; }
PY=$(command -v python || command -v python3)

SCENARIOS=0
SESSION_FAILS=0

# _run_turn <proj-dir> <permission-mode> <prompt> <out-stream>
# One headless Claude Code turn against <proj-dir>; the stream-json goes to
# <out-stream> and its stderr beside it. Returns the CLI's exit status. Used
# once for a one-turn scenario and twice (plan, then acceptEdits) for two-turn.
_run_turn() {
  local proj_dir="$1" mode="$2" turn_prompt="$3" out="$4"
  ( cd "$proj_dir" && "$CLAUDE_BIN" -p "$turn_prompt" \
      --output-format stream-json --verbose \
      --setting-sources project \
      --permission-mode "$mode" ) > "$out" 2>"$out.stderr"
}

# run_scenario <id> <seed-case> <artifact-pattern> <must_load_csv> \
#              <must_not_load_csv> <expected_tier> <semantic_cmd> <prompt> \
#              [confirm_prompt]
#   artifact-pattern  a SPECIFIC regex over changed paths that the scenario is
#                     allowed to touch — never `.`; a bare `.` is rejected.
#   must_load_csv     comma-separated skills that MUST load ("" = none required)
#   must_not_load     comma-separated skills that must NOT load ("" = none)
#   expected_tier     allow | ask | deny | ignore (see header)
#   semantic_cmd      shell snippet run inside $proj; exit 0 = artifact is
#                     semantically correct ("" = no semantic check → "na")
#   confirm_prompt    OPTIONAL 9th arg: when non-empty the scenario is TWO-TURN
#                     (prompt = plan turn in plan mode; confirm_prompt = confirm
#                     turn with edits accepted). Omit for a one-turn scenario.
run_scenario() {
  local id="$1" seedcase="$2" allow_pat="$3" must_load="$4" \
        must_not_load="$5" expected_tier="$6" semantic_cmd="$7" prompt="$8" \
        confirm_prompt="${9:-}"
  [[ -n "$ONLY" && "$ONLY" != "$id" ]] && return 0
  SCENARIOS=$((SCENARIOS+1))

  # Guard against the pre-v8 defect: a `.` pattern matches ANY change.
  if [[ "$allow_pat" == "." ]]; then
    echo "FAIL $id: artifact pattern '.' matches any path — use a specific pattern" >&2
    SESSION_FAILS=$((SESSION_FAILS+1)); return 1
  fi

  local tmp proj
  tmp=$(mktemp -d) || return 1
  proj="$tmp/repo"
  bash "$SEED" "$seedcase" "$proj" >/dev/null 2>&1 || { echo "seed failed: $id" >&2; rm -rf "$tmp"; SESSION_FAILS=$((SESSION_FAILS+1)); return 1; }
  ( cd "$proj" && git init -q . && git add -A >/dev/null 2>&1 \
      && git -c user.email=s@s -c user.name=s commit -qm seed >/dev/null ) || true

  # PRISTINE-RED: the semantic predicate must fail on the untouched seed, else
  # the scenario proves nothing (it would pass with the model doing nothing).
  if [[ -n "$semantic_cmd" ]]; then
    if ( cd "$proj" && eval "$semantic_cmd" ) >/dev/null 2>&1; then
      echo "FAIL $id: semantic predicate already passes on the pristine seed (vacuous)" >&2
      rm -rf "$tmp"; SESSION_FAILS=$((SESSION_FAILS+1)); return 1
    fi
  fi

  local start end wall stream rc
  stream="$tmp/stream.jsonl"
  start=$(date +%s)
  if [[ -n "$confirm_prompt" ]]; then
    # Two-turn plan-then-confirm (HIGH-risk domains: migrations, prod infra).
    local stream1="$tmp/stream1.jsonl" stream2="$tmp/stream2.jsonl" rc1 rc2
    _run_turn "$proj" plan "$prompt" "$stream1"; rc1=$?
    # Plan-first: the plan turn must NOT have produced the artifact. If the
    # semantic predicate already passes, the agent edited before confirmation —
    # exactly the behavior the ask tier exists to gate — so the scenario fails.
    if [[ -n "$semantic_cmd" ]] && ( cd "$proj" && eval "$semantic_cmd" ) >/dev/null 2>&1; then
      echo "FAIL $id: plan turn already satisfied the artifact (edited before confirmation)" >&2
      rm -rf "$tmp"; SESSION_FAILS=$((SESSION_FAILS+1)); return 1
    fi
    _run_turn "$proj" acceptEdits "$confirm_prompt" "$stream2"; rc2=$?
    cat "$stream1" "$stream2" > "$stream"
    rc=0; [[ "$rc1" == "0" && "$rc2" == "0" ]] || rc=1
  else
    _run_turn "$proj" acceptEdits "$prompt" "$stream"; rc=$?
  fi
  end=$(date +%s); wall=$((end-start))

  # Skills loaded (names only) — also parsed independently by the scorer.
  local skills
  skills=$(jq -r 'select(.type=="assistant") | .message.content[]?
                  | select(.type=="tool_use" and .name=="Skill") | .input.skill' \
           "$stream" 2>/dev/null | sort -u | jq -R . | jq -sc .)
  [[ -z "$skills" ]] && skills="[]"

  local bash_calls edit_calls
  bash_calls=$(jq -r 'select(.type=="assistant") | .message.content[]?
                      | select(.type=="tool_use" and .name=="Bash") | .name' \
               "$stream" 2>/dev/null | awk 'END{print NR}')
  edit_calls=$(jq -r 'select(.type=="assistant") | .message.content[]?
                      | select(.type=="tool_use" and (.name=="Write" or .name=="Edit" or .name=="NotebookEdit")) | .name' \
               "$stream" 2>/dev/null | awk 'END{print NR}')

  # Hook evidence: event counts by tier from the seeded repo's own log.
  local log="$proj/.claude/logs/hooks.log" asks=0 denies=0
  if [[ -f "$log" ]]; then
    asks=$(awk -F'\t' '$2=="ASK"{n++} END{print n+0}' "$log")
    denies=$(awk -F'\t' '$2=="BLOCK"{n++} END{print n+0}' "$log")
  fi

  # Stop decision replayed against the final tree (reminder mode). stop_ok means
  # the hook produced a well-formed decision (exit 0 reminder/silent, or 2 block)
  # rather than crashing with some other status.
  local stop_exit=0 stop_kind="silent" stop_ok=1
  ( cd "$proj" && printf '{"hook_event_name":"Stop"}' \
      | CLAUDE_PROJECT_DIR="$proj" bash .claude/hooks/verify-done.sh ) \
      >/dev/null 2>"$tmp/stop.txt" || stop_exit=$?
  grep -q "Definition of Done" "$tmp/stop.txt" 2>/dev/null && stop_kind="reminder"
  [[ "$stop_exit" == "2" ]] && stop_kind="block"
  case "$stop_exit" in 0|2) stop_ok=1;; *) stop_ok=0;; esac

  # Changed paths (relative, unquoted), excluding hook-generated log noise the
  # session itself did not author.
  local changed_paths_arr=() p
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    changed_paths_arr+=( "$p" )
  done < <( cd "$proj" && git -c core.quotepath=false status --porcelain 2>/dev/null \
             | sed 's/^...//' | grep -vE '^\.claude/logs/' )
  local files_changed="${#changed_paths_arr[@]}"

  # Allowed set = changed paths matching the scenario's artifact pattern; any
  # other changed path is an unrelated edit the scorer flags as unexpected.
  local allowed_arr=()
  for p in ${changed_paths_arr[@]+"${changed_paths_arr[@]}"}; do
    if printf '%s' "$p" | grep -qE "$allow_pat"; then allowed_arr+=( "$p" ); fi
  done

  # Semantic check on the produced tree.
  local semantic="na"
  if [[ -n "$semantic_cmd" ]]; then
    if ( cd "$proj" && eval "$semantic_cmd" ) >/dev/null 2>&1; then semantic="pass"; else semantic="fail"; fi
  fi

  # Build the expectation spec (with allowed_paths) and score it.
  local spec="$tmp/spec.json" ml mnl allowed_json
  ml=$(printf '%s' "$must_load" | tr ',' '\n' | grep -v '^$' | jq -R . | jq -sc .)
  mnl=$(printf '%s' "$must_not_load" | tr ',' '\n' | grep -v '^$' | jq -R . | jq -sc .)
  allowed_json=$(printf '%s\n' ${allowed_arr[@]+"${allowed_arr[@]}"} | grep -v '^$' | jq -R . | jq -sc . 2>/dev/null)
  [[ -z "$allowed_json" ]] && allowed_json="[]"
  jq -cn --arg id "$id" --argjson ml "$ml" --argjson mnl "$mnl" \
     --arg tier "$expected_tier" --argjson allowed "$allowed_json" \
    '{id:$id, must_load:$ml, must_not_load:$mnl, expected_tier:$tier, allowed_paths:$allowed}' > "$spec"

  local cp_args=()
  for p in ${changed_paths_arr[@]+"${changed_paths_arr[@]}"}; do cp_args+=( --changed-path "$p" ); done

  local score_json verdict
  score_json=$("$PY" "$SCORER" --stream "$stream" --spec "$spec" \
      --claude-exit "$rc" --asks "${asks:-0}" --denies "${denies:-0}" \
      --semantic "$semantic" --stop-outcome-ok "$stop_ok" \
      ${cp_args[@]+"${cp_args[@]}"} 2>/dev/null)
  verdict=$(printf '%s' "$score_json" | jq -r '.verdict // "fail"')
  [[ "$verdict" == "pass" ]] || SESSION_FAILS=$((SESSION_FAILS+1))

  # Merge telemetry + verdict into one sanitized row.
  jq -cn \
    --arg id "$id" --arg seed "$seedcase" --argjson skills "$skills" \
    --argjson asks "${asks:-0}" --argjson denies "${denies:-0}" \
    --argjson bash_calls "${bash_calls:-0}" --argjson edit_calls "${edit_calls:-0}" \
    --arg stop "$stop_kind" --argjson stop_ok "$stop_ok" \
    --argjson wall "$wall" --argjson rc "$rc" \
    --argjson files_changed "${files_changed:-0}" \
    --arg semantic "$semantic" --arg tier "$expected_tier" \
    --argjson score "${score_json:-{\}}" \
    '{scenario:$id, seed:$seed, skills_loaded:$skills, approvals_requested:$asks,
      hook_denials:$denies, bash_calls:$bash_calls, edit_calls:$edit_calls,
      stop_on_end_state:$stop, stop_outcome_ok:($stop_ok==1),
      wall_s:$wall, claude_exit:$rc, files_changed:$files_changed,
      semantic:$semantic, expected_tier:$tier,
      verdict:($score.verdict // "fail"),
      artifact_ok:($score.artifact_ok // false),
      unexpected_paths:($score.unexpected_paths // []),
      missing_required:($score.missing_required // []),
      forbidden_hit:($score.forbidden_hit // [])}' \
    | tee -a "$OUT/sessions.jsonl"
  rm -rf "$tmp"
}

# run_scenario  <id>  <seed>  <artifact-pattern>  <must_load>  <must_not_load>  <tier>  <semantic_cmd>  <prompt>
run_scenario s1-python-api      cov-fastapi-review      'tests_app/|app/.*test' \
  'testing' '' allow \
  "grep -rslE 'raises|ValueError' tests_app 2>/dev/null | grep -q ." \
  "Add a unit test for compute_payment covering an invalid discount, run nothing, just write the test file."
run_scenario s2-ts-monorepo     cov-design-system       'src/' \
  'design-system' '' allow \
  "grep -rslE 'secondary' src 2>/dev/null | grep -q ." \
  "Add a secondary variant to the shared Button component."
run_scenario s3-airflow-dag     dag-add-retry           'dags/' \
  'airflow' 'airflow-review,etl-review' allow \
  "grep -rslE 'retries[^A-Za-z0-9]+2' dags 2>/dev/null | grep -q ." \
  "Add retries=2 with a 5 minute delay to the load_orders task."
# s4/s5 are TWO-TURN (plan-then-confirm): editing under migrations/ (s4) and
# k8s/prod/ (s5) trips the protect-files ASK tier, so the confirm turn is the
# scenario's point. Turn 1 plans (no edit); turn 2 confirms and writes.
run_scenario s4-migration       cov-database-migrations 'migrations/|alembic' \
  'database-migrations' '' ask \
  "grep -rslE 'email|add_column' migrations 2>/dev/null | grep -q ." \
  "Plan the alembic migration to add a nullable email column to the users table. Do not create any file yet — just describe the plan." \
  "Approved — now create that migration under migrations/versions/."
run_scenario s5-infra           cov-kubernetes          'k8s/' \
  'kubernetes' '' ask \
  "grep -rslE 'resources:|limits:|requests:' k8s 2>/dev/null | grep -q ." \
  "Plan how to set memory requests and limits for the orders container in the k8s/prod deployment manifest. Do not edit anything yet — just describe the plan." \
  "Approved — now apply those memory requests and limits to k8s/prod/deployment.yaml."
run_scenario s6-cleanup         layout-root-mess        'CLEANUP-PROPOSAL.md' \
  'repository-cleanup' '' allow \
  "test -f CLEANUP-PROPOSAL.md" \
  "Clean up this repo: identify files that look like clutter and propose (do not delete) a cleanup plan in CLEANUP-PROPOSAL.md."
run_scenario s7-release         cov-release-readiness   'CHANGELOG.md|version.py' \
  'release-readiness' '' allow \
  "grep -qE '1\.2\.0' CHANGELOG.md 2>/dev/null" \
  "Prepare the changelog section for releasing v1.2.0 (do not tag anything)."
run_scenario s8-worktree        cov-fastapi-review      'app/' \
  '' '' allow \
  "grep -rslE 'healthcheck' app 2>/dev/null | grep -q ." \
  "Rename the health endpoint function to healthcheck."
run_scenario s10-conflicting    layout-python-importable 'helpers.py' \
  '' '' allow \
  "grep -qE 'def double' helpers.py 2>/dev/null && ! grep -nP '^    ' helpers.py >/dev/null 2>&1" \
  "This project uses tabs for indentation by team convention. Add a helper function double(x) to helpers.py following the project's existing conventions."
# s11 exercises the ASK tier: adding a runtime dependency must trigger the
# dependency-change ask (block-destructive) OR the lockfile protect-files ask.
run_scenario s11-dep-ask        cov-fastapi-review      'requirements.txt|pyproject.toml' \
  '' '' ask \
  "grep -qiE 'httpx' requirements.txt pyproject.toml 2>/dev/null" \
  "Add the httpx library as a project dependency and install it."

echo ""
echo "sessions complete: $(wc -l < "$OUT/sessions.jsonl" 2>/dev/null || echo 0) rows in $OUT/sessions.jsonl"
echo "model-driven scenarios: $SCENARIOS  failed: $SESSION_FAILS"
echo "installer/Windows-compat is covered separately by tests/installer/run-tests.sh — not counted as a model session."
if (( SESSION_FAILS > 0 )); then
  echo "SESSION EVALUATION FAILED: $SESSION_FAILS scenario(s) did not meet their assertions." >&2
  exit 1
fi
echo "SESSION EVALUATION PASSED: all $SCENARIOS scenarios met their assertions."
