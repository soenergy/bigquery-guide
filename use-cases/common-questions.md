# Common Questions & Queries

Quick answers to frequently asked questions. Copy-paste ready.

---

## Customer Metrics

### How many customers do we have?

```sql
-- Active customers (Nova)
SELECT COUNT(DISTINCT id) AS active_customers
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.customer`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND deleted IS NULL
  AND state = 'ACTIVE'
```

### Customer acquisition over time

```sql
SELECT
  DATE_TRUNC(created_at, MONTH) AS month,
  COUNT(*) AS new_customers
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.customer`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND created_at >= TIMESTAMP('2024-01-01')
GROUP BY month
ORDER BY month
```

### Customer churn (cancellations)

```sql
SELECT
  DATE_TRUNC(created_at, MONTH) AS month,
  COUNT(*) AS cancellations
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.cancellations`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND created_at >= TIMESTAMP('2024-01-01')
GROUP BY month
ORDER BY month
```

### Cancellation reasons

```sql
SELECT
  r.reason,
  COUNT(*) AS count
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.cancellations` c
JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.cancellation_reasons` r
  ON c.reason_id = r.id
  AND r.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
WHERE c.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND c.created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
GROUP BY r.reason
ORDER BY count DESC
```

---

## Support Metrics (Amazon Connect)

### How many cases today/this week?

```sql
-- Today
SELECT COUNT(DISTINCT id) AS cases_today
FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
WHERE detail_event_type = 'CASE.CREATED'
  AND DATE(detail_case_createddatetime) = CURRENT_DATE();

-- Last 7 days
SELECT
  DATE(detail_case_createddatetime) AS date,
  COUNT(DISTINCT id) AS cases
FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
WHERE detail_event_type = 'CASE.CREATED'
  AND detail_case_createddatetime >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY date
ORDER BY date DESC
```

### Open case backlog

```sql
SELECT COUNT(DISTINCT id) AS open_cases
FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
WHERE detail_case_fields_status NOT IN ('Closed', 'Resolved')
  AND meta_enriched_landed_date = (
    SELECT MAX(meta_enriched_landed_date)
    FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
  )
```

### Complaints volume

```sql
SELECT
  DATE(detail_case_createddatetime) AS date,
  COUNT(DISTINCT id) AS complaints
FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
WHERE detail_case_fields_is_complaint = TRUE
  AND detail_event_type = 'CASE.CREATED'
  AND detail_case_createddatetime >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY date
ORDER BY date DESC
```

### Complaints by subject

```sql
SELECT
  detail_case_fields_complaint_subject AS subject,
  COUNT(DISTINCT id) AS count
FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
WHERE detail_case_fields_is_complaint = TRUE
  AND detail_event_type = 'CASE.CREATED'
  AND detail_case_createddatetime >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
GROUP BY subject
ORDER BY count DESC
```

### Cases by category

```sql
SELECT
  detail_case_fields_level_1 AS category,
  COUNT(DISTINCT id) AS count
FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
WHERE detail_event_type = 'CASE.CREATED'
  AND detail_case_createddatetime >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY category
ORDER BY count DESC
```

### Overdue cases (>2 working days)

```sql
SELECT COUNT(DISTINCT id) AS overdue_cases
FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
WHERE detail_case_fields_is_overdue = TRUE
  AND detail_case_fields_status NOT IN ('Closed', 'Resolved')
  AND meta_enriched_landed_date = (
    SELECT MAX(meta_enriched_landed_date)
    FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
  )
```

---

## Call Center Metrics (Amazon Connect)

### Call volume by channel

```sql
SELECT
  channel,
  COUNT(*) AS contacts
FROM `soe-prod-data-core-7529.amazon_connect_enriched.ctr_events`
WHERE initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY channel
ORDER BY contacts DESC
```

### Average queue wait time

```sql
SELECT
  queue_name,
  AVG(queue_duration) AS avg_wait_seconds
FROM `soe-prod-data-core-7529.amazon_connect_enriched.ctr_events`
WHERE queue_duration IS NOT NULL
  AND initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY queue_name
ORDER BY avg_wait_seconds DESC
```

### Average handle time by agent

```sql
SELECT
  agent_username,
  AVG(agent_agentinteractionduration) AS avg_handle_seconds,
  COUNT(*) AS contacts_handled
FROM `soe-prod-data-core-7529.amazon_connect_enriched.ctr_events`
WHERE agent_username IS NOT NULL
  AND initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY agent_username
ORDER BY contacts_handled DESC
```

---

## Billing & Account Metrics

### How many active accounts?

```sql
SELECT COUNT(DISTINCT id) AS active_accounts
FROM `soe-prod-data-core-7529.junifer_enriched.account`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND cancel_fl != 'Y'
  AND (to_dttm IS NULL OR to_dttm > CURRENT_TIMESTAMP())
```

### Accounts by payment method

```sql
SELECT
  pmt.name AS payment_method,
  COUNT(DISTINCT a.id) AS accounts
FROM `soe-prod-data-core-7529.junifer_enriched.account` a
JOIN `soe-prod-data-core-7529.junifer_enriched.account_payment_method` apm
  ON a.id = apm.account_fk
  AND apm.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
JOIN `soe-prod-data-core-7529.junifer_enriched.payment_method_type` pmt
  ON apm.payment_method_type_fk = pmt.id
WHERE a.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
GROUP BY pmt.name
ORDER BY accounts DESC
```

---

## Smart Meter Metrics

### Smart meter bookings

```sql
SELECT
  DATE(created_at) AS date,
  COUNT(*) AS bookings
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.smart_meter_bookings`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY date
ORDER BY date DESC
```

---

## Referrals

### Referral performance

```sql
SELECT
  DATE_TRUNC(created_at, MONTH) AS month,
  COUNT(*) AS referrals
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.customer_referrals`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND created_at >= TIMESTAMP('2024-01-01')
GROUP BY month
ORDER BY month DESC
```

---

## Tips for Building Queries

1. **Always use the SCD2 filter for enriched tables**: `WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')`
2. **Amazon Connect doesn't use SCD2**: Filter by `meta_enriched_landed_date` or event timestamps instead
3. **Start with LIMIT**: Add `LIMIT 100` when exploring
4. **Use date filters**: Filter by timestamps to reduce data scanned
5. **Check partition requirements**: Some tables require partition filters
