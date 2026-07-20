#!/usr/bin/env bash
# Checkpointed driver for the live routing evaluation.
#
# Runs run_eval.py one case at a time, parking each case's rows in a per-case
# file, and SKIPS cases already done — so the full 45-case evaluation survives
# interruption and can be executed as a series of bounded invocations (this
# session's tool calls are capped at 10 minutes). A time guard stops picking up
# new cases near the cap; relaunching resumes where it left off.
# merge_eval.py combines the per-case files into the canonical result pair.
#
# Usage: bash tests/skills/routing/drive_eval.sh <percase-dir> [budget-seconds]
set -uo pipefail

OUT="${1:?usage: drive_eval.sh <percase-dir> [budget-seconds]}"
BUDGET="${2:-420}"
HERE="$(cd "$(dirname "$0")" && pwd)"
RESULTS="$HERE/../results"
mkdir -p "$OUT"
START=$(date +%s)

# tr -d '\r': Windows Python writes CRLF to a pipe; an id carrying an invisible
# \r makes run_eval's --only filter match nothing ("no case with id X" with the
# X looking identical). Cost of not doing this: every case fails instantly.
mapfile -t IDS < <(python - <<'EOF' | tr -d '\r'
import io, yaml
d = yaml.safe_load(io.open('tests/skills/trigger-cases.yaml', encoding='utf-8'))
for cluster, entries in d.items():
    if cluster == 'evaluated_runs' or not isinstance(entries, list):
        continue
    for case in entries:
        print(case['id'])
EOF
)

DONE=0; SKIPPED=0
for id in "${IDS[@]}"; do
  if [[ -s "$OUT/$id.jsonl" ]]; then
    SKIPPED=$((SKIPPED+1))
    continue
  fi
  ELAPSED=$(( $(date +%s) - START ))
  if (( ELAPSED > BUDGET )); then
    echo "BUDGET: ${ELAPSED}s elapsed > ${BUDGET}s — stopping before $id (relaunch to resume)"
    echo "PROGRESS: done_this_run=$DONE already_done=$SKIPPED remaining=$(( ${#IDS[@]} - DONE - SKIPPED ))"
    exit 0
  fi
  echo "== case $id =="
  # Sentinel BEFORE the run: only a result file newer than it may be claimed.
  # Without this, a failed run_eval left `ls -t | head -1` pointing at a
  # COMMITTED historical result, which the first draft of this driver then
  # misfiled as the case's output (real incident, v7).
  SENTINEL="$OUT/.sentinel"
  touch "$SENTINEL"
  if ! python "$HERE/run_eval.py" --only "$id" --runs 3; then
    echo "WARN: run_eval exited non-zero for $id (rows still collected if written)"
  fi
  NEWEST=$(find "$RESULTS" -maxdepth 1 -name 'routing-*.jsonl' -newer "$SENTINEL" | head -1)
  if [[ -n "$NEWEST" && -s "$NEWEST" ]]; then
    mv "$NEWEST" "$OUT/$id.jsonl"
    rm -f "${NEWEST%.jsonl}-summary.json"
    DONE=$((DONE+1))
  else
    echo "ERROR: no result file produced for $id"
  fi
done
echo "ALL CASES PRESENT: done_this_run=$DONE already_done=$SKIPPED total=${#IDS[@]}"
