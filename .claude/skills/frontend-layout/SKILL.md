---
name: frontend-layout
description: >-
  Use when structuring frontend code — components, hooks, store, utils
  placement, colocation, feature folders, barrel files. Trigger: "organize the
  frontend", "where should this component live", "folder structure for React".
  Do NOT use for backend or general repo structure (project-layout),
  rendered-UI review (ui-review), or shared component governance
  (design-system).

---

# Frontend Layout

Extends `CLAUDE.md`. General structure is owned by [project-layout](../project-layout/SKILL.md) (domain-grouping canonical there); file-naming defaults by `CLAUDE.md` §8. This skill owns the frontend-specific placement conventions.

## Purpose

Frontend code multiplies fast — components beget hooks beget utils. Without placement rules, `components/` becomes a 90-file flat directory nobody can navigate.

## When to use

- Organizing or growing `src/` in a web app; deciding where a new component/hook/util lives; splitting an oversized folder; taming barrel files.

## When NOT to use

- General/monorepo structure → [project-layout](../project-layout/SKILL.md).
- Reviewing what renders → ui-review. Token/component governance → design-system.

## Core rules

- **Baseline tree** (match the repo's existing convention first, `CLAUDE.md` §1): `src/components/` (shared UI), `src/hooks/`, `src/store/`, `src/api/` (client + endpoint wrappers), `src/utils/`, `src/pages/` or `src/routes/` (framework-dictated).
- **Group by feature past ~10 components.** `src/features/<feature>/` holding its components/hooks/api together beats type-folders at scale (domain-grouping canonical: [project-layout](../project-layout/SKILL.md)). Shared-by-3+ pieces graduate to the top-level shared folders.
- **Colocate what changes together:** component + its test + its styles in one folder (`CLAUDE.md` §8 test co-location). A component folder: `order-table/` → `order-table.tsx`, `order-table.test.tsx`, styles.
- **Components render; logic lives in hooks/utils.** Data fetching, transforms, and business rules belong in hooks or `api/` — a component with embedded fetch + transform + render is three files in one (§6 one-thing rule).
- **Barrel files (`index.ts`) with care:** fine as a folder's public API; a finding when they create import cycles or re-export entire trees (breaks tree-shaking, hides dependencies). Never deep-import past another feature's barrel.
- **Route data access through the API layer.** In client-side data-loading (React Query/SWR/raw hooks), components should not scatter `fetch`/`axios` calls — endpoint wrappers in `src/api/` own URLs, types, and error mapping (boundary rule: `CLAUDE.md` §7). Exception: framework server-data contexts fetch by design — React Server Components, Next.js `page.tsx`/route handlers, Remix `loader`s — keep that fetch in the loader/server entry (still typed and centralized), not pushed into leaf client components.
- **Assets near their user:** component-specific assets in the component folder; app-wide assets in `src/assets/`. Generated bundles never committed (ignore list: git-hygiene).

## Cross-references

- [project-layout](../project-layout/SKILL.md) — general structure, domain grouping (canonical)
- `CLAUDE.md` §8 — naming and import conventions

## Done criteria (in addition to CLAUDE.md §14)

- [ ] New files placed per the tree/feature rules; nothing added to a >10-item flat folder without a split proposal.
- [ ] Components free of fetch/business logic; API calls only in the api layer.
- [ ] No new import cycles via barrels (lint or madge evidence when available).
