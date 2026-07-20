---
name: ui-review
description: >-
  Use when reviewing UI changes before merge — visual evidence, interaction
  states, responsiveness, accessibility, text rendering. Trigger: "review the
  UI change", "does this screen look right", "accessibility check". Do NOT use
  for shared component/token governance (design-system) or frontend folder
  structure (frontend-layout).

---

# UI Review

Extends `CLAUDE.md` §14 — canonical there: UI changes require VISUAL confirmation (screenshot or dev server), not code-reading. This skill owns what that confirmation must cover.

## Purpose

UI bugs live in the states nobody rendered during development: the empty list, the 500 error, the Thai string that wraps nothing like the English mock. Review means seeing them, not imagining them.

## When to use

- Reviewing any PR that changes rendered output; pre-release screen walkthroughs; accessibility passes.

## When NOT to use

- Where code lives → [frontend-layout](../frontend-layout/SKILL.md). Setting up visual-regression tests → [testing](../testing/SKILL.md). Token/component standards → [design-system](../design-system/SKILL.md).

## Review checklist (visual evidence per item — screenshots or live walkthrough)

1. **The state matrix, rendered:** loading / empty / error / success / partial data. A screen shown only in its success state is unreviewed. Error states show actionable messages, never stack traces (`CLAUDE.md` §12).
2. **Real-shaped data:** long names, zero rows, thousands of rows (does it paginate/virtualize?), missing optional fields — and for Thai products: Thai text (no inter-word spaces and taller stacked glyphs — line-box metrics differ from the English mock, so check truncation, wrapping, and clipping rather than assuming the mock's dimensions), Buddhist-calendar dates displayed as users expect.
3. **Responsive breakpoints:** the change at mobile/tablet/desktop widths; *unintended* horizontal scroll on mobile is a finding (the page body scrolling sideways). Intentionally scrollable elements — carousels, wide data grids/tables in their own `overflow-x` container, code blocks — are not, provided the scroll is contained and discoverable.
4. **Accessibility basics:** interactive elements keyboard-reachable with visible focus; images/icons carry labels; form fields have real `<label>`s; color contrast readable; color never the only signal.
5. **Destructive or externally-visible actions confirm:** delete, pay, publish, send, and other hard-to-reverse flows show consequence + confirmation (mirrors `CLAUDE.md` §2 philosophy in the product). An ordinary, reversible save/submit does **not** need a confirmation step — over-confirming trains users to click through; reserve it for actions that lose data, spend money, or are visible to others.
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
