#!/usr/bin/env bash
# Realistic-session evaluation (v7 plan §8; v8 assertions): scenario repos, one
# real headless Claude Code session each, scored against declared expectations.
#
# v8 change — this harness now ASSERTS, it does not only record. Each scenario
# declares must_load / must_not_load skills, an expected permission tier, an
# expected artifact path (a real path, never `.`), and a semantic check the
# produced artifact must satisfy. A scenario FAILS (and the run exits non-zero)
# when a required skill did not load, a forbidden skill loaded, the artifact was
# merely touched instead of correctly changed, the semantic check failed, or the
# expected tier was not exercised. Scoring is factored into score_session.py so
# it is unit-tested offline (test_score_session.py) without model calls.
#
# Per scenario it still records the sanitized telemetry: skills loaded (Skill
# tool_use events, names only), hook events by tier (from the seeded repo's
# .claude/logs/hooks.log), asks/denials, the Stop end-state decision (verify-done
# replayed against the final tree — headless -p cannot surface the reminder
# itself), wall-clock, and the artifact-level outcome. Nothing from the
# transcript is stored except skill names and counts.
#
# The installer/Windows-compat check is deliberately NOT a model session here —
# it lives in tests/installer/run-tests.sh; counting it as a session would
# inflate the model-driven denominator.
#
# Usage: bash tests/sessions/run-sessions.sh <out-dir> [only-scenario-id]
# Needs an authenticated Claude Code CLI + jq; this is a LOCAL evaluation, not a
# CI step (CI runs the offline scorer tests instead).
set -uo pipefail

OUT="${1:?usage: run-sessions.sh <out-dir> [only-id]}"
ONLY="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SEED="$REPO/tests/skills/routing/seed-repo.sh"
SCORER="$HERE/score_session.py"
mkdir -p "$OUT"

command -v claude >/dev/null || { echo "need claude CLI" >&2; exit 1; }
command -v jq >/dev/null || { echo "need jq" >&2; exit 1; }
command -v python >/dev/null || command -v python3 >/dev/null || { echo "need python" >&2; exit 1; }
PY=$(command -v python || command -v python3)

SCENARIOS=0
SESSION_FAILS=0

# run_scenario <id> <seed-case> <outcome-regex> <must_load_csv> \
#              <must_not_load_csv> <expected_tier> <semantic_cmd> <prompt>
#   outcome-regex   a SPECIFIC path (regex over `git status --porcelain`) that
#                   must have changed — never `.`; a bare `.` is rejected below.
#   must_load_csv   comma-separated skills that MUST load ("" = none required)
#   must_not_load   comma-separated skills that must NOT load ("" = none)
#   expected_tier   none | ask | deny — the hook tier this scenario should exercise
#   semantic_cmd    shell snippet run inside $proj; exit 0 = the artifact is
#                   semantically correct ("" = no semantic check → "na")
run_scenario() {
  local id="$1" seedcase="$2" outcome_glob="$3" must_load="$4" \
        must_not_load="$5" expected_tier="$6" semantic_cmd="$7" prompt="$8"
  [[ -n "$ONLY" && "$ONLY" != "$id" ]] && return 0
  SCENARIOS=$((SCENARIOS+1))

  # Guard against the pre-v8 defect: a `.` outcome regex matches ANY change.
  if [[ "$outcome_glob" == "." ]]; then
    echo "FAIL $id: outcome regex '.' matches any path — use a specific artifact path" >&2
    SESSION_FAILS=$((SESSION_FAILS+1)); return 1
  fi

  local tmp proj
  tmp=$(mktemp -d) || return 1
  proj="$tmp/repo"
  bash "$SEED" "$seedcase" "$proj" >/dev/null 2>&1 || { echo "seed failed: $id" >&2; rm -rf "$tmp"; SESSION_FAILS=$((SESSION_FAILS+1)); return 1; }
  ( cd "$proj" && git init -q . && git add -A >/dev/null 2>&1 \
      && git -c user.email=s@s -c user.name=s commit -qm seed >/dev/null ) || true

  local start end wall stream
  stream="$tmp/stream.jsonl"
  start=$(date +%s)
  ( cd "$proj" && claude -p "$prompt" \
      --output-format stream-json --verbose \
      --setting-sources project \
      --permission-mode acceptEdits ) > "$stream" 2>"$tmp/stderr.txt"
  local rc=$?
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

  # Stop decision replayed against the final tree (reminder mode).
  local stop_exit=0 stop_kind="silent"
  ( cd "$proj" && printf '{"hook_event_name":"Stop"}' \
      | CLAUDE_PROJECT_DIR="$proj" bash .claude/hooks/verify-done.sh ) \
      >/dev/null 2>"$tmp/stop.txt" || stop_exit=$?
  grep -q "Definition of Done" "$tmp/stop.txt" 2>/dev/null && stop_kind="reminder"
  [[ "$stop_exit" == "2" ]] && stop_kind="block"

  # Artifact: did the EXPECTED path change relative to the seed commit?
  local changed artifact_changed=0
  changed=$( cd "$proj" && git status --porcelain 2>/dev/null | wc -l )
  if ( cd "$proj" && git status --porcelain 2>/dev/null | grep -qE "$outcome_glob" ); then
    artifact_changed=1
  fi

  # Semantic check: run the snippet inside the produced tree.
  local semantic="na"
  if [[ -n "$semantic_cmd" ]]; then
    if ( cd "$proj" && eval "$semantic_cmd" ) >/dev/null 2>&1; then
      semantic="pass"
    else
      semantic="fail"
    fi
  fi

  # Build the expectation spec and score it.
  local spec="$tmp/spec.json" ml mnl
  ml=$(printf '%s' "$must_load" | tr ',' '\n' | grep -v '^$' | jq -R . | jq -sc .)
  mnl=$(printf '%s' "$must_not_load" | tr ',' '\n' | grep -v '^$' | jq -R . | jq -sc .)
  jq -cn --arg id "$id" --argjson ml "$ml" --argjson mnl "$mnl" --arg tier "$expected_tier" \
    '{id:$id, must_load:$ml, must_not_load:$mnl, expected_tier:$tier}' > "$spec"

  local score_json verdict
  score_json=$("$PY" "$SCORER" --stream "$stream" --spec "$spec" \
      --asks "${asks:-0}" --denies "${denies:-0}" \
      --artifact-changed "$artifact_changed" --semantic "$semantic" 2>/dev/null)
  verdict=$(printf '%s' "$score_json" | jq -r '.verdict // "fail"')
  [[ "$verdict" == "pass" ]] || SESSION_FAILS=$((SESSION_FAILS+1))

  # Merge telemetry + verdict into one sanitized row.
  jq -cn \
    --arg id "$id" --arg seed "$seedcase" --argjson skills "$skills" \
    --argjson asks "${asks:-0}" --argjson denies "${denies:-0}" \
    --argjson bash_calls "${bash_calls:-0}" --argjson edit_calls "${edit_calls:-0}" \
    --arg stop "$stop_kind" --argjson wall "$wall" --argjson rc "$rc" \
    --argjson artifact_changed "$artifact_changed" --argjson files_changed "${changed:-0}" \
    --arg semantic "$semantic" --arg tier "$expected_tier" \
    --argjson score "${score_json:-{\}}" \
    '{scenario:$id, seed:$seed, skills_loaded:$skills, approvals_requested:$asks,
      hook_denials:$denies, bash_calls:$bash_calls, edit_calls:$edit_calls,
      stop_on_end_state:$stop, wall_s:$wall, claude_exit:$rc,
      artifact_changed:($artifact_changed==1), files_changed:$files_changed,
      semantic:$semantic, expected_tier:$tier,
      verdict:($score.verdict // "fail"),
      missing_required:($score.missing_required // []),
      forbidden_hit:($score.forbidden_hit // [])}' \
    | tee -a "$OUT/sessions.jsonl"
  rm -rf "$tmp"
}

# run_scenario  <id>  <seed>  <outcome-regex>  <must_load>  <must_not_load>  <tier>  <semantic_cmd>  <prompt>
run_scenario s1-python-api      cov-fastapi-review      'tests_app/|app/.*test' \
  'testing' '' none \
  "grep -rslE 'def test_|compute_payment' tests_app app 2>/dev/null | grep -q ." \
  "Add a unit test for compute_payment covering an invalid discount, run nothing, just write the test file."
run_scenario s2-ts-monorepo     cov-design-system       'src/' \
  'design-system' '' none \
  "grep -rslE 'variant' src 2>/dev/null | grep -q ." \
  "Add a secondary variant to the shared Button component."
run_scenario s3-airflow-dag     dag-add-retry           'dags/' \
  'airflow' 'airflow-review,etl-review' none \
  "grep -rslE 'retries' dags 2>/dev/null | grep -q ." \
  "Add retries=2 with a 5 minute delay to the load_orders task."
run_scenario s4-migration       cov-database-migrations 'migrations/|alembic' \
  'database-migrations' '' none \
  "grep -rslE 'email|add_column' migrations alembic 2>/dev/null | grep -q ." \
  "Create the next alembic migration adding a nullable email column to users."
run_scenario s5-infra           cov-kubernetes          'k8s/' \
  'kubernetes' '' none \
  "grep -rslE 'resources:|limits:|requests:' k8s 2>/dev/null | grep -q ." \
  "Set memory requests and limits for the orders container in the deployment manifest."
run_scenario s6-cleanup         layout-root-mess        'CLEANUP-PROPOSAL.md' \
  'repository-cleanup' '' none \
  "test -f CLEANUP-PROPOSAL.md" \
  "Clean up this repo: identify files that look like clutter and propose (do not delete) a cleanup plan in CLEANUP-PROPOSAL.md."
run_scenario s7-release         cov-release-readiness   'CHANGELOG.md|version.py' \
  'release-readiness' '' none \
  "grep -qE '1\.2\.0' CHANGELOG.md 2>/dev/null" \
  "Prepare the changelog section for releasing v1.2.0 (do not tag anything)."
run_scenario s8-worktree        cov-fastapi-review      'app/' \
  '' '' none \
  "grep -rslE 'healthcheck' app 2>/dev/null | grep -q ." \
  "Rename the health endpoint function to healthcheck."
run_scenario s10-conflicting    layout-python-importable 'helpers.py' \
  '' '' none \
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
