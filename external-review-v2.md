# External Repository Review — Round 2

Repository: https://github.com/theptipteacharsripaitoon/claude-template  
Reviewer: OpenAI GPT-5.6 Thinking  
Review type: Independent external reassessment after PR #5  
Reviewed merge commit: `3127a65ae33a44058eb581cb81d955f192d8ec5e`

## Important review status

This document contains an external reviewer’s assessment, not established facts.

Claude must independently reproduce and verify every technical finding against
the current repository commit before changing source files.

Claude may:

- Confirm a finding
- Partly confirm it
- Reject it with evidence
- Mark it not reproducible
- Mark it obsolete if the repository changed
- Treat it as a subjective design preference
- Preserve the current implementation when it is demonstrably better

Do not optimize for the numerical score. Improve only behavior supported by
tests, measurements, current Claude Code documentation, and appropriate
authoritative domain references.

---

# Re-review result

The improved branch is merged into `main` through PR #5 at merge commit
`3127a65ae33a44058eb581cb81d955f192d8ec5e`.

The repository materially improved, but the external reviewer could not confirm
the reported 8.1/10 score.

## Current external score: 7.0/10

| Category | Score |
|---|---:|
| Technical correctness | 8.0 |
| Skill trigger quality | 7.7 |
| Hook correctness | 6.3 |
| Conflict avoidance | 7.8 |
| Safety and permissions | 6.5 |
| Testing and evaluations | 5.8 |
| Context efficiency | 6.5 |
| Team usability | 6.8 |
| Maintainability | 7.8 |
| Public-template readiness | 5.8 |

This is a real improvement from the original 5.9–6.2 range. It appears
reasonable for careful personal use, but it is not yet a 9+ team-ready template.

# What was successfully improved

The merged version now includes:

- A root README, `.gitignore`, `.gitattributes`, changelog, CI workflow, and test directories.
- Current `NotebookEdit` hook coverage instead of the stale settings matcher.
- Clean handling of malformed hook JSON.
- A Stop-hook re-entry guard.
- The clean-worktree Stop-hook crash fix.
- The installer failure-counter fix.
- An approval prompt for direct dependency-install commands.
- Better Airflow authoring/review separation.
- Narrower `git-hygiene` triggers.
- Clear SQL Server/T-SQL labels on `database-review` and `sql-layout`.
- Better production-versus-development qualification in Kubernetes and observability guidance.

The external reviewer also revised one earlier recommendation:

Not every review skill needs to be manual-only. Explicit review skills such as
`api-review`, `airflow-review`, `docker-review`, and `ci-review` may remain
automatic when their descriptions are precise. Manual-only invocation is most
important for workflows that cause broad side effects or lengthy orchestration.

# Confirmed or strongly evidenced remaining problems

## 1. The new CI workflow is failing

The pushed audit commit had a completed `template-tests` workflow with a failure
conclusion. The only job, `hooks-and-catalog`, failed.

The workflow runs:

1. Hook regression tests
2. Installer tests
3. ShellCheck
4. Catalog validation

The external reviewer could not retrieve the failed job log because GitHub
returned `BlobNotFound`, so the exact failed step was not independently
established.

The workflow also appears to violate requirements stated by the repository’s
own `ci-review` skill:

- No explicit `permissions:` block
- No `timeout-minutes`
- PyYAML installed without a pinned version

Claude must inspect the current GitHub Actions run and identify the exact failure
before changing the workflow.

## 2. The secret-scanner same-pattern bypass appears to remain

For each secret pattern, the current scanner appears to:

1. Select only the first matching secret.
2. Select only the first matching line.
3. If that first line contains a fake marker, skip the entire pattern.
4. Never inspect later matches of the same secret type.

Potential reproducer:

```text
EXAMPLE_KEY=AKIAABCDEFGHIJKLMNOP
REAL_KEY=AKIA1234567890ABCDEF
```

If the first AWS-shaped line contains `EXAMPLE`, the scanner may continue to the
next pattern without evaluating the second AWS-shaped value.

Another potential bypass:

```text
AWS_KEY=AKIA1234567890ABCDEF  # example configuration
```

A real secret may be skipped merely because its line contains a fake marker.

The existing tests appear to cover:

- A fake secret alone
- Multiple secrets using different token patterns

They do not appear to cover a fake first match followed by a real second match
of the same pattern.

Claude must reproduce or reject this claim with an executable regression case.

## 3. Protected-file approval still appears non-functional

`protect-files.sh` still appears to hard-block lockfiles, workflows, migrations,
infrastructure, `.gitattributes`, Claude settings, and hooks with exit code 2.

The documented alternatives appear to be:

- Ask the user to edit the file directly
- Restart Claude with a session override
- Remove the rule

Therefore, this flow may still fail:

1. Claude asks for permission.
2. User approves.
3. Claude tries the edit.
4. The hook blocks it anyway.

Dependency installs were converted to a structured `ask` decision, but protected
files were not.

Potential path-matching defects also remain:

- `.env` is matched as a substring, which may block unrelated filenames.
- Allowlist entries are also substring matches, so `.env.example.secret` may be
  allowed merely because it contains `.env.example`.

Claude must determine which protected categories should:

- Always deny
- Ask for approval
- Warn
- Allow

Path matching should be tested with normalized exact basenames, directory
components, or explicit glob semantics.

## 4. Generated projects may not receive root protections

The root `.gitignore` excludes machine-local Claude state, hook logs, `.env`
files, and generated artifacts.

The root `.gitattributes` enforces LF line endings for shell scripts.

However, `claude-init.sh` appears to copy only:

```text
CLAUDE.md
.claude/
```

It does not appear to copy `.gitignore` or `.gitattributes` into generated
projects, then tells users to run `git add -A`.

Therefore the fixes may protect the template repository itself but not projects
created from the template.

Claude must generate a temporary project and inspect the actual generated tree
and staged files before deciding the fix.

## 5. The Stop hook still appears to attribute unrelated dirty files to Claude

`verify-done.sh` appears to use:

```bash
git status --porcelain
```

It then reports those files as changed in the current session.

That may include:

- Files dirty before Claude started
- User edits made in another terminal
- Unrelated work in the same working tree

Blocking mode also appears to use an `if/elif` project detector, so a repository
containing multiple ecosystems may run checks for only one.

It may also print “All verification checks passed” when no applicable checker
was discovered or installed.

The clean-tree failure and re-entry loop were fixed, but session attribution,
polyglot verification, and “no checks ran” reporting require independent tests.

## 6. The universal Definition of Done remains contradictory

The policy still appears to say every task always requires:

- Compiling and running code
- All existing tests
- New happy-path and failure-path tests
- Linter, formatter, and type checker
- A Conventional Commit message
- Execution of the changed code path

Earlier sections describe low-risk documentation tasks and proportional
verification, but the final DoD says all items are always required.

This may be impossible or inappropriate for:

- Code review
- Architecture analysis
- Documentation-only changes
- Typo corrections
- Investigation-only tasks
- Projects without a type checker
- Work where the user did not request a commit

The policy also appears to forbid referencing any function, class, file, or type
not opened during the current session, which may cause unnecessary reading and
context expansion.

Claude should build a task-type applicability matrix and preserve strictness for
behavioral and high-risk work without applying irrelevant requirements to every
task.

## 7. Skill-trigger evaluation is still only a fixture

`tests/skills/trigger-cases.yaml` explicitly states that it is not executable and
requires live Claude Code sessions.

Its `evaluated_runs` list appears empty.

The catalog checker validates:

- YAML frontmatter
- Names
- Description length
- Catalog counts
- Broken links

It does not evaluate whether Claude actually loads the correct skills.

Therefore trigger-quality scores are not yet supported by measured live results.

Claude should run the fixtures against the current Claude Code version and record:

- Expected skills
- Actual skills
- Unexpected skills
- Missing skills
- Precision
- Recall
- Conflict rate

## 8. Side-effect workflow skills may still be better as manual-only

Strong candidates:

- `repository-cleanup`
- `git-hygiene`
- `release-readiness`
- Possibly `verification`

`repository-cleanup` still appears to auto-trigger on phrases such as
“organize the project” and then mandates branch creation, planning files,
approval gates, repeated commits, and verification.

Adding “invoke deliberately” to a description is advisory. It does not enforce
manual invocation.

Claude should decide each skill independently from measured routing behavior,
workflow breadth, and side-effect risk. Do not make all review skills
manual-only as a blanket rule.

## 9. Skill-body contradictions remain

### Docker

The Docker skill appears to say multi-stage builds are the default and permits
some single-stage exceptions, while its Done criteria still require a
multi-stage build unconditionally.

Its description also still appears to include review ownership despite a
separate `docker-review` skill.

### Kubernetes and observability

Kubernetes is better scoped to production, but it may still present HPA as a
general resilience requirement and require readiness to fail based on downstream
dependency availability too broadly.

Dependency-aware readiness can be correct when a service cannot function without
the dependency, but blindly failing all instances during a shared dependency
outage can amplify the incident.

### Database migrations

Engine labeling improved, but the skill may still require every migration to be
reversible and CI to perform `up → down → up`.

That is not universally appropriate when a down migration would destroy or
misrepresent data. Unsafe reversibility may need documented recovery procedures
instead of executable destructive down migrations.

Claude should verify these claims against current authoritative documentation
and preserve useful strict defaults where justified.

## 10. Documentation drift remains

Potential drift includes:

- Hook documentation still describing dependency installs as hard-denied
- Hook documentation omitting `NotebookEdit`
- Documentation still using `claude code`
- Hook file headers still mentioning stale `MultiEdit` semantics
- README test counts not matching the actual suite
- Reports not reflecting current CI status

Claude should compare documentation directly against current implementation.

# Current disposition of all 37 skills

## Strong enough to keep largely as written

- `agent-design`
- `airflow-layout`
- `airflow-review`
- `api-review`
- `ci-review`
- `config-management`
- `dependency-review`
- `design-system`
- `etl-review`
- `fastapi-review`
- `frontend-layout`
- `llm-evaluation`
- `prompt-engineering`
- `python-performance`
- `python-review`
- `security-review`
- `ssis-review`
- `testing`
- `ui-review`

## Good foundation, but still needs narrowing or conditional rules

- `airflow`
- `api-design`
- `database-migrations`
- `database-review`
- `docker`
- `docker-review`
- `documentation`
- `kubernetes`
- `observability`
- `project-layout`
- `python-layout`
- `python-refactor`
- `sql-layout`
- `web-security`

The database naming and routing are now much clearer, so these are refinement
issues rather than fundamental failures.

## Best candidates for deliberate/manual workflows

- `git-hygiene`
- `repository-cleanup`
- `release-readiness`
- `verification`

These coordinate branches, commits, tags, rollbacks, broad scans, or repeated
command execution. They are workflows rather than passive domain knowledge.

# Readiness assessment

| Use case | Current readiness |
|---|---:|
| Learning and personal experimentation | 8/10 |
| Daily personal use | 7/10 |
| Small-team default | 6/10 |
| Public reusable template | 5.5/10 |
| Security-sensitive production use | 5/10 |

The public-template score is also capped because the repository has no license
and states that all rights are reserved until one is added.

# Recommended improvement order

## P0

1. Fix or disprove the same-pattern secret-scanner bypass.
2. Diagnose and fix the failed GitHub Actions run.
3. Ensure generated projects receive `.gitignore` and `.gitattributes`.
4. Replace uncontrolled substring protected-path matching.
5. Make legitimate protected-file operations use structured approval where safe.

## P1

1. Convert the DoD to task-type applicability.
2. Track session-specific edits for the Stop hook.
3. Make verification polyglot.
4. Distinguish “passed,” “failed,” “no checks found,” and “checks unavailable.”
5. Execute skill-routing fixtures in real Claude Code sessions.
6. Make broad side-effect workflows manual-only where evidence supports it.
7. Add a license selected by the owner.

## P2

1. Synchronize hook documentation with implementation.
2. Add explicit short hook timeouts in `settings.json`.
3. Resolve Docker’s multi-stage contradiction.
4. Make Kubernetes readiness and autoscaling requirements contextual.
5. Add versioned sources and benchmark references inside domain skills.

# Conditions for a higher score

After P0 fixes and green CI, the repository could reasonably move into the
7.8–8.2 range.

A score above 9.0 requires:

- Green CI
- No known P0 defect
- No approval-versus-enforcement contradiction
- Hook regression coverage for confirmed failure modes
- Live skill-routing measurements
- Generated-project bootstrap validation
- Task-applicable policy
- Honest documentation of limitations

A score of 9.5 additionally requires:

- Every major category at least 9/10
- No unresolved P1 correctness defect
- Measured trigger precision above 95%
- Measured trigger recall above 90%
- A defined hook threat model
- Dangerous defined cases blocked at 100%
- Legitimate-action false-positive rate below 2%
- Multiple realistic Claude Code session evaluations
- Green CI on the final pushed commit
- A public license selected by the owner
- Clear version and compatibility information

Do not add complexity merely to increase the score.

# Final external judgment

The first Claude iteration was valuable and fixed many real issues.

The pushed repository is substantially better engineered than the original
version, but it is not yet independently verified at 8.1 because:

- CI was failing at the time of review.
- A likely secret-scanning bypass remained.
- Generated projects appeared to miss root protection files.
- Protected-file approval still appeared to require manual editing or restart.
- The universal DoD conflict remained.
- Skill-trigger fixtures had not been executed.

Every finding in this document must be independently tested against the current
repository before implementation.
