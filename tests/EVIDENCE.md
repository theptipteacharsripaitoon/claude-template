# Live evaluation evidence — regeneration & release floors

The offline suites (run by `tests/verify-offline.sh`, gated in CI) prove the
scorers, parsers, and results-consistency logic. The **live** evaluations —
skill routing and realistic sessions — need an authenticated Claude Code CLI and
real model calls, so they run **out-of-band**, not in CI. Their committed
evidence lives under `tests/skills/results/` and `tests/sessions/results/`.

> **Release rule.** A score above 9 must be earned by evidence generated on the
> **exact release commit**, with valid provenance. Repository-authored prose is
> not evidence. The committed evidence today predates v9 (`repo_commit` ≠ HEAD,
> `cc_version: null`) and must be regenerated on the candidate commit before
> release.

## Regenerating routing evidence

Detached (each case is ~10–15 min wall; 45+ cases → hours). On Windows, launch
with `Start-Process` so it survives the shell:

```bash
# from the repo root, on the candidate commit, with `claude` authenticated
python tests/skills/routing/run_eval.py --runs 3
# → writes tests/skills/results/routing-<UTC>.jsonl + -summary.json
```

Every row now carries immutable provenance (`prompt_sha256`,
`expectation_sha256`, `repo_commit`, `fixture_digest`, `descriptions_digest`,
`os`, `generated_utc`). After the run:

```bash
python tests/skills/routing/test_results_consistency.py   # rows vs current fixture
```

### Routing release floors (per the review)

- every skill recall **≥ 0.90**; macro precision **≥ 0.95**
- conflict rate **≤ 0.01**; non-observational stability **≥ 0.90**; **zero errors**
- coverage: **≥ 2 positive paraphrases + ≥ 1 hard negative per skill**, plus
  collision pairs and composition cases (grow `tests/skills/trigger-cases.yaml`;
  the current 45 cases are below this — expanding the fixture is part of the
  gated run).

## Regenerating session evidence

```bash
bash tests/sessions/run-sessions.sh <out-dir>        # one real session per scenario
```

The scorer (`score_session.py`, unit-tested offline at 22/22) now requires, per
scenario: Claude exit 0, every non-blank stream line valid JSON, a terminal
`result` event, the expected Stop outcome, required/forbidden skills, the
permission tier (`ask`/`deny`/`allow`=zero-asks-and-denies/`ignore`), an exact
changed-path allowlist (no unrelated edits), and the semantic check. The driver
still needs finalizing to feed these inputs and to make the migration/infra
scenarios two-turn (plan-then-confirm) with pristine-red semantic predicates —
best done together with a live run.

## Status

- Offline halves: **done and CI-gated** (scorers, parsers, consistency, matrix,
  corpus, installer, hooks).
- Live regen + fixture expansion + `run-sessions.sh` finalize: **pending
  approval** — they cost real model time and their correctness is only provable
  by running them.
