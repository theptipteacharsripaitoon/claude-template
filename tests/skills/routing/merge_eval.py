#!/usr/bin/env python3
"""Merge per-case routing rows (from drive_eval.sh) into the canonical result
pair, scoring through run_eval's own tested summarize().

Usage: python tests/skills/routing/merge_eval.py <percase-dir>
"""
import datetime as dt
import json
import pathlib
import sys

import run_eval as re_


def main() -> None:
    percase = pathlib.Path(sys.argv[1])
    cases = re_.load_cases()
    expected_ids = [c["id"] for c in cases]
    missing = [i for i in expected_ids if not (percase / f"{i}.jsonl").exists()]
    if missing:
        sys.exit(f"incomplete: {len(missing)} case(s) missing rows: {missing}")

    rows = []
    for cid in expected_ids:
        with open(percase / f"{cid}.jsonl", encoding="utf-8") as fh:
            for line in fh:
                if line.strip():
                    rows.append(json.loads(line))

    summary = re_.summarize(rows)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%S")
    out_jsonl = re_.RESULTS_DIR / f"routing-{stamp}.jsonl"
    out_summary = re_.RESULTS_DIR / f"routing-{stamp}-summary.json"
    with open(out_jsonl, "w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")

    cc_version = next((r["cc_version"] for r in rows if r.get("cc_version")), None)
    meta = {
        "date": stamp,
        "cc_version": cc_version,
        "model": next((r["model"] for r in rows if r.get("model")), None),
        "runs_per_case": 3,
        "results_file": out_jsonl.name,
        "repo_commit": re_._git_head(),
        "os": sys.platform,
        "case_count": len(expected_ids),
        "fixture_digest": re_._sha256_file(re_.FIXTURE),
        "descriptions_digest": re_._descriptions_digest(),
        "merged_from_percase": True,
        **summary,
    }
    with open(out_summary, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2, ensure_ascii=False)
    print(json.dumps(meta, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
