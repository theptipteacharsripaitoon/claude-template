#!/usr/bin/env python3
"""Unit tests for the routing scoring math (score/summarize), the fixture
loader, and the stream-JSON extraction layer (parse_stream/stream_anomaly).

Runs offline — no `claude`/`bash`/model calls. Plain asserts so it works under
`python tests/skills/routing/test_run_eval.py` or pytest. Guards the metric
definitions the committed results depend on, and guards the parser so a
Claude Code output-schema change fails VISIBLY instead of silently scoring
every run as a valid no-load.
"""
import importlib.util
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("run_eval", HERE / "run_eval.py")
run_eval = importlib.util.module_from_spec(spec)
spec.loader.exec_module(run_eval)

score = run_eval.score
summarize = run_eval.summarize


def _row(**kw):
    base = {
        "case_id": "c",
        "cluster": "k",
        "run": 1,
        "prompt": "p",
        "must_load": [],
        "allowed_companions": [],
        "must_not_load": [],
        "loaded": [],
        "model": "m",
        "cc_version": "9.9.9",
        "is_error": False,
        "error": None,
        "duration_s": 1.0,
    }
    base.update(kw)
    return base


def test_required_ok_and_extra():
    r = score(_row(must_load=["a"], allowed_companions=["b"], loaded=["a", "b", "c"]))
    assert r["required_ok"] is True
    assert r["extra"] == ["c"]  # c is neither required nor allowed
    assert r["forbidden_hit"] == []
    assert r["no_load"] is False


def test_forbidden_hit_and_missing_required():
    r = score(_row(must_load=["a"], must_not_load=["x"], loaded=["x"]))
    assert r["required_ok"] is False
    assert r["forbidden_hit"] == ["x"]
    assert r["no_load"] is False  # something loaded, just the wrong thing


def test_no_load_only_when_must_load_nonempty_and_nothing_loaded():
    assert score(_row(must_load=["a"], loaded=[]))["no_load"] is True
    assert score(_row(must_load=[], loaded=[]))["no_load"] is False


def test_summarize_recall_precision_conflict():
    rows = [
        score(_row(case_id="c1", must_load=["a"], loaded=["a"])),          # ok
        score(_row(case_id="c1", must_load=["a"], loaded=["a", "z"])),     # ok but different set -> c1 unstable, extra z
        score(_row(case_id="c2", must_load=["a"], loaded=["a"])),          # ok, stable
        score(_row(case_id="c3", must_load=["a"], must_not_load=["x"], loaded=["x"])),  # conflict + miss
    ]
    s = summarize(rows)
    # recall: 3 of 4 must-load runs had the required subset (c3 missed)
    assert s["recall"] == round(3 / 4, 3)
    # precision: good loads / all loads = (1+1+1+0) / (1+2+1+1) = 3/5
    assert s["precision"] == round(3 / 5, 3)
    # conflict_rate: 1 of 4 runs hit a forbidden skill
    assert s["conflict_rate"] == round(1 / 4, 3)
    # stability: c1 has two different loaded sets -> unstable; c2, c3 stable => 2/3
    assert s["stability"] == round(2 / 3, 3)
    assert s["cases"] == 3


def test_summarize_excludes_errored_rows():
    rows = [
        score(_row(case_id="c1", must_load=["a"], loaded=["a"])),
        {**_row(case_id="c2", is_error=True, must_load=["a"], loaded=[]),
         "required_ok": False, "forbidden_hit": [], "no_load": True, "extra": []},
    ]
    s = summarize(rows)
    assert s["runs_total"] == 2
    assert s["runs_errored"] == 1
    assert s["recall"] == 1.0  # only the non-errored run counts


def test_load_cases_rejects_duplicate_ids(tmp_path=None):
    import tempfile
    import textwrap

    dup = textwrap.dedent(
        """
        cluster_a:
          - id: same
            prompt: one
            must_load: [x]
        cluster_b:
          - id: same
            prompt: two
            must_load: [y]
        """
    )
    with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False, encoding="utf-8") as fh:
        fh.write(dup)
        path = fh.name
    old = run_eval.FIXTURE
    run_eval.FIXTURE = pathlib.Path(path)
    try:
        raised = False
        try:
            run_eval.load_cases()
        except SystemExit as exc:
            raised = True
            assert "duplicate case id" in str(exc)
        assert raised, "duplicate ids must abort load_cases"
    finally:
        run_eval.FIXTURE = old


# --- stream-JSON extraction fixtures -----------------------------------------
parse_stream = run_eval.parse_stream
stream_anomaly = run_eval.stream_anomaly


def _init_evt():
    return json.dumps(
        {"type": "system", "subtype": "init", "model": "claude-sonnet-5", "version": "2.1.214"}
    )


def _skill_evt(*skills):
    return json.dumps(
        {
            "type": "assistant",
            "message": {
                "content": [
                    {"type": "tool_use", "name": "Skill", "input": {"skill": s}}
                    for s in skills
                ]
            },
        }
    )


def _result_evt(is_error=False, result="done"):
    return json.dumps({"type": "result", "is_error": is_error, "result": result})


def test_parse_one_skill():
    p = parse_stream([_init_evt(), _skill_evt("docker"), _result_evt()])
    assert p["loaded"] == ["docker"]
    assert p["model"] == "claude-sonnet-5"
    assert p["cc_version"] == "2.1.214"
    assert p["is_error"] is False
    assert p["malformed"] == 0 and p["saw_result"] is True
    assert stream_anomaly(p) is None


def test_parse_multiple_skills_deduped_sorted():
    p = parse_stream([_skill_evt("testing", "docker"), _skill_evt("docker"), _result_evt()])
    assert p["loaded"] == ["docker", "testing"]


def test_parse_unrelated_events_load_nothing():
    text_block = json.dumps(
        {"type": "assistant", "message": {"content": [{"type": "text", "text": "hi"}]}}
    )
    other_tool = json.dumps(
        {"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Bash", "input": {"command": "ls"}}]}}
    )
    p = parse_stream([_init_evt(), text_block, other_tool, _result_evt()])
    assert p["loaded"] == []
    assert stream_anomaly(p) is None  # clean stream: a true no-load stays valid


def test_parse_malformed_line_counts_as_anomaly():
    p = parse_stream([_init_evt(), '{"type": "assistant", CORRUPT', _skill_evt("docker"), _result_evt()])
    assert p["loaded"] == ["docker"]  # later events still parsed
    assert p["malformed"] == 1
    assert "malformed" in stream_anomaly(p)


def test_parse_error_event_captured():
    p = parse_stream([_init_evt(), _result_evt(is_error=True, result="boom")])
    assert p["is_error"] is True
    assert "boom" in p["error"]


def test_parse_missing_skill_input_not_counted_no_crash():
    no_input = json.dumps(
        {"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Skill", "input": {}}]}}
    )
    null_input = json.dumps(
        {"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Skill"}]}}
    )
    p = parse_stream([no_input, null_input, _result_evt()])
    assert p["loaded"] == []
    assert stream_anomaly(p) is None


def test_parse_schema_variation_fails_visibly():
    # content not a list / message absent / top-level non-object: none of these
    # may crash, and none may silently pass as a clean stream.
    weird_content = json.dumps({"type": "assistant", "message": {"content": "oops"}})
    no_message = json.dumps({"type": "assistant"})
    non_object = json.dumps(["not", "an", "object"])
    p = parse_stream([weird_content, no_message, non_object, _result_evt()])
    assert p["loaded"] == []
    assert p["malformed"] >= 2  # weird content + non-object are anomalies
    assert stream_anomaly(p) is not None


def test_parse_garbage_only_stream_is_anomalous_not_noload():
    p = parse_stream(["plain text banner", "% not json", ""])
    assert p["loaded"] == []
    assert p["saw_result"] is False
    a = stream_anomaly(p)
    assert a is not None and "no terminal result" in a


def test_parse_empty_stream_missing_result_is_anomalous():
    # A stream that just ends (crash before the result event) must not score.
    p = parse_stream([_init_evt(), _skill_evt("docker")])
    assert stream_anomaly(p) is not None


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"PASS {t.__name__}")
        except AssertionError as exc:
            failed += 1
            print(f"FAIL {t.__name__}: {exc}")
    print(f"\nrouting scoring tests: {len(tests) - failed}/{len(tests)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
