-- SMBP No-Slots Funnel with Filter Dimensions
-- Shows: SMBP No Slots → Waiting List → Offered Slot → Booked → Completed
--
-- Appointment outcome based on COALESCE(aes_status, mop_status)
--   - aes_status: historical data
--   - mop_status: new data
-- Appointment date based on slot_start_date_time
--
-- For Looker Studio: Add filter controls on offer_channel, first_contact_week, appointment_week
-- Use as funnel chart with stage_name dimension and customers metric

WITH
-- Customers who visited SMBP, found no slots, joined waiting list
waiting_list AS (
  SELECT
    billing_account_id,
    DATE(registration_date) AS registration_date,
    registration_source,
    waiting_status
  FROM `soe-prod-data-curated.nova_be_customers_enriched.smartmeter_customer_waiting_list`
  WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
    AND registration_source = 'SMBP'
),

-- Slot offerings
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

-- Build customer journeys with all stages
customer_journeys AS (
  SELECT
    wl.billing_account_id,
    wl.registration_date,

    -- First contact date (earliest of registration, offer, or booking)
    LEAST(
      COALESCE(wl.registration_date, DATE '9999-12-31'),
      COALESCE(o.offer_date, DATE '9999-12-31'),
      COALESCE(b.booking_date, DATE '9999-12-31')
    ) AS first_contact_date,

    -- Filter dimensions
    COALESCE(o.offer_channel, 'Not Yet Offered') AS offer_channel,
    o.offer_date,
    FORMAT_DATE('%Y-W%V', o.offer_date) AS offer_week,
    FORMAT_DATE('%Y-%m', o.offer_date) AS offer_month,
    FORMAT_DATE('%Y-W%V', wl.registration_date) AS registration_week,
    FORMAT_DATE('%Y-W%V', b.appointment_date) AS appointment_week,
    FORMAT_DATE('%Y-%m', b.appointment_date) AS appointment_month,

    -- Stage flags
    TRUE AS on_waitlist,
    o.billing_account_id IS NOT NULL AS was_offered,
    b.billing_account_id IS NOT NULL AS booked,
    b.outcome = 'Completed' AS completed,
    b.outcome

  FROM waiting_list wl
  LEFT JOIN offerings o ON wl.billing_account_id = o.billing_account_id
  LEFT JOIN bookings b ON COALESCE(o.billing_account_id, wl.billing_account_id) = b.billing_account_id
),

-- Add first contact week/month labels
journeys_with_contact AS (
  SELECT
    *,
    FORMAT_DATE('%Y-W%V', first_contact_date) AS first_contact_week,
    FORMAT_DATE('%Y-%m', first_contact_date) AS first_contact_month
  FROM customer_journeys
  WHERE first_contact_date != DATE '9999-12-31'
),

-- Generate funnel rows with filter dimensions
funnel_data AS (
  -- Stage 1: On Waitlist
  SELECT
    1 AS stage_number,
    '1. SMBP No Slots → Waitlist' AS stage_name,
    offer_channel,
    first_contact_week,
    first_contact_month,
    offer_week,
    offer_month,
    registration_week,
    appointment_week,
    appointment_month,
    billing_account_id
  FROM journeys_with_contact

  UNION ALL

  -- Stage 2: Offered Slot
  SELECT
    2 AS stage_number,
    '2. Offered Slot' AS stage_name,
    offer_channel,
    first_contact_week,
    first_contact_month,
    offer_week,
    offer_month,
    registration_week,
    appointment_week,
    appointment_month,
    billing_account_id
  FROM journeys_with_contact
  WHERE was_offered = TRUE

  UNION ALL

  -- Stage 3: Booked
  SELECT
    3 AS stage_number,
    '3. Booked' AS stage_name,
    offer_channel,
    first_contact_week,
    first_contact_month,
    offer_week,
    offer_month,
    registration_week,
    appointment_week,
    appointment_month,
    billing_account_id
  FROM journeys_with_contact
  WHERE booked = TRUE

  UNION ALL

  -- Stage 4: Completed
  SELECT
    4 AS stage_number,
    '4. Completed' AS stage_name,
    offer_channel,
    first_contact_week,
    first_contact_month,
    offer_week,
    offer_month,
    registration_week,
    appointment_week,
    appointment_month,
    billing_account_id
  FROM journeys_with_contact
  WHERE completed = TRUE
)

-- Final output with filter dimensions
SELECT
  stage_number,
  stage_name,
  COALESCE(offer_channel, 'Not Yet Offered') AS offer_channel,
  COALESCE(first_contact_week, 'N/A') AS first_contact_week,
  COALESCE(first_contact_month, 'N/A') AS first_contact_month,
  COALESCE(offer_week, 'N/A') AS offer_week,
  COALESCE(offer_month, 'N/A') AS offer_month,
  COALESCE(registration_week, 'N/A') AS registration_week,
  COALESCE(appointment_week, 'N/A') AS appointment_week,
  COALESCE(appointment_month, 'N/A') AS appointment_month,
  COUNT(DISTINCT billing_account_id) AS customers
FROM funnel_data
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
ORDER BY stage_number, offer_channel, first_contact_week
