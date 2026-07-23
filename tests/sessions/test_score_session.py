#!/usr/bin/env python3
"""Offline unit tests for score_session — no model calls.

Feeds synthetic stream-json fixtures and expectation specs through the scorer
and asserts the verdict. Proves the (stricter, v9) ASSERTIONS work so the live
harness can be trusted to gate on them (review P1-5).
"""
import io
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import score_session as S  # noqa: E402

PASS = 0
FAIL = 0


def check(name: str, cond: bool) -> None:
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"PASS {name}")
    else:
        FAIL += 1
        print(f"FAIL {name}")


def _stream(*skills: str, terminal: bool = True, malformed: bool = False) -> str:
    """Write a stream.jsonl: a system init, a non-Skill tool_use (ignored), one
    assistant Skill event per skill, optionally a malformed line, and optionally
    a terminal `result` event."""
    fd, path = tempfile.mkstemp(suffix=".jsonl")
    with io.open(fd, "w", encoding="utf-8") as fh:
        fh.write(json.dumps({"type": "system", "subtype": "init"}) + "\n")
        fh.write(json.dumps({
            "type": "assistant",
            "message": {"content": [
                {"type": "tool_use", "name": "Bash", "input": {"command": "ls"}}
            ]},
        }) + "\n")
        for sk in skills:
            fh.write(json.dumps({
                "type": "assistant",
                "message": {"content": [
                    {"type": "tool_use", "name": "Skill", "input": {"skill": sk}}
                ]},
            }) + "\n")
        if malformed:
            fh.write("{not json\n")
        if terminal:
            fh.write(json.dumps({"type": "result", "subtype": "success"}) + "\n")
    return path


def _score(**over):
    """A baseline ALL-PASS score() call; override one field per test."""
    base = dict(
        loaded=["testing"], must_load=["testing"], must_not_load=[],
        expected_tier="ignore", observed_asks=0, observed_denies=0, semantic="na",
        claude_exit=0, stream_valid=True, terminal_result=True,
        changed_paths=["a.py"], allowed_paths=["a.py"], stop_outcome_ok=True,
    )
    base.update(over)
    return S.score(
        base["loaded"], base["must_load"], base["must_not_load"], base["expected_tier"],
        base["observed_asks"], base["observed_denies"], base["semantic"],
        claude_exit=base["claude_exit"], stream_valid=base["stream_valid"],
        terminal_result=base["terminal_result"], changed_paths=base["changed_paths"],
        allowed_paths=base["allowed_paths"], stop_outcome_ok=base["stop_outcome_ok"],
    )


# --- stream parsing / validation -------------------------------------------
def test_parse_ignores_non_skill_events():
    p = _stream("testing"); loaded = S.parse_loaded_skills(p); os.unlink(p)
    check("parse_ignores_non_skill_events", loaded == ["testing"])


def test_parse_dedupes_and_sorts():
    p = _stream("verification", "testing", "testing"); loaded = S.parse_loaded_skills(p); os.unlink(p)
    check("parse_dedupes_and_sorts", loaded == ["testing", "verification"])


def test_validate_stream_ok():
    p = _stream("docker"); sv, tr = S.validate_stream(p); os.unlink(p)
    check("validate_stream_ok", sv is True and tr is True)


def test_validate_stream_malformed_is_invalid():
    # v9 contract flip: a malformed line makes the stream INVALID (was silently
    # skipped and accepted before).
    p = _stream("docker", malformed=True); sv, tr = S.validate_stream(p); os.unlink(p)
    check("validate_stream_malformed_is_invalid", sv is False)


def test_validate_stream_no_terminal():
    p = _stream("docker", terminal=False); sv, tr = S.validate_stream(p); os.unlink(p)
    check("validate_stream_no_terminal", sv is True and tr is False)


# --- verdict: baseline + each gate -----------------------------------------
def test_baseline_all_ok_passes():
    check("baseline_all_ok_passes", _score()["verdict"] == "pass")


def test_nonzero_exit_fails():
    check("nonzero_exit_fails", _score(claude_exit=1)["verdict"] == "fail")


def test_invalid_stream_fails():
    check("invalid_stream_fails", _score(stream_valid=False)["verdict"] == "fail")


def test_missing_terminal_fails():
    check("missing_terminal_fails", _score(terminal_result=False)["verdict"] == "fail")


def test_bad_stop_outcome_fails():
    check("bad_stop_outcome_fails", _score(stop_outcome_ok=False)["verdict"] == "fail")


def test_required_missing_fails():
    r = _score(loaded=["docker"], must_load=["testing"])
    check("required_missing_fails", r["verdict"] == "fail" and r["missing_required"] == ["testing"])


def test_forbidden_hit_fails():
    r = _score(loaded=["testing", "repository-cleanup"], must_not_load=["repository-cleanup"])
    check("forbidden_hit_fails", r["verdict"] == "fail" and r["forbidden_hit"] == ["repository-cleanup"])


# --- tier: ask / deny / allow / ignore -------------------------------------
def test_ask_tier_requires_an_ask():
    no_ask = _score(expected_tier="ask", observed_asks=0)
    with_ask = _score(expected_tier="ask", observed_asks=1)
    check("ask_tier_requires_an_ask", no_ask["verdict"] == "fail" and with_ask["verdict"] == "pass")


def test_deny_tier_requires_a_deny():
    no_deny = _score(expected_tier="deny", observed_denies=0)
    with_deny = _score(expected_tier="deny", observed_denies=1)
    check("deny_tier_requires_a_deny", no_deny["verdict"] == "fail" and with_deny["verdict"] == "pass")


def test_allow_tier_requires_zero_asks_and_denies():
    clean = _score(expected_tier="allow", observed_asks=0, observed_denies=0)
    dirty = _score(expected_tier="allow", observed_asks=1, observed_denies=0)
    check("allow_tier_requires_zero", clean["verdict"] == "pass" and dirty["verdict"] == "fail")


def test_ignore_tier_is_dont_care():
    r = _score(expected_tier="ignore", observed_asks=3, observed_denies=2)
    check("ignore_tier_is_dont_care", r["verdict"] == "pass")


def test_unknown_tier_fails():
    check("unknown_tier_fails", _score(expected_tier="none")["verdict"] == "fail")


# --- artifact: exact changed-path allowlist / no unrelated edits ------------
def test_no_change_fails():
    r = _score(changed_paths=[], allowed_paths=["a.py"])
    check("no_change_fails", r["verdict"] == "fail" and r["artifact_ok"] is False)


def test_unrelated_edit_fails():
    r = _score(changed_paths=["a.py", "secret.env"], allowed_paths=["a.py"])
    check("unrelated_edit_fails", r["verdict"] == "fail" and r["unexpected_paths"] == ["secret.env"])


def test_exact_allowed_change_passes():
    r = _score(changed_paths=[".claude/CLEANUP_PLAN.md"],
               allowed_paths=[".claude/CLEANUP_PLAN.md", ".claude/CLEANUP_EXECUTION.md"])
    check("exact_allowed_change_passes", r["verdict"] == "pass")


# --- semantic ---------------------------------------------------------------
def test_semantic_fail_fails():
    check("semantic_fail_fails", _score(semantic="fail")["verdict"] == "fail")


def test_semantic_na_and_pass_pass():
    check("semantic_na_and_pass_pass",
          _score(semantic="na")["verdict"] == "pass" and _score(semantic="pass")["verdict"] == "pass")


def main() -> int:
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print(f"\nsession scoring tests: {PASS}/{PASS + FAIL} passed")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
