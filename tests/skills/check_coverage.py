#!/usr/bin/env python3
"""Routing-fixture coverage floor (review P1-6 / 9.0 gate).

Every skill must have at least TWO positive cases (paraphrases where it is in
must_load) and at least ONE hard negative (a case where it is in must_not_load,
i.e. a prompt that plausibly looks like it but must NOT load it). Reports the
gap per skill and exits non-zero until the floor is met.

Offline; no model calls. Wired into verify-offline.sh (the fixture now meets the
floor via the coverage_floor cluster in trigger-cases.yaml).
"""
import io
import pathlib
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests" / "skills" / "trigger-cases.yaml"
SKILLS = ROOT / ".claude" / "skills"
MIN_POS = 2
MIN_NEG = 1


def main() -> int:
    skills = sorted(p.parent.name for p in SKILLS.glob("*/SKILL.md"))
    doc = yaml.safe_load(io.open(FIXTURE, encoding="utf-8"))
    pos: dict[str, int] = {s: 0 for s in skills}
    neg: dict[str, int] = {s: 0 for s in skills}
    for cluster, cases in doc.items():
        if cluster == "evaluated_runs" or not isinstance(cases, list):
            continue
        for case in cases:
            for s in case.get("must_load") or []:
                if s in pos:
                    pos[s] += 1
            for s in case.get("must_not_load") or []:
                if s in neg:
                    neg[s] += 1

    gaps = []
    for s in skills:
        if pos[s] < MIN_POS or neg[s] < MIN_NEG:
            gaps.append((s, pos[s], neg[s]))

    print(f"coverage: {len(skills)} skills; "
          f"{len(skills) - len(gaps)} meet the floor (>= {MIN_POS} pos, >= {MIN_NEG} neg)")
    if gaps:
        print(f"below floor ({len(gaps)}):")
        for s, p, n in gaps:
            need = []
            if p < MIN_POS:
                need.append(f"+{MIN_POS - p} pos")
            if n < MIN_NEG:
                need.append(f"+{MIN_NEG - n} neg")
            print(f"  {s:24s} pos={p} neg={n}  need {', '.join(need)}")
        return 1
    print("coverage: ALL CHECKS PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
