#!/usr/bin/env python3
"""Consistency gate for committed routing evidence. Offline, no model calls.

Guards three invariants the reports rely on:
  1. Every results JSONL has a summary whose metrics recompute EXACTLY from
     the raw rows (re-scored from loaded/must_load/... via run_eval's score/
     summarize, whose math is unit-tested separately) — a hand-edited summary
     or a truncated JSONL fails here.
  2. Every `evaluated_runs` entry in trigger-cases.yaml points at an existing
     results file and repeats that run's summary faithfully (metrics, model,
     runs_per_case, cases). A `cc_version` that the summary file does not back
     must carry a `cc_version_note` explaining its provenance.
  3. The newest full-fixture run (cases == current fixture case count) IS
     recorded in `evaluated_runs` — the authoritative run can't silently
     stay out of the fixture's history again.

Structural checks: unique (case_id, run) pairs, complete 1..runs_per_case run
numbering, and every result case_id present in the current fixture.

Run: python tests/skills/routing/test_results_consistency.py
"""
import importlib.util
import json
import pathlib
import sys

import yaml

HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE.parent / "results"
FIXTURE = HERE.parent / "trigger-cases.yaml"

spec = importlib.util.spec_from_file_location("run_eval", HERE / "run_eval.py")
run_eval = importlib.util.module_from_spec(spec)
spec.loader.exec_module(run_eval)

METRIC_KEYS = ("recall", "precision", "conflict_rate", "no_load_rate", "stability")
failures = []


def fail(msg: str) -> None:
    failures.append(msg)
    print("FAIL:", msg)


def load_rows(jsonl: pathlib.Path) -> list[dict]:
    with open(jsonl, encoding="utf-8") as fh:
        return [json.loads(line) for line in fh if line.strip()]


with open(FIXTURE, encoding="utf-8") as fh:
    fixture = yaml.safe_load(fh)
fixture_ids = {
    case["id"]
    for cluster, entries in fixture.items()
    if cluster != "evaluated_runs" and isinstance(entries, list)
    for case in entries
}
evaluated = fixture.get("evaluated_runs") or []

summaries: dict[str, dict] = {}
for jsonl in sorted(RESULTS.glob("*.jsonl")):
    summary_path = RESULTS / (jsonl.stem + "-summary.json")
    if not summary_path.exists():
        fail(f"{jsonl.name}: no matching summary file")
        continue
    with open(summary_path, encoding="utf-8") as fh:
        summary = json.load(fh)
    summaries[jsonl.name] = summary

    rows = load_rows(jsonl)
    seen: set[tuple] = set()
    per_case: dict[str, set] = {}
    for r in rows:
        key = (r["case_id"], r["run"])
        if key in seen:
            fail(f"{jsonl.name}: duplicate row {key}")
        seen.add(key)
        per_case.setdefault(r["case_id"], set()).add(r["run"])
    expected_runs = set(range(1, summary["runs_per_case"] + 1))
    for cid, runs in per_case.items():
        if runs != expected_runs:
            fail(f"{jsonl.name}: case {cid} has runs {sorted(runs)}, want {sorted(expected_runs)}")
        if cid not in fixture_ids:
            fail(f"{jsonl.name}: case {cid} not in current fixture")

    rescored = [run_eval.score(dict(r)) for r in rows]
    recomputed = run_eval.summarize(rescored)
    for key, want in recomputed.items():
        got = summary.get(key)
        if got != want:
            fail(f"{jsonl.name}: summary {key}={got!r} but recomputed {want!r}")

for entry in evaluated:
    rf = pathlib.Path(entry["results_file"]).name
    if rf not in summaries:
        fail(f"evaluated_runs: results file {rf} does not exist under tests/skills/results/")
        continue
    summary = summaries[rf]
    for key in METRIC_KEYS:
        want = summary.get(key)
        got = entry.get("metrics", {}).get(key)
        if got != want:
            fail(f"evaluated_runs[{rf}]: metrics.{key}={got!r} but summary says {want!r}")
    for key in ("model", "runs_per_case", "cases"):
        if entry.get(key) != summary.get(key):
            fail(f"evaluated_runs[{rf}]: {key}={entry.get(key)!r} but summary says {summary.get(key)!r}")
    if entry.get("cc_version") != summary.get("cc_version") and not entry.get("cc_version_note"):
        fail(
            f"evaluated_runs[{rf}]: cc_version={entry.get('cc_version')!r} not backed by "
            f"summary ({summary.get('cc_version')!r}) and no cc_version_note explains it"
        )

full_runs = sorted(
    (name for name, s in summaries.items() if s.get("cases") == len(fixture_ids)),
    key=lambda name: summaries[name].get("date") or name,
)
if full_runs:
    latest_full = full_runs[-1]
    recorded = {pathlib.Path(e["results_file"]).name for e in evaluated}
    if latest_full not in recorded:
        fail(f"latest full-fixture run {latest_full} is not recorded in evaluated_runs")

print(f"consistency: {len(summaries)} result set(s), {len(evaluated)} evaluated_runs entr(ies), fixture cases={len(fixture_ids)}")
print("consistency: ALL CHECKS PASS" if not failures else f"consistency: {len(failures)} FAILURE(S)")
sys.exit(1 if failures else 0)
