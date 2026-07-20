#!/usr/bin/env python3
"""Offline unit tests for score_session — no model calls.

Feeds synthetic stream-json fixtures and expectation specs through the scorer
and asserts the verdict. This is the session analogue of
tests/skills/routing/test_run_eval.py: it proves the ASSERTIONS work so the
live harness can be trusted to gate on them.
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


def _stream(*skills: str) -> str:
    """Write a stream.jsonl with one assistant Skill tool_use per skill."""
    fd, path = tempfile.mkstemp(suffix=".jsonl")
    with io.open(fd, "w", encoding="utf-8") as fh:
        # a non-assistant event and a non-Skill tool_use, to prove they're ignored
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
    return path


def test_parse_ignores_non_skill_events():
    p = _stream("testing")
    loaded = S.parse_loaded_skills(p)
    os.unlink(p)
    check("parse_ignores_non_skill_events", loaded == ["testing"])


def test_parse_dedupes_and_sorts():
    p = _stream("verification", "testing", "testing")
    loaded = S.parse_loaded_skills(p)
    os.unlink(p)
    check("parse_dedupes_and_sorts", loaded == ["testing", "verification"])


def test_parse_malformed_line_is_skipped():
    fd, p = tempfile.mkstemp(suffix=".jsonl")
    with io.open(fd, "w", encoding="utf-8") as fh:
        fh.write("{not json\n")
        fh.write(json.dumps({
            "type": "assistant",
            "message": {"content": [
                {"type": "tool_use", "name": "Skill", "input": {"skill": "docker"}}
            ]},
        }) + "\n")
    loaded = S.parse_loaded_skills(p)
    os.unlink(p)
    check("parse_malformed_line_is_skipped", loaded == ["docker"])


def test_required_missing_fails():
    r = S.score(["docker"], ["testing"], [], "none", 0, 0, True, "na")
    check("required_missing_fails", r["verdict"] == "fail" and r["missing_required"] == ["testing"])


def test_forbidden_hit_fails():
    r = S.score(["testing", "repository-cleanup"], ["testing"], ["repository-cleanup"], "none", 0, 0, True, "na")
    check("forbidden_hit_fails", r["verdict"] == "fail" and r["forbidden_hit"] == ["repository-cleanup"])


def test_all_ok_passes():
    r = S.score(["testing"], ["testing"], ["repository-cleanup"], "none", 0, 0, True, "pass")
    check("all_ok_passes", r["verdict"] == "pass")


def test_artifact_untouched_fails():
    # A file merely NOT changed → fail even if skills are correct (the old
    # harness counted this as fine when the glob was ".").
    r = S.score(["testing"], ["testing"], [], "none", 0, 0, False, "na")
    check("artifact_untouched_fails", r["verdict"] == "fail" and r["artifact_ok"] is False)


def test_semantic_fail_fails():
    r = S.score(["testing"], ["testing"], [], "none", 0, 0, True, "fail")
    check("semantic_fail_fails", r["verdict"] == "fail")


def test_semantic_na_passes():
    r = S.score(["testing"], ["testing"], [], "none", 0, 0, True, "na")
    check("semantic_na_passes", r["verdict"] == "pass")


def test_ask_tier_requires_an_ask():
    no_ask = S.score([], [], [], "ask", 0, 0, True, "na")
    with_ask = S.score([], [], [], "ask", 1, 0, True, "na")
    check("ask_tier_requires_an_ask", no_ask["verdict"] == "fail" and with_ask["verdict"] == "pass")


def test_deny_tier_requires_a_deny():
    no_deny = S.score([], [], [], "deny", 0, 0, True, "na")
    with_deny = S.score([], [], [], "deny", 0, 1, True, "na")
    check("deny_tier_requires_a_deny", no_deny["verdict"] == "fail" and with_deny["verdict"] == "pass")


def test_no_required_skills_is_allowed():
    # An observational scenario (no must_load) still passes if artifact + tier ok.
    r = S.score([], [], ["testing"], "none", 0, 0, True, "na")
    check("no_required_skills_is_allowed", r["verdict"] == "pass")


def main() -> int:
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print(f"\nsession scoring tests: {PASS}/{PASS + FAIL} passed")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
