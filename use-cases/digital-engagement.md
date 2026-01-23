# Digital Engagement Metrics

Data for understanding customer engagement across digital channels (App, Website), page visits, and journey completion rates.

---

## Key Tables

| Table | Dataset | Description |
|-------|---------|-------------|
| `digital_user_engagement` | `soe_junifer_model` | Customer-level digital engagement tracking (~11.4M rows) |
| `digital_journey_performance` | `soe_junifer_model` | Journey completion by channel (~4.2M rows) |
| `events_*` | `analytics_382914461` | **Google Analytics 4** raw events (daily tables) |
| `users_*` | `analytics_382914461` | GA4 user data (daily tables) |
| `bookings_landed` | `soe_website` | Website booking data |
| `card_payments` | `soe_website` | Website card payment events |
| `refer_a_friend` | `soe_website` | Referral programme tracking |

> ⚠️ **Note**: Mixpanel (`soe_mixpanel`) is deprecated - use Google Analytics (`analytics_382914461`) for raw event/traffic data.

---

## Digital User Engagement

The `digital_user_engagement` table provides a comprehensive view of customer digital activity.

### Digitally engaged customers overview

```sql
SELECT
  Platform,
  COUNT(DISTINCT account_number) AS engaged_accounts
FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
WHERE event_date = (
  SELECT MAX(event_date)
  FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
)
GROUP BY Platform
ORDER BY engaged_accounts DESC
```

### Customers engaged in last 3 months

```sql
SELECT
  digitally_engaged_in_last_three_month,
  COUNT(DISTINCT account_number) AS accounts
FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
WHERE event_date = (
  SELECT MAX(event_date)
  FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
)
GROUP BY digitally_engaged_in_last_three_month
```

### Page visits breakdown

```sql
SELECT
  SUM(CASE WHEN visited_support_page = 'Y' THEN 1 ELSE 0 END) AS support_page,
  SUM(CASE WHEN visited_Usage_page = 'Y' THEN 1 ELSE 0 END) AS usage_page,
  SUM(CASE WHEN visited_Reading_page = 'Y' THEN 1 ELSE 0 END) AS reading_page,
  SUM(CASE WHEN visited_Bills_Transactions_page = 'Y' THEN 1 ELSE 0 END) AS bills_page,
  SUM(CASE WHEN visited_payments_page = 'Y' THEN 1 ELSE 0 END) AS payments_page,
  SUM(CASE WHEN visited_Tariff_page = 'Y' THEN 1 ELSE 0 END) AS tariff_page,
  SUM(CASE WHEN visited_personal_details_page = 'Y' THEN 1 ELSE 0 END) AS personal_details,
  SUM(CASE WHEN visited_refer_a_friend_page = 'Y' THEN 1 ELSE 0 END) AS refer_friend,
  SUM(CASE WHEN visited_moving_home_page = 'Y' THEN 1 ELSE 0 END) AS moving_home
FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
WHERE event_date = (
  SELECT MAX(event_date)
  FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
)
```

### Engagement by customer segment

```sql
SELECT
  account_status,
  fixed_svt AS tariff_type,
  COUNT(DISTINCT account_number) AS accounts,
  SUM(CASE WHEN digitally_engaged_in_last_three_month = 'Y' THEN 1 ELSE 0 END) AS engaged_3m
FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
WHERE event_date = (
  SELECT MAX(event_date)
  FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
)
GROUP BY account_status, fixed_svt
ORDER BY accounts DESC
```

### Smart meter vs non-smart engagement

```sql
SELECT
  smart_meter_fl,
  COUNT(DISTINCT account_number) AS accounts,
  SUM(CASE WHEN digitally_engaged_in_last_three_month = 'Y' THEN 1 ELSE 0 END) AS engaged,
  ROUND(SUM(CASE WHEN digitally_engaged_in_last_three_month = 'Y' THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT account_number), 2) AS engagement_rate
FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
WHERE event_date = (
  SELECT MAX(event_date)
  FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
)
GROUP BY smart_meter_fl
```

### Usage graph visibility

```sql
SELECT
  usage_graph_visible,
  usage_graph_not_visible,
  COUNT(DISTINCT account_number) AS accounts
FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
WHERE event_date = (
  SELECT MAX(event_date)
  FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
)
  AND visited_Usage_page = 'Y'
GROUP BY usage_graph_visible, usage_graph_not_visible
```

### Engagement by tenure

```sql
SELECT
  Tenure_in_year,
  COUNT(DISTINCT account_number) AS accounts,
  SUM(CASE WHEN digitally_engaged_in_last_three_month = 'Y' THEN 1 ELSE 0 END) AS engaged
FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
WHERE event_date = (
  SELECT MAX(event_date)
  FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
)
GROUP BY Tenure_in_year
ORDER BY Tenure_in_year
```

---

## Digital Journey Performance

### Journey completion rates by channel

```sql
SELECT
  KPI_name,
  Channel,
  COUNT(*) AS total_attempts,
  SUM(CASE WHEN Success_status = 'Success' THEN 1 ELSE 0 END) AS successful,
  ROUND(SUM(CASE WHEN Success_status = 'Success' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS success_rate_pct
FROM `soe-prod-data-core-7529.soe_junifer_model.digital_journey_performance`
WHERE Created_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY KPI_name, Channel
ORDER BY KPI_name, Channel
```

### App vs Web performance comparison

```sql
SELECT
  KPI_name,
  SUM(CASE WHEN Channel = 'App' AND Success_status = 'Success' THEN 1 ELSE 0 END) AS app_success,
  SUM(CASE WHEN Channel = 'App' THEN 1 ELSE 0 END) AS app_total,
  ROUND(SUM(CASE WHEN Channel = 'App' AND Success_status = 'Success' THEN 1 ELSE 0 END) * 100.0 /
    NULLIF(SUM(CASE WHEN Channel = 'App' THEN 1 ELSE 0 END), 0), 2) AS app_rate,
  SUM(CASE WHEN Channel = 'Web' AND Success_status = 'Success' THEN 1 ELSE 0 END) AS web_success,
  SUM(CASE WHEN Channel = 'Web' THEN 1 ELSE 0 END) AS web_total,
  ROUND(SUM(CASE WHEN Channel = 'Web' AND Success_status = 'Success' THEN 1 ELSE 0 END) * 100.0 /
    NULLIF(SUM(CASE WHEN Channel = 'Web' THEN 1 ELSE 0 END), 0), 2) AS web_rate
FROM `soe-prod-data-core-7529.soe_junifer_model.digital_journey_performance`
WHERE Created_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY KPI_name
ORDER BY KPI_name
```

### Daily journey trends

```sql
SELECT
  Created_date,
  KPI_name,
  COUNT(*) AS attempts,
  SUM(CASE WHEN Success_status = 'Success' THEN 1 ELSE 0 END) AS successes
FROM `soe-prod-data-core-7529.soe_junifer_model.digital_journey_performance`
WHERE Created_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
GROUP BY Created_date, KPI_name
ORDER BY Created_date DESC, KPI_name
```

---

## Google Analytics 4 (GA4)

Raw event-level data from the website and app, exported directly from GA4 to BigQuery.

**Dataset**: `analytics_382914461` (GA4 Property ID: 382914461)

**Table Structure**: Date-sharded tables - use wildcards to query date ranges:
- `events_*` - All events (page views, clicks, conversions)
- `users_*` - User-level data
- `pseudonymous_users_*` - Pseudonymous user data

### Total events by day

```sql
SELECT
  event_date,
  COUNT(*) AS total_events,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM `soe-prod-data-core-7529.analytics_382914461.events_*`
WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
  AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY event_date
ORDER BY event_date DESC
```

### Event types breakdown

```sql
SELECT
  event_name,
  COUNT(*) AS event_count
FROM `soe-prod-data-core-7529.analytics_382914461.events_*`
WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
  AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY event_name
ORDER BY event_count DESC
LIMIT 30
```

### Traffic by platform (Web vs App)

```sql
SELECT
  platform,
  COUNT(*) AS events,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM `soe-prod-data-core-7529.analytics_382914461.events_*`
WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
  AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY platform
ORDER BY events DESC
```

### Traffic by device category

```sql
SELECT
  device.category AS device_category,
  device.operating_system,
  COUNT(*) AS events,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM `soe-prod-data-core-7529.analytics_382914461.events_*`
WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
  AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY device.category, device.operating_system
ORDER BY events DESC
```

### Traffic sources

```sql
SELECT
  traffic_source.source,
  traffic_source.medium,
  COUNT(DISTINCT user_pseudo_id) AS unique_users,
  COUNT(*) AS events
FROM `soe-prod-data-core-7529.analytics_382914461.events_*`
WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
  AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY traffic_source.source, traffic_source.medium
ORDER BY unique_users DESC
LIMIT 20
```

### Page views by page

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_url,
  COUNT(*) AS page_views
FROM `soe-prod-data-core-7529.analytics_382914461.events_*`
WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
  AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name = 'page_view'
GROUP BY page_url
ORDER BY page_views DESC
LIMIT 30
```

### Sessions by browser

```sql
SELECT
  device.browser,
  COUNT(DISTINCT
    CONCAT(user_pseudo_id,
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
    )
  ) AS sessions
FROM `soe-prod-data-core-7529.analytics_382914461.events_*`
WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
  AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY device.browser
ORDER BY sessions DESC
```

### Geographic distribution

```sql
SELECT
  geo.country,
  geo.city,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM `soe-prod-data-core-7529.analytics_382914461.events_*`
WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
  AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY geo.country, geo.city
ORDER BY unique_users DESC
LIMIT 20
```

### Extract event parameter values

GA4 stores custom parameters in nested arrays. Use UNNEST to extract:

```sql
SELECT
  event_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_title') AS page_title,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_url,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_ms
FROM `soe-prod-data-core-7529.analytics_382914461.events_*`
WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name = 'page_view'
LIMIT 100
```

---

## Website Data

### Refer-a-friend performance

```sql
SELECT
  DATE(meta_inserted_timestamp) AS date,
  COUNT(*) AS referrals
FROM `soe-prod-data-core-7529.soe_website.refer_a_friend`
WHERE meta_inserted_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY date
ORDER BY date DESC
```

---

## Key Fields Reference

### digital_user_engagement

| Column | Description |
|--------|-------------|
| `event_date` | Snapshot date |
| `Platform` | App or Web |
| `account_number` | Junifer account number |
| `account_status` | Account status (Active, Closed, etc.) |
| `smart_meter_fl` | Has smart meter (Y/N) |
| `fuel_type` | ELEC, GAS, DUAL |
| `fixed_svt` | Fixed or Variable tariff |
| `Tenure_in_year` | Years as customer |
| `dual_fuel_flag` | Has both fuels |
| `visited_support_page` | Visited support (Y/N) |
| `visited_Usage_page` | Visited usage (Y/N) |
| `visited_Reading_page` | Visited readings (Y/N) |
| `visited_Bills_Transactions_page` | Visited bills (Y/N) |
| `visited_payments_page` | Visited payments (Y/N) |
| `visited_Tariff_page` | Visited tariff (Y/N) |
| `visited_personal_details_page` | Visited profile (Y/N) |
| `visited_refer_a_friend_page` | Visited referrals (Y/N) |
| `visited_moving_home_page` | Visited move home (Y/N) |
| `usage_graph_visible` | Can see usage graph |
| `digitally_engaged_in_last_three_month` | Active in 3 months (Y/N) |
| `last_digitally_engaged_date` | Last activity date |
| `EV_tariff` | On EV tariff |
| `Solar_installed` | Has solar |
| `psr_flag` | On Priority Services Register |

### digital_journey_performance

| Column | Description |
|--------|-------------|
| `Account_number` | Customer account |
| `Mpxn` | Meter point reference |
| `KPI_name` | Journey type (see list below) |
| `DB_Source` | Source database |
| `Base` | Customer base segment |
| `Channel` | App or Web |
| `Created_date` | Event date |
| `Success_status` | Success or Failed |

**KPI Names:**
- Direct Debit Setup
- Direct Debit Amount Changes
- Direct Debit Date Changes
- Submit a read
- Smart meter bookings
- Make a Card Payment
- Renewals
- Acquisition
- COT Move Out
- COT Move In

### GA4 events_* schema

| Column | Description |
|--------|-------------|
| `event_date` | Date string (YYYYMMDD) |
| `event_timestamp` | Microseconds since Unix epoch |
| `event_name` | Event type (page_view, session_start, click, etc.) |
| `event_params` | Nested array of key-value parameters |
| `user_id` | Your user ID (if set) |
| `user_pseudo_id` | GA-generated anonymous user ID |
| `user_properties` | Nested array of user properties |
| `device.category` | desktop, mobile, tablet |
| `device.browser` | Browser name |
| `device.operating_system` | OS name |
| `geo.country` | Country |
| `geo.city` | City |
| `geo.region` | Region/State |
| `traffic_source.source` | Traffic source |
| `traffic_source.medium` | Traffic medium |
| `platform` | WEB, IOS, ANDROID |
| `app_info.id` | App package name |
| `app_info.version` | App version |

**Common event_params keys:**
- `page_location` - Full URL
- `page_title` - Page title
- `page_referrer` - Referrer URL
- `ga_session_id` - Session identifier
- `engagement_time_msec` - Engagement time in ms

---

## Cross-Channel Analysis

### Contact after digital engagement

```sql
SELECT
  d.Platform,
  d.digitally_engaged_in_last_three_month,
  COUNT(DISTINCT d.account_number) AS accounts,
  SUM(CASE WHEN d.post_ticket_id IS NOT NULL THEN 1 ELSE 0 END) AS contacted_support
FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement` d
WHERE d.event_date = (
  SELECT MAX(event_date)
  FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
)
GROUP BY d.Platform, d.digitally_engaged_in_last_three_month
ORDER BY d.Platform, d.digitally_engaged_in_last_three_month
```

### Engagement by account balance status

```sql
SELECT
  account_balance_status,
  COUNT(DISTINCT account_number) AS accounts,
  SUM(CASE WHEN digitally_engaged_in_last_three_month = 'Y' THEN 1 ELSE 0 END) AS engaged,
  ROUND(SUM(CASE WHEN digitally_engaged_in_last_three_month = 'Y' THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT account_number), 2) AS engagement_rate
FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
WHERE event_date = (
  SELECT MAX(event_date)
  FROM `soe-prod-data-core-7529.soe_junifer_model.digital_user_engagement`
)
GROUP BY account_balance_status
ORDER BY accounts DESC
```

---

## Notes

- **Mixpanel**: DEPRECATED - use Google Analytics for raw event/traffic data
- **Google Analytics (GA4)**: Use `_TABLE_SUFFIX` with wildcards to query date ranges. Data available from Sep 2024 onwards.
- **digital_user_engagement**: Refreshed daily, use latest `event_date` for current snapshot
- **digital_journey_performance**: Transaction-level data, filter by `Created_date` for time periods
