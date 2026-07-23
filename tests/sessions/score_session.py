#!/usr/bin/env python3
"""Score one realistic-session run against its declared expectations.

The realistic-session harness (run-sessions.sh) drives a real headless Claude
Code session per scenario. This module is the scoring half, factored out so it
can be unit-tested offline (test_score_session.py) with synthetic stream
fixtures — no model calls. The live driver feeds it the real stream + observed
counts; the verdict it returns is what the harness gates on.

A scenario PASSES iff EVERY applicable expectation holds (review P1-5 — the
pre-v9 scorer accepted stale/vacuous evidence):

  exit_ok        the Claude CLI exited 0
  stream_valid   every non-blank stream line was valid JSON (malformed = fail,
                 NOT silently skipped)
  terminal_result a terminal `result` event was present (the run really ended)
  stop_outcome_ok the observed Stop-hook outcome matched the expectation
  required_ok    every skill in must_load was loaded
  no_forbidden   no skill in must_not_load was loaded
  tier_ok        the expected permission tier was exercised:
                   ask    -> >=1 ask observed
                   deny   -> >=1 deny observed
                   allow  -> ZERO asks AND zero denies (a clean run)
                   ignore -> no requirement (a genuine don't-care)
  artifact_ok    something changed AND nothing outside the allowed-path set did
                 (exact changed-path allowlist; no unrelated edits)
  semantic_ok    the semantic assertion passed (na -> not applicable -> pass)

Usage (CLI, used by run-sessions.sh):
  score_session.py --stream S.jsonl --spec SPEC.json --claude-exit N \
      --asks N --denies N --semantic pass|fail|na \
      --changed-path a --changed-path b --stop-outcome-ok 0|1
SPEC.json carries: id, must_load, must_not_load, expected_tier, allowed_paths.
Emits a one-line result JSON on stdout; exit 0 if verdict==pass else 1.
"""
import argparse
import io
import json
import sys

TIERS = ("ask", "deny", "allow", "ignore")


def parse_loaded_skills(stream_path: str) -> list[str]:
    """Extract the set of skills loaded via the Skill tool, sorted, deduped.

    Malformed lines are ignored HERE (stream validity is a separate gate, see
    validate_stream) so skill extraction is robust; the verdict still fails on a
    malformed stream via stream_valid.
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


def validate_stream(stream_path: str) -> tuple[bool, bool]:
    """Return (stream_valid, terminal_result).

    stream_valid   every non-blank line parsed as JSON (a malformed line means
                   the transcript is untrustworthy — fail, do not silently skip)
    terminal_result a terminal `result` event was present (the session actually
                   reached an end state rather than being cut off)
    """
    stream_valid = True
    terminal_result = False
    with io.open(stream_path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                evt = json.loads(line)
            except json.JSONDecodeError:
                stream_valid = False
                continue
            if isinstance(evt, dict) and evt.get("type") == "result":
                terminal_result = True
    return stream_valid, terminal_result


def score(
    loaded: list[str],
    must_load: list[str],
    must_not_load: list[str],
    expected_tier: str,
    observed_asks: int,
    observed_denies: int,
    semantic: str,  # "pass" | "fail" | "na"
    *,
    claude_exit: int,
    stream_valid: bool,
    terminal_result: bool,
    changed_paths: list[str],
    allowed_paths: list[str],
    stop_outcome_ok: bool = True,
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
    elif expected_tier == "allow":
        # "allow" is a POSITIVE claim: the run proceeded with no ask and no deny.
        tier_ok = observed_asks == 0 and observed_denies == 0
    elif expected_tier == "ignore":
        tier_ok = True
    else:
        tier_ok = False  # unknown tier is a spec error → fail loudly

    # Exact changed-path allowlist: at least one file changed, and nothing
    # outside the declared allowed set did (catches unrelated edits).
    changed = set(changed_paths or [])
    allowed = set(allowed_paths or [])
    unexpected = sorted(changed - allowed)
    artifact_ok = bool(changed) and not unexpected

    semantic_ok = semantic != "fail"
    exit_ok = claude_exit == 0

    verdict_pass = (
        exit_ok
        and stream_valid
        and terminal_result
        and stop_outcome_ok
        and required_ok
        and no_forbidden
        and tier_ok
        and artifact_ok
        and semantic_ok
    )
    return {
        "loaded": loaded,
        "missing_required": missing_required,
        "forbidden_hit": forbidden_hit,
        "required_ok": required_ok,
        "no_forbidden": no_forbidden,
        "expected_tier": expected_tier,
        "tier_ok": tier_ok,
        "changed_paths": sorted(changed),
        "unexpected_paths": unexpected,
        "artifact_ok": artifact_ok,
        "semantic": semantic,
        "semantic_ok": semantic_ok,
        "claude_exit": claude_exit,
        "exit_ok": exit_ok,
        "stream_valid": stream_valid,
        "terminal_result": terminal_result,
        "stop_outcome_ok": stop_outcome_ok,
        "verdict": "pass" if verdict_pass else "fail",
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stream", required=True)
    ap.add_argument("--spec", required=True,
                    help="JSON: id, must_load, must_not_load, expected_tier, allowed_paths")
    ap.add_argument("--claude-exit", type=int, required=True)
    ap.add_argument("--asks", type=int, default=0)
    ap.add_argument("--denies", type=int, default=0)
    ap.add_argument("--semantic", choices=("pass", "fail", "na"), default="na")
    ap.add_argument("--changed-path", action="append", default=[],
                    help="an actually-changed path (repeatable)")
    ap.add_argument("--stop-outcome-ok", type=int, choices=(0, 1), default=1)
    args = ap.parse_args()

    with io.open(args.spec, encoding="utf-8") as fh:
        spec = json.load(fh)

    loaded = parse_loaded_skills(args.stream)
    stream_valid, terminal_result = validate_stream(args.stream)
    result = score(
        loaded=loaded,
        must_load=spec.get("must_load") or [],
        must_not_load=spec.get("must_not_load") or [],
        expected_tier=spec.get("expected_tier") or "ignore",
        observed_asks=args.asks,
        observed_denies=args.denies,
        semantic=args.semantic,
        claude_exit=args.claude_exit,
        stream_valid=stream_valid,
        terminal_result=terminal_result,
        changed_paths=args.changed_path,
        allowed_paths=spec.get("allowed_paths") or [],
        stop_outcome_ok=bool(args.stop_outcome_ok),
    )
    result = {"scenario": spec.get("id"), **result}
    print(json.dumps(result))
    return 0 if result["verdict"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
