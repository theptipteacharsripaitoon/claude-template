#!/usr/bin/env python3
"""Unit tests for the routing scoring math (score/summarize) and fixture loader.

Runs offline — no `claude`/`bash`/model calls. Plain asserts so it works under
`python tests/skills/routing/test_run_eval.py` or pytest. Guards the metric
definitions the committed results depend on.
"""
import importlib.util
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
