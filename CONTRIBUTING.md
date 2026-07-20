# Contributing

Thanks for considering a contribution. This repository is a governance
template — its product is *policy plus enforcement plus the tests that keep
the enforcement honest*. Contributions are judged by that bar: a new rule
without a test is a suggestion, not a change.

## Ground rules

- **License.** The project is licensed under Apache-2.0 (see [LICENSE](LICENSE)).
  By submitting a contribution you agree it is licensed under the same terms
  (Apache-2.0 §5: inbound = outbound). Do not submit code you do not have the
  right to license.
- **Every enforcement change ships with evidence.** A hook edit needs a
  regression case in `tests/hooks/run-tests.sh` (or a corpus row in
  `tests/hooks/corpus.jsonl`) that fails before the change and passes after. A
  skill-description edit needs a routing re-run
  (`python tests/skills/routing/run_eval.py`) or an explicit note that one is
  pending — description text is a routing signal, not prose.
- **No regex widening without a policy row.** Before widening any
  `block-destructive` pattern, state the policy (deny/ask/allow and why) and
  add corpus rows proving the widening does not create a false deny. The
  hooks README's "Bounded guarantee" section is the contract; keep it true.
- **Conventional Commits**, one logical change per commit
  (`CLAUDE.md` §11): `<type>(<scope>): <subject>`.
- Branch from `main` as `<type>/<kebab-description>`; open a PR; never push to
  `main` directly.

## Dev setup

```bash
git clone <fork> && cd claude-template
bash .claude/hooks/install.sh        # verifies deps + runs embedded checks
```

Requirements: bash ≥ 4, jq ≥ 1.6, git, Python ≥ 3.10 (3.12 in CI) with PyYAML.
ShellCheck v0.10.0 — the CI-pinned version; without a local install, use
Docker: `docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:v0.10.0 …`.

## Test suites (run what you touched; CI runs all)

| Change | Run |
|---|---|
| Hooks | `bash tests/hooks/run-tests.sh` and `bash tests/hooks/run-corpus.sh` |
| Installer / bootstrap | `bash tests/installer/run-tests.sh` |
| Skills / catalog | `python tests/skills/check_catalog.py` |
| Routing scoring/parser | `python tests/skills/routing/test_run_eval.py` |
| Committed results | `python tests/skills/routing/test_results_consistency.py` |
| Docs | `python tests/check_links.py` |
| Any `.sh` | ShellCheck v0.10.0 with `-x -P .claude/hooks` |

Live routing evaluation (`run_eval.py`) needs an authenticated Claude Code CLI
and real model calls — it runs locally, never in CI. If your change touches a
skill description, say in the PR whether you re-ran it and attach the summary.

## What gets accepted

- Fixes with a failing-first regression: almost always.
- New destructive-command coverage with corpus rows: yes, if the false-deny
  rate stays 0 on the harmless-prose rows.
- New skills: they must pass `check_catalog.py`, carry a routing-signal
  description (Use-when + triggers + Do-NOT boundary), and add a positive
  fixture case in `tests/skills/trigger-cases.yaml`.
- Style-only churn in hooks or policy text: generally no — the wording is
  load-bearing and measured.
