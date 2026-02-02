-- Smart Meter Booking Sankey with Filter Dimensions
-- For Looker Studio: Use filter controls on the dimension columns
--
-- Appointment outcome based on COALESCE(aes_status, mop_status)
--   - aes_status: historical data
--   - mop_status: new data
-- Appointment date based on slot_start_date_time
--
-- FILTER DIMENSIONS:
--   Time: first_contact_week, first_contact_month, offer_week, appointment_week
--   Preferences: has_preferences, flexibility_level, time_preference
--   Path: entry_path, offer_channel, booking_status, outcome

WITH
-- Waiting list with extracted preferences
waiting_list AS (
  SELECT
    billing_account_id,
    registration_date,
    DATE(registration_date) AS registration_date_dt,
    registration_source,
    waiting_status,
    customer_availability,

    -- Extract preference flags
    customer_availability IS NOT NULL
      AND JSON_VALUE(customer_availability) != '{}'
      AND JSON_VALUE(customer_availability) != 'null' AS has_preferences_raw,

    -- Count available slots (max 10: 5 days x 2 slots)
    (CASE WHEN JSON_VALUE(customer_availability, '$.monday.am') = 'true' THEN 1 ELSE 0 END +
     CASE WHEN JSON_VALUE(customer_availability, '$.monday.pm') = 'true' THEN 1 ELSE 0 END +
     CASE WHEN JSON_VALUE(customer_availability, '$.tuesday.am') = 'true' THEN 1 ELSE 0 END +
     CASE WHEN JSON_VALUE(customer_availability, '$.tuesday.pm') = 'true' THEN 1 ELSE 0 END +
     CASE WHEN JSON_VALUE(customer_availability, '$.wednesday.am') = 'true' THEN 1 ELSE 0 END +
     CASE WHEN JSON_VALUE(customer_availability, '$.wednesday.pm') = 'true' THEN 1 ELSE 0 END +
     CASE WHEN JSON_VALUE(customer_availability, '$.thursday.am') = 'true' THEN 1 ELSE 0 END +
     CASE WHEN JSON_VALUE(customer_availability, '$.thursday.pm') = 'true' THEN 1 ELSE 0 END +
     CASE WHEN JSON_VALUE(customer_availability, '$.friday.am') = 'true' THEN 1 ELSE 0 END +
     CASE WHEN JSON_VALUE(customer_availability, '$.friday.pm') = 'true' THEN 1 ELSE 0 END
    ) AS available_slots_count,

    -- AM vs PM preference
    (JSON_VALUE(customer_availability, '$.monday.am') = 'true' OR
     JSON_VALUE(customer_availability, '$.tuesday.am') = 'true' OR
     JSON_VALUE(customer_availability, '$.wednesday.am') = 'true' OR
     JSON_VALUE(customer_availability, '$.thursday.am') = 'true' OR
     JSON_VALUE(customer_availability, '$.friday.am') = 'true'
    ) AS am_available_raw,

    (JSON_VALUE(customer_availability, '$.monday.pm') = 'true' OR
     JSON_VALUE(customer_availability, '$.tuesday.pm') = 'true' OR
     JSON_VALUE(customer_availability, '$.wednesday.pm') = 'true' OR
     JSON_VALUE(customer_availability, '$.thursday.pm') = 'true' OR
     JSON_VALUE(customer_availability, '$.friday.pm') = 'true'
    ) AS pm_available_raw

  FROM `soe-prod-data-curated.nova_be_customers_enriched.smartmeter_customer_waiting_list`
  WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
),

-- Slot offerings
offerings AS (
  SELECT
    billing_account_id,
    offer_channel,
    offer_date,
    appointment_start_datetime
  FROM `soe-prod-data-curated.nova_be_customers_enriched.smartmeter_appointment_offerings`
  WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
),

-- Bookings with outcomes based on COALESCE(aes_status, mop_status)
bookings AS (
  SELECT
    CAST(billing_account_id AS INT64) AS billing_account_id,
    created_at AS booking_created_at,
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

-- Combined customer journeys with all dimensions
customer_journeys AS (
  SELECT
    COALESCE(o.billing_account_id, wl.billing_account_id, b.billing_account_id) AS billing_account_id,

    -- === FIRST CONTACT DATE (earliest of registration, offer, or booking) ===
    LEAST(
      COALESCE(wl.registration_date_dt, DATE '9999-12-31'),
      COALESCE(o.offer_date, DATE '9999-12-31'),
      COALESCE(b.booking_date, DATE '9999-12-31')
    ) AS first_contact_date,

    -- === TIME FILTER DIMENSIONS ===
    wl.registration_date_dt AS registration_date,
    FORMAT_DATE('%Y-W%V', wl.registration_date_dt) AS registration_week_label,

    o.offer_date,
    FORMAT_DATE('%Y-W%V', o.offer_date) AS offer_week_label,
    FORMAT_DATE('%Y-%m', o.offer_date) AS offer_month_label,

    b.appointment_date,
    FORMAT_DATE('%Y-W%V', b.appointment_date) AS appointment_week_label,
    FORMAT_DATE('%Y-%m', b.appointment_date) AS appointment_month_label,

    -- === PREFERENCE FILTER DIMENSIONS ===
    CASE WHEN wl.has_preferences_raw THEN 'Yes' ELSE 'No' END AS has_preferences,

    CASE
      WHEN wl.available_slots_count >= 8 THEN 'Fully Flexible (8-10 slots)'
      WHEN wl.available_slots_count >= 5 THEN 'Mostly Flexible (5-7 slots)'
      WHEN wl.available_slots_count >= 2 THEN 'Limited (2-4 slots)'
      WHEN wl.available_slots_count >= 1 THEN 'Very Limited (1 slot)'
      ELSE 'No Preferences Set'
    END AS flexibility_level,

    CASE
      WHEN wl.am_available_raw AND wl.pm_available_raw THEN 'AM & PM'
      WHEN wl.am_available_raw THEN 'AM Only'
      WHEN wl.pm_available_raw THEN 'PM Only'
      ELSE 'Not Set'
    END AS time_preference,

    -- === SANKEY STAGE DIMENSIONS ===
    CASE
      WHEN wl.billing_account_id IS NOT NULL THEN 'Waiting List'
      ELSE 'Direct'
    END AS entry_path,

    CASE
      WHEN o.offer_channel = 'EMAIL' THEN 'Email Offer'
      WHEN o.offer_channel = 'SMBP' THEN 'SMBP Offer'
      WHEN o.offer_channel IS NOT NULL THEN CONCAT('Other: ', o.offer_channel)
      ELSE 'No Offer Record'
    END AS offer_channel,

    o.offer_channel AS offer_channel_raw,

    CASE
      WHEN b.billing_account_id IS NOT NULL THEN 'Booked'
      ELSE 'Not Booked'
    END AS booking_status,

    b.booking_source,
    COALESCE(b.outcome, 'No Booking') AS outcome,
    b.status AS outcome_raw

  FROM offerings o
  FULL OUTER JOIN waiting_list wl ON o.billing_account_id = wl.billing_account_id
  FULL OUTER JOIN bookings b ON COALESCE(o.billing_account_id, wl.billing_account_id) = b.billing_account_id
),

-- Add first_contact week/month labels
journeys_with_contact_date AS (
  SELECT
    *,
    FORMAT_DATE('%Y-W%V', first_contact_date) AS first_contact_week_label,
    FORMAT_DATE('%Y-%m', first_contact_date) AS first_contact_month_label
  FROM customer_journeys
  WHERE first_contact_date != DATE '9999-12-31'
),

-- Generate Sankey links with filter dimensions
link1 AS (
  SELECT
    entry_path AS source,
    offer_channel AS target,
    1 AS stage,
    'Entry → Offer' AS link_type,
    first_contact_week_label,
    first_contact_month_label,
    offer_week_label,
    offer_month_label,
    appointment_week_label,
    appointment_month_label,
    has_preferences,
    flexibility_level,
    time_preference,
    COUNT(*) AS value
  FROM journeys_with_contact_date
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),

link2 AS (
  SELECT
    offer_channel AS source,
    booking_status AS target,
    2 AS stage,
    'Offer → Booking' AS link_type,
    first_contact_week_label,
    first_contact_month_label,
    offer_week_label,
    offer_month_label,
    appointment_week_label,
    appointment_month_label,
    has_preferences,
    flexibility_level,
    time_preference,
    COUNT(*) AS value
  FROM journeys_with_contact_date
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),

link3 AS (
  SELECT
    booking_status AS source,
    outcome AS target,
    3 AS stage,
    'Booking → Outcome' AS link_type,
    first_contact_week_label,
    first_contact_month_label,
    offer_week_label,
    offer_month_label,
    appointment_week_label,
    appointment_month_label,
    has_preferences,
    flexibility_level,
    time_preference,
    COUNT(*) AS value
  FROM journeys_with_contact_date
  WHERE booking_status = 'Booked'
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),

all_links AS (
  SELECT * FROM link1
  UNION ALL SELECT * FROM link2
  UNION ALL SELECT * FROM link3
)

SELECT
  source,
  target,
  value,
  stage,
  link_type,
  -- Filter dimensions for Looker Studio
  COALESCE(first_contact_week_label, 'N/A') AS first_contact_week,
  COALESCE(first_contact_month_label, 'N/A') AS first_contact_month,
  COALESCE(offer_week_label, 'N/A') AS offer_week,
  COALESCE(offer_month_label, 'N/A') AS offer_month,
  COALESCE(appointment_week_label, 'N/A') AS appointment_week,
  COALESCE(appointment_month_label, 'N/A') AS appointment_month,
  COALESCE(has_preferences, 'N/A') AS has_preferences,
  COALESCE(flexibility_level, 'N/A') AS flexibility_level,
  COALESCE(time_preference, 'N/A') AS time_preference
FROM all_links
WHERE value > 0
ORDER BY stage, value DESC
