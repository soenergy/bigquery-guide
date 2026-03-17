# So Energy FE Development Guide

Context for working across **fe-nova** (agent/customer Vue app) and **fe-monorepo** (SMBP and other standalone Vue apps).

---

## System Architecture Overview

| System | Repo | What It Is |
|--------|------|-----------|
| **Nova** | `fe-nova` | Main agent-facing CRM and customer portal (Vue 2 → 3 migration in progress) |
| **SMBP** | `fe-monorepo` (`smart-meter-booking`) | Smart Meter Booking Portal — customer-facing standalone app |
| **IMBP** | `fe-monorepo` (`in-home-metering-booking`) | In-Home Metering Booking Portal — booking flow for meter exchanges |
| **BE** | `be-microservices` | Kotlin/Spring microservices (Flyway for DB migrations) |
| **Hasura** | manual config | GraphQL layer over PostgreSQL — Nova and FE use Hasura for most reads |

**Data flow**: Customer/agent action → FE → Hasura (GraphQL) → BE → PostgreSQL

---

## PR Process

### Approvals
- Most PRs require **2 approvals**, at least 1 from outside your squad
- Trivial changes (single constant, few-line copy) may need only 1

### Merge windows
- Approved changes released no later than **5 PM weekdays**, **3 PM Fridays**
- Notify `#releases` Slack before enabling auto-merge
- Auto-merge only after QA passed + 2 approvals
- Smoke test required after release

### PR description must include
- The **business reason** — someone outside the team should understand *why*, not just what changed
- Jira ticket number
- Account numbers if the change can be tested on the UI

### PR size
- Keep changed lines below ~1000 (excluding `package-lock.json` and generated files)
- If larger, split into smaller PRs

---

## CI Check Interpretation

### fe-monorepo: `deploy-ondemand-services (be-customers)`
This is an **on-demand test environment** that spins up a BE service alongside the FE change. Its failure does **not** mean the BE microservices PR is blocked — these are separate concerns.

### Rerunning failed checks
When checks fail transiently (network, flaky tests): rerun with `gh run rerun <id> --failed` before assuming there's a real problem.

### Hasura schema check
A Hasura check failure in an FE PR is **expected** if it depends on a table/field not yet tracked in Hasura prod (e.g. a BE migration not yet merged). Merge BE + do Hasura config first.

---

## fe-monorepo (SMBP / IMBP) Code Style

### Prettier config (`.prettierrc.js`)
```
singleQuote: false
semi: false
printWidth: 80 (default)
```

### ESLint runs at build time
`vue-cli-service build` enforces:
- `plugin:vue/vue3-recommended` — catches `vue/no-dupe-keys`, template issues
- `eslint:recommended` — catches `no-unused-vars` (unused imports fail the build)
- `plugin:prettier/recommended` — formatting as lint errors

### Common build failures to pre-empt
| Issue | Fix |
|-------|-----|
| Unused imports | Remove when deleting code that used them |
| Duplicate computed property names (e.g. in both `mapGetters` and `computed`) | `vue/no-dupe-keys` error — pick one |
| Lines over 80 chars (code, not strings) | Break at `=`, `?`, operators, after `if(...)` |
| Multi-attribute elements: content inline with `>` | Put content on its own line |
| Unnecessary quotes on object keys | `"DUAL_GAS_ONLY"` → `DUAL_GAS_ONLY`; hyphenated keys like `"DUAL_TRAD-TRAD"` still need quotes |

### Validate before pushing (lint only, fast)
```bash
pnpm lint:smart-meter-booking
```

---

## Self-Review Checklist (before every commit)

1. **Unused imports** — did you delete any code? Check every import still has a reference.
2. **Duplicate keys** — if you touched `mapGetters`, none of those names should also be in explicit `computed`.
3. **Line length** — scan new lines. Over 80 chars (excluding string values)? Break at `=`, `?`, operators.
4. **Template formatting** — multi-attribute elements must have content on its own line between `>` and `</tag>`.
5. **Object key quotes** — remove quotes from keys that are valid JS identifiers (no hyphens/spaces).
6. **Tests** — do changes have coverage? Tests assert on DOM/props, not `wrapper.vm` internals.
7. **Scope** — are you changing anything beyond what the ticket asks for?
8. **PR description** — does it explain the business reason, not just what changed?

---

## Vue Testing Conventions (fe-nova)

### Core principle: test via public interface only
Never access `wrapper.vm.someMethod()` or `wrapper.vm.someProp` directly — these are implementation details.

### Triggering interactions
```js
// ✅ correct
await wrapper.find('[data-test-id="submit-button"]').trigger('click')

// ❌ wrong
wrapper.vm.handleSubmit()
```

### Driving component state
```js
// ✅ correct — pass props or set store state
const wrapper = mount(MyComponent, { props: { isLoading: true } })

// ❌ wrong
await wrapper.setData({ isLoading: true })
```

### Assertions
```js
// ✅ assert on rendered DOM
expect(wrapper.find('.error-message').exists()).toBe(true)
expect(wrapper.find('.status').text()).toBe('Active')

// ❌ wrong — testing internal computed value, not output
expect(wrapper.vm.hasError).toBe(true)
```

### Finding elements
```js
// by data-test-id
wrapper.find('[data-test-id="book-button"]')

// by attribute prefix
wrapper.find('[title^="Book"]')

// by text inside a list
wrapper.findAll('.item').find(el => el.text().includes('Gas'))
```

### `data-test-id` naming convention
Derived from `title` prop: `title.toLowerCase().replace(/\s/g, '-')`
- `'Book Smart Meter Exchange'` → `button-book-smart-meter-exchange`

### SoButton stub pattern
`SoButton` uses `inheritAttrs: false` + `emits: ['click']`, so `@click` is a Vue component event (not DOM), and `data-testid` falls through to `$attrs` on the root `<div>`.

To test clicks correctly, stub as:
```js
SoButton: {
  inheritAttrs: false,
  template: '<button v-bind="$attrs">{{ $attrs.title }}</button>'
}
```
This puts `data-testid` and `onClick` on the `<button>`, and renders the title as `.text()`.

### Don't run tests locally
Push and let CI run them — local `npm run test` / `npx vitest` not reliable in this setup.

---

## BE Migrations (be-microservices / Flyway)

### Version collision risk
When main merges new migrations while your branch is open, your version numbers may clash. Before pushing, check what's on main:

```bash
git ls-tree origin/main kotlin-services/services/be-customers/service/src/main/resources/db/migration/ \
  | awk '{print $4}' | xargs -I{} basename {} | grep "^V" | sort
```

Rename your migration files to the next available version.

### Multi-repo feature order
For features spanning BE + Hasura + FE, merge in this order:
1. BE migration merges → deployed
2. Hasura tracks new table/fields (manual config)
3. FE PR merges (Hasura check will fail until step 2 is done)

---

## Useful Commands

```bash
# Check PR CI status
gh pr checks <pr-number>

# Rerun failed checks
gh run rerun <run-id> --failed

# List runs on a branch
gh run list --branch <branch-name>

# View PR details
gh pr view <pr-number>
```

---

## References

- FE Code Review Guide: https://soenergy.atlassian.net/wiki/spaces/FD/pages/3770286149/FE+Code+Review+Guide
- BigQuery data guide: https://github.com/soenergy/bigquery-guide
