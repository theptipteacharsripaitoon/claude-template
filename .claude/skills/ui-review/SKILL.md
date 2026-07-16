---
name: ui-review
description: Use when reviewing UI changes before merge — visual evidence, interaction states, responsiveness, accessibility, text rendering. Trigger on phrases like "review the UI change", "does this screen look right", "check the new page", "accessibility check", "Thai text overflows". Covers the state matrix, visual-evidence requirements, and a11y basics. Do NOT use for code structure (frontend-layout), visual-regression tooling (testing), or design-token governance (design-system).
---

# UI Review

Extends `CLAUDE.md` §14 — canonical there: UI changes require VISUAL confirmation (screenshot or dev server), not code-reading. This skill owns what that confirmation must cover.

## Purpose

UI bugs live in the states nobody rendered during development: the empty list, the 500 error, the Thai string twice as long as the English mock. Review means seeing them, not imagining them.

## When to use

- Reviewing any PR that changes rendered output; pre-release screen walkthroughs; accessibility passes.

## When NOT to use

- Where code lives → [frontend-layout](../frontend-layout/SKILL.md). Setting up visual-regression tests → [testing](../testing/SKILL.md). Token/component standards → [design-system](../design-system/SKILL.md).

## Review checklist (visual evidence per item — screenshots or live walkthrough)

1. **The state matrix, rendered:** loading / empty / error / success / partial data. A screen shown only in its success state is unreviewed. Error states show actionable messages, never stack traces (`CLAUDE.md` §12).
2. **Real-shaped data:** long names, zero rows, thousands of rows (does it paginate/virtualize?), missing optional fields — and for Thai products: Thai text (longer lines, taller glyphs, no word spaces — check truncation and wrapping), Buddhist-calendar dates displayed as users expect.
3. **Responsive breakpoints:** the change at mobile/tablet/desktop widths; horizontal scroll on mobile is a finding.
4. **Accessibility basics:** interactive elements keyboard-reachable with visible focus; images/icons carry labels; form fields have real `<label>`s; color contrast readable; color never the only signal.
5. **Destructive actions confirm:** delete/submit/pay flows show consequence + confirmation (mirrors `CLAUDE.md` §2 philosophy in the product).
6. **Console clean:** no new errors/warnings in the browser console while walking the change.
7. **Regression guard:** shared-component changes checked where they're REUSED, not just the screen in the PR (blast radius); visual-regression suite updated if one exists ([testing](../testing/SKILL.md)).

## Cross-references

- [testing](../testing/SKILL.md) — E2E and visual-regression tooling
- [design-system](../design-system/SKILL.md) — when review reveals a missing/duplicated component
- [frontend-layout](../frontend-layout/SKILL.md) — when review reveals misplaced logic
- `CLAUDE.md` §12 (user-facing errors), §14 (visual confirmation canonical)

## Done criteria (in addition to CLAUDE.md §14)

- [ ] State matrix rendered and captured; realistic + Thai-shaped data exercised.
- [ ] Keyboard/label/contrast basics pass; destructive flows confirm.
- [ ] Console clean; shared-component blast radius checked.
