-- Meter Point Consent State Transitions (Sankey Diagram)
--
-- Shows how meter points transition between consent states
-- between two configurable dates, per consent_definition.
--
-- Usage: Open in Looker Studio as a BigQuery custom query.
-- Add Looker Studio parameters for date_from / date_to,
-- or edit the inline timestamps below.
-- Visualise with a Sankey chart (or use the Google Sankey community viz).

WITH state_at_start AS (
  -- State of each meter point at the start date
  SELECT
    meter_point_id,
    consent_definition,
    setting AS state_from
  FROM `soe-prod-data-curated.nova_be_assets_enriched.meter_point_consent`
  WHERE meta_effective_to_timestamp = TIMESTAMP '9999-01-01 00:00:00 UTC'
    AND from_date <= TIMESTAMP '2026-01-01 00:00:00 UTC'
    AND (to_date IS NULL OR to_date > TIMESTAMP '2026-01-01 00:00:00 UTC')
),

state_at_end AS (
  -- State of each meter point at the end date
  SELECT
    meter_point_id,
    consent_definition,
    setting AS state_to
  FROM `soe-prod-data-curated.nova_be_assets_enriched.meter_point_consent`
  WHERE meta_effective_to_timestamp = TIMESTAMP '9999-01-01 00:00:00 UTC'
    AND from_date <= TIMESTAMP(CURRENT_DATE())
    AND (to_date IS NULL OR to_date > TIMESTAMP(CURRENT_DATE()))
),

transitions AS (
  SELECT
    COALESCE(s.consent_definition, e.consent_definition) AS consent_definition,
    COALESCE(s.meter_point_id, e.meter_point_id) AS meter_point_id,
    IF(COALESCE(s.state_from, 'NO_CONSENT') = 'NO_CONSENT', 'NO_CONSENT', s.state_from) || ' (before)' AS source,
    IF(COALESCE(e.state_to, 'NO_CONSENT') = 'NO_CONSENT', 'NO_CONSENT', e.state_to) || ' (after)' AS target
  FROM state_at_start s
  FULL OUTER JOIN state_at_end e
    ON s.meter_point_id = e.meter_point_id
    AND s.consent_definition = e.consent_definition
)

SELECT
  consent_definition,
  source,
  target,
  COUNT(*) AS meter_point_count
FROM transitions
GROUP BY consent_definition, source, target
ORDER BY consent_definition, meter_point_count DESC
