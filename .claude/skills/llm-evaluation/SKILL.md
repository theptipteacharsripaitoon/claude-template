---
name: llm-evaluation
description: >-
  Use when measuring LLM output quality — building eval sets, judging outputs,
  comparing prompts or models, catching regressions before deploy. Trigger:
  "evaluate the prompt", "did the new model get worse", "LLM as judge",
  "golden set". Do NOT use for writing or fixing the prompt itself
  (prompt-engineering) or agent architecture (agent-design).

---

# LLM Evaluation

Extends `CLAUDE.md`. Owns HOW LLM behavior is measured and gated. What evals are to prompts, tests are to code (`CLAUDE.md` §10 spirit): no behavior change ships unmeasured.

## Purpose

"The new prompt feels better" is not evidence. Evals turn prompt/model changes into pass/fail engineering decisions.

## When to use

- Before shipping any prompt, model, temperature, or tool-description change; building the first eval set for an LLM feature; investigating quality complaints.

## When NOT to use

- Fixing the prompt itself → [prompt-engineering](../prompt-engineering/SKILL.md). Redesigning the system → [agent-design](../agent-design/SKILL.md).

## Core rules

- **Golden set first.** A versioned set of real inputs with expected outputs (or grading criteria) — including the hard cases that broke production before (for Thai pipelines: BE dates, invisible characters, mixed languages). Synthetic-only sets grade a product nobody uses.
- **Graded dimensions, not one score:** correctness, format validity (does it parse against the schema — canonical: `CLAUDE.md` §7), completeness, safety. A change can win one and lose another; a single number hides it.
- **Format validity is binary and automated.** Parse every output; a "mostly valid JSON" rate below 100% is a defect to fix before shipping — usually via constrained/structured decoding or a parse-repair step, occasionally the prompt — never acceptable variance.
- **LLM-as-judge is calibrated, not trusted.** The judge prompt is versioned like any prompt; spot-check judge verdicts against human labels before relying on it; never let a model judge its own outputs with the same prompt under test.
- **Control the randomness.** Deterministic settings where the task allows; where it doesn't, multiple samples per input and report the distribution — a one-sample eval of a stochastic system is a coin flip (`CLAUDE.md` §10 determinism spirit).
- **Regressions are BLOCKING.** New prompt/model must meet or beat the current one on the golden set before deploy — same posture as [verification](../verification/SKILL.md) for code. A knowingly-shipped regression needs the user's explicit acceptance, stated in the PR.
- **Mask PII before sending eval data to external APIs** (canonical: `CLAUDE.md` §7 LLM-specific).
- **Track over time.** Store per-version pass rates; quality drift without a change on your side means the provider moved — you want the graph that proves it.

## Workflow

Build/extend golden set → run current champion → run challenger (one variable changed — [prompt-engineering](../prompt-engineering/SKILL.md)) → compare per dimension → ship / iterate / escalate → record scores with the commit.

## Cross-references

- [prompt-engineering](../prompt-engineering/SKILL.md) — the artifact under test
- [agent-design](../agent-design/SKILL.md) — system-level fixes when evals fail structurally
- [verification](../verification/SKILL.md) — the blocking-gate posture this mirrors
- `CLAUDE.md` §7 (schema validation, PII masking), §10 (test discipline spirit)

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Golden set exists, versioned, includes known-hard cases.
- [ ] Format validity at 100% parse rate; dimensions reported separately.
- [ ] Champion/challenger compared with one variable changed; regression blocked or explicitly accepted.
