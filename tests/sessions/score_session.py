#!/usr/bin/env python3
"""Score one realistic-session run against its declared expectations.

The realistic-session harness (run-sessions.sh) drives a real headless Claude
Code session per scenario. Before v8 it recorded telemetry (skills loaded,
counts, wall-clock) but asserted almost nothing: the outcome check was a path
regex — `.` for two scenarios — so a session that loaded the wrong skill or
merely *touched* a file still counted as fine.

This module is the scoring half, factored out so it can be unit-tested offline
(test_score_session.py) with synthetic stream fixtures — no model calls. The
live driver feeds it the real stream + observed hook counts; the verdict it
returns is what the harness gates on.

A scenario PASSES iff every applicable expectation holds:
  required_ok   every skill in must_load was loaded
  no forbidden  no skill in must_not_load was loaded
  tier_ok       the expected permission tier was exercised
                (ask → >=1 ask observed; deny → >=1 deny; none → no requirement)
  artifact_ok   the expected artifact actually changed
  semantic_ok   the semantic assertion passed (skipped → not applicable → pass)

Usage (CLI, used by run-sessions.sh):
  score_session.py --stream S.jsonl --spec SPEC.json \
      --asks N --denies N --artifact-changed 0|1 --semantic 0|1|na
Emits a one-line result JSON on stdout; exit 0 if verdict==pass else 1.
"""
import argparse
import io
import json
import sys


def parse_loaded_skills(stream_path: str) -> list[str]:
    """Extract the set of skills loaded via the Skill tool, sorted, deduped.

    Mirrors run_eval.py's parser: assistant tool_use events named "Skill",
    reading .input.skill. Malformed lines are skipped, not fatal.
    """
    loaded: set[str] = set()
    with io.open(stream_path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                evt = json.loads(line)
            except json.JSONDecodeError:
                continue
            if evt.get("type") != "assistant":
                continue
            content = (evt.get("message") or {}).get("content") or []
            if not isinstance(content, list):
                continue
            for block in content:
                if (
                    isinstance(block, dict)
                    and block.get("type") == "tool_use"
                    and block.get("name") == "Skill"
                ):
                    skill = (block.get("input") or {}).get("skill")
                    if isinstance(skill, str) and skill:
                        loaded.add(skill)
    return sorted(loaded)


def score(
    loaded: list[str],
    must_load: list[str],
    must_not_load: list[str],
    expected_tier: str,
    observed_asks: int,
    observed_denies: int,
    artifact_changed: bool,
    semantic: str,  # "pass" | "fail" | "na"
) -> dict:
    loaded_set = set(loaded)
    missing_required = sorted(set(must_load) - loaded_set)
    forbidden_hit = sorted(set(must_not_load) & loaded_set)

    required_ok = not missing_required
    no_forbidden = not forbidden_hit

    if expected_tier == "ask":
        tier_ok = observed_asks >= 1
    elif expected_tier == "deny":
        tier_ok = observed_denies >= 1
    else:  # "none"
        tier_ok = True

    artifact_ok = bool(artifact_changed)
    # "na" (no semantic check declared) or "pass" → ok; only "fail" fails.
    semantic_ok = semantic != "fail"

    verdict_pass = (
        required_ok and no_forbidden and tier_ok and artifact_ok and semantic_ok
    )
    return {
        "loaded": loaded,
        "missing_required": missing_required,
        "forbidden_hit": forbidden_hit,
        "required_ok": required_ok,
        "no_forbidden": no_forbidden,
        "expected_tier": expected_tier,
        "tier_ok": tier_ok,
        "artifact_ok": artifact_ok,
        "semantic": semantic,
        "semantic_ok": semantic_ok,
        "verdict": "pass" if verdict_pass else "fail",
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stream", required=True)
    ap.add_argument("--spec", required=True, help="JSON: id, must_load, must_not_load, expected_tier, prompt")
    ap.add_argument("--asks", type=int, default=0)
    ap.add_argument("--denies", type=int, default=0)
    ap.add_argument("--artifact-changed", type=int, choices=(0, 1), required=True)
    ap.add_argument("--semantic", choices=("pass", "fail", "na"), default="na")
    args = ap.parse_args()

    with io.open(args.spec, encoding="utf-8") as fh:
        spec = json.load(fh)

    loaded = parse_loaded_skills(args.stream)
    result = score(
        loaded=loaded,
        must_load=spec.get("must_load") or [],
        must_not_load=spec.get("must_not_load") or [],
        expected_tier=spec.get("expected_tier") or "none",
        observed_asks=args.asks,
        observed_denies=args.denies,
        artifact_changed=bool(args.artifact_changed),
        semantic=args.semantic,
    )
    result = {"scenario": spec.get("id"), **result}
    print(json.dumps(result))
    return 0 if result["verdict"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
