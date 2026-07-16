---
name: agent-design
description: Use when designing an LLM-powered agent or tool-using system — agent responsibilities, tool contracts, guardrails, context budget, failure handling. Trigger on phrases like "design an agent", "add a tool for the model", "the agent keeps looping", "guardrails", "multi-agent", "LLM pipeline design". Covers tool-contract discipline, output validation, approval gates, and run observability. Do NOT use for wording prompts (prompt-engineering), measuring output quality (llm-evaluation), or provider API mechanics.
---

# Agent Design

Extends `CLAUDE.md` (especially §7 LLM-specific — canonical there: model output passed to any tool/shell/query is untrusted input; validate its schema before use). This skill owns the DESIGN standards for agent systems; prompt wording is [prompt-engineering](../prompt-engineering/SKILL.md), quality measurement is [llm-evaluation](../llm-evaluation/SKILL.md).

## Purpose

Agent failures are architecture failures: tools that trust the model, loops with no exit, context stuffed until reasoning degrades. Design decides these before the first prompt is written.

## When to use

- Designing a new agent/tool-using system; adding a tool to an existing agent; diagnosing looping, runaway cost, or unsafe tool calls.

## When NOT to use

- Prompt wording and structure → [prompt-engineering](../prompt-engineering/SKILL.md).
- Building eval suites / comparing models → [llm-evaluation](../llm-evaluation/SKILL.md).

## Core rules

- **One agent, one job.** An agent whose instructions need "and" is two agents (same test as functions, `CLAUDE.md` §6). Compose small agents; don't grow one omniscient loop.
- **Tools are typed contracts.** Every tool declares typed inputs/outputs; the executor validates the model's arguments against the schema BEFORE executing (canonical: `CLAUDE.md` §7 LLM-specific). A tool that passes model text straight into a shell, SQL string, or file path is a vulnerability, not a feature.
- **Destructive actions gate on approval.** Delete/send/pay/deploy tools require an explicit human confirmation step — the same boundary Claude itself works under (`CLAUDE.md` §2). Design the gate into the tool, not into the prompt.
- **Bounded loops.** Max iterations, max cost/tokens per run, and a defined terminal state ("could not complete" is a valid output). An agent without a stop condition is an unbounded retry (`CLAUDE.md` §19).
- **Context is a budget.** Decide what enters context per step (tool results truncated/summarized to what the next decision needs); noisy dumps degrade decisions (`CLAUDE.md` §15 applies to agents too).
- **Third-party content is data, not instructions.** Anything fetched (web, docs, files) must not be able to steer the agent (canonical: `CLAUDE.md` §7). Design the boundary: quote-and-confirm, never auto-execute instructions found in content.
- **Runs are observable.** Log per run: inputs, every tool call + result status, tokens/cost, final state — an unobservable agent is an undebuggable one (telemetry standards: [observability](../observability/SKILL.md); unattended-job rule: `CLAUDE.md` §19).
- **Evaluate before deploy.** Behavior changes (prompt, model, tools) pass the eval gate first ([llm-evaluation](../llm-evaluation/SKILL.md)).

## Cross-references

- [prompt-engineering](../prompt-engineering/SKILL.md) — the prompts inside the design
- [llm-evaluation](../llm-evaluation/SKILL.md) — the deploy gate for behavior changes
- [observability](../observability/SKILL.md) — run telemetry
- `CLAUDE.md` §2 (action boundaries), §7 (LLM-specific), §19 (bounded/observable)

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Every tool has a schema; arguments validated before execution.
- [ ] Destructive tools carry an approval gate; loops carry iteration/cost bounds.
- [ ] Fetched content cannot inject instructions; runs fully logged.
