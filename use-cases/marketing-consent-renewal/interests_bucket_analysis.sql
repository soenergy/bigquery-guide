-- INTERESTS BUCKET ANALYSIS
-- Count customers in each interest category and calculate % of opted-in with interests
-- Data linkage: DotDigital -> billing_account -> customer_setting

WITH marketing_with_interests AS (
  -- Join marketing consent data with customer interests
  SELECT
    m.account_number,
    m.dotdigital_subscription_status,
    m.ene_acc_status,
    -- Interest flags from customer_setting
    cs.intend_to_buy_ev,
    cs.smart_meter_interest,
    cs.ev_tariff_marketing_consent
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master` m
  LEFT JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.billing_account` ba
    ON m.account_number = ba.number
    AND ba.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  LEFT JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.customer_setting` cs
    ON ba.settings_id = cs.id
    AND cs.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
    AND cs.deleted IS NULL
  WHERE m.ene_acc_status = 'Active'
),

-- Categorize by consent status
consent_groups AS (
  SELECT
    CASE
      WHEN dotdigital_subscription_status = 'Subscribed' THEN 'Opted In'
      WHEN dotdigital_subscription_status IN ('Unsubscribed', 'SoftBounced', 'HardBounced') THEN 'Opted Out'
      ELSE 'Unknown'
    END AS consent_status,
    intend_to_buy_ev,
    smart_meter_interest,
    ev_tariff_marketing_consent,
    -- Has any interest flag set
    (COALESCE(intend_to_buy_ev, FALSE)
     OR COALESCE(smart_meter_interest, FALSE)
     OR COALESCE(ev_tariff_marketing_consent, FALSE)) AS has_any_interest
  FROM marketing_with_interests
)

-- Summary by consent status and interest
SELECT
  consent_status,
  COUNT(*) AS total_accounts,

  -- Interest bucket counts
  SUM(CASE WHEN intend_to_buy_ev = TRUE THEN 1 ELSE 0 END) AS ev_interest_count,
  SUM(CASE WHEN smart_meter_interest = TRUE THEN 1 ELSE 0 END) AS smart_meter_interest_count,
  SUM(CASE WHEN ev_tariff_marketing_consent = TRUE THEN 1 ELSE 0 END) AS ev_tariff_consent_count,
  SUM(CASE WHEN has_any_interest = TRUE THEN 1 ELSE 0 END) AS has_any_interest_count,

  -- Percentage with interests
  ROUND(SUM(CASE WHEN intend_to_buy_ev = TRUE THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS ev_interest_pct,
  ROUND(SUM(CASE WHEN smart_meter_interest = TRUE THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS smart_meter_pct,
  ROUND(SUM(CASE WHEN ev_tariff_marketing_consent = TRUE THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS ev_tariff_consent_pct,
  ROUND(SUM(CASE WHEN has_any_interest = TRUE THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS any_interest_pct

FROM consent_groups
GROUP BY consent_status
ORDER BY
  CASE consent_status
    WHEN 'Opted In' THEN 1
    WHEN 'Opted Out' THEN 2
    ELSE 3
  END;


-- DETAILED INTEREST COMBINATIONS
-- Show all combinations of interests for opted-in customers
SELECT
  COALESCE(CAST(intend_to_buy_ev AS STRING), 'NULL') AS ev_interest,
  COALESCE(CAST(smart_meter_interest AS STRING), 'NULL') AS smart_meter,
  COALESCE(CAST(ev_tariff_marketing_consent AS STRING), 'NULL') AS ev_tariff_consent,
  COUNT(*) AS account_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct_of_total
FROM (
  SELECT
    m.account_number,
    cs.intend_to_buy_ev,
    cs.smart_meter_interest,
    cs.ev_tariff_marketing_consent
  FROM `soe-prod-data-core-7529.dotdigital.customer_marketing_master` m
  LEFT JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.billing_account` ba
    ON m.account_number = ba.number
    AND ba.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  LEFT JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.customer_setting` cs
    ON ba.settings_id = cs.id
    AND cs.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
    AND cs.deleted IS NULL
  WHERE m.ene_acc_status = 'Active'
    AND m.dotdigital_subscription_status = 'Subscribed'
)
GROUP BY 1, 2, 3
ORDER BY account_count DESC;
