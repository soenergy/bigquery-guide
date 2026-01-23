-- CHURN RATE BY MARKETING CONSENT STATUS
-- Compare churn rates between opted-in vs opted-out customers
-- Links cancellations to marketing consent data

WITH active_accounts_start AS (
  -- Snapshot of active accounts at start of period (90 days ago)
  SELECT
    m.account_number,
    m.dotdigital_subscription_status,
    m.ene_acc_status,
    m.ene_acc_created_dt
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master` m
  WHERE m.ene_acc_status = 'Active'
    -- Account was active before the analysis period started
    AND DATE(m.ene_acc_created_dt) < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
),

cancellations_in_period AS (
  -- Get cancellations that occurred in the last 90 days
  SELECT DISTINCT
    ba.number AS account_number,
    c.created_at AS cancellation_date,
    c.reason AS cancellation_reason,
    c.type AS cancellation_type
  FROM `soe-prod-data-core-7529.nova_be_customers_enriched.cancellations` c
  INNER JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.billing_account` ba
    ON c.billing_account_id = ba.id
    AND ba.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  WHERE c.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
    AND c.deleted_at IS NULL
    AND DATE(c.created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
),

accounts_with_churn AS (
  SELECT
    a.account_number,
    CASE
      WHEN a.dotdigital_subscription_status = 'Subscribed' THEN 'Opted In'
      WHEN a.dotdigital_subscription_status IN ('Unsubscribed', 'SoftBounced', 'HardBounced') THEN 'Opted Out'
      ELSE 'Unknown'
    END AS consent_status,
    CASE WHEN c.account_number IS NOT NULL THEN 1 ELSE 0 END AS churned,
    c.cancellation_reason
  FROM active_accounts_start a
  LEFT JOIN cancellations_in_period c
    ON a.account_number = c.account_number
)

SELECT
  consent_status,
  COUNT(*) AS active_at_period_start,
  SUM(churned) AS churned_count,
  COUNT(*) - SUM(churned) AS retained_count,
  ROUND(SUM(churned) * 100.0 / COUNT(*), 2) AS churn_rate_pct,
  ROUND((COUNT(*) - SUM(churned)) * 100.0 / COUNT(*), 2) AS retention_rate_pct
FROM accounts_with_churn
GROUP BY consent_status
ORDER BY
  CASE consent_status
    WHEN 'Opted In' THEN 1
    WHEN 'Opted Out' THEN 2
    ELSE 3
  END;


-- CHURN REASONS BY CONSENT STATUS
-- Breakdown of why customers are leaving, segmented by marketing consent
SELECT
  CASE
    WHEN a.dotdigital_subscription_status = 'Subscribed' THEN 'Opted In'
    WHEN a.dotdigital_subscription_status IN ('Unsubscribed', 'SoftBounced', 'HardBounced') THEN 'Opted Out'
    ELSE 'Unknown'
  END AS consent_status,
  COALESCE(c.reason, 'Unknown') AS cancellation_reason,
  COUNT(*) AS cancellation_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (
    PARTITION BY CASE
      WHEN a.dotdigital_subscription_status = 'Subscribed' THEN 'Opted In'
      WHEN a.dotdigital_subscription_status IN ('Unsubscribed', 'SoftBounced', 'HardBounced') THEN 'Opted Out'
      ELSE 'Unknown'
    END
  ), 1) AS pct_of_consent_group
FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master` a
INNER JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.billing_account` ba
  ON a.account_number = ba.number
  AND ba.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
INNER JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.cancellations` c
  ON ba.id = c.billing_account_id
  AND c.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND c.deleted_at IS NULL
  AND DATE(c.created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
GROUP BY 1, 2
ORDER BY consent_status, cancellation_count DESC;


-- CHURN RATE DELTA
-- Calculate the difference between opted-in and opted-out churn rates
WITH churn_rates AS (
  SELECT
    CASE
      WHEN a.dotdigital_subscription_status = 'Subscribed' THEN 'Opted In'
      WHEN a.dotdigital_subscription_status IN ('Unsubscribed', 'SoftBounced', 'HardBounced') THEN 'Opted Out'
      ELSE 'Unknown'
    END AS consent_status,
    COUNT(*) AS total_active,
    SUM(CASE WHEN c.account_number IS NOT NULL THEN 1 ELSE 0 END) AS churned
  FROM (
    SELECT account_number, dotdigital_subscription_status
    FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
    WHERE ene_acc_status = 'Active'
      AND DATE(ene_acc_created_dt) < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  ) a
  LEFT JOIN (
    SELECT DISTINCT ba.number AS account_number
    FROM `soe-prod-data-core-7529.nova_be_customers_enriched.cancellations` c
    INNER JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.billing_account` ba
      ON c.billing_account_id = ba.id
      AND ba.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
    WHERE c.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
      AND c.deleted_at IS NULL
      AND DATE(c.created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  ) c ON a.account_number = c.account_number
  GROUP BY 1
)

SELECT
  MAX(CASE WHEN consent_status = 'Opted In' THEN ROUND(churned * 100.0 / NULLIF(total_active, 0), 2) END) AS opted_in_churn_rate,
  MAX(CASE WHEN consent_status = 'Opted Out' THEN ROUND(churned * 100.0 / NULLIF(total_active, 0), 2) END) AS opted_out_churn_rate,
  MAX(CASE WHEN consent_status = 'Opted Out' THEN ROUND(churned * 100.0 / NULLIF(total_active, 0), 2) END) -
  MAX(CASE WHEN consent_status = 'Opted In' THEN ROUND(churned * 100.0 / NULLIF(total_active, 0), 2) END) AS delta_pp
FROM churn_rates
WHERE consent_status IN ('Opted In', 'Opted Out');
