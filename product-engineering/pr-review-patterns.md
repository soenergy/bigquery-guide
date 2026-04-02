# PR Review Patterns — What Reviewers Flag

Recurring review feedback observed on fe-nova and fe-monorepo PRs. Use this to pre-empt common review comments before raising PRs.

---

## 1. Always run codegen after GraphQL changes

If you modify files in `/api/backoffice/queries`, `/api/backoffice/mutations`, `/api/hasura/queries`, or `/api/hasura/mutations` — run `pnpm run codegen:backoffice` or `pnpm run codegen:hasura` respectively. NEVER edit files in `/api/backoffice/generated` or `/api/hasura/generated` directly.

**Why:** @mt-5 flagged this on #1823 — GraphQL query was changed but generated types weren't regenerated. The mismatch between query and types causes runtime issues.

**How to apply:** After any `.graphql` file change, run the corresponding codegen command before committing.

---

## 2. Use existing type abstractions — don't inline logic in components

Before adding meter-type checks, fuel-type logic, or similar conditions inline in a Vue component, check if there are already getters or type helpers in the relevant `*.types.ts` file (e.g., `meterpointDetails.types.ts`). Add new getters there instead of duplicating logic in the component.

**Why:** @mt-5 flagged on #1819 — checks for meter types already existed in `meterpointDetails.types.ts` but the PR added them inline in `ImbpNewAppointmentType.vue`.

**How to apply:** Before writing conditional logic about domain concepts (meter types, fuel types, appointment types), search for existing getters/helpers in the `models/` directory first.

---

## 3. Const enums over string literal types

When defining a set of string constants (e.g., photo source types, appointment statuses), use `const enum` rather than TypeScript string literal union types.

**Why:** @mt-5 flagged twice on #1810 — string literals like `'CUSTOMER' | 'SITE_VISIT'` should be `const enum PhotoSource { CUSTOMER = 'CUSTOMER', SITE_VISIT = 'SITE_VISIT' }`.

**How to apply:** When creating new string unions with 2+ values, default to const enum. Store in the relevant `*.types.ts` file.

---

## 4. Rename consistently across the entire codebase

When renaming a concept (e.g., `NoSlotsModal` → `RegisterInterestModal`), find and rename ALL references: component names, v-model bindings, variable names, test descriptions, method names. Don't leave the old name in some places.

**Why:** @GillianLeeSoEnergy left 8+ comments on #1780 about inconsistent naming — the modal was renamed but `showNoSlotsModal` remained as v-model names across multiple files.

**How to apply:** After renaming, grep the entire repo for the old name. Every hit must be updated or explicitly justified.

---

## 5. No nested ternaries — use lookup maps or if/else

Nested ternaries reduce readability. Use a lookup object/map, if/else chain, or `??`/`?.` operators instead.

**Why:** @GillianLeeSoEnergy (#1780) and @tonybatty (#1040) both flagged this. SonarCloud also flags it as `S3358`.

**How to apply:** If you find yourself writing `a ? b : c ? d : e`, refactor immediately. For mapping values, use `const map = { key: value }; return map[x]`.

---

## 6. Simplify expressions — don't ternary when ?? suffices

`this.interests?.registered ?? false` is cleaner than `this.interests?.interest ? Object.values(...).some(...) : false` when the getter already handles the logic.

**Why:** @GillianLeeSoEnergy flagged on #1780 — the ternary was duplicating logic already in the `registered` getter.

**How to apply:** Before writing a ternary, check if the object already has a getter/computed that handles the edge case. Use `??` for nullish defaults.

---

## 7. Don't create duplicate tests

When adding new test cases, check if an existing test already covers the same scenario. Especially after renaming or refactoring, old tests may duplicate new ones.

**Why:** @GillianLeeSoEnergy found 3 duplicate/near-duplicate tests in #1780 after the modal rename.

**How to apply:** After writing tests, review the full test file for overlapping coverage. If two tests assert the same condition with different descriptions, merge them.

---

## 8. Tests MUST use DOM assertions (reminder)

We have a convention to never use `wrapper.vm.X` — but #1780 shipped with `wrapper.vm.showRegisterInterestModal` assertions. Reviewers will catch this.

**Why:** @GillianLeeSoEnergy explicitly called this out — "tests should assert that the modal element exists in the DOM" instead of checking a data property.

**How to apply:** This is already in our test conventions. Treat as a hard rule: if you see `wrapper.vm.` in test assertions, replace with `.find()/.exists()/.text()` DOM checks.

---

## 9. Replace fully — don't leave old code as pass-through

When replacing a component (e.g., swapping `NoSlotsModal` for `RegisterInterestModal`), don't keep the old component as a wrapper that just delegates to the new one. Replace it entirely at each call site.

**Why:** @GillianLeeSoEnergy on #1780 suggested replacing `RtsModal` entirely with `ImbpRegisterInterestModal` instead of having `RtsModal` emit an event to open the new modal through `ModalHandler`.

**How to apply:** When replacing component A with component B, update every call site to use B directly. Remove A if it has no other callers.
