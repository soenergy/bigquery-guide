-- RENEWAL RATE BY MARKETING CONSENT STATUS
-- Compare renewal rates between opted-in vs opted-out customers
-- Analysis period: Contracts that ended in the last 90 days

WITH contracts_ended AS (
  -- Get accounts where tariff ended in the analysis period
  SELECT
    m.account_number,
    m.dotdigital_subscription_status,
    m.ene_acc_status,
    -- Determine if tariff ended (electricity or gas)
    COALESCE(m.ele_cur_tarif_end, m.gas_cur_tarif_end) AS tariff_end_date,
    -- Check renewal status
    CASE
      WHEN m.ele_rnwl_status = 'Renewed' OR m.gas_rnwl_status = 'Renewed' THEN 'Renewed'
      WHEN m.ele_next_tariff IS NOT NULL OR m.gas_next_tarif IS NOT NULL THEN 'Renewed'
      WHEN m.ene_acc_status = 'Closing' OR m.ene_acc_status = 'Final' THEN 'Churned'
      ELSE 'Pending'
    END AS renewal_outcome
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master` m
  WHERE
    -- Tariff ended in the last 90 days
    (m.ele_cur_tarif_end BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE()
     OR m.gas_cur_tarif_end BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE())
    -- Active or recently closed accounts only
    AND m.ene_acc_status IN ('Active', 'Closing', 'Final')
),

consent_summary AS (
  SELECT
    -- Normalize consent status
    CASE
      WHEN dotdigital_subscription_status = 'Subscribed' THEN 'Opted In'
      WHEN dotdigital_subscription_status IN ('Unsubscribed', 'SoftBounced', 'HardBounced') THEN 'Opted Out'
      ELSE 'Unknown'
    END AS consent_status,
    renewal_outcome,
    COUNT(*) AS account_count
  FROM contracts_ended
  GROUP BY 1, 2
)

SELECT
  consent_status,
  SUM(account_count) AS total_contracts_ended,
  SUM(CASE WHEN renewal_outcome = 'Renewed' THEN account_count ELSE 0 END) AS renewed_count,
  SUM(CASE WHEN renewal_outcome = 'Churned' THEN account_count ELSE 0 END) AS churned_count,
  SUM(CASE WHEN renewal_outcome = 'Pending' THEN account_count ELSE 0 END) AS pending_count,

  -- Renewal rate (excluding pending)
  ROUND(
    SUM(CASE WHEN renewal_outcome = 'Renewed' THEN account_count ELSE 0 END) * 100.0 /
    NULLIF(SUM(CASE WHEN renewal_outcome IN ('Renewed', 'Churned') THEN account_count ELSE 0 END), 0),
    1
  ) AS renewal_rate_pct,

  -- Churn rate (excluding pending)
  ROUND(
    SUM(CASE WHEN renewal_outcome = 'Churned' THEN account_count ELSE 0 END) * 100.0 /
    NULLIF(SUM(CASE WHEN renewal_outcome IN ('Renewed', 'Churned') THEN account_count ELSE 0 END), 0),
    1
  ) AS churn_rate_pct

FROM consent_summary
GROUP BY consent_status
ORDER BY
  CASE consent_status
    WHEN 'Opted In' THEN 1
    WHEN 'Opted Out' THEN 2
    ELSE 3
  END;


-- RENEWAL RATE DELTA CALCULATION
-- Calculate the difference between opted-in and opted-out renewal rates
WITH renewal_rates AS (
  SELECT
    CASE
      WHEN dotdigital_subscription_status = 'Subscribed' THEN 'Opted In'
      WHEN dotdigital_subscription_status IN ('Unsubscribed', 'SoftBounced', 'HardBounced') THEN 'Opted Out'
      ELSE 'Unknown'
    END AS consent_status,
    COUNT(*) AS total_ended,
    SUM(CASE
      WHEN ele_rnwl_status = 'Renewed' OR gas_rnwl_status = 'Renewed'
           OR ele_next_tariff IS NOT NULL OR gas_next_tarif IS NOT NULL
      THEN 1 ELSE 0
    END) AS renewed
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master`
  WHERE
    (ele_cur_tarif_end BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE()
     OR gas_cur_tarif_end BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE())
    AND ene_acc_status IN ('Active', 'Closing', 'Final')
  GROUP BY 1
)

SELECT
  MAX(CASE WHEN consent_status = 'Opted In' THEN ROUND(renewed * 100.0 / NULLIF(total_ended, 0), 1) END) AS opted_in_renewal_rate,
  MAX(CASE WHEN consent_status = 'Opted Out' THEN ROUND(renewed * 100.0 / NULLIF(total_ended, 0), 1) END) AS opted_out_renewal_rate,
  MAX(CASE WHEN consent_status = 'Opted In' THEN ROUND(renewed * 100.0 / NULLIF(total_ended, 0), 1) END) -
  MAX(CASE WHEN consent_status = 'Opted Out' THEN ROUND(renewed * 100.0 / NULLIF(total_ended, 0), 1) END) AS delta_pp
FROM renewal_rates
WHERE consent_status IN ('Opted In', 'Opted Out');
