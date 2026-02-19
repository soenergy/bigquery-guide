# Tariff Cost Comparison

Estimating what a customer would pay on different electricity tariffs, based on their actual half-hourly consumption.

Takes an account number as input and outputs one row per available electricity tariff (including the current one), with estimated annual cost and savings.

---

## Key Tables

| Table | Dataset | Description |
|-------|---------|-------------|
| `w_account_product_history_d` | `soe_junifer_model` | Customer agreements - current tariff, MPAN, contract end dates |
| `w_xreads_hh_elec_f` | `soe_xreads` | Half-hourly electricity consumption from smart meters (xreads/ESG) |
| `product` | `nova_be_products_enriched` | Product/tariff catalog (ELEC, GAS, DUAL) |
| `product_rate` | `nova_be_products_enriched` | Pricing per product (standing charge, unit rates) |

### Key column mappings

| Column | Table | Notes |
|--------|-------|-------|
| `mpxn` | `w_account_product_history_d` | STRING - meter point reference (MPAN for elec) |
| `import_mpan` | `w_xreads_hh_elec_f` | INTEGER - must CAST mpxn to INT64 for join |
| `primary_value` | `w_xreads_hh_elec_f` | NUMERIC - kWh consumed per half-hour interval |
| `ending_tariff_display_name` | `w_account_product_history_d` | Current tariff name - used to flag `is_current_tariff` |

---

## Runnable Query

```sql
-- ============================================================
-- Tariff Cost Comparison
-- Input: account number (set below)
-- Output: one row per electricity tariff with estimated annual cost
-- ============================================================

DECLARE target_account STRING DEFAULT 'REPLACE_WITH_ACCOUNT_NUMBER';

-- 1. Customer's current tariff, MPAN, and contract info
WITH customer_current AS (
  SELECT
    Account_number,
    mpxn,
    ending_tariff_display_name AS current_tariff_name,
    ending_tariff_end_date AS contract_end_date,
    renewal_days_remaining,
    fixed_svt
  FROM `soe-prod-data-core-7529.soe_junifer_model.w_account_product_history_d`
  WHERE Account_number = target_account
    AND fuel_type = 'Elec'               -- TODO: verify exact value ('Elec' vs 'ELEC')
    AND active_tarifff_flag = 'Y'        -- note: 3 f's in column name
    AND most_recent_tariff_flag = 'Y'
),

-- 2. Aggregate 12 months of HH consumption for the customer's MPAN
hh_consumption AS (
  SELECT
    SUM(xr.primary_value) AS total_kwh,
    COUNT(*) AS hh_readings,
    COUNT(DISTINCT DATE(xr.timestamp)) AS days_of_data,
    MIN(xr.timestamp) AS data_from,
    MAX(xr.timestamp) AS data_to
  FROM `soe-prod-data-core-7529.soe_xreads.w_xreads_hh_elec_f` xr
  INNER JOIN customer_current cc
    ON xr.import_mpan = CAST(cc.mpxn AS INT64)
  WHERE xr.timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 365 DAY)
),

-- 3. All electricity tariff rates, pivoted to one row per product
tariff_rates AS (
  SELECT
    p.id AS product_id,
    p.name AS tariff_name,
    p.code AS tariff_code,
    -- TODO: verify exact rate_type strings - run discovery query below
    MAX(CASE WHEN LOWER(pr.rate_type) LIKE '%unit%' THEN pr.value END) AS unit_rate_p_per_kwh,
    MAX(CASE WHEN LOWER(pr.rate_type) LIKE '%standing%' THEN pr.value END) AS standing_charge_p_per_day
  FROM `soe-prod-data-core-7529.nova_be_products_enriched.product` p
  INNER JOIN `soe-prod-data-core-7529.nova_be_products_enriched.product_rate` pr
    ON p.id = pr.product_id
    AND pr.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  WHERE p.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
    AND p.type = 'ELEC'
  GROUP BY p.id, p.name, p.code
),

-- 4. Calculate estimated annual cost per tariff
cost_per_tariff AS (
  SELECT
    cc.Account_number,
    cc.current_tariff_name,
    cc.contract_end_date,
    cc.renewal_days_remaining,
    cc.fixed_svt AS current_tariff_type,
    tr.tariff_name,
    tr.tariff_code,

    -- Consumption
    hc.total_kwh,
    hc.days_of_data,
    ROUND(hc.total_kwh / hc.days_of_data * 365, 2) AS annualised_kwh,

    -- Rates
    tr.unit_rate_p_per_kwh,
    tr.standing_charge_p_per_day,

    -- Estimated annual cost in £ (assumes rates are stored in pence)
    -- TODO: verify rate units - see discovery queries below
    ROUND(
      (
        (hc.total_kwh / hc.days_of_data * 365) * tr.unit_rate_p_per_kwh
        + 365 * tr.standing_charge_p_per_day
      ) / 100,
      2
    ) AS estimated_annual_cost_gbp,

    -- Flag current tariff
    cc.current_tariff_name = tr.tariff_name AS is_current_tariff,

    -- Data quality
    hc.data_from,
    hc.data_to,
    hc.hh_readings
  FROM customer_current cc
  CROSS JOIN hh_consumption hc
  CROSS JOIN tariff_rates tr
  WHERE tr.unit_rate_p_per_kwh IS NOT NULL
)

-- 5. Final output with savings vs current tariff
SELECT
  Account_number,
  current_tariff_name,
  contract_end_date,
  renewal_days_remaining,
  current_tariff_type,
  tariff_name,
  tariff_code,
  is_current_tariff,
  annualised_kwh,
  unit_rate_p_per_kwh,
  standing_charge_p_per_day,
  estimated_annual_cost_gbp,

  -- Savings vs current tariff (positive = cheaper than current)
  ROUND(
    FIRST_VALUE(estimated_annual_cost_gbp) OVER (
      ORDER BY CASE WHEN is_current_tariff THEN 0 ELSE 1 END
    ) - estimated_annual_cost_gbp,
    2
  ) AS saving_vs_current_gbp,

  -- Data quality fields
  data_from,
  data_to,
  days_of_data,
  hh_readings
FROM cost_per_tariff
ORDER BY estimated_annual_cost_gbp ASC
```

---

## Discovery Queries

Run these first to verify assumptions and fill in TODOs.

### 1. Check `fuel_type` values in account product history

```sql
SELECT DISTINCT fuel_type
FROM `soe-prod-data-core-7529.soe_junifer_model.w_account_product_history_d`
LIMIT 10
```

### 2. Check `rate_type` values in product_rate

```sql
SELECT DISTINCT pr.rate_type, COUNT(*) AS rate_count
FROM `soe-prod-data-core-7529.nova_be_products_enriched.product_rate` pr
WHERE pr.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
GROUP BY pr.rate_type
ORDER BY rate_count DESC
```

Update the `CASE WHEN` patterns in the `tariff_rates` CTE once you know the exact strings.

### 3. Verify rate units (pence vs pounds)

```sql
-- Pick a known tariff and compare its rates to published values
SELECT p.name, pr.rate_type, pr.value
FROM `soe-prod-data-core-7529.nova_be_products_enriched.product` p
JOIN `soe-prod-data-core-7529.nova_be_products_enriched.product_rate` pr
  ON p.id = pr.product_id
  AND pr.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
WHERE p.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND p.type = 'ELEC'
LIMIT 20
```

If values are ~20-30 they're likely pence/kWh. If ~0.2-0.3 they're pounds. Adjust the `/100` divisor in the cost formula accordingly.

### 4. Verify tariff name matching

```sql
-- Check if current tariff name from account history matches any Nova product name
SELECT DISTINCT ending_tariff_display_name
FROM `soe-prod-data-core-7529.soe_junifer_model.w_account_product_history_d`
WHERE fuel_type = 'Elec'
  AND active_tarifff_flag = 'Y'
ORDER BY ending_tariff_display_name
LIMIT 30
```

Compare against:

```sql
SELECT DISTINCT name
FROM `soe-prod-data-core-7529.nova_be_products_enriched.product`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND type = 'ELEC'
ORDER BY name
LIMIT 30
```

If names don't match directly, you may need to join via `pb_dfn_id` → `junifer_enriched.product_bundle_dfn` instead.

### 5. Check xreads data availability for an account

```sql
-- Verify HH data exists and check volume
SELECT
  COUNT(*) AS readings,
  MIN(timestamp) AS earliest,
  MAX(timestamp) AS latest,
  SUM(primary_value) AS total_kwh
FROM `soe-prod-data-core-7529.soe_xreads.w_xreads_hh_elec_f` xr
WHERE xr.import_mpan = CAST('YOUR_MPAN_HERE' AS INT64)
  AND xr.timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 365 DAY)
```

---

## Looker Studio Notes

- The `DECLARE` statement works in BigQuery console but not directly in Looker Studio. To parameterise in Looker Studio, replace `target_account` with a [Looker Studio parameter](https://support.google.com/looker-studio/answer/9002005): `@DS_target_account`.
- Output is one row per tariff, pre-sorted by cost. Useful Looker Studio visualisations:
  - **Bar chart**: `tariff_name` vs `estimated_annual_cost_gbp`, colour by `is_current_tariff`
  - **Table**: all columns, conditional formatting on `saving_vs_current_gbp`
  - **Scorecard**: filter to `is_current_tariff = TRUE` for current cost

---

## Assumptions & Gaps

| Area | Assumption | Action to Verify |
|------|------------|------------------|
| `fuel_type` value | `'Elec'` | Run discovery query 1 |
| `rate_type` strings | Contains 'unit' and 'standing' (case-insensitive LIKE) | Run discovery query 2 |
| Rate units | Values in pence (divided by 100 for £) | Run discovery query 3 |
| Standing charge | Per day | Run discovery query 3 |
| Current tariff matching | `ending_tariff_display_name` = `product.name` | Run discovery query 4 |
| Tariff eligibility | All ELEC products included (no active/available filter yet) | Explore `product` for status fields |
| TOU rates | Not handled — assumes flat unit rate | If rate_type has peak/off-peak, needs per-period calculation |
| Gas | Out of scope | Same approach with MPRN + gas reads + gas product rates |
