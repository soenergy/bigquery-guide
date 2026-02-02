-- Smart Meter Intervention Conversion Stats
-- Purpose: Summary statistics to measure EMAIL offer intervention effectiveness
--
-- Appointment outcome based on COALESCE(aes_status, mop_status)
--   - aes_status: historical data
--   - mop_status: new data
-- Appointment date based on slot_start_date_time
--
-- Key metrics:
--   - Booking rate: % of offered customers who make a booking
--   - Completion rate: % of booked customers with COMPLETED status
--   - End-to-end rate: % of offered customers who complete installation

WITH waiting_list AS (
  SELECT DISTINCT billing_account_id
  FROM `soe-prod-data-curated.nova_be_customers_enriched.smartmeter_customer_waiting_list`
  WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
),

offerings AS (
  SELECT billing_account_id, offer_channel
  FROM `soe-prod-data-curated.nova_be_customers_enriched.smartmeter_appointment_offerings`
  WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
),

bookings AS (
  SELECT
    CAST(billing_account_id AS INT64) AS billing_account_id,
    slot_start_date_time,
    DATE(slot_start_date_time) AS appointment_date,
    COALESCE(aes_status, mop_status) AS status,
    -- Normalize outcome from combined status
    CASE
      WHEN UPPER(COALESCE(aes_status, mop_status)) = 'COMPLETED'
           OR COALESCE(aes_status, mop_status) = 'Completed - Install & Leave' THEN 'Completed'
      WHEN UPPER(COALESCE(aes_status, mop_status)) = 'ABORTED' THEN 'Aborted'
      WHEN UPPER(COALESCE(aes_status, mop_status)) = 'CANCELLED' THEN 'Cancelled'
      WHEN COALESCE(aes_status, mop_status) IN ('BOOKED', 'RESCHEDULED', 'STARTED', 'ON_SITE', 'ON_ROUTE', 'PAUSED') THEN 'Pending'
      WHEN COALESCE(aes_status, mop_status) IS NULL THEN 'Pending'
      ELSE 'Other'
    END AS outcome
  FROM `soe-prod-data-curated.nova_be_customers_enriched.smart_meter_bookings`
  WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
),

journeys AS (
  SELECT
    CASE WHEN wl.billing_account_id IS NOT NULL THEN 'Waiting List' ELSE 'Direct' END AS entry_path,
    COALESCE(o.offer_channel, 'No Offer') AS offer_channel,
    b.billing_account_id IS NOT NULL AS booked,
    b.outcome
  FROM offerings o
  FULL OUTER JOIN waiting_list wl ON o.billing_account_id = wl.billing_account_id
  FULL OUTER JOIN bookings b ON COALESCE(o.billing_account_id, wl.billing_account_id) = b.billing_account_id
)

SELECT
  entry_path,
  offer_channel,
  COUNT(*) AS total_customers,
  SUM(CASE WHEN booked THEN 1 ELSE 0 END) AS booked_count,
  ROUND(100.0 * SUM(CASE WHEN booked THEN 1 ELSE 0 END) / COUNT(*), 1) AS booking_rate_pct,
  SUM(CASE WHEN outcome = 'Completed' THEN 1 ELSE 0 END) AS completed_count,
  ROUND(100.0 * SUM(CASE WHEN outcome = 'Completed' THEN 1 ELSE 0 END) /
        NULLIF(SUM(CASE WHEN booked THEN 1 ELSE 0 END), 0), 1) AS completion_rate_of_booked_pct,
  ROUND(100.0 * SUM(CASE WHEN outcome = 'Completed' THEN 1 ELSE 0 END) / COUNT(*), 1) AS end_to_end_completion_pct,
  SUM(CASE WHEN outcome = 'Aborted' THEN 1 ELSE 0 END) AS aborted_count,
  SUM(CASE WHEN outcome = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled_count,
  SUM(CASE WHEN outcome = 'Pending' THEN 1 ELSE 0 END) AS pending_count
FROM journeys
GROUP BY 1, 2
ORDER BY 1, 2
