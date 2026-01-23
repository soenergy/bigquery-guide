# Commercial Metrics

Data for understanding customer tariffs, renewals, and acquisition funnel performance.

---

## Key Tables

| Table | Description |
|-------|-------------|
| `junifer_enriched.product_bundle` | Customer's active tariff/product with contract dates |
| `junifer_enriched.product_bundle_dfn` | Tariff definitions (names, types) |
| `junifer_enriched.product` | Individual products within bundles |
| `nova_be_customers_enriched.renewal` | Renewal records and status |
| `nova_be_products_enriched.quote` | Customer quotes (for fall-through analysis) |

---

## Customers by Tariff

### What tariff is each customer on?

```sql
SELECT
  a.number AS account_number,
  pbd.name AS tariff_name,
  pb.from_dttm AS tariff_start,
  pb.contracted_to_dttm AS contract_end_date,
  pb.to_dttm AS tariff_end
FROM `soe-prod-data-core-7529.junifer_enriched.product_bundle` pb
JOIN `soe-prod-data-core-7529.junifer_enriched.product_bundle_dfn` pbd
  ON pb.product_bundle_dfn_fk = pbd.id
  AND pbd.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
JOIN `soe-prod-data-core-7529.junifer_enriched.account` a
  ON pb.account_fk = a.id
  AND a.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
WHERE pb.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND pb.cancel_fl != 'Y'
  AND (pb.to_dttm IS NULL OR pb.to_dttm > CURRENT_TIMESTAMP())
```

### Customer count by tariff

```sql
SELECT
  pbd.name AS tariff_name,
  COUNT(DISTINCT pb.account_fk) AS customer_count
FROM `soe-prod-data-core-7529.junifer_enriched.product_bundle` pb
JOIN `soe-prod-data-core-7529.junifer_enriched.product_bundle_dfn` pbd
  ON pb.product_bundle_dfn_fk = pbd.id
  AND pbd.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
WHERE pb.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND pb.cancel_fl != 'Y'
  AND (pb.to_dttm IS NULL OR pb.to_dttm > CURRENT_TIMESTAMP())
GROUP BY pbd.name
ORDER BY customer_count DESC
```

### Fixed vs Variable tariff split

```sql
SELECT
  CASE
    WHEN pbd.name LIKE '%Fixed%' THEN 'Fixed'
    WHEN pbd.name LIKE '%Variable%' OR pbd.name LIKE '%SVT%' OR pbd.name LIKE '%Flex%' THEN 'Variable'
    ELSE 'Other'
  END AS tariff_type,
  COUNT(DISTINCT pb.account_fk) AS customer_count
FROM `soe-prod-data-core-7529.junifer_enriched.product_bundle` pb
JOIN `soe-prod-data-core-7529.junifer_enriched.product_bundle_dfn` pbd
  ON pb.product_bundle_dfn_fk = pbd.id
  AND pbd.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
WHERE pb.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND pb.cancel_fl != 'Y'
  AND (pb.to_dttm IS NULL OR pb.to_dttm > CURRENT_TIMESTAMP())
GROUP BY tariff_type
ORDER BY customer_count DESC
```

---

## Renewals

### Upcoming renewals (contracts ending soon)

```sql
SELECT
  DATE(pb.contracted_to_dttm) AS contract_end_date,
  COUNT(DISTINCT pb.account_fk) AS accounts_expiring
FROM `soe-prod-data-core-7529.junifer_enriched.product_bundle` pb
WHERE pb.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND pb.cancel_fl != 'Y'
  AND pb.contracted_to_dttm >= CURRENT_TIMESTAMP()
  AND pb.contracted_to_dttm <= TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
GROUP BY contract_end_date
ORDER BY contract_end_date
```

### Renewals by month

```sql
SELECT
  FORMAT_TIMESTAMP('%Y-%m', pb.contracted_to_dttm) AS renewal_month,
  COUNT(DISTINCT pb.account_fk) AS accounts_due_renewal
FROM `soe-prod-data-core-7529.junifer_enriched.product_bundle` pb
WHERE pb.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND pb.cancel_fl != 'Y'
  AND pb.contracted_to_dttm >= CURRENT_TIMESTAMP()
  AND pb.contracted_to_dttm <= TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 365 DAY)
GROUP BY renewal_month
ORDER BY renewal_month
```

### Renewal status (from Nova)

```sql
SELECT
  status,
  COUNT(*) AS count
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.renewal`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND deleted IS NULL
  AND cancelled = FALSE
GROUP BY status
ORDER BY count DESC
```

---

## Fall-Through / Conversion

Fall-through typically refers to quotes that don't convert to sales.

### Enrolment status (sign-up funnel)

```sql
SELECT
  status,
  COUNT(*) AS count
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.enrolment`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY status
ORDER BY count DESC
```

### Broker renewals by status

```sql
SELECT
  broker,
  status,
  COUNT(*) AS count
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.renewal`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND deleted IS NULL
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
GROUP BY broker, status
ORDER BY broker, count DESC
```

---

## Key Fields Reference

### product_bundle (Customer's tariff)

| Column | Description |
|--------|-------------|
| `account_fk` | FK to junifer account |
| `product_bundle_dfn_fk` | FK to tariff definition |
| `from_dttm` | When tariff started |
| `to_dttm` | When tariff ends |
| `contracted_to_dttm` | Contract end date (for renewals) |
| `cancel_fl` | Cancelled flag (Y/N) |
| `follow_on_fl` | Has follow-on tariff |

### product_bundle_dfn (Tariff definitions)

| Column | Description |
|--------|-------------|
| `id` | Tariff definition ID |
| `name` | Tariff name (e.g., "So Price Promise Jan 2024") |
| `status` | Active/Inactive |
| `deemed_default` | Is this the default/SVT tariff |

### renewal (Nova renewal records)

| Column | Description |
|--------|-------------|
| `billing_account_id` | FK to billing account |
| `status` | Renewal status |
| `broker` | Broker if applicable |
| `cancelled` | Was renewal cancelled |
