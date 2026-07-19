#!/usr/bin/env python3
"""Live skill-routing evaluation over tests/skills/trigger-cases.yaml.

For every fixture case this seeds a domain-representative scratch repo
(seed-repo.sh), runs the prompt through headless `claude -p` N times
(default 3), extracts which skills the model loaded (Skill tool_use events
in the stream-json output), and scores routing quality.

Definitions (recorded in the summary):
  required_ok   every skill in must_load was loaded            (per run)
  forbidden_hit any skill in must_not_load was loaded          (per run)
  no_load       must_load is non-empty but nothing loaded      (per run)
  extra         loaded - must_load - allowed_companions        (per run)
  recall        mean(required_ok) over runs with must_load
  precision     sum(len(loaded & (must|allowed))) / sum(len(loaded))
                over runs that loaded anything
  conflict_rate mean(forbidden_hit) over all runs
  no_load_rate  mean(no_load) over runs with must_load
  stability     share of cases whose N runs loaded identical skill sets

Needs an authenticated Claude Code CLI; this is a local evaluation, not a
CI step. Results go to tests/skills/results/ as JSONL (per run) plus a
summary JSON; append the summary to `evaluated_runs` in trigger-cases.yaml.

Usage: python tests/skills/routing/run_eval.py [--runs 3] [--only CASE_ID]
"""

import argparse
import datetime as dt
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

import yaml

HERE = pathlib.Path(__file__).resolve().parent
FIXTURE = HERE.parent / "trigger-cases.yaml"
RESULTS_DIR = HERE.parent / "results"
SEED = HERE / "seed-repo.sh"
RUN_TIMEOUT_S = 300

# Every top-level YAML key is a cluster of cases EXCEPT this one (run metadata),
# so a new cluster is discovered automatically — no hardcoded list to update.
NON_CLUSTER_KEYS = {"evaluated_runs"}


def load_cases() -> list[dict]:
    with open(FIXTURE, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    cases = []
    seen: dict[str, str] = {}  # id -> cluster, to reject duplicates
    for cluster, entries in doc.items():
        if cluster in NON_CLUSTER_KEYS or not isinstance(entries, list):
            continue
        for case in entries:
            if "id" not in case:
                sys.exit(f"fixture case without id in {cluster}: {case.get('prompt')!r}")
            cid = case["id"]
            if cid in seen:
                sys.exit(
                    f"duplicate case id {cid!r} in clusters {seen[cid]!r} and {cluster!r}"
                )
            seen[cid] = cluster
            cases.append(
                {
                    "cluster": cluster,
                    "id": cid,
                    "prompt": case["prompt"],
                    "must_load": case.get("must_load") or [],
                    "must_not_load": case.get("must_not_load") or [],
                    "allowed_companions": case.get("allowed_companions") or [],
                }
            )
    return cases


def claude_version(claude: str) -> str | None:
    """Best-effort `claude --version` -> the version token, or None."""
    try:
        out = subprocess.run(
            [claude, "--version"], capture_output=True, text=True, timeout=30
        ).stdout.strip()
    except (subprocess.SubprocessError, OSError):
        return None
    # Output looks like "2.1.214 (Claude Code)"; take the leading version token.
    return out.split()[0] if out else None


def parse_stream(lines: list[str]) -> dict:
    """Pure extraction over stream-json output lines.

    Returns loaded skills, model/cc_version provenance, error events, and —
    critically — anomaly signals: `malformed` (lines that are not valid JSON
    objects) and `saw_result` (whether a terminal `result` event arrived).
    A parse failure must surface as an anomaly, never silently score as a
    valid "nothing loaded" run; run_once turns anomalies into errored rows.
    """
    out = {
        "loaded": [],
        "model": None,
        "cc_version": None,
        "is_error": False,
        "error": None,
        "malformed": 0,
        "saw_result": False,
    }
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if not line.startswith("{"):
            out["malformed"] += 1
            continue
        try:
            evt = json.loads(line)
        except json.JSONDecodeError:
            out["malformed"] += 1
            continue
        if not isinstance(evt, dict):
            out["malformed"] += 1
            continue
        if evt.get("type") == "system" and evt.get("subtype") == "init":
            out["model"] = evt.get("model")
            out["cc_version"] = evt.get("version")
        if evt.get("type") == "assistant":
            content = (evt.get("message") or {}).get("content") or []
            if not isinstance(content, list):
                out["malformed"] += 1
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "tool_use" and block.get("name") == "Skill":
                    skill = (block.get("input") or {}).get("skill")
                    if skill:
                        out["loaded"].append(skill)
        if evt.get("type") == "result":
            out["saw_result"] = True
            if evt.get("is_error"):
                out["is_error"] = True
                out["error"] = str(evt.get("result"))[:300]
    out["loaded"] = sorted(set(out["loaded"]))
    return out


def stream_anomaly(parsed: dict) -> str | None:
    """Error string when the stream itself is unusable evidence, else None."""
    problems = []
    if parsed["malformed"]:
        problems.append(f"{parsed['malformed']} malformed stream line(s)")
    if not parsed["saw_result"]:
        problems.append("no terminal result event")
    return "; ".join(problems) if problems else None


def run_once(claude: str, bash: str, case: dict, run_no: int) -> dict:
    row = {
        "case_id": case["id"],
        "cluster": case["cluster"],
        "run": run_no,
        "prompt": case["prompt"],
        "must_load": case["must_load"],
        "allowed_companions": case["allowed_companions"],
        "must_not_load": case["must_not_load"],
        "loaded": [],
        "model": None,
        "cc_version": None,
        "is_error": False,
        "error": None,
        "duration_s": None,
    }
    with tempfile.TemporaryDirectory(prefix=f"route-{case['id']}-") as tmp:
        seeded = pathlib.Path(tmp) / "repo"
        subprocess.run(
            [bash, str(SEED), case["id"], str(seeded)],
            check=True,
            capture_output=True,
            timeout=120,
        )
        start = dt.datetime.now(dt.timezone.utc)
        try:
            proc = subprocess.run(
                [
                    claude,
                    "-p",
                    case["prompt"],
                    "--output-format",
                    "stream-json",
                    "--verbose",
                    "--setting-sources",
                    "project",
                ],
                cwd=seeded,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=RUN_TIMEOUT_S,
            )
        except subprocess.TimeoutExpired:
            row["is_error"] = True
            row["error"] = f"timeout after {RUN_TIMEOUT_S}s"
            return row
        row["duration_s"] = round(
            (dt.datetime.now(dt.timezone.utc) - start).total_seconds(), 1
        )
        parsed = parse_stream(proc.stdout.splitlines())
        row["loaded"] = parsed["loaded"]
        row["model"] = parsed["model"]
        row["cc_version"] = parsed["cc_version"]
        row["is_error"] = parsed["is_error"]
        row["error"] = parsed["error"]
        anomaly = stream_anomaly(parsed)
        if anomaly and not row["is_error"]:
            # An unusable stream is an ERRORED run (excluded from metrics,
            # counted in runs_errored) — never a scored no-load.
            row["is_error"] = True
            row["error"] = f"stream anomaly: {anomaly}"
        if proc.returncode != 0 and not row["is_error"]:
            row["is_error"] = True
            row["error"] = f"claude exited {proc.returncode}: {proc.stderr[:300]}"
    return row


def score(row: dict) -> dict:
    loaded = set(row["loaded"])
    must = set(row["must_load"])
    allowed = must | set(row["allowed_companions"])
    row["required_ok"] = must.issubset(loaded)
    row["forbidden_hit"] = sorted(loaded & set(row["must_not_load"]))
    row["no_load"] = bool(must) and not loaded
    row["extra"] = sorted(loaded - allowed)
    return row


def summarize(rows: list[dict]) -> dict:
    ok_rows = [r for r in rows if not r["is_error"]]
    with_must = [r for r in ok_rows if r["must_load"]]
    with_load = [r for r in ok_rows if r["loaded"]]
    loaded_total = sum(len(r["loaded"]) for r in with_load)
    good_total = sum(len(r["loaded"]) - len(r["extra"]) for r in with_load)
    by_case: dict[str, list] = {}
    for r in ok_rows:
        by_case.setdefault(r["case_id"], []).append(tuple(r["loaded"]))
    stable = sum(1 for sets in by_case.values() if len(set(sets)) == 1)
    return {
        "runs_total": len(rows),
        "runs_errored": len(rows) - len(ok_rows),
        "recall": round(
            sum(r["required_ok"] for r in with_must) / len(with_must), 3
        )
        if with_must
        else None,
        "precision": round(good_total / loaded_total, 3) if loaded_total else None,
        "conflict_rate": round(
            sum(bool(r["forbidden_hit"]) for r in ok_rows) / len(ok_rows), 3
        )
        if ok_rows
        else None,
        "no_load_rate": round(
            sum(r["no_load"] for r in with_must) / len(with_must), 3
        )
        if with_must
        else None,
        "stability": round(stable / len(by_case), 3) if by_case else None,
        "cases": len(by_case),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--only", help="run a single case id")
    ap.add_argument(
        "--min-recall", type=float, help="exit non-zero if recall is below this"
    )
    ap.add_argument(
        "--max-conflict", type=float, help="exit non-zero if conflict_rate exceeds this"
    )
    ap.add_argument(
        "--fail-on-miss",
        action="store_true",
        help="exit non-zero if any non-errored run is a MISS (required skill not loaded or a forbidden one loaded)",
    )
    ap.add_argument(
        "--fail-on-error",
        action="store_true",
        help="exit non-zero if any run errored (timeout, nonzero exit, error event, or stream anomaly)",
    )
    args = ap.parse_args()

    claude = shutil.which("claude")
    bash = shutil.which("bash")
    if not claude or not bash:
        sys.exit("need `claude` and `bash` on PATH")

    cases = load_cases()
    if args.only:
        cases = [c for c in cases if c["id"] == args.only]
        if not cases:
            sys.exit(f"no case with id {args.only}")

    RESULTS_DIR.mkdir(exist_ok=True)
    # Seconds precision + an explicit collision guard so a same-timeframe rerun
    # never silently overwrites a prior result file.
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%S")
    suffix = ""
    n = 1
    while (RESULTS_DIR / f"routing-{stamp}{suffix}.jsonl").exists():
        suffix = f"-{n}"
        n += 1
    stamp = f"{stamp}{suffix}"
    out_jsonl = RESULTS_DIR / f"routing-{stamp}.jsonl"
    out_summary = RESULTS_DIR / f"routing-{stamp}-summary.json"

    rows = []
    with open(out_jsonl, "w", encoding="utf-8") as fh:
        for case in cases:
            for run_no in range(1, args.runs + 1):
                row = score(run_once(claude, bash, case, run_no))
                rows.append(row)
                fh.write(json.dumps(row, ensure_ascii=False) + "\n")
                fh.flush()
                status = "ERR" if row["is_error"] else (
                    "ok" if row["required_ok"] and not row["forbidden_hit"] else "MISS"
                )
                print(
                    f"[{status}] {case['id']} run{run_no}: loaded={row['loaded']}"
                    + (f" error={row['error']}" if row["error"] else ""),
                    flush=True,
                )

    summary = summarize(rows)
    # Prefer the version reported in the stream; fall back to `claude --version`
    # so provenance is captured automatically instead of hand-entered.
    cc_version = next((r["cc_version"] for r in rows if r["cc_version"]), None)
    if not cc_version:
        cc_version = claude_version(claude)
    meta = {
        "date": stamp,
        "cc_version": cc_version,
        "model": next((r["model"] for r in rows if r["model"]), None),
        "runs_per_case": args.runs,
        "results_file": out_jsonl.name,
        **summary,
    }
    with open(out_summary, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2, ensure_ascii=False)
    print(json.dumps(meta, indent=2, ensure_ascii=False))

    # Optional gates: exit non-zero so a routing regression can fail a check.
    failures = []
    if args.min_recall is not None and (summary["recall"] or 0) < args.min_recall:
        failures.append(f"recall {summary['recall']} < min {args.min_recall}")
    if args.max_conflict is not None and (summary["conflict_rate"] or 0) > args.max_conflict:
        failures.append(
            f"conflict_rate {summary['conflict_rate']} > max {args.max_conflict}"
        )
    if args.fail_on_miss:
        misses = [
            r["case_id"]
            for r in rows
            if not r["is_error"] and (not r["required_ok"] or r["forbidden_hit"])
        ]
        if misses:
            failures.append(f"{len(misses)} MISS run(s): {sorted(set(misses))}")
    if args.fail_on_error and summary["runs_errored"]:
        errs = sorted({r["case_id"] for r in rows if r["is_error"]})
        failures.append(f"{summary['runs_errored']} errored run(s): {errs}")
    if failures:
        sys.exit("routing gate failed: " + "; ".join(failures))


if __name__ == "__main__":
    main()
