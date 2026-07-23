#!/usr/bin/env bash
# Single documented offline-verification entrypoint for claude-template.
#
# Runs EVERY maintained offline suite — no model calls, no network — and exits
# non-zero if any fails. This is the authoritative offline gate: CI runs it (on
# each supported platform), and a contributor runs it locally before a PR. The
# live model evaluations (skill routing, realistic sessions) are separate and
# run out-of-band; their exact-SHA evidence lives under tests/*/results/.
#
# Requirements: bash, jq, git, node, python3. The one pip dependency (PyYAML) is
# pinned in tests/requirements-verify.txt — install it with
#   python -m pip install -r tests/requirements-verify.txt
# ShellCheck is optional here (a warning if absent); CI installs the pinned
# ShellCheck + the same PyYAML pin and gates on both.
#
# Usage: bash tests/verify-offline.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
cd "$REPO" || exit 2
PY="$(command -v python3 || command -v python || true)"
[[ -n "$PY" ]] || { echo "✗ python3 not found" >&2; exit 2; }

FAIL=0
run() {
  local name="$1"; shift
  printf '\n──── %s\n' "$name"
  if "$@"; then
    printf '   ✓ %s\n' "$name"
  else
    printf '   ✗ %s FAILED\n' "$name"
    FAIL=$((FAIL + 1))
  fi
}

# --- Hook enforcement -------------------------------------------------------
run "hook regression suite"        bash tests/hooks/run-tests.sh
run "hook policy corpus (gate)"    bash tests/hooks/run-corpus.sh --gate

# --- Installer / bootstrap --------------------------------------------------
run "installer failure-injection"  bash tests/installer/run-tests.sh
run "hook installer end-to-end"    bash .claude/hooks/install.sh

# --- Policy contract --------------------------------------------------------
run "policy consistency gate"      "$PY" tests/policy_consistency.py
run "action-matrix validator"      "$PY" tests/policy_matrix.py

# --- Skills / routing / sessions (offline halves) ---------------------------
run "skill catalog consistency"    "$PY" tests/skills/check_catalog.py
run "routing scorer + parser"      "$PY" tests/skills/routing/test_run_eval.py
run "routing results consistency"  "$PY" tests/skills/routing/test_results_consistency.py
run "session scorer unit tests"    "$PY" tests/sessions/test_score_session.py
run "session driver<->scorer contract" "$PY" tests/sessions/test_driver_contract.py

# --- Static integrity -------------------------------------------------------
run "markdown link check"          "$PY" tests/check_links.py
run "python compilation" "$PY" - <<'PYEOF'
import glob, py_compile, sys, tempfile, os
tmp = tempfile.mkdtemp()
bad = 0
for f in glob.glob("**/*.py", recursive=True):
    try:
        py_compile.compile(f, cfile=os.path.join(tmp, f.replace(os.sep, "_") + "c"), doraise=True)
    except py_compile.PyCompileError as e:
        print(e); bad += 1
sys.exit(1 if bad else 0)
PYEOF
run "JSON + JSONL parse" "$PY" - <<'PYEOF'
import glob, json, sys
bad = 0
# .json is a whole-file object; .jsonl is one JSON value per line.
for f in glob.glob("**/*.json", recursive=True):
    with open(f, encoding="utf-8") as fh:
        try:
            json.load(fh)
        except json.JSONDecodeError as e:
            print(f"{f}: {e}"); bad += 1
for f in glob.glob("**/*.jsonl", recursive=True):
    with open(f, encoding="utf-8") as fh:
        for i, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                json.loads(line)
            except json.JSONDecodeError as e:
                print(f"{f}:{i}: {e}"); bad += 1
sys.exit(1 if bad else 0)
PYEOF
run "YAML parse" "$PY" - <<'PYEOF'
import glob, io, sys, yaml
bad = 0
for f in glob.glob("**/*.yaml", recursive=True) + glob.glob("**/*.yml", recursive=True):
    try:
        yaml.safe_load(io.open(f, encoding="utf-8"))
    except yaml.YAMLError as e:
        print(f"{f}: {e}"); bad += 1
sys.exit(1 if bad else 0)
PYEOF
run "generated-file cleanliness" bash -c '! (git ls-files "*.pyc" | grep -q . || git ls-files | grep -qE "(^|/)__pycache__(/|$)")'

# --- ShellCheck (optional locally; pinned + required in CI) ------------------
if command -v shellcheck >/dev/null 2>&1; then
  # -x + -P so the shared lib.sh source is followed from the hooks dir.
  mapfile -t SH < <(git ls-files '*.sh')
  run "shellcheck (all shell files)" shellcheck -x -P .claude/hooks "${SH[@]}"
else
  printf '\n──── shellcheck (all shell files)\n   ⚠ shellcheck not installed — skipped locally (CI gates on the pinned version)\n'
fi

echo ""
if (( FAIL > 0 )); then
  echo "OFFLINE VERIFICATION FAILED: $FAIL suite(s) failed." >&2
  exit 1
fi
echo "OFFLINE VERIFICATION PASSED: all offline suites green."
