---
name: prompt-engineering
description: Use when writing or changing a production prompt — system prompts, instruction blocks, few-shot examples, output format specs. Trigger on phrases like "improve this prompt", "the model ignores my instructions", "output format keeps breaking", "write a system prompt", "prompt template". Covers prompt structure, schema-first outputs, injection resistance, and prompt versioning. Do NOT use for agent architecture (agent-design) or building eval suites (llm-evaluation).
---

# Prompt Engineering

Extends `CLAUDE.md` (especially §7 LLM-specific). Owns the WRITING standards for production prompts. System design around the prompt is [agent-design](../agent-design/SKILL.md); proving a prompt change helps is [llm-evaluation](../llm-evaluation/SKILL.md).

## Purpose

Production prompts are code: they have structure, versions, tests, and regressions. Treating them as chat messages is how "it worked yesterday" happens.

## When to use

- Writing a new production prompt; fixing instruction-following or format failures; reviewing a prompt change PR.

## When NOT to use

- Choosing tools/loops/guardrails → [agent-design](../agent-design/SKILL.md).
- Measuring whether a change helped → [llm-evaluation](../llm-evaluation/SKILL.md).

## Core rules

- **Fixed structure, labeled sections:** role → task → constraints → examples → output format. The model finds instructions reliably when they live in predictable places; so do reviewers.
- **Schema-first outputs.** Specify the exact output format (JSON schema, labeled fields) and PARSE it downstream — never regex-mine free text. Consumer code validates the shape before use (canonical: `CLAUDE.md` §7 LLM-specific).
- **Positive instructions.** Say what TO do ("answer in Thai") over long "do not" lists; reserve negations for hard boundaries. Models follow affirmative patterns better.
- **Few-shot examples are load-bearing.** Match them to the real input distribution (include the ugly cases — for Thai data: mixed calendars, invisible characters); a misleading example outweighs a paragraph of instructions. Examples count as production code (`CLAUDE.md` §7 "examples count").
- **Separate instructions from data.** Delimit any retrieved/user content clearly and state that it is data to process, not instructions to follow (canonical: `CLAUDE.md` §7 — third-party content is potentially adversarial). Never concatenate untrusted text into the instruction section.
- **Prompts are versioned artifacts.** They live in git, change via reviewed commits (`CLAUDE.md` §11), and each change states its intent — "tweaked wording" is not a change description.
- **One change at a time.** A prompt edit bundled with a model bump or temperature change is unattributable; split them so the eval can assign cause ([llm-evaluation](../llm-evaluation/SKILL.md)).
- **Token budget stated.** Know the prompt's size and the room left for input/output at the model's context limit; a prompt that grows unboundedly (accreted rules, stale examples) gets pruned like dead code (`CLAUDE.md` §6).

## Workflow

Draft with the fixed structure → run the golden set ([llm-evaluation](../llm-evaluation/SKILL.md)) → compare against current prompt → ship only on non-regression → commit with intent-stating message.

## Cross-references

- [agent-design](../agent-design/SKILL.md) — the system around the prompt
- [llm-evaluation](../llm-evaluation/SKILL.md) — the gate for every prompt change
- `CLAUDE.md` §7 (LLM-specific, examples count), §11 (versioning)

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Fixed section structure; output schema specified and parsed downstream.
- [ ] Untrusted content delimited as data; instructions never concatenated with it.
- [ ] Change shipped alone, eval-gated, committed with stated intent.
