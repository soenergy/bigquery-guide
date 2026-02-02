-- SMBP No-Slots Funnel Query
-- Shows: SMBP No Slots → Waiting List → Offered Slot → Booked → Completed
--
-- Appointment outcome based on COALESCE(aes_status, mop_status)
--   - aes_status: historical data
--   - mop_status: new data
-- Appointment date based on slot_start_date_time
--
-- For Looker Studio: Use as funnel chart or bar chart with stage on X-axis

WITH
-- Stage 1: Customers who visited SMBP, found no slots, joined waiting list
waiting_list AS (
  SELECT
    billing_account_id,
    registration_date,
    registration_source,
    waiting_status
  FROM `soe-prod-data-curated.nova_be_customers_enriched.smartmeter_customer_waiting_list`
  WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
    AND registration_source = 'SMBP'  -- Came from Smart Meter Booking Portal
),

-- Stage 2: Those who were offered a slot
offered AS (
  SELECT
    o.billing_account_id,
    o.offer_channel,
    o.offer_date
  FROM `soe-prod-data-curated.nova_be_customers_enriched.smartmeter_appointment_offerings` o
  INNER JOIN waiting_list wl ON o.billing_account_id = wl.billing_account_id
  WHERE o.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
),

-- Stage 3 & 4: Those who booked and their outcomes
booked AS (
  SELECT
    CAST(b.billing_account_id AS INT64) AS billing_account_id,
    b.created_at AS booking_date,
    b.source AS booking_source,
    b.slot_start_date_time,
    DATE(b.slot_start_date_time) AS appointment_date,
    COALESCE(b.aes_status, b.mop_status) AS status,
    -- Normalize outcome from combined status
    CASE
      WHEN UPPER(COALESCE(b.aes_status, b.mop_status)) = 'COMPLETED'
           OR COALESCE(b.aes_status, b.mop_status) = 'Completed - Install & Leave' THEN 'Completed'
      WHEN UPPER(COALESCE(b.aes_status, b.mop_status)) = 'ABORTED' THEN 'Aborted'
      WHEN UPPER(COALESCE(b.aes_status, b.mop_status)) = 'CANCELLED' THEN 'Cancelled'
      WHEN COALESCE(b.aes_status, b.mop_status) IN ('BOOKED', 'RESCHEDULED', 'STARTED', 'ON_SITE', 'ON_ROUTE', 'PAUSED') THEN 'Pending'
      WHEN COALESCE(b.aes_status, b.mop_status) IS NULL THEN 'Pending'
      ELSE 'Other'
    END AS outcome,
    UPPER(COALESCE(b.aes_status, b.mop_status)) = 'COMPLETED'
      OR COALESCE(b.aes_status, b.mop_status) = 'Completed - Install & Leave' AS is_completed
  FROM `soe-prod-data-curated.nova_be_customers_enriched.smart_meter_bookings` b
  INNER JOIN offered o ON CAST(b.billing_account_id AS INT64) = o.billing_account_id
  WHERE b.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
),

-- Calculate funnel metrics
funnel_counts AS (
  SELECT
    COUNT(DISTINCT wl.billing_account_id) AS stage1_on_waitlist,
    COUNT(DISTINCT o.billing_account_id) AS stage2_offered_slot,
    COUNT(DISTINCT b.billing_account_id) AS stage3_booked,
    COUNT(DISTINCT CASE WHEN b.is_completed THEN b.billing_account_id END) AS stage4_completed
  FROM waiting_list wl
  LEFT JOIN offered o ON wl.billing_account_id = o.billing_account_id
  LEFT JOIN booked b ON o.billing_account_id = b.billing_account_id
)

-- Output as funnel stages (for Looker Studio funnel chart)
SELECT
  stage_number,
  stage_name,
  customers,
  ROUND(100.0 * customers / FIRST_VALUE(customers) OVER (ORDER BY stage_number), 1) AS pct_of_start,
  ROUND(100.0 * customers / LAG(customers) OVER (ORDER BY stage_number), 1) AS conversion_from_prev
FROM (
  SELECT 1 AS stage_number, '1. SMBP No Slots → Waitlist' AS stage_name, stage1_on_waitlist AS customers FROM funnel_counts
  UNION ALL
  SELECT 2, '2. Offered Slot', stage2_offered_slot FROM funnel_counts
  UNION ALL
  SELECT 3, '3. Booked', stage3_booked FROM funnel_counts
  UNION ALL
  SELECT 4, '4. Completed', stage4_completed FROM funnel_counts
)
ORDER BY stage_number
