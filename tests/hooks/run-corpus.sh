#!/usr/bin/env bash
# Hook policy corpus runner: replays every labeled row in corpus.jsonl through
# the real enforcement hooks and reports a confusion matrix.
#
# Labels per row (see corpus.jsonl):
#   expected  the CONTRACT decision (allow|ask|deny) — what the shipped policy
#             says must happen. A mismatch here is a live defect.
#   ideal     the semantic ground truth when it differs from the contract
#             (documented trade-offs: prose false positives, out-of-scope
#             equivalents). Defaults to expected. Mismatches against ideal are
#             MEASURED (fp_vs_ideal / fn_vs_ideal), not failed.
#   oos       true when the row is a known out-of-scope semantic equivalent
#             (e.g. shutil.rmtree) — counted in out_of_scope_rate.
#
# Decision model mirrors Claude Code: Bash rows run block-destructive; file
# rows run protect-files + scan-secrets + check-diff-size. Any exit 2 = deny;
# else any permissionDecision:"ask" = ask; else allow.
#
# Usage: bash tests/hooks/run-corpus.sh [--gate] [corpus.jsonl]
#   --gate  exit 1 when any non-oos row's got != expected (post-fix CI mode).
#           Default (measure mode) always exits 0 and just reports.
# Needs bash + jq + git. Results: tests/hooks/results/corpus-<stamp>{.jsonl,-summary.json}

set -uo pipefail

GATE=0
if [[ "${1:-}" == "--gate" ]]; then GATE=1; shift; fi
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
HOOKS="$REPO/.claude/hooks"
CORPUS="${1:-$HERE/corpus.jsonl}"
RESULTS_DIR="$HERE/results"
mkdir -p "$RESULTS_DIR"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
OUT="$RESULTS_DIR/corpus-$STAMP.jsonl"
SUMMARY="$RESULTS_DIR/corpus-$STAMP-summary.json"

command -v jq >/dev/null || { echo "need jq" >&2; exit 1; }

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
export CLAUDE_PROJECT_DIR="$SCRATCH"
# Never inherit an override from the calling shell: the corpus measures the
# hooks' own decisions, and an active override would silently allow everything.
unset CLAUDE_HOOK_OVERRIDE

# Branch fixtures for protected-branch rows (project: main|feat).
PB_MAIN="$SCRATCH/pb-main"; mkdir -p "$PB_MAIN"
( cd "$PB_MAIN" && git init -q -b main . && printf 'x\n' > f.txt && git add f.txt \
  && git -c user.email=t@t -c user.name=t commit -qm init )
PB_FEAT="$SCRATCH/pb-feat"; mkdir -p "$PB_FEAT"
( cd "$PB_FEAT" && git init -q -b feat/x . && printf 'x\n' > f.txt && git add f.txt \
  && git -c user.email=t@t -c user.name=t commit -qm init )
# Sibling repo for cross-repo -C rows (target: main).
OTHER="$SCRATCH/other-repo"; mkdir -p "$OTHER"
( cd "$OTHER" && git init -q -b main . && printf 'x\n' > f.txt && git add f.txt \
  && git -c user.email=t@t -c user.name=t commit -qm init )

gen_lines() { seq 1 "$1" | sed 's/^/line /'; }

# run_hook <script> <payload> <project_dir> -> sets HOOK_EXIT / HOOK_OUT
run_hook() {
  local script="$1" payload="$2" proj="$3"
  HOOK_EXIT=0
  HOOK_OUT="$(printf '%s' "$payload" \
    | env CLAUDE_PROJECT_DIR="$proj" bash "$HOOKS/$script" 2>/dev/null)" \
    || HOOK_EXIT=$?
}

ROWS=0
: > "$OUT"
while IFS= read -r row; do
  [[ -z "$row" ]] && continue
  ROWS=$((ROWS+1))
  id=$(jq -r '.id' <<<"$row")
  tool=$(jq -r '.tool' <<<"$row")
  expected=$(jq -r '.expected' <<<"$row")
  project=$(jq -r '.project // "none"' <<<"$row")

  proj="$SCRATCH"
  case "$project" in
    main) proj="$PB_MAIN" ;;
    feat) proj="$PB_FEAT" ;;
  esac

  # Build content: joined content_parts, or gen_lines lines, or empty.
  content=""
  if jq -e '.content_parts' <<<"$row" >/dev/null; then
    content=$(jq -r '.content_parts | join("")' <<<"$row")
  elif jq -e '.gen_lines' <<<"$row" >/dev/null; then
    content=$(gen_lines "$(jq -r '.gen_lines' <<<"$row")")
  fi

  got="allow"; asked=0; denied=0
  case "$tool" in
    Bash)
      payload=$(jq -c '{tool_name:"Bash",tool_input:{command:.command}}' <<<"$row")
      run_hook block-destructive.sh "$payload" "$proj"
      [[ "$HOOK_EXIT" == 2 ]] && denied=1
      grep -q '"permissionDecision":"ask"' <<<"$HOOK_OUT" && asked=1
      ;;
    Write|Edit|NotebookEdit)
      payload=$(jq -c --arg t "$tool" --arg c "$content" '
        if $t == "Write" then {tool_name:$t,tool_input:{file_path:.file_path,content:$c}}
        elif $t == "Edit" then {tool_name:$t,tool_input:{file_path:.file_path,old_string:"old",new_string:$c}}
        else {tool_name:$t,tool_input:{notebook_path:.file_path,new_source:$c}}
        end' <<<"$row")
      for h in protect-files.sh scan-secrets.sh check-diff-size.sh; do
        run_hook "$h" "$payload" "$proj"
        [[ "$HOOK_EXIT" == 2 ]] && denied=1
        grep -q '"permissionDecision":"ask"' <<<"$HOOK_OUT" && asked=1
      done
      ;;
    *)
      echo "SKIP $id: unknown tool $tool" >&2
      continue
      ;;
  esac
  if [[ "$denied" == 1 ]]; then got="deny"
  elif [[ "$asked" == 1 ]]; then got="ask"
  fi

  jq -c --arg got "$got" '. + {ideal: (.ideal // .expected), oos: (.oos // false), got: $got, match: ($got == .expected)}' <<<"$row" >> "$OUT"
  status=$([[ "$got" == "$expected" ]] && echo "ok  " || echo "VIOL")
  printf '%s %-7s expected=%-5s got=%-5s\n' "$status" "$id" "$expected" "$got"
done < "$CORPUS"

jq -s '
  def rate(n; d): if d == 0 then null else ((n / d) * 1000 | round) / 1000 end;
  . as $r
  | ($r | length) as $n
  | [$r[] | select(.oos == true)] as $oos
  | [$r[] | select(.oos != true)] as $scored
  | [$scored[] | select(.got != .expected)] as $viol
  | {
      rows: $n,
      scored_rows: ($scored | length),
      out_of_scope_rows: ($oos | length),
      out_of_scope_rate: rate(($oos | length); $n),
      contract_violations: ($viol | length),
      violation_ids: [$viol[].id],
      confusion: {
        expected_deny:  {deny:  [$r[] | select(.expected=="deny"  and .got=="deny")]  | length,
                         ask:   [$r[] | select(.expected=="deny"  and .got=="ask")]   | length,
                         allow: [$r[] | select(.expected=="deny"  and .got=="allow")] | length},
        expected_ask:   {deny:  [$r[] | select(.expected=="ask"   and .got=="deny")]  | length,
                         ask:   [$r[] | select(.expected=="ask"   and .got=="ask")]   | length,
                         allow: [$r[] | select(.expected=="ask"   and .got=="allow")] | length},
        expected_allow: {deny:  [$r[] | select(.expected=="allow" and .got=="deny")]  | length,
                         ask:   [$r[] | select(.expected=="allow" and .got=="ask")]   | length,
                         allow: [$r[] | select(.expected=="allow" and .got=="allow")] | length}
      },
      dangerous_action_recall: rate([$r[] | select((.expected=="deny" or .expected=="ask") and .got != "allow")] | length;
                                    [$r[] | select(.expected=="deny" or .expected=="ask")] | length),
      strict_deny_recall:      rate([$r[] | select(.expected=="deny" and .got=="deny")] | length;
                                    [$r[] | select(.expected=="deny")] | length),
      legit_allow_rate:        rate([$r[] | select(.expected=="allow" and .got=="allow")] | length;
                                    [$r[] | select(.expected=="allow")] | length),
      false_deny_rate:         rate([$r[] | select(.expected=="allow" and .got=="deny")] | length;
                                    [$r[] | select(.expected=="allow")] | length),
      false_allow_rate:        rate([$r[] | select((.expected=="deny" or .expected=="ask") and .got=="allow")] | length;
                                    [$r[] | select(.expected=="deny" or .expected=="ask")] | length),
      ask_accuracy:            rate([$r[] | select(.expected=="ask" and .got=="ask")] | length;
                                    [$r[] | select(.expected=="ask")] | length),
      fp_vs_ideal:  [$r[] | select(.ideal=="allow" and .got != "allow")] | length,
      fn_vs_ideal:  [$r[] | select(.ideal != "allow" and .got=="allow")] | length,
      by_category: ([$r[].category] | unique | map({key: ., value: {
          rows: [$r[] | select(.category == .)] | length
        }}) | from_entries)
    }
  | .by_category = ( $r | group_by(.category) | map({key: .[0].category, value: {
        rows: length,
        violations: [.[] | select(.oos != true and .got != .expected)] | length
      }}) | from_entries )
' "$OUT" > "$SUMMARY"

echo ""
echo "results: $OUT"
echo "summary: $SUMMARY"
jq . "$SUMMARY"

if [[ "$GATE" == 1 ]]; then
  V=$(jq -r '.contract_violations' "$SUMMARY")
  if [[ "$V" != 0 ]]; then
    echo "corpus gate FAILED: $V contract violation(s)" >&2
    exit 1
  fi
  echo "corpus gate passed: 0 contract violations"
fi
exit 0
