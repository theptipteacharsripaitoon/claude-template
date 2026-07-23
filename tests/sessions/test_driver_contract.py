#!/usr/bin/env python3
"""Offline contract test: the live driver (run-sessions.sh) must invoke the
scorer (score_session.py) exactly as the scorer's CLI expects, and never with a
removed option.

The v9 review (P — "Live session driver finalization") caught the driver and
scorer drifting: the scorer was upgraded to the strict contract while the driver
still passed the removed --artifact-changed and omitted --claude-exit, so a live
run would die at argument parsing. That drift is invisible offline unless
something asserts the two agree. This test is that assertion — it parses both
files statically (no model calls, no network) and fails if:

  * the driver passes a flag the scorer does not define (e.g. a removed option);
  * the driver omits a flag the scorer marks required;
  * the driver builds a spec missing a key the scorer reads;
  * a scenario declares a permission tier the scorer does not accept.

Exit 1 on any mismatch.
"""
import io
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
DRIVER = HERE / "run-sessions.sh"
SCORER = HERE / "score_session.py"

failures: list[str] = []


def read(p: pathlib.Path) -> str:
    with io.open(p, encoding="utf-8") as fh:
        return fh.read()


def scorer_argparse() -> tuple[set[str], set[str], set[str], set[str]]:
    """Return (all_flags, required_flags, spec_keys_read, accepted_tiers)."""
    text = read(SCORER)
    all_flags: set[str] = set()
    required: set[str] = set()
    # add_argument("--flag", ... required=True ...) — the option string is first.
    for m in re.finditer(r'add_argument\(\s*"(--[a-z][a-z-]*)"([^)]*)\)', text):
        flag, tail = m.group(1), m.group(2)
        all_flags.add(flag)
        if "required=True" in tail:
            required.add(flag)
    spec_keys = set(re.findall(r'spec\.get\(\s*"([a-z_]+)"', text))
    tiers_m = re.search(r'TIERS\s*=\s*\(([^)]*)\)', text)
    tiers = set(re.findall(r'"([a-z]+)"', tiers_m.group(1))) if tiers_m else set()
    return all_flags, required, spec_keys, tiers


def driver_scorer_call() -> str:
    """Return the shell text of the driver's scorer invocation (from the
    `"$SCORER"` token to the end of that command's backslash-continued line)."""
    text = read(DRIVER)
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if '"$SCORER"' in line:
            block = [line]
            j = i
            while lines[j].rstrip().endswith("\\") and j + 1 < len(lines):
                j += 1
                block.append(lines[j])
            return "\n".join(block)
    return ""


def main() -> int:
    all_flags, required, spec_keys, tiers = scorer_argparse()
    if not all_flags or not tiers:
        print("contract: could not parse score_session.py argparse/TIERS", file=sys.stderr)
        return 2

    call = driver_scorer_call()
    if not call:
        failures.append("driver: no scorer invocation found in run-sessions.sh")
    driver_flags = set(re.findall(r"(--[a-z][a-z-]*)", call))

    # 1. Every flag the driver passes must be one the scorer defines.
    for f in sorted(driver_flags - all_flags):
        failures.append(f"driver passes unknown/removed scorer flag: {f}")

    # 2. Every required scorer flag must be passed by the driver.
    for f in sorted(required - driver_flags):
        failures.append(f"driver omits required scorer flag: {f}")

    # 3. The spec the driver builds must carry every key the scorer reads.
    #    The driver builds the spec with a jq object literal: `{id:$id, ...}`.
    driver_text = read(DRIVER)
    spec_obj = re.search(r"'\{id:\$id[^']*\}'", driver_text)
    spec_built = set(re.findall(r"(\b[a-z_]+):", spec_obj.group(0))) if spec_obj else set()
    for k in sorted(spec_keys - spec_built):
        failures.append(f"driver spec missing key the scorer reads: {k}")

    # 4. Every scenario's declared tier must be one the scorer accepts.
    #    run_scenario <id> <seed> <pattern> <must_load> <must_not_load> <TIER> ...
    for m in re.finditer(r"^\s+'[^']*'\s+'[^']*'\s+(allow|ask|deny|ignore|none|[a-z]+)\s*\\?\s*$",
                         driver_text, re.MULTILINE):
        tier = m.group(1)
        if tier not in tiers:
            failures.append(f"scenario declares tier '{tier}' the scorer rejects")

    if failures:
        print("driver<->scorer contract: FAILURES")
        for f in failures:
            print("  " + f)
        return 1
    print(f"driver<->scorer contract: OK "
          f"({len(driver_flags)} flags, {len(required)} required, "
          f"{len(spec_keys)} spec keys, tiers={sorted(tiers)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
