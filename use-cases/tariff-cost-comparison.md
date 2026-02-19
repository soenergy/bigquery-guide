# Tariff Cost Comparison

Estimating what a customer would pay on different tariffs, based on their actual half-hourly electricity consumption.

---

## Key Tables

| Table | Dataset | Description |
|-------|---------|-------------|
| `product` | `nova_be_products_enriched` | Product/tariff catalog (ELEC, GAS, DUAL) |
| `product_rate` | `nova_be_products_enriched` | Pricing per product (standing charge, unit rates) |
| `product_bundle` | `junifer_enriched` | Customer's current tariff assignment + contract dates |
| `product_bundle_dfn` | `junifer_enriched` | Tariff definitions (names, types, deemed/SVT flag) |
| `Elec_D0071` | `soe_dataflows` | Aggregated half-hourly electricity consumption (industry data) |
| `mpan` | `junifer_enriched` | Electricity meter points - links account to MPAN |
| `billing_account` | `nova_be_customers_enriched` | Links Nova customer to Junifer account number |

> **Note**: CentreStage / xreads may provide extended HH consumption history but is not yet fully documented. `Elec_D0071` is the documented industry source for aggregated half-hourly data.

---

## Step 1: Get Customer's Current Tariff & Contract End Date

Identify what each customer is currently on and when their agreement ends, so you know who is eligible to switch.

```sql
SELECT
  a.number AS account_number,
  pbd.name AS current_tariff,
  pb.from_dttm AS tariff_start,
  pb.contracted_to_dttm AS contract_end_date,
  pb.to_dttm AS tariff_end,
  pbd.deemed_default AS is_svt
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

Customers whose `contract_end_date` is approaching (or past) are the primary candidates for switching.

---

## Step 2: Get Available Tariff Rates

Pull the pricing for all electricity products that customers could switch to.

```sql
SELECT
  p.id AS product_id,
  p.name AS product_name,
  p.code AS product_code,
  pr.rate_type,
  pr.value
FROM `soe-prod-data-core-7529.nova_be_products_enriched.product` p
JOIN `soe-prod-data-core-7529.nova_be_products_enriched.product_rate` pr
  ON p.id = pr.product_id
  AND pr.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
WHERE p.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND p.type = 'ELEC'
```

> **TODO**: Filter to only currently available/active tariffs. Explore `product` for status or validity date fields to exclude legacy/internal products.

### Understanding rate_type values

Before building cost calculations, check what rate types exist:

```sql
SELECT DISTINCT pr.rate_type, COUNT(*) AS product_count
FROM `soe-prod-data-core-7529.nova_be_products_enriched.product_rate` pr
WHERE pr.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
GROUP BY pr.rate_type
ORDER BY product_count DESC
```

Expected types include standing charge and unit rate. If there are time-of-use (TOU) rates, the cost calculation in Step 4 will need to apply different rates per settlement period.

---

## Step 3: Get Customer HH Electricity Consumption

Link the customer's account to their MPAN, then pull half-hourly reads.

### Link account to MPAN

```sql
SELECT
  a.number AS account_number,
  m.mpan_core AS mpan
FROM `soe-prod-data-core-7529.junifer_enriched.account` a
JOIN `soe-prod-data-core-7529.junifer_enriched.mpan` m
  ON a.id = m.account_fk
  AND m.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
WHERE a.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND a.cancel_fl != 'Y'
```

### Pull HH consumption from D0071

```sql
-- Schema fields TBC - explore Elec_D0071 to confirm column names
-- Expected key fields: MPAN, settlement_date, settlement_period (1-48), consumption_kwh
SELECT *
FROM `soe-prod-data-core-7529.soe_dataflows.Elec_D0071`
LIMIT 100
```

> **TODO**: Confirm the exact column names in `Elec_D0071`. The query below assumes `mpan`, `settlement_date`, `settlement_period`, and `kwh` - adjust once schema is verified.

### Aggregate to annual consumption per customer

```sql
WITH customer_mpan AS (
  SELECT
    a.number AS account_number,
    m.mpan_core AS mpan
  FROM `soe-prod-data-core-7529.junifer_enriched.account` a
  JOIN `soe-prod-data-core-7529.junifer_enriched.mpan` m
    ON a.id = m.account_fk
    AND m.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  WHERE a.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
    AND a.cancel_fl != 'Y'
)
SELECT
  cm.account_number,
  SUM(hh.kwh) AS total_kwh,
  COUNT(DISTINCT hh.settlement_date) AS days_of_data
FROM customer_mpan cm
JOIN `soe-prod-data-core-7529.soe_dataflows.Elec_D0071` hh
  ON cm.mpan = hh.mpan
WHERE hh.settlement_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
GROUP BY cm.account_number
```

---

## Step 4: Calculate Expected Cost per Tariff

Apply each tariff's rates to the customer's actual consumption to produce a comparable annual cost.

### Simple model (flat unit rate + standing charge)

```sql
WITH customer_consumption AS (
  -- Use Step 3 query to get total_kwh and days_of_data per account
  SELECT account_number, total_kwh, days_of_data
  FROM (/* Step 3 query */)
),

tariff_rates AS (
  SELECT
    p.id AS product_id,
    p.name AS product_name,
    MAX(CASE WHEN pr.rate_type = 'unit rate' THEN pr.value END) AS unit_rate,
    MAX(CASE WHEN pr.rate_type = 'Standing charge' THEN pr.value END) AS standing_charge_daily
  FROM `soe-prod-data-core-7529.nova_be_products_enriched.product` p
  JOIN `soe-prod-data-core-7529.nova_be_products_enriched.product_rate` pr
    ON p.id = pr.product_id
    AND pr.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  WHERE p.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
    AND p.type = 'ELEC'
  GROUP BY p.id, p.name
)

SELECT
  cc.account_number,
  tr.product_name,
  cc.total_kwh,
  -- Annualise if less than 365 days of data
  ROUND((cc.total_kwh / cc.days_of_data) * 365 * tr.unit_rate
    + 365 * tr.standing_charge_daily, 2) AS estimated_annual_cost
FROM customer_consumption cc
CROSS JOIN tariff_rates tr
ORDER BY cc.account_number, estimated_annual_cost ASC
```

> **Rate units**: Check whether `product_rate.value` is stored in pence or pounds, and whether standing charge is daily or annual. Adjust the formula accordingly.

### Comparing to current tariff

To show savings/cost vs. the customer's current tariff, join Step 1 to identify which `product_name` is their current tariff and compute the difference:

```sql
-- Wrap the above in a CTE, then:
SELECT
  account_number,
  product_name,
  estimated_annual_cost,
  estimated_annual_cost - current_tariff_cost AS cost_difference
FROM (
  SELECT
    *,
    FIRST_VALUE(estimated_annual_cost) OVER (
      PARTITION BY account_number
      ORDER BY CASE WHEN product_name = current_tariff THEN 0 ELSE 1 END
    ) AS current_tariff_cost
  FROM cost_by_tariff
)
ORDER BY account_number, cost_difference ASC
```

---

## Gaps & Next Steps

| Area | Status | Action |
|------|--------|--------|
| `Elec_D0071` schema | Not documented | Run `SELECT *` with `LIMIT` to confirm column names for MPAN, date, period, kWh |
| `product_rate.rate_type` values | Not documented | Run distinct values query (Step 2) to confirm standing charge / unit rate naming |
| Rate units (pence vs pounds) | Unknown | Check a few known tariffs against published rates |
| TOU / multi-register rates | Unknown | If `rate_type` includes peak/off-peak, the cost model needs per-period rate application using HH settlement periods |
| Tariff eligibility filter | Not documented | Explore `product` for status/availability fields; may also need to check `nova_be_products_enriched` for valid-from/valid-to dates |
| xreads / CentreStage | Not documented | May provide richer HH history than D0071 - explore if available |
| Gas extension | Out of scope (elec only) | Same approach applies using MPRN + gas reads + gas product rates |
