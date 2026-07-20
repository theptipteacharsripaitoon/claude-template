#!/usr/bin/env bash
# Realistic-session evaluation (v7 plan §8): ten scenario repos, one real
# headless Claude Code session each, structured sanitized evidence out.
#
# Per scenario this records: skills loaded (Skill tool_use events), hook
# events by tier (from the seeded repo's .claude/logs/hooks.log), asks
# requested, denials, whether the session's END STATE would trigger the Stop
# reminder (verify-done replayed against the final tree — headless -p cannot
# surface the reminder itself, so this is the hook's decision on the same
# state, labelled as such), wall-clock, and an artifact-level outcome check.
# Nothing from the transcript is stored except skill names and counts.
#
# Scenario 9 (Windows/WSL install) is NOT a model session: it reuses the
# installer test suite result on this platform; WSL stays declared unmeasured.
#
# Usage: bash tests/sessions/run-sessions.sh <out-dir> [only-scenario-id]
set -uo pipefail

OUT="${1:?usage: run-sessions.sh <out-dir> [only-id]}"
ONLY="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SEED="$REPO/tests/skills/routing/seed-repo.sh"
mkdir -p "$OUT"

command -v claude >/dev/null || { echo "need claude CLI" >&2; exit 1; }
command -v jq >/dev/null || { echo "need jq" >&2; exit 1; }

# scenario <id> <seed-case> <outcome-glob> <prompt>
# seed-case: an existing seed-repo.sh shape for the domain.
# outcome-glob: a path (glob ok) that must have been modified/created for the
#               session to count as having produced its artifact.
run_scenario() {
  local id="$1" seedcase="$2" outcome_glob="$3" prompt="$4"
  [[ -n "$ONLY" && "$ONLY" != "$id" ]] && return 0
  local tmp proj
  tmp=$(mktemp -d) || return 1
  proj="$tmp/repo"
  bash "$SEED" "$seedcase" "$proj" >/dev/null 2>&1 || { echo "seed failed: $id" >&2; rm -rf "$tmp"; return 1; }
  ( cd "$proj" && git init -q . && git add -A >/dev/null 2>&1 \
      && git -c user.email=s@s -c user.name=s commit -qm seed ) || true

  local start end wall stream
  stream="$tmp/stream.jsonl"
  start=$(date +%s)
  ( cd "$proj" && claude -p "$prompt" \
      --output-format stream-json --verbose \
      --setting-sources project \
      --permission-mode acceptEdits ) > "$stream" 2>"$tmp/stderr.txt"
  local rc=$?
  end=$(date +%s); wall=$((end-start))

  # Skills loaded: Skill tool_use events only — names, nothing else.
  local skills
  skills=$(jq -r 'select(.type=="assistant") | .message.content[]?
                  | select(.type=="tool_use" and .name=="Skill") | .input.skill' \
           "$stream" 2>/dev/null | sort -u | jq -R . | jq -sc .)
  [[ -z "$skills" ]] && skills="[]"

  # Hook evidence: event counts by type from the seeded repo's own log.
  local log="$proj/.claude/logs/hooks.log" asks=0 denies=0
  if [[ -f "$log" ]]; then
    asks=$(grep -c '\[ASK\]' "$log" 2>/dev/null || true)
    denies=$(grep -c '\[BLOCK\]' "$log" 2>/dev/null || true)
  fi

  # Stop decision replayed against the final tree (reminder mode).
  local stop_exit=0 stop_kind="silent"
  ( cd "$proj" && printf '{"hook_event_name":"Stop"}' \
      | CLAUDE_PROJECT_DIR="$proj" bash .claude/hooks/verify-done.sh ) \
      >/dev/null 2>"$tmp/stop.txt" || stop_exit=$?
  grep -q "Definition of Done" "$tmp/stop.txt" 2>/dev/null && stop_kind="reminder"
  [[ "$stop_exit" == "2" ]] && stop_kind="block"

  # Outcome: did the expected artifact change relative to the seed commit?
  local changed outcome="no-artifact-change"
  changed=$( cd "$proj" && git status --porcelain 2>/dev/null | wc -l )
  if ( cd "$proj" && git status --porcelain 2>/dev/null | grep -qE "$outcome_glob" ); then
    outcome="artifact-changed"
  fi

  jq -cn \
    --arg id "$id" --arg seed "$seedcase" --argjson skills "$skills" \
    --argjson asks "${asks:-0}" --argjson denies "${denies:-0}" \
    --arg stop "$stop_kind" --argjson wall "$wall" --argjson rc "$rc" \
    --arg outcome "$outcome" --argjson files_changed "${changed:-0}" \
    '{scenario:$id, seed:$seed, skills_loaded:$skills, approvals_requested:$asks,
      hook_denials:$denies, stop_on_end_state:$stop, wall_s:$wall,
      claude_exit:$rc, outcome:$outcome, files_changed:$files_changed}' \
    | tee -a "$OUT/sessions.jsonl"
  rm -rf "$tmp"
}

# id                seed-case               outcome-glob                 prompt
run_scenario s1-python-api      cov-fastapi-review   'app/|tests_app/' \
  "Add a unit test for compute_payment covering an invalid discount, run nothing, just write the test file."
run_scenario s2-ts-monorepo     cov-design-system    'src/' \
  "Add a secondary variant to the shared Button component."
run_scenario s3-airflow-dag     dag-add-retry        'dags/' \
  "Add retries=2 with a 5 minute delay to the load_orders task."
run_scenario s4-migration       cov-database-migrations 'migrations/' \
  "Create the next alembic migration adding a nullable email column to users."
run_scenario s5-infra           cov-kubernetes       'k8s/' \
  "Set memory requests and limits for the orders container in the deployment manifest."
run_scenario s6-cleanup         layout-root-mess     '.' \
  "Clean up this repo: identify files that look like clutter and propose (do not delete) a cleanup plan in CLEANUP-PROPOSAL.md."
run_scenario s7-release         cov-release-readiness 'CHANGELOG.md|version.py' \
  "Prepare the changelog section for releasing v1.2.0 (do not tag anything)."
run_scenario s8-worktree        cov-fastapi-review   'app/' \
  "Rename the health endpoint function to healthcheck."
run_scenario s10-conflicting    layout-python-importable '.' \
  "This project uses tabs for indentation by team convention. Add a helper function double(x) to helpers.py following the project's existing conventions."

echo ""
echo "sessions complete: $(wc -l < "$OUT/sessions.jsonl" 2>/dev/null || echo 0) rows in $OUT/sessions.jsonl"
echo "scenario 9 (Windows/WSL install) is covered by tests/installer/run-tests.sh on this platform; WSL: declared unmeasured (SUPPORT.md)."
