# Troubleshooting & Error Diagnosis

Correlating application errors with customer behavior and support contacts to diagnose issues.

---

## Key Tables

| Table | Dataset | Description |
|-------|---------|-------------|
| `event_logs` | `nova_customers_enriched` | App events with error flag (~16.9M rows) |
| `server_exception` | `junifer_enriched` | Billing system exceptions (~8.3M rows) |
| `case_events` | `amazon_connect_enriched` | Support cases/tickets |
| `events_*` | `analytics_382914461` | GA4 app/web events |
| `Elec_D0030`, etc. | `soe_dataflows` | Industry dataflows (operational health) |

---

## The Correlation Chain

```
App Error (event_logs.is_error = TRUE)
    ↓ billing_account_id
Customer Account (billing_account)
    ↓ account_number
Support Contact (case_events.account)
```

---

## App Error Analysis

### Errors by type (last 7 days)

```sql
SELECT
  event,
  COUNT(*) AS error_count,
  COUNT(DISTINCT billing_account_id) AS affected_accounts
FROM `soe-prod-data-core-7529.nova_customers_enriched.event_logs`
WHERE is_error = TRUE
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY event
ORDER BY error_count DESC
```

### Error timeline

```sql
SELECT
  DATE(created_at) AS date,
  event,
  COUNT(*) AS errors
FROM `soe-prod-data-core-7529.nova_customers_enriched.event_logs`
WHERE is_error = TRUE
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY date, event
ORDER BY date DESC, errors DESC
```

### Errors for a specific account

```sql
SELECT
  created_at,
  event,
  description,
  trace_id
FROM `soe-prod-data-core-7529.nova_customers_enriched.event_logs`
WHERE billing_account_id = '12345678'  -- Replace with account
  AND is_error = TRUE
ORDER BY created_at DESC
LIMIT 100
```

### Accounts with most errors

```sql
SELECT
  billing_account_id,
  COUNT(*) AS error_count,
  COUNT(DISTINCT event) AS unique_error_types,
  MIN(created_at) AS first_error,
  MAX(created_at) AS last_error
FROM `soe-prod-data-core-7529.nova_customers_enriched.event_logs`
WHERE is_error = TRUE
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY billing_account_id
ORDER BY error_count DESC
LIMIT 50
```

---

## Error → Support Contact Correlation

### Did errors lead to support contact?

```sql
WITH errors AS (
  SELECT
    billing_account_id,
    MIN(created_at) AS first_error_time,
    COUNT(*) AS error_count
  FROM `soe-prod-data-core-7529.nova_customers_enriched.event_logs`
  WHERE is_error = TRUE
    AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  GROUP BY billing_account_id
),
contacts AS (
  SELECT
    account,
    MIN(detail_case_createddatetime) AS first_contact_time
  FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
  WHERE detail_event_type = 'CASE.CREATED'
    AND detail_case_createddatetime >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  GROUP BY account
)
SELECT
  e.billing_account_id,
  e.error_count,
  e.first_error_time,
  c.first_contact_time,
  TIMESTAMP_DIFF(c.first_contact_time, e.first_error_time, HOUR) AS hours_to_contact
FROM errors e
JOIN contacts c ON e.billing_account_id = c.account
WHERE c.first_contact_time > e.first_error_time  -- Contact after error
ORDER BY e.error_count DESC
LIMIT 100
```

### Error types that lead to support contact

```sql
WITH error_accounts AS (
  SELECT DISTINCT
    billing_account_id,
    event AS error_type
  FROM `soe-prod-data-core-7529.nova_customers_enriched.event_logs`
  WHERE is_error = TRUE
    AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
),
contacted AS (
  SELECT DISTINCT account
  FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
  WHERE detail_event_type = 'CASE.CREATED'
    AND detail_case_createddatetime >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
)
SELECT
  e.error_type,
  COUNT(DISTINCT e.billing_account_id) AS accounts_with_error,
  COUNT(DISTINCT CASE WHEN c.account IS NOT NULL THEN e.billing_account_id END) AS accounts_that_contacted,
  ROUND(COUNT(DISTINCT CASE WHEN c.account IS NOT NULL THEN e.billing_account_id END) * 100.0 /
    COUNT(DISTINCT e.billing_account_id), 2) AS contact_rate_pct
FROM error_accounts e
LEFT JOIN contacted c ON e.billing_account_id = c.account
GROUP BY e.error_type
ORDER BY accounts_with_error DESC
```

### Support cases mentioning errors

```sql
SELECT
  id,
  account,
  detail_case_fields_level_1 AS category,
  detail_case_fields_level_2 AS subcategory,
  detail_case_createddatetime
FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
WHERE detail_event_type = 'CASE.CREATED'
  AND (
    LOWER(detail_case_fields_level_1) LIKE '%error%'
    OR LOWER(detail_case_fields_level_1) LIKE '%app%'
    OR LOWER(detail_case_fields_level_2) LIKE '%technical%'
  )
  AND detail_case_createddatetime >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
ORDER BY detail_case_createddatetime DESC
```

---

## Billing System Exceptions (Junifer)

### Exception types

```sql
SELECT
  exception_class,
  COUNT(*) AS count
FROM `soe-prod-data-core-7529.junifer_enriched.server_exception`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND created_dttm >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY exception_class
ORDER BY count DESC
```

### Exception timeline

```sql
SELECT
  DATE(created_dttm) AS date,
  exception_class,
  COUNT(*) AS exceptions
FROM `soe-prod-data-core-7529.junifer_enriched.server_exception`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND created_dttm >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY date, exception_class
ORDER BY date DESC, exceptions DESC
```

### Exception details with message

```sql
SELECT
  created_dttm,
  exception_class,
  message,
  server_version
FROM `soe-prod-data-core-7529.junifer_enriched.server_exception`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND created_dttm >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
ORDER BY created_dttm DESC
LIMIT 100
```

---

## Industry Dataflows Health

Dataflows indicate operational health. Missing or failed dataflows can cause downstream issues.

### Available Dataflows

**Electricity:**
- `Elec_D0010` - Meter readings
- `Elec_D0030` - Validated meter data
- `Elec_D0086` - Settlement data
- `Elec_D0296` - Agent appointments
- `Elec_D0300/D0301` - Change of supplier

**Gas:**
- `Gas_MRI` - Meter reading info
- `Gas_NOSI` - Notification of supply
- `Gas_RET` - Rejections

### Dataflow FTP health

```sql
SELECT *
FROM `soe-prod-data-core-7529.soe_dataflows.w_df_ftp_info_d`
ORDER BY 1 DESC
LIMIT 100
```

### D0030 meter data volume by day

```sql
SELECT
  DATE(J0015) AS date,  -- Or appropriate date column
  COUNT(*) AS records
FROM `soe-prod-data-core-7529.soe_dataflows.Elec_D0030`
GROUP BY date
ORDER BY date DESC
LIMIT 30
```

---

## GA4 Error Events

### JavaScript errors in app/web

```sql
SELECT
  event_date,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'description') AS error_description,
  COUNT(*) AS error_count
FROM `soe-prod-data-core-7529.analytics_382914461.events_*`
WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
  AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name = 'exception'
GROUP BY event_date, page, error_description
ORDER BY error_count DESC
```

---

## Complete Customer Error Journey

### Full picture for an account

```sql
-- Replace '12345678' with the account number
DECLARE account_num STRING DEFAULT '12345678';

-- App errors
SELECT 'App Error' AS source, created_at AS timestamp, event AS type, description AS detail
FROM `soe-prod-data-core-7529.nova_customers_enriched.event_logs`
WHERE billing_account_id = account_num
  AND is_error = TRUE
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)

UNION ALL

-- Support contacts
SELECT 'Support Case' AS source, detail_case_createddatetime AS timestamp,
  detail_case_fields_level_1 AS type, detail_case_fields_level_2 AS detail
FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
WHERE account = account_num
  AND detail_event_type = 'CASE.CREATED'
  AND detail_case_createddatetime >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)

ORDER BY timestamp DESC
```

---

## Key Fields Reference

### event_logs (Nova)

| Column | Description |
|--------|-------------|
| `id` | Event ID |
| `billing_account_id` | **Links to customer** |
| `event` | Event type/name |
| `description` | Event description |
| `is_error` | **Boolean - TRUE for errors** |
| `trace_id` | Distributed tracing ID |
| `booking_id` | Related booking if applicable |
| `campaign_id` | Related campaign if applicable |
| `created_at` | Event timestamp |

### server_exception (Junifer)

| Column | Description |
|--------|-------------|
| `id` | Exception ID |
| `exception_class` | Java exception class |
| `message` | Exception message |
| `server_version` | Junifer version |
| `created_dttm` | When exception occurred |
| `cause_server_exception_fk` | Chained exception |
| `root_server_exception_fk` | Root cause exception |

---

## Diagnostic Workflow

1. **Identify the problem**: Check `event_logs` for recent errors
2. **Scope the impact**: Count affected accounts
3. **Check correlation**: Did affected accounts contact support?
4. **Check billing system**: Any `server_exception` spikes?
5. **Check dataflows**: Any missing industry data?
6. **Check GA4**: Any frontend/JS errors?
7. **Build timeline**: Use the full journey query

---

## Notes

- **event_logs**: Not SCD2 - query directly by `created_at`
- **server_exception**: Uses SCD2 - filter `meta_effective_to_timestamp = TIMESTAMP('9999-01-01')`
- **Trace IDs**: Use `trace_id` to correlate with Datadog/CloudWatch if needed
- **For real-time debugging**: Consider adding CloudWatch/Datadog MCP for live log tailing
