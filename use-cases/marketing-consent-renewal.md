# Marketing Consent Renewal Rate Analysis

Track renewal rates by marketing consent status to understand the relationship between customer engagement and retention.

---

## Overview

This analysis compares renewal and churn rates between customers who have opted into marketing communications versus those who have opted out. The hypothesis is that engaged customers (opted-in) are more likely to renew and less likely to churn.

### Key Questions Answered

1. **What is the renewal rate difference** between opted-in vs opted-out customers?
2. **How does churn rate vary** by marketing consent status?
3. **What % of opted-in customers** have provided interest data (EV, smart meter)?
4. **How are these metrics trending** week-over-week?

---

## Data Sources

### Primary Table: DotDigital Marketing Master

```sql
`soe-prod-data-core-7529.dotdigital.customer_marketing_master`
```

| Field | Description |
|-------|-------------|
| `account_number` | Links to billing/junifer accounts |
| `dotdigital_subscription_status` | Marketing consent: Subscribed, Unsubscribed, SoftBounced, HardBounced |
| `ene_acc_status` | Account status: Active, Closing, Final |
| `ele_rnwl_status` / `gas_rnwl_status` | Renewal status: On Supply, Renewed, Up for Renewal |
| `ele_cur_tarif_end` / `gas_cur_tarif_end` | Current tariff end date |
| `ele_next_tariff` / `gas_next_tarif` | Next tariff (if renewed) |

### Interests Data: Customer Setting

```sql
`soe-prod-data-core-7529.nova_be_customers_enriched.customer_setting`
```

| Field | Description |
|-------|-------------|
| `intend_to_buy_ev` | Customer interested in EV |
| `smart_meter_interest` | Customer interested in smart meter |
| `ev_tariff_marketing_consent` | Consented to EV tariff marketing |
| `marketing_opt_in` | Nova-level marketing opt-in |

### Data Linkage

```
dotdigital.customer_marketing_master (account_number)
           │
           └──► nova_be_customers_enriched.billing_account (number)
                        │
                        └──► settings_id ──► customer_setting (id)
```

### Cancellations Data

```sql
`soe-prod-data-core-7529.nova_be_customers_enriched.cancellations`
```

| Field | Description |
|-------|-------------|
| `billing_account_id` | Links to billing_account.id |
| `created_at` | Cancellation request date |
| `reason` | Cancellation reason |

---

## Metrics Definitions

### Marketing Consent Status

| Status | Classification |
|--------|----------------|
| `Subscribed` | **Opted In** - Actively receiving marketing |
| `Unsubscribed` | **Opted Out** - Manually unsubscribed |
| `SoftBounced` | **Opted Out** - Emails bouncing |
| `HardBounced` | **Opted Out** - Invalid email |
| `NULL` or other | **Unknown** - No consent data |

### Renewal Detection

A customer is considered **renewed** if any of:
- `ele_rnwl_status = 'Renewed'` OR `gas_rnwl_status = 'Renewed'`
- `ele_next_tariff IS NOT NULL` OR `gas_next_tarif IS NOT NULL`

### Churn Detection

A customer is considered **churned** if:
- Account exists in `cancellations` table within the analysis period
- OR `ene_acc_status IN ('Closing', 'Final')` with no renewal

---

## SQL Queries

### 1. Weekly Marketing Consent Summary

```sql
-- Current opt-in/opt-out counts and rates
SELECT
  dotdigital_subscription_status,
  COUNT(*) AS account_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
WHERE ene_acc_status = 'Active'
GROUP BY dotdigital_subscription_status
ORDER BY account_count DESC;
```

### 2. Renewal Rate by Consent Status

```sql
-- Compare renewal rates: Opted In vs Opted Out
SELECT
  CASE
    WHEN dotdigital_subscription_status = 'Subscribed' THEN 'Opted In'
    WHEN dotdigital_subscription_status IN ('Unsubscribed', 'SoftBounced', 'HardBounced') THEN 'Opted Out'
    ELSE 'Unknown'
  END AS consent_status,
  COUNT(*) AS contracts_ended,
  SUM(CASE
    WHEN ele_rnwl_status = 'Renewed' OR gas_rnwl_status = 'Renewed'
         OR ele_next_tariff IS NOT NULL OR gas_next_tarif IS NOT NULL
    THEN 1 ELSE 0
  END) AS renewed,
  ROUND(
    SUM(CASE WHEN ele_rnwl_status = 'Renewed' OR gas_rnwl_status = 'Renewed'
             OR ele_next_tariff IS NOT NULL OR gas_next_tarif IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    1
  ) AS renewal_rate_pct
FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
WHERE (ele_cur_tarif_end BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE()
       OR gas_cur_tarif_end BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE())
  AND ene_acc_status IN ('Active', 'Closing', 'Final')
GROUP BY 1
ORDER BY 1;
```

### 3. Renewal Rate Delta

```sql
-- Calculate the percentage point difference
WITH rates AS (
  SELECT
    CASE WHEN dotdigital_subscription_status = 'Subscribed' THEN 'Opted In' ELSE 'Opted Out' END AS consent,
    COUNT(*) AS total,
    SUM(CASE WHEN ele_rnwl_status = 'Renewed' OR gas_rnwl_status = 'Renewed'
             OR ele_next_tariff IS NOT NULL OR gas_next_tarif IS NOT NULL THEN 1 ELSE 0 END) AS renewed
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
  WHERE (ele_cur_tarif_end BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE()
         OR gas_cur_tarif_end BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE())
    AND ene_acc_status IN ('Active', 'Closing', 'Final')
    AND dotdigital_subscription_status IS NOT NULL
  GROUP BY 1
)
SELECT
  MAX(CASE WHEN consent = 'Opted In' THEN ROUND(renewed * 100.0 / total, 1) END) AS opted_in_rate,
  MAX(CASE WHEN consent = 'Opted Out' THEN ROUND(renewed * 100.0 / total, 1) END) AS opted_out_rate,
  MAX(CASE WHEN consent = 'Opted In' THEN ROUND(renewed * 100.0 / total, 1) END) -
  MAX(CASE WHEN consent = 'Opted Out' THEN ROUND(renewed * 100.0 / total, 1) END) AS delta_pp
FROM rates;
```

### 4. Interests Breakdown by Consent

```sql
-- Count customers with each interest flag
SELECT
  CASE WHEN m.dotdigital_subscription_status = 'Subscribed' THEN 'Opted In' ELSE 'Opted Out' END AS consent,
  COUNT(*) AS total,
  SUM(CASE WHEN cs.intend_to_buy_ev = TRUE THEN 1 ELSE 0 END) AS ev_interest,
  SUM(CASE WHEN cs.smart_meter_interest = TRUE THEN 1 ELSE 0 END) AS smart_meter,
  SUM(CASE WHEN cs.ev_tariff_marketing_consent = TRUE THEN 1 ELSE 0 END) AS ev_tariff,
  ROUND(SUM(CASE WHEN cs.intend_to_buy_ev = TRUE OR cs.smart_meter_interest = TRUE
                      OR cs.ev_tariff_marketing_consent = TRUE THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS any_interest_pct
FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master` m
LEFT JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.billing_account` ba
  ON m.account_number = ba.number AND ba.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
LEFT JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.customer_setting` cs
  ON ba.settings_id = cs.id AND cs.meta_effective_to_timestamp = TIMESTAMP('9999-01-01') AND cs.deleted IS NULL
WHERE m.ene_acc_status = 'Active'
GROUP BY 1;
```

### 5. Churn Rate by Consent

See `marketing-consent-renewal/churn_rate_by_consent.sql` for full query.

### 6. Week-over-Week Trend

See `marketing-consent-renewal/dashboard_query.sql` for 12-week trend query.

---

## HTML Dashboard

An interactive HTML dashboard is available at:

```
use-cases/marketing-consent-renewal/marketing_consent_dashboard.html
```

### Dashboard Features

1. **KPI Summary Cards** - Opt-in rate, renewal rates, delta metrics
2. **Renewal Rate Chart** - Stacked bar comparing renewed vs churned
3. **Interests Breakdown** - Doughnut chart of customer interests
4. **Weekly Trend** - Line chart of renewal rates over time
5. **Churn Comparison** - Bar chart of churn rates
6. **Data Tables** - Detailed breakdown with all metrics

### Updating the Dashboard

1. Run `dashboard_query.sql` in BigQuery
2. Copy the results into the `dashboardData` object in the HTML
3. Refresh the browser

---

## Expected Results

### Typical Renewal Rates by Consent

| Consent Status | Renewal Rate | Churn Rate |
|----------------|-------------:|----------:|
| Opted In | ~75-80% | ~2-3% |
| Opted Out | ~68-73% | ~4-5% |
| Unknown | ~60-68% | ~5-6% |

### Typical Delta

- **Renewal Delta**: +5 to +10 percentage points (opted-in performs better)
- **Churn Delta**: -1.5 to -2.5 percentage points (opted-in churns less)

---

## Verification Checklist

1. **Total counts match** - Compare with DotDigital export
2. **Join completeness** - Check % of accounts linked to customer_setting
3. **Renewal logic** - Verify against `product_bundle.follow_on_fl`
4. **Churn counts** - Cross-check with cancellations table
5. **Trend consistency** - Ensure week-over-week values are reasonable

---

## Related Documentation

- `weekly-deflection-report.md` - Similar report structure
- `commercial-metrics.md` - Tariffs and renewal context
- `../../CLAUDE.md` - BigQuery table reference

---

## Appendix: Full SQL Files

All SQL queries are in the `marketing-consent-renewal/` directory:

```
marketing-consent-renewal/
├── dashboard_query.sql          # Combined query for dashboard
├── renewal_rate_by_consent.sql  # Core renewal comparison
├── interests_bucket_analysis.sql # Interests breakdown
├── churn_rate_by_consent.sql    # Churn analysis
├── marketing_consent_dashboard.html  # Interactive dashboard
└── README.md                    # Quick reference
```
