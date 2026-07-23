#!/usr/bin/env python3
"""Validate the machine-readable action matrix (policy/action-matrix.yaml).

The matrix is the single source of truth for the guardrail decisions. This gate
checks the matrix is well-formed, that every hook it names exists, and that the
hook corpus actually exercises the decisions the matrix assigns to each hook —
so the contract cannot silently drift from the enforcement it documents
(review P1-8: policy, hooks, corpus, and sessions lacked one contract).

Offline; no model calls, no network. Exit 1 on any failure.
"""
import io
import json
import pathlib
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]
MATRIX = ROOT / "policy" / "action-matrix.yaml"
HOOKS = ROOT / ".claude" / "hooks"
CORPUS = ROOT / "tests" / "hooks" / "corpus.jsonl"

DECISIONS = {"allow", "ask", "deny"}
RISKS = {"low", "medium", "high"}
APPROVAL = {"required", "not-required"}
EXECUTORS = {"claude", "user"}
REQUIRED_FIELDS = (
    "id", "description", "risk", "decision", "current_message_approval",
    "executor", "waiver", "owner", "enforced_by",
)

failures: list[str] = []


def load_matrix() -> dict:
    with io.open(MATRIX, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def check_wellformed(doc: dict) -> list[dict]:
    ops = (doc or {}).get("operations") or []
    if not ops:
        failures.append("matrix has no operations")
        return ops
    seen: set[str] = set()
    for op in ops:
        oid = op.get("id", "<no-id>")
        for field in REQUIRED_FIELDS:
            if field not in op:
                failures.append(f"[{oid}] missing field '{field}'")
        if oid in seen:
            failures.append(f"[{oid}] duplicate id")
        seen.add(oid)
        if op.get("decision") not in DECISIONS:
            failures.append(f"[{oid}] bad decision {op.get('decision')!r}")
        if op.get("risk") not in RISKS:
            failures.append(f"[{oid}] bad risk {op.get('risk')!r}")
        if op.get("current_message_approval") not in APPROVAL:
            failures.append(f"[{oid}] bad current_message_approval")
        if op.get("executor") not in EXECUTORS:
            failures.append(f"[{oid}] bad executor")
        if not isinstance(op.get("waiver"), bool):
            failures.append(f"[{oid}] waiver must be a bool")
    return ops


def check_hooks_exist(ops: list[dict]) -> None:
    for op in ops:
        enf = op.get("enforced_by", "")
        if enf.endswith(".sh") and not (HOOKS / enf).exists():
            failures.append(f"[{op.get('id')}] enforced_by names a missing hook: {enf}")


def load_corpus() -> list[dict]:
    rows = []
    with io.open(CORPUS, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def check_corpus_coverage(ops: list[dict], rows: list[dict]) -> None:
    """Every non-allow decision the matrix assigns to a HOOK must be exercised by
    at least one corpus row for that hook's tool class (Bash -> block-destructive;
    Write -> protect-files / scan-secrets). Guards against the contract claiming
    a decision the tests never prove."""
    bash_decisions = {r.get("expected") for r in rows if r.get("tool") == "Bash"}
    file_decisions = {r.get("expected") for r in rows if r.get("tool") == "Write"}
    for op in ops:
        enf = op.get("enforced_by", "")
        dec = op.get("decision")
        if dec == "allow":
            continue  # allow = no hook opinion; not a corpus obligation
        if enf == "block-destructive.sh" and dec not in bash_decisions:
            failures.append(f"[{op.get('id')}] decision '{dec}' not exercised by any Bash corpus row")
        if enf in ("protect-files.sh", "scan-secrets.sh") and dec not in file_decisions:
            failures.append(f"[{op.get('id')}] decision '{dec}' not exercised by any Write corpus row")


def main() -> int:
    doc = load_matrix()
    ops = check_wellformed(doc)
    check_hooks_exist(ops)
    check_corpus_coverage(ops, load_corpus())
    if failures:
        print("policy_matrix: FAILURES")
        for f in failures:
            print("  " + f)
        return 1
    print(f"policy_matrix: {len(ops)} operations — ALL CHECKS PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
