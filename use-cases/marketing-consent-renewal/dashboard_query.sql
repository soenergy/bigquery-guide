-- MARKETING CONSENT RENEWAL DASHBOARD - Combined Query
-- Returns all metrics needed for the HTML dashboard in a single query
-- Run this query weekly to populate the dashboard

-- ============================================================================
-- SECTION 1: WEEKLY MARKETING CONSENT SUMMARY (with cohort tracking)
-- ============================================================================
WITH weekly_consent_summary AS (
  SELECT
    dotdigital_subscription_status,
    -- Current snapshot (active today)
    COUNT(*) AS account_count,
    SUM(CASE WHEN ele_rnwl_status = 'Renewed' OR gas_rnwl_status = 'Renewed' THEN 1 ELSE 0 END) AS renewed_count,
    SUM(CASE WHEN ene_acc_status = 'Closing' THEN 1 ELSE 0 END) AS closing_count,
    -- Cohort: Active at start of period (created before 90 days ago)
    SUM(CASE WHEN DATE(ene_acc_created_dt) < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) THEN 1 ELSE 0 END) AS active_at_period_start,
    -- Joined during period (created within last 90 days)
    SUM(CASE WHEN DATE(ene_acc_created_dt) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) THEN 1 ELSE 0 END) AS joined_during_period
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
  WHERE ene_acc_status = 'Active'
  GROUP BY dotdigital_subscription_status
),

-- Customers who LEFT during the 90-day period (were active, now Closing/Final)
customers_left AS (
  SELECT
    dotdigital_subscription_status,
    COUNT(*) AS left_during_period
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
  WHERE ene_acc_status IN ('Closing', 'Final')
    AND DATE(ene_acc_closed_dt) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  GROUP BY dotdigital_subscription_status
),

-- ============================================================================
-- SECTION 2: RENEWAL RATE BY CONSENT (90-day cohort)
-- ============================================================================
renewal_cohort AS (
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
    SUM(CASE
      WHEN ene_acc_status IN ('Closing', 'Final')
           AND (ele_rnwl_status != 'Renewed' OR ele_rnwl_status IS NULL)
           AND (gas_rnwl_status != 'Renewed' OR gas_rnwl_status IS NULL)
      THEN 1 ELSE 0
    END) AS churned
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
  WHERE (ele_cur_tarif_end BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE()
         OR gas_cur_tarif_end BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE())
    AND ene_acc_status IN ('Active', 'Closing', 'Final')
  GROUP BY 1
),

-- ============================================================================
-- SECTION 3: INTERESTS BUCKETS (with linkage to customer_setting)
-- ============================================================================
interests_summary AS (
  SELECT
    CASE
      WHEN m.dotdigital_subscription_status = 'Subscribed' THEN 'Opted In'
      WHEN m.dotdigital_subscription_status IN ('Unsubscribed', 'SoftBounced', 'HardBounced') THEN 'Opted Out'
      ELSE 'Unknown'
    END AS consent_status,
    COUNT(*) AS total,
    SUM(CASE WHEN cs.intend_to_buy_ev = TRUE THEN 1 ELSE 0 END) AS ev_interest,
    SUM(CASE WHEN cs.smart_meter_interest = TRUE THEN 1 ELSE 0 END) AS smart_meter_interest,
    SUM(CASE WHEN cs.ev_tariff_marketing_consent = TRUE THEN 1 ELSE 0 END) AS ev_tariff_consent,
    SUM(CASE WHEN cs.intend_to_buy_ev = TRUE
                  OR cs.smart_meter_interest = TRUE
                  OR cs.ev_tariff_marketing_consent = TRUE THEN 1 ELSE 0 END) AS any_interest
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master` m
  LEFT JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.billing_account` ba
    ON m.account_number = ba.number
    AND ba.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  LEFT JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.customer_setting` cs
    ON ba.settings_id = cs.id
    AND cs.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
    AND cs.deleted IS NULL
  WHERE m.ene_acc_status = 'Active'
  GROUP BY 1
),

-- ============================================================================
-- SECTION 4: WEEK-OVER-WEEK TREND (12 weeks)
-- Uses product_bundle for historical tracking
-- ============================================================================
weekly_trend AS (
  SELECT
    DATE_TRUNC(DATE(pb.contracted_to_dttm), WEEK(MONDAY)) AS week_ending,
    CASE
      WHEN m.dotdigital_subscription_status = 'Subscribed' THEN 'Opted In'
      ELSE 'Opted Out'
    END AS consent_status,
    COUNT(DISTINCT pb.account_fk) AS contracts_ended,
    SUM(CASE WHEN pb.follow_on_fl = 'Y' THEN 1 ELSE 0 END) AS renewed
  FROM `soe-prod-data-core-7529.junifer_enriched.product_bundle` pb
  INNER JOIN `soe-prod-data-core-7529.junifer_enriched.account` a
    ON pb.account_fk = a.id
    AND a.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  LEFT JOIN `soe-prod-data-core-7529.dotdigital.customer_marketing_master` m
    ON a.number = m.account_number
  WHERE pb.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
    AND pb.cancel_fl != 'Y'
    AND DATE(pb.contracted_to_dttm) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 12 WEEK) AND CURRENT_DATE()
  GROUP BY 1, 2
)

-- ============================================================================
-- OUTPUT: Combined results for dashboard
-- ============================================================================

-- Result Set 1: Overall Summary (KPI Cards) with cohort breakdown
SELECT
  'summary' AS result_type,
  CAST(SUM(CASE WHEN w.dotdigital_subscription_status = 'Subscribed' THEN w.account_count ELSE 0 END) AS STRING) AS opted_in_count,
  CAST(SUM(CASE WHEN w.dotdigital_subscription_status IN ('Unsubscribed', 'SoftBounced', 'HardBounced') THEN w.account_count ELSE 0 END) AS STRING) AS opted_out_count,
  CAST(SUM(w.account_count) AS STRING) AS total_active_accounts,
  CAST(ROUND(
    SUM(CASE WHEN w.dotdigital_subscription_status = 'Subscribed' THEN w.account_count ELSE 0 END) * 100.0 /
    NULLIF(SUM(w.account_count), 0), 1
  ) AS STRING) AS opt_in_rate_pct,
  'current_snapshot' AS consent_status,
  CAST(SUM(w.joined_during_period) AS STRING) AS metric_value,  -- New customers in period
  CAST(SUM(COALESCE(l.left_during_period, 0)) AS STRING) AS week_ending  -- Customers who left
FROM weekly_consent_summary w
LEFT JOIN customers_left l ON w.dotdigital_subscription_status = l.dotdigital_subscription_status

UNION ALL

-- Result Set 2: Renewal Rates by Consent
SELECT
  'renewal_rate' AS result_type,
  CAST(contracts_ended AS STRING) AS opted_in_count,
  CAST(renewed AS STRING) AS opted_out_count,
  CAST(churned AS STRING) AS total_active_accounts,
  CAST(ROUND(renewed * 100.0 / NULLIF(contracts_ended, 0), 1) AS STRING) AS opt_in_rate_pct,
  consent_status,
  CAST(ROUND(renewed * 100.0 / NULLIF(contracts_ended, 0), 1) AS STRING) AS metric_value,
  NULL AS week_ending
FROM renewal_cohort

UNION ALL

-- Result Set 3: Interests Summary
SELECT
  'interests' AS result_type,
  CAST(ev_interest AS STRING) AS opted_in_count,
  CAST(smart_meter_interest AS STRING) AS opted_out_count,
  CAST(ev_tariff_consent AS STRING) AS total_active_accounts,
  CAST(ROUND(any_interest * 100.0 / NULLIF(total, 0), 1) AS STRING) AS opt_in_rate_pct,
  consent_status,
  CAST(any_interest AS STRING) AS metric_value,
  NULL AS week_ending
FROM interests_summary

UNION ALL

-- Result Set 4: Weekly Trend
SELECT
  'weekly_trend' AS result_type,
  CAST(contracts_ended AS STRING) AS opted_in_count,
  CAST(renewed AS STRING) AS opted_out_count,
  CAST(ROUND(renewed * 100.0 / NULLIF(contracts_ended, 0), 1) AS STRING) AS total_active_accounts,
  NULL AS opt_in_rate_pct,
  consent_status,
  CAST(ROUND(renewed * 100.0 / NULLIF(contracts_ended, 0), 1) AS STRING) AS metric_value,
  CAST(week_ending AS STRING) AS week_ending
FROM weekly_trend
ORDER BY result_type, consent_status, week_ending;


-- ============================================================================
-- COHORT ANALYSIS QUERY
-- Properly tracks customers across the 90-day period
-- ============================================================================

/*
-- COHORT SUMMARY: Track customer movement over 90-day period
WITH
-- Customers active TODAY
current_active AS (
  SELECT
    CASE
      WHEN dotdigital_subscription_status = 'Subscribed' THEN 'Opted In'
      WHEN dotdigital_subscription_status IN ('Unsubscribed', 'SoftBounced', 'HardBounced') THEN 'Opted Out'
      ELSE 'Unknown'
    END AS consent_status,
    account_number,
    ene_acc_created_dt,
    'Active' AS current_state
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
  WHERE ene_acc_status = 'Active'
),

-- Customers who LEFT in the last 90 days (Closing/Final with recent close date)
recently_left AS (
  SELECT
    CASE
      WHEN dotdigital_subscription_status = 'Subscribed' THEN 'Opted In'
      WHEN dotdigital_subscription_status IN ('Unsubscribed', 'SoftBounced', 'HardBounced') THEN 'Opted Out'
      ELSE 'Unknown'
    END AS consent_status,
    account_number,
    ene_acc_created_dt,
    'Left' AS current_state
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
  WHERE ene_acc_status IN ('Closing', 'Final')
    AND DATE(ene_acc_closed_dt) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
),

-- Combine for full cohort view
all_accounts AS (
  SELECT * FROM current_active
  UNION ALL
  SELECT * FROM recently_left
)

SELECT
  consent_status,

  -- Active at START of 90-day period (existed before period, still here OR left during period)
  SUM(CASE
    WHEN DATE(ene_acc_created_dt) < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
    THEN 1 ELSE 0
  END) AS active_at_period_start,

  -- JOINED during period (created in last 90 days, currently active)
  SUM(CASE
    WHEN DATE(ene_acc_created_dt) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
         AND current_state = 'Active'
    THEN 1 ELSE 0
  END) AS joined_during_period,

  -- LEFT during period
  SUM(CASE WHEN current_state = 'Left' THEN 1 ELSE 0 END) AS left_during_period,

  -- Active at END of period (current snapshot)
  SUM(CASE WHEN current_state = 'Active' THEN 1 ELSE 0 END) AS active_at_period_end,

  -- Churn rate = Left / Active at Start
  ROUND(
    SUM(CASE WHEN current_state = 'Left' THEN 1 ELSE 0 END) * 100.0 /
    NULLIF(SUM(CASE WHEN DATE(ene_acc_created_dt) < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) THEN 1 ELSE 0 END), 0),
    2
  ) AS churn_rate_pct,

  -- Net growth = (Joined - Left) / Active at Start
  ROUND(
    (SUM(CASE WHEN DATE(ene_acc_created_dt) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND current_state = 'Active' THEN 1 ELSE 0 END) -
     SUM(CASE WHEN current_state = 'Left' THEN 1 ELSE 0 END)) * 100.0 /
    NULLIF(SUM(CASE WHEN DATE(ene_acc_created_dt) < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) THEN 1 ELSE 0 END), 0),
    2
  ) AS net_growth_pct

FROM all_accounts
GROUP BY consent_status
ORDER BY consent_status;
*/


-- ============================================================================
-- DATA GRAIN VERIFICATION
-- Run this FIRST to understand what we're counting
-- ============================================================================

-- Q1: Accounts vs Customers summary
SELECT
  COUNT(*) AS total_billing_accounts,
  COUNT(DISTINCT cus_customer_number) AS unique_customers,
  ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT cus_customer_number), 2) AS accounts_per_customer,
  -- Fuel breakdown
  SUM(CASE WHEN ele_mpan IS NOT NULL AND gas_mprn IS NOT NULL THEN 1 ELSE 0 END) AS dual_fuel_accounts,
  SUM(CASE WHEN ele_mpan IS NOT NULL AND gas_mprn IS NULL THEN 1 ELSE 0 END) AS elec_only_accounts,
  SUM(CASE WHEN ele_mpan IS NULL AND gas_mprn IS NOT NULL THEN 1 ELSE 0 END) AS gas_only_accounts
FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
WHERE ene_acc_status = 'Active';


-- Q2: How many customers have multiple accounts?
SELECT
  num_accounts,
  COUNT(*) AS customer_count,
  SUM(COUNT(*)) OVER() AS total_customers,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM (
  SELECT
    cus_customer_number,
    COUNT(DISTINCT account_number) AS num_accounts
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
  WHERE ene_acc_status = 'Active'
    AND cus_customer_number IS NOT NULL
  GROUP BY cus_customer_number
)
GROUP BY num_accounts
ORDER BY num_accounts;


-- Q3: IS CONSENT AT ACCOUNT OR CUSTOMER LEVEL?
-- Check if customers with multiple accounts have SAME or DIFFERENT consent
SELECT
  CASE
    WHEN num_accounts = 1 THEN 'Single account'
    WHEN consent_statuses = 1 THEN 'Multi-account, SAME consent'
    ELSE 'Multi-account, DIFFERENT consent'
  END AS consent_consistency,
  COUNT(*) AS customer_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM (
  SELECT
    cus_customer_number,
    COUNT(DISTINCT account_number) AS num_accounts,
    COUNT(DISTINCT dotdigital_subscription_status) AS consent_statuses
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
  WHERE ene_acc_status = 'Active'
    AND cus_customer_number IS NOT NULL
  GROUP BY cus_customer_number
)
GROUP BY 1
ORDER BY customer_count DESC;


-- Q4: Examples of customers with DIFFERENT consent across accounts
SELECT
  cus_customer_number,
  account_number,
  dotdigital_subscription_status,
  ene_acc_created_dt
FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
WHERE cus_customer_number IN (
  SELECT cus_customer_number
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
  WHERE ene_acc_status = 'Active'
  GROUP BY cus_customer_number
  HAVING COUNT(DISTINCT account_number) > 1
     AND COUNT(DISTINCT dotdigital_subscription_status) > 1
  LIMIT 5
)
AND ene_acc_status = 'Active'
ORDER BY cus_customer_number, ene_acc_created_dt;


-- Q5: Consent summary at CUSTOMER level (not account)
-- If customer has ANY opted-in account, count as opted-in
SELECT
  CASE
    WHEN MAX(CASE WHEN dotdigital_subscription_status = 'Subscribed' THEN 1 ELSE 0 END) = 1 THEN 'Opted In (any account)'
    ELSE 'Opted Out (all accounts)'
  END AS customer_consent,
  COUNT(DISTINCT cus_customer_number) AS unique_customers
FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
WHERE ene_acc_status = 'Active'
  AND cus_customer_number IS NOT NULL
GROUP BY cus_customer_number;

-- Wrapped version for summary:
SELECT
  customer_consent,
  COUNT(*) AS customers,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM (
  SELECT
    cus_customer_number,
    CASE
      WHEN MAX(CASE WHEN dotdigital_subscription_status = 'Subscribed' THEN 1 ELSE 0 END) = 1 THEN 'Opted In'
      ELSE 'Opted Out'
    END AS customer_consent
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
  WHERE ene_acc_status = 'Active'
    AND cus_customer_number IS NOT NULL
  GROUP BY cus_customer_number
)
GROUP BY customer_consent;


-- ============================================================================
-- SIMPLIFIED DASHBOARD DATA EXPORT
-- Run this for easier JSON export to the HTML dashboard
-- ============================================================================

/*
-- KPI Summary (current snapshot) - BY UNIQUE CUSTOMERS
SELECT
  COUNT(DISTINCT cus_customer_number) AS unique_customers,
  COUNT(*) AS billing_accounts,
  SUM(CASE WHEN dotdigital_subscription_status = 'Subscribed' THEN 1 ELSE 0 END) AS opted_in_accounts,
  ROUND(SUM(CASE WHEN dotdigital_subscription_status = 'Subscribed' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS opt_in_rate
FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
WHERE ene_acc_status = 'Active';
*/
