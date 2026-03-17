# So Energy BE Development Guide

Context for working on **be-microservices** (Kotlin/Spring), **be-assets**, **be-ac-junifer**, and the backoffice API gateway.

---

## Service Overview

| Service | Repo / Module | What It Is |
|---------|---------------|-----------|
| **be-customers** | `be-microservices` | Core customer/smart meter service (gRPC) |
| **be-api-gateway-portal** | `be-microservices` | Internal portal REST/GraphQL gateway |
| **be-api-gateway-backoffice** | `be-microservices` | Backoffice REST gateway (used by Nova) |
| **be-assets** | `be-microservices` | Meter point and asset data (gRPC) |
| **be-ac-junifer** | `be-microservices` | Junifer data sync processor |
| **be-identity** | `be-microservices` | Feature flags, identity service |

**Inter-service communication**: gRPC (protobuf)
**External API**: REST (backoffice gateway)
**DB migrations**: Flyway (in-service, `resources/db/migration/`)

---

## Branch Naming

| Repo | Convention | Example |
|------|-----------|---------|
| `be-microservices` | `SO-XXXXX_description_NOFF` | `SO-29475_meter-exclusion-list_NOFF` |
| `fe-nova` | `task/SO-XXXXX_description` | `task/SO-29475_meter-exclusion-list` |
| `fe-monorepo` | `task/SO-XXXXX_description` | `task/SO-29475_meter-exclusion-list` |

`_NOFF` = no feature flag (work ships without a flag). Use `_OFF` if the work is behind a feature flag.

---

## Flyway Migrations

### Version collision risk
Multiple engineers often have branches open simultaneously. When `main` merges new migrations, your version numbers can clash.

**Always check what's on main before pushing a branch with new migrations:**
```bash
git ls-tree origin/main kotlin-services/services/be-customers/service/src/main/resources/db/migration/ \
  | awk '{print $4}' | xargs -I{} basename {} | grep "^V" | sort
```

Rename your migration files to the next available version if there's a clash.

### No-op migration pitfall
On-demand CI environments have their own DB. If the environment was created from an older main, it may be missing migrations. A no-op migration (empty `-- no-op` file) forces Flyway to run and brings the environment in sync. However:
- **Do not include no-op migrations in PRs** — close and reopen with a clean branch instead
- A clean branch from current main avoids this entirely

---

## Feature Flags

### Pattern
Feature flags are stored in `be-identity`. To add a new flag:

1. Add to `FeatureName` proto enum (in be-identity proto):
   ```protobuf
   TMP_SO_XXXXX_DESCRIPTION = <next_number>;
   ```
2. Add a Flyway migration in be-identity to insert the flag row (disabled by default):
   ```sql
   INSERT INTO feature_flags (name, enabled) VALUES ('TMP_SO_XXXXX_DESCRIPTION', false);
   ```
3. Use the flag in service code via the feature flag client.

### Naming convention
- `TMP_` prefix = temporary flag, will be removed after rollout
- All uppercase with underscores
- Include story number: `TMP_SO_23897_RTS_METER_SYNC`

---

## Protobuf Conventions

### Nullable fields: use `NullableBoolean`
For optional booleans that need to be distinguishable from `false` (i.e., PATCH semantics):
```protobuf
optional NullableBoolean is_rts_meter = 17;
```
`unset` = leave DB value unchanged; `TRUE`/`FALSE` = explicitly set.

### Removing RPCs and message types
When deleting a feature, clean up in this order:
1. Remove the `rpc` definition from `*_service.proto`
2. Remove request/response message types from `*_dto.proto` (verify zero Kotlin references first)
3. Remove the handler override in the gRPC service class
4. Remove the client method from `*Client.kt`
5. Remove repository methods and/or the entire repository if unused

**Always grep for references before deleting message types** — protobuf types are referenced by string name in generated code and can be missed by IDE find-usages.

---

## Multi-Repo Feature Deployment Order

Most features span BE + Hasura + FE. Deploy in this order:

```
1. BE migration merges and deploys
2. Hasura config updated (manually track new table/fields with correct permissions)
3. FE PR merges
```

**Why**: FE queries through Hasura; Hasura schema check in FE CI will fail until the table is tracked. This is expected — don't wait for the check to pass before merging Hasura config.

### If FE needs to ship before BE is live
Use a feature flag (`_OFF` branch suffix) so FE code is deployed but inactive. Activate via flag when BE is ready.

---

## On-Demand CI Environments

BE PRs in `be-microservices` get an on-demand environment at:
```
https://staging.soenergy.co/be-customers/so-XXXXX
```
(derived from branch name)

### On-demand in fe-monorepo PRs
`deploy-ondemand-services (be-customers)` in an **fe-monorepo** PR spins up a BE service for integration testing. Its failure **does not** mean the BE microservices PR is blocked — completely separate CI concern.

### Stale branch pitfall
The on-demand runner greps for FE branches by story number:
```bash
gh api repos/soenergy/fe-nova/branches --jq '.[].name' --paginate | grep -i "so-XXXXX" | head -n 1
```
If a stale branch from an earlier attempt exists (e.g. `task/SO-XXXXX_old-name`), it may be picked up instead of the real branch. Delete old branches or use a fresh branch with a unique name.

---

## RTS Meter Detection (Junifer SQL)

To detect if a meter is an RTS meter from Junifer data:
```sql
SELECT EXISTS (
    SELECT 1
    FROM "junifer__UkTprMapping" utm
    JOIN "junifer__UkTimePatternRegime" utpr ON utpr.id = utm."ukTimePatternRegimeFk"
    WHERE utm."ukStdSettlementConfigFk" = :ukStdSettlementConfigFk
      AND utm."deleteFl" = 'N'
      AND utm."fromDt" <= :currentDatetime
      AND (utm."toDt" >= :currentDatetime OR utm."toDt" IS NULL)
      AND CAST(utpr."regimeId" AS BIGINT) > 999
) AS is_rts_meter
```

RTS meters have a `regimeId > 999` in the time pattern regime. This is the canonical check used in `be-ac-junifer` sync.

---

## Smart Meter Eligibility Service

Key eligibility outcomes returned by `SmartMeterEligibilityService`:
- `INELIGIBLE_ON_EXCLUSION_LIST` — meter MSN is on the `smart_meter_exclusion_list` table
- `arrangementTooComplex` — dual fuel with incompatible meter configuration

The exclusion list table (`smart_meter_exclusion_list`) is keyed on `(mpxn, msn)` with fields: `fuel`, `meter_type`, `exclusion_reason`, `confirmed_etc_waived`, `source_file`, `created_at`, `updated_at`.

---

## Useful Commands

```bash
# Check what Flyway migrations are on main
git ls-tree origin/main <path_to_migration_dir> | awk '{print $4}' | xargs -I{} basename {} | sort

# Cherry-pick specific commits to a fresh branch
git cherry-pick <commit-hash>

# Check PR CI status
gh pr checks <pr-number>

# Rerun failed checks
gh run rerun <run-id> --failed

# List runs on a branch
gh run list --branch <branch-name>
```

---

## References

- FE development guide: `engineering/fe-development-guide.md` (this repo)
- BigQuery data guide: `CLAUDE.md` (this repo)
