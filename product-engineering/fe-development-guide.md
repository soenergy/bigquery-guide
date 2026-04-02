# So Energy FE Development Guide

Context for working across **fe-nova** (agent/customer Vue app), **fe-monorepo** (SMBP and other standalone Vue apps), and **fe-nexus** (MyAccount rebuild).

---

## System Architecture Overview

| System | Repo | What It Is |
|--------|------|-----------|
| **Nova** | `fe-nova` | Main agent-facing CRM and customer portal (Vue 2 → 3 migration in progress) |
| **SMBP** | `fe-monorepo` (`smart-meter-booking`) | Smart Meter Booking Portal — customer-facing standalone app |
| **IMBP** | `fe-monorepo` (`in-home-metering-booking`) | In-Home Metering Booking Portal — booking flow for meter exchanges |
| **BE** | `be-microservices` | Kotlin/Spring microservices (Flyway for DB migrations) |
| **Nexus** | `fe-nexus` | MyAccount rebuild — customer-facing, Vue 3 + Composition API |
| **Hasura** | manual config | GraphQL layer over PostgreSQL — Nova and FE use Hasura for most reads |

**Data flow**: Customer/agent action → FE → Hasura (GraphQL) → BE → PostgreSQL

### Vue API: Options vs Composition
- **fe-nova**: Options API (Vue 2 → 3 migration in progress)
- **fe-nexus**: Composition API for all new components
- **fe-monorepo**: Options API (Vue 2-era apps)

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

## TypeScript Conventions

### Constant naming
Constants in `UPPERCASE_SNAKE_CASE`. Include units in names to avoid ambiguity:
- `MAX_RETRY_ATTEMPTS`, `TIMEOUT_IN_MS`, `AMOUNT_IN_PENCE`

### External resources
Separate API calls and third-party plugin integrations into their own folder/file so they can be imported as regular modules and easily mocked during testing.

---

## GraphQL Workflow

Queries and mutations are written in `.graphql` files. Codegen watches these files and outputs TypeScript types + Document objects.

```
.graphql file → codegen → TypeScript types + Document → graphql-request + Tanstack Query
```

- **Full type safety**: if a Hasura column is removed, the FE build fails
- **Never edit generated files** in `src/api/backoffice/generated/` or `src/api/hasura/generated/` directly
- After changing `.graphql` files, run the corresponding codegen command (see BE Development Guide > Codegen)

### Local codegen against on-demand BE
To generate types from a BE on-demand environment (before BE is merged to main):
1. Add to your `.env` file: `SO_X_BRANCH_NAME=so-123456` (Nova) or `VITE_X_BRANCH_NAME=so-123456` (Nexus)
2. Run `npm run codegen`
3. The Header Injector will use the env var automatically

**Limitation**: Header Injector doesn't work with Hasura and ARK endpoints — only `portal-api-gateway`, `portal-api-gateway-v2`, and `backoffice-api-gateway`.

---

## Dependency Management

### Installing/updating packages
- CI must use `npm ci` or `pnpm install --frozen-lockfile` — never `npm install`
- Commit `package.json` and `package-lock.json` together in the same PR
- PR description must explain **why** the dependency is needed
- Any change to `package.json` or lock files requires **CODEOWNER approval**
- Only import what you use — keep bundles small and tree-shakable

### Reviewing dependency PRs
- Verify the package is from an official source (not typosquatting)
- Ensure both `package.json` and lock file are updated
- Be wary of large, unexplained lockfile churn — red flag

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

1. **TODO/FIXME comments** — grep new files for `TODO`/`FIXME` and remove them. They always trigger SonarCloud `S1135`.
2. **Unused imports** — did you delete any code? Check every import still has a reference.
3. **Duplicate keys** — if you touched `mapGetters`, none of those names should also be in explicit `computed`.
4. **Line length** — scan new lines. Over 80 chars (excluding string values)? Break at `=`, `?`, operators.
5. **Template formatting** — multi-attribute elements must have content on its own line between `>` and `</tag>`.
6. **Object key quotes** — remove quotes from keys that are valid JS identifiers (no hyphens/spaces).
7. **Nested ternaries** — SonarCloud `S3358`. Extract to if/else or a helper function.
8. **Tests** — do changes have coverage? Tests assert on DOM/props, not `wrapper.vm` internals.
9. **Scope** — are you changing anything beyond what the ticket asks for?
10. **PR description** — does it explain the business reason, not just what changed?
11. **SonarCloud** — after pushing, query the API (see SonarCloud section above) to check for 0 new code smells before requesting review.

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

## Cypress E2E Testing

### What to test
E2E tests should cover **critical user journeys** and business-critical flows:
- Complete user workflows (e.g., move-in, payment submission, booking flow)
- Multi-step processes integrating multiple components
- Core business functionality that would break the app if failed

### What NOT to test in E2E
- Static text validation (e.g., checking a page title exists)
- Basic component rendering
- CSS styling details
- Component behaviour that unit tests already cover (e.g., Vuetify sort buttons)

### Selector strategy: semantic-first
Prefer semantic selectors that mirror how users interact — these survive refactoring and catch accessibility issues:

```js
// ✅ Preferred — semantic
cy.findByRole('button', { name: 'Priority Services' }).click()

// ✅ Acceptable — test ID as performance anchor
cy.get('[data-testid="psr-button"]').click()

// ❌ Avoid — brittle CSS selectors
cy.get('.btn-primary.psr-section > button').click()
```

`findByRole()` is superior because it survives component changes (e.g., `<button>` → `<input type="button">`), works with accessible names, and tests accessibility compliance alongside functionality.

**Known components where `findByRole` doesn't work** (due to Vuetify wrapping): `SoAlert`, `SoTextField`, `SoDatePicker`, `SoSelect`. Use `data-testid` for these.

### File structure
```
e2e/          — test files, organised by feature/domain
page-objects/ — reusable UI interactions
locators/     — centralised selectors
utils/        — shared utilities (e.g., GraphQL mocking)
```

### Note: E2E vs unit test selectors
The semantic-first approach applies to **E2E tests** (user journeys against a running app). **Unit tests** (component tests with `@vue/test-utils`) can use `data-test-id` selectors as documented in the Vue Testing Conventions section above — different contexts, different trade-offs.

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

## Branch Naming

| Repo | Convention | Example |
|------|-----------|---------|
| `fe-nova` | `{type}/SO-XXXXX_{kebab-desc}` | `task/SO-29475_meter-exclusion-list` |
| `fe-monorepo` | `{type}/SO-XXXXX_{kebab-desc}` | `bug/SO-29688_smbp-exchange-subtext` |

Valid type prefixes: `task/`, `bug/`, `fix/`. **Not** `feat/`, `chore/`, etc.

Use `SO-NONE` or `SO-00000` when there's no Jira ticket.

PR title: `SO-XXXXX: {short description}` (e.g. `SO-29956: Show SMEX tooltip and rename troubleshooting appointment type`).

### Never rename a branch with an open PR

GitHub silently closes the PR rather than redirecting it. If you need to change a branch name (e.g., to add a NOFF suffix), create a new branch + new PR instead.

---

## SonarCloud Quality Gate

### Key rules that will block your PR
| Rule | What it catches |
|------|----------------|
| `S1135` | TODO/FIXME comments — **always** triggers, remove before pushing |
| `S3358` | Nested ternaries — extract to if/else or helper functions |
| `S3366` | Public fields that should be private |
| `S4055` | Unused interfaces |
| Cognitive complexity | Functions with complexity > 15 |
| `any` type | Explicit `any` in TypeScript |

Quality gate threshold: **0 new code smells allowed**.

### Pre-push: grep for TODO/FIXME
Always scan new files before pushing — a single TODO comment will fail the quality gate and require an extra commit + CI cycle.

```bash
grep -rn "TODO\|FIXME" path/to/new/files/
```

### Check SonarCloud after pushing
Query the API to verify 0 new issues before requesting review:

```bash
SONAR_TOKEN=$(cat ~/.config/sonarcloud/token)
curl -s -u "$SONAR_TOKEN:" \
  "https://sonarcloud.io/api/issues/search?componentKeys=soenergy_fe-nova&pullRequest=<PR_NUMBER>&inNewCodePeriod=true" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for issue in data.get('issues', []):
    comp = issue.get('component','').split(':')[-1]
    print(f'{issue.get(\"rule\")}: {issue.get(\"message\")} ({comp}:{issue.get(\"line\")})')
print(f'Total: {data.get(\"total\", 0)}')
"
```

For fe-monorepo, use `componentKeys=soenergy_fe-monorepo`.

Fallback (if no SonarCloud token):
```bash
gh api repos/soenergy/fe-nova/issues/<PR_NUMBER>/comments \
  --jq '.[] | select(.user.login | test("sonar"; "i")) | .body'
```

SonarCloud exclusions: `src/api/hasura/generated/**`, `src/api/backoffice/generated/**`, test files.

---

## Vercel Previews

fe-nova and fe-monorepo PRs get Vercel preview deployments at `*.preview.soenergy.co`.

### Check deployment status
```bash
VERCEL_TOKEN=$(python3 -c "import json; print(json.load(open('$HOME/.config/vercel/auth.json'))['token'])")
TEAM_ID="team_t8yrLwYKM3BxZfvw3bpdZXom"

# List recent deployments for a project
curl -s -H "Authorization: Bearer $VERCEL_TOKEN" \
  "https://api.vercel.com/v6/deployments?teamId=$TEAM_ID&app=fe-nova&limit=20" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for d in data.get('deployments', []):
    pr = d.get('meta', {}).get('githubPrId', '')
    print(d['uid'], '|', d['state'], '|', f'PR {pr}', '|', d.get('url',''))
"
```

### Get build error logs
```bash
DEPLOYMENT_ID="dpl_xxxx"
curl -s -H "Authorization: Bearer $VERCEL_TOKEN" \
  "https://api.vercel.com/v2/deployments/$DEPLOYMENT_ID/events?teamId=$TEAM_ID&builds=1" \
  | python3 -c "
import json, sys
for line in sys.stdin:
    try:
        e = json.loads(line)
        if e.get('type') == 'stderr' or (e.get('type') == 'stdout' and 'error' in e.get('payload', {}).get('text','').lower()):
            print(e.get('payload', {}).get('text',''))
    except: pass
"
```

Key values:
- Team: `So Energy` / ID: `team_t8yrLwYKM3BxZfvw3bpdZXom`
- Projects: `fe-nova`, `fe-nexus`, `fe-nexus-histoire`

### QA with on-demand BE
To share a preview environment connected to a BE on-demand environment for QA:
1. Open the Vercel preview URL
2. Click "Connect to on-demand BE" in the Header Injector widget
3. Enter the Jira ticket number (e.g., `SO-29721`)
4. Click "Share Link" — generates a URL with the on-demand header baked in
5. Share that URL with QA

If changes are BE-only (no FE PR), use Nova staging directly with the Header Injector.

---

## Staging Test Accounts

Staging accounts are synced from Junifer via `https://nova.staging.soenergy.co/admin/sync-accounts` (one-off or automatic). See BE Development Guide for more detail.

Cypress e2e tests use several staging accounts (configured in `common.config.js`). If a test account's data goes stale (e.g., DD rejections, expired tariffs), it can cause flaky e2e tests. Check the account state in staging before investigating test failures.

To create a login for a synced account: Nova > User List > Create User with the account number.

---

## References

- FE Guidelines: https://soenergy.atlassian.net/wiki/spaces/FD/pages/1244463133/FE+Guidelines
- FE Code Review Guide: https://soenergy.atlassian.net/wiki/spaces/FD/pages/3770286149/FE+Code+Review+Guide
- Cypress E2E Testing Guidelines: https://soenergy.atlassian.net/wiki/spaces/FD/pages/4875976755/Cypress+E2E+Testing+Guidelines
- Backend On-Demand with FE: https://soenergy.atlassian.net/wiki/spaces/FD/pages/4791730264/How+to+use+Backend+On-Demand+with+Frontend+environments
- NPM Package Management: https://soenergy.atlassian.net/wiki/spaces/FD/pages/4891344946/How+to+update+install+NPM+packages
- BigQuery data guide: https://github.com/soenergy/bigquery-guide
