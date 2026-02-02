-- Smart Meter Booking Sankey Flow Query
-- Purpose: Measure intervention impact - do waiting list customers with EMAIL offers convert better?
--
-- Flow: Entry Path → Offer Channel → Booking Status → Appointment Outcome
--
-- Key intervention: offer_channel = 'EMAIL' (proactive email offering to waiting list)
-- Compare to: offer_channel = 'SMBP' (existing portal-based offering)
--
-- Appointment outcome based on COALESCE(aes_status, mop_status)
--   - aes_status: historical data
--   - mop_status: new data
-- Appointment date based on slot_start_date_time
--
-- For Looker: Use source, target, value columns. Stage is for ordering.

WITH
-- Waiting list entries
waiting_list AS (
  SELECT DISTINCT
    billing_account_id,
    DATE(registration_date) AS registration_date
  FROM `soe-prod-data-curated.nova_be_customers_enriched.smartmeter_customer_waiting_list`
  WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
),

-- Slot offerings with channel
offerings AS (
  SELECT
    billing_account_id,
    offer_channel,
    offer_date
  FROM `soe-prod-data-curated.nova_be_customers_enriched.smartmeter_appointment_offerings`
  WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
),

-- Bookings with outcomes based on COALESCE(aes_status, mop_status)
bookings AS (
  SELECT
    CAST(billing_account_id AS INT64) AS billing_account_id,
    DATE(created_at) AS booking_date,
    source AS booking_source,
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

-- Build customer journeys
customer_journeys AS (
  SELECT
    COALESCE(o.billing_account_id, wl.billing_account_id, b.billing_account_id) AS billing_account_id,

    -- Stage 1: Entry path
    CASE
      WHEN wl.billing_account_id IS NOT NULL THEN 'Waiting List'
      ELSE 'Direct'
    END AS stage1_entry,

    -- Stage 2: Offer channel
    CASE
      WHEN o.offer_channel = 'EMAIL' THEN 'Email Offer'
      WHEN o.offer_channel = 'SMBP' THEN 'SMBP Offer'
      WHEN o.offer_channel IS NOT NULL THEN CONCAT('Other: ', o.offer_channel)
      ELSE 'No Offer Record'
    END AS stage2_offer,

    -- Stage 3: Booking status
    CASE
      WHEN b.billing_account_id IS NOT NULL THEN 'Booked'
      ELSE 'Not Booked'
    END AS stage3_booking,

    -- Stage 4: Appointment outcome
    COALESCE(b.outcome, 'No Booking') AS stage4_outcome

  FROM offerings o
  FULL OUTER JOIN waiting_list wl ON o.billing_account_id = wl.billing_account_id
  FULL OUTER JOIN bookings b ON COALESCE(o.billing_account_id, wl.billing_account_id) = b.billing_account_id
),

-- Link 1: Entry → Offer Channel
link1 AS (
  SELECT
    stage1_entry AS source,
    stage2_offer AS target,
    COUNT(*) AS value,
    1 AS stage
  FROM customer_journeys
  GROUP BY 1, 2
),

-- Link 2: Offer Channel → Booking Status
link2 AS (
  SELECT
    stage2_offer AS source,
    stage3_booking AS target,
    COUNT(*) AS value,
    2 AS stage
  FROM customer_journeys
  GROUP BY 1, 2
),

-- Link 3: Booking Status → Appointment Outcome (only for those who booked)
link3 AS (
  SELECT
    stage3_booking AS source,
    stage4_outcome AS target,
    COUNT(*) AS value,
    3 AS stage
  FROM customer_journeys
  WHERE stage3_booking = 'Booked'
  GROUP BY 1, 2
),

-- Combine all links
all_links AS (
  SELECT * FROM link1
  UNION ALL SELECT * FROM link2
  UNION ALL SELECT * FROM link3
)

SELECT source, target, value, stage
FROM all_links
WHERE value > 0
ORDER BY stage, value DESC
