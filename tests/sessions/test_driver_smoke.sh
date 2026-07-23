#!/usr/bin/env bash
# Offline smoke test for the realistic-session driver (run-sessions.sh).
#
# It drives the REAL driver with a STUBBED `claude` (injected via CLAUDE_BIN) so
# the whole shell orchestration runs with NO model calls and NO network:
#   * real seeding (seed-repo.sh) and the pristine-red gate,
#   * the one-turn path AND the two-turn plan-then-confirm path,
#   * hook-log ASK counting, changed-path allowlisting, and scorer wiring.
# The live MODEL behavior (does the agent actually plan first, does the real hook
# ask) is proven separately by an authenticated run — see tests/EVIDENCE.md. This
# test proves the driver's plumbing, which is otherwise unexercised offline
# (test_driver_contract.py only parses it statically).
#
# Run: bash tests/sessions/test_driver_smoke.sh   (needs bash, jq, python, git)
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DRIVER="$HERE/run-sessions.sh"

command -v jq >/dev/null 2>&1 || { echo "smoke: need jq" >&2; exit 2; }
command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 \
  || { echo "smoke: need python" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- The stub `claude` -------------------------------------------------------
# Emits canned stream-json and, only on a confirm (edits-accepted) turn, produces
# the artifact and logs the protect-files ASK. Its behavior is driven entirely by
# STUB_* env vars the test sets per case, so it hardcodes no scenario.
STUB="$WORK/claude"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
set -u
mode=""
while [ $# -gt 0 ]; do
  case "$1" in
    --permission-mode) mode="${2:-}"; shift 2 || shift ;;
    -p|--output-format|--setting-sources) shift 2 || shift ;;
    *) shift ;;
  esac
done

printf '%s\n' '{"type":"system","subtype":"init"}'
if [ -n "${STUB_SKILL:-}" ]; then
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"%s"}}]}}\n' "$STUB_SKILL"
fi
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}'

# A plan turn leaves the tree pristine; only the confirm turn writes the artifact
# and (for a protected path) logs the ASK the driver counts.
if [ "$mode" != "plan" ] && [ -n "${STUB_ARTIFACT:-}" ]; then
  mkdir -p "$(dirname "$STUB_ARTIFACT")"
  printf '%s\n' "${STUB_ARTIFACT_CONTENT:-artifact}" > "$STUB_ARTIFACT"
  if [ "${STUB_ASK:-0}" = "1" ]; then
    mkdir -p .claude/logs
    printf '%s\tASK\tprotect-files\tprotected-file\tstub\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> .claude/logs/hooks.log
  fi
fi
printf '%s\n' '{"type":"result","subtype":"success"}'
exit 0
STUBEOF
chmod +x "$STUB"

PASS=0
FAIL=0

# run_case <name> <scenario-id> <expect: pass|fail> <STUB_ENV=val ...>
# Drives one scenario through the real driver (via its ONLY filter) with the stub.
run_case() {
  local name="$1" sid="$2" expect="$3"; shift 3
  local out="$WORK/$name"; mkdir -p "$out"
  local rc=0
  env CLAUDE_BIN="$STUB" "$@" bash "$DRIVER" "$out" "$sid" >"$out/log.txt" 2>&1 || rc=$?
  local v
  v=$(jq -r "select(.scenario==\"$sid\") | .verdict" "$out/sessions.jsonl" 2>/dev/null | tail -1)
  [ -n "$v" ] || v="<none>"
  if [ "$expect" = pass ]; then
    if [ "$v" = pass ] && [ "$rc" = 0 ]; then
      PASS=$((PASS+1)); echo "PASS $name  ($sid verdict=$v rc=$rc)"
    else
      FAIL=$((FAIL+1)); echo "FAIL $name  ($sid verdict=$v rc=$rc)"; sed 's/^/    /' "$out/log.txt"
    fi
  else
    if [ "$v" = fail ] || [ "$rc" != 0 ]; then
      PASS=$((PASS+1)); echo "PASS $name  (negative: $sid verdict=$v rc=$rc)"
    else
      FAIL=$((FAIL+1)); echo "FAIL $name  (negative expected a fail, got verdict=$v rc=$rc)"; sed 's/^/    /' "$out/log.txt"
    fi
  fi
}

# One-turn allow scenario: artifact written, no ask, testing loads.
run_case one-turn-allow  s1-python-api pass \
  STUB_SKILL=testing \
  STUB_ARTIFACT=tests_app/test_payment.py \
  STUB_ARTIFACT_CONTENT='def test_bad(): raise ValueError("bad discount")' \
  STUB_ASK=0

# Two-turn plan-then-confirm ask scenario: plan turn writes nothing (stays red),
# confirm turn writes the migration under migrations/ and logs the ASK tier.
run_case two-turn-ask    s4-migration  pass \
  STUB_SKILL=database-migrations \
  STUB_ARTIFACT=migrations/versions/0002_add_email.py \
  STUB_ARTIFACT_CONTENT='def upgrade(): op.add_column("users", sa.Column("email"))' \
  STUB_ASK=1

# Negative: the confirm/edit produces no artifact — the artifact gate must bite.
run_case negative-no-art s4-migration  fail \
  STUB_SKILL=database-migrations \
  STUB_ARTIFACT= \
  STUB_ASK=1

echo ""
echo "driver smoke: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || { echo "DRIVER SMOKE FAILED" >&2; exit 1; }
echo "DRIVER SMOKE PASSED"
