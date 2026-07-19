---
name: design-system
description: >-
  Use when creating or governing shared UI components and design tokens —
  reuse decisions, token usage, component API consistency, deprecating
  components. Trigger: "add a shared component", "should this be a variant",
  "hardcoded colors", "design tokens". Do NOT use for reviewing rendered UI
  (ui-review) or frontend folder structure (frontend-layout).

---

# Design System

Extends `CLAUDE.md`. Owns the governance of SHARED UI: when something becomes a shared component, how tokens are used, how components evolve and retire. Screen review is [ui-review](../ui-review/SKILL.md); placement is [frontend-layout](../frontend-layout/SKILL.md).

## Purpose

Design drift is duplication with pixels: five slightly-different buttons, three grays that should be one. Governance keeps the UI one system instead of an archaeology site.

## When to use

- Adding/changing a shared component; deciding variant-vs-new; token questions; retiring a component; aligning inconsistent UI.

## When NOT to use

- Reviewing a feature screen → [ui-review](../ui-review/SKILL.md). Where files live → [frontend-layout](../frontend-layout/SKILL.md).

## Core rules

- **Reuse before create** (`CLAUDE.md` §1 read-before-write, applied to UI): search the existing components first; the second copy of almost-a-Button is where drift starts. Extend with a variant prop before forking a new component.
- **Variant, not fork.** Behavior/style differences within one concept are props (`variant="danger"`, `size="sm"`); a fork is justified only when the CONCEPT differs. Two components sharing 80% of markup are one component.
- **Tokens over literals.** Colors, spacing, radii, type sizes come from the token set — a hardcoded `#3477eb` or `margin: 13px` in feature code is a finding (magic values, `CLAUDE.md` §6). Missing token → propose the token, don't inline the value.
- **Component APIs read like one library:** consistent prop names across components (`disabled`, `onChange`, `size`), controlled/uncontrolled behavior consistent, sensible defaults. Intent-revealing naming per §6.
- **Shared = documented + tested.** Promotion to shared requires: usage doc with do/don't, states covered ([ui-review](../ui-review/SKILL.md) matrix), a test ([testing](../testing/SKILL.md)), and a11y built in (labels, focus) so consumers inherit it.
- **Deprecate, don't abandon** — the api-design discipline applied to components ([api-design](../api-design/SKILL.md) deprecation cycle as the model): mark deprecated with the replacement named, migrate usages, then remove. A silently-orphaned component gets copy-pasted forever.
- **Breaking a shared component's props = breaking an API:** find all consumers first (the blast-radius habit from ui-review), migrate in the same change or provide the compatible path.

## Cross-references

- [ui-review](../ui-review/SKILL.md) — state matrix and a11y a shared component must pass
- [frontend-layout](../frontend-layout/SKILL.md) — where shared components live
- [api-design](../api-design/SKILL.md) — the deprecation model applied here
- [testing](../testing/SKILL.md) — component tests
- `CLAUDE.md` §1, §6 — reuse and no-magic-values canon

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Existing components searched before any new one; variants preferred over forks.
- [ ] Zero new hardcoded color/spacing literals; tokens proposed where missing.
- [ ] Promoted components documented, tested, accessible; deprecations name their replacement.
