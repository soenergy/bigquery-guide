# Operations Performance Metrics

Data for tracking operational KPIs including smart metering, billing operations, meter readings, and customer journeys.

---

## Key Tables

| Table | Dataset | Description |
|-------|---------|-------------|
| `smart_meter_bookings` | `nova_be_customers_enriched` | Smart meter installation bookings (~159K rows) |
| `meter_reading` | `nova_be_assets_enriched` | Customer meter reading submissions (~4.1M rows) |
| `w_actual_meterreads` | `soe_junifer_model` | Actual meter reads with consumption (~110M rows) |
| `bill` | `junifer_enriched` | Bills generated (~25.6M rows) |
| `bill_period` | `junifer_enriched` | Billing periods (~24.3M rows) |
| `bill_delivery` | `soe_operations_report` | Bill delivery method tracking |
| `digital_journey_performance` | `soe_junifer_model` | Digital journey KPIs by channel |

---

## Smart Metering Performance

### Smart meter bookings by status

```sql
SELECT
  aes_status,
  COUNT(*) AS bookings
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.smart_meter_bookings`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
GROUP BY aes_status
ORDER BY bookings DESC
```

### Smart meter installs over time

```sql
SELECT
  DATE(installed_datetime) AS install_date,
  COUNT(*) AS installs
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.smart_meter_bookings`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND installed_datetime IS NOT NULL
  AND installed_datetime >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY install_date
ORDER BY install_date DESC
```

### Smart meter bookings by fuel type

```sql
SELECT
  fuel_type,
  installation_type,
  COUNT(*) AS bookings
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.smart_meter_bookings`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
GROUP BY fuel_type, installation_type
ORDER BY bookings DESC
```

### Failed smart meter installations

```sql
SELECT
  failure_reason,
  COUNT(*) AS failed_installs
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.smart_meter_bookings`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND failed_datetime IS NOT NULL
GROUP BY failure_reason
ORDER BY failed_installs DESC
```

### Cancelled bookings by reason

```sql
SELECT
  cancel_reason,
  COUNT(*) AS cancelled
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.smart_meter_bookings`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND cancellation_date_time IS NOT NULL
GROUP BY cancel_reason
ORDER BY cancelled DESC
```

### Smart meter bookings by source

```sql
SELECT
  source,
  COUNT(*) AS bookings
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.smart_meter_bookings`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY source
ORDER BY bookings DESC
```

---

## Meter Reading Operations

### Meter readings by source

```sql
SELECT
  source,
  COUNT(*) AS readings
FROM `soe-prod-data-core-7529.nova_be_assets_enriched.meter_reading`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY source
ORDER BY readings DESC
```

### Meter reading submission status

```sql
SELECT
  status,
  workflow_status,
  COUNT(*) AS readings
FROM `soe-prod-data-core-7529.nova_be_assets_enriched.meter_reading`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
GROUP BY status, workflow_status
ORDER BY readings DESC
```

### Meter reads by read source (Junifer model)

```sql
SELECT
  Read_Source,
  COUNT(*) AS reads,
  SUM(Consumption) AS total_consumption
FROM `soe-prod-data-core-7529.soe_junifer_model.w_actual_meterreads`
WHERE Read_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY Read_Source
ORDER BY reads DESC
```

### Daily meter reading submissions

```sql
SELECT
  DATE(created_at) AS date,
  source,
  COUNT(*) AS submissions
FROM `soe-prod-data-core-7529.nova_be_assets_enriched.meter_reading`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY date, source
ORDER BY date DESC, submissions DESC
```

---

## Billing Operations

### Bills generated over time

```sql
SELECT
  DATE(created_dttm) AS bill_date,
  COUNT(*) AS bills_generated,
  SUM(gross_amount) AS total_billed
FROM `soe-prod-data-core-7529.junifer_enriched.bill`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND created_dttm >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND status = 'ACCEPTED'
GROUP BY bill_date
ORDER BY bill_date DESC
```

### Bills by status

```sql
SELECT
  status,
  COUNT(*) AS count,
  SUM(gross_amount) AS total_amount
FROM `soe-prod-data-core-7529.junifer_enriched.bill`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND created_dttm >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY status
ORDER BY count DESC
```

### Bill delivery method breakdown

```sql
SELECT
  billDelivery,
  COUNT(DISTINCT account_number) AS accounts
FROM `soe-prod-data-core-7529.soe_operations_report.bill_delivery`
WHERE meta_report_period_end_date = (
  SELECT MAX(meta_report_period_end_date)
  FROM `soe-prod-data-core-7529.soe_operations_report.bill_delivery`
)
GROUP BY billDelivery
ORDER BY accounts DESC
```

### Billing period status

```sql
SELECT
  status_code,
  COUNT(*) AS periods
FROM `soe-prod-data-core-7529.junifer_enriched.bill_period`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
GROUP BY status_code
ORDER BY periods DESC
```

---

## Digital Journey Performance

This table tracks KPIs across digital channels (App, Web).

### Journey KPIs overview

```sql
SELECT
  KPI_name,
  Channel,
  COUNT(*) AS events,
  SUM(CASE WHEN Success_status = 'Success' THEN 1 ELSE 0 END) AS successful,
  ROUND(SUM(CASE WHEN Success_status = 'Success' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS success_rate
FROM `soe-prod-data-core-7529.soe_junifer_model.digital_journey_performance`
WHERE Created_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY KPI_name, Channel
ORDER BY KPI_name, Channel
```

### Available KPIs

The `digital_journey_performance` table tracks these journeys:
- **Direct Debit Setup** - New DD setups
- **Direct Debit Amount Changes** - DD amount modifications
- **Direct Debit Date Changes** - DD date modifications
- **Submit a read** - Meter reading submissions
- **Smart meter bookings** - SMETS2 installation bookings
- **Make a Card Payment** - One-off card payments
- **Renewals** - Tariff renewal completions
- **Acquisition** - New customer sign-ups
- **COT Move Out** - Change of tenancy (moving out)
- **COT Move In** - Change of tenancy (moving in)

### Daily journey performance

```sql
SELECT
  Created_date,
  KPI_name,
  Channel,
  COUNT(*) AS attempts,
  SUM(CASE WHEN Success_status = 'Success' THEN 1 ELSE 0 END) AS successes
FROM `soe-prod-data-core-7529.soe_junifer_model.digital_journey_performance`
WHERE Created_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY Created_date, KPI_name, Channel
ORDER BY Created_date DESC, KPI_name
```

### Journey success by database source

```sql
SELECT
  DB_Source,
  KPI_name,
  COUNT(*) AS total,
  SUM(CASE WHEN Success_status = 'Success' THEN 1 ELSE 0 END) AS successful
FROM `soe-prod-data-core-7529.soe_junifer_model.digital_journey_performance`
WHERE Created_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY DB_Source, KPI_name
ORDER BY DB_Source, total DESC
```

---

## Key Fields Reference

### smart_meter_bookings

| Column | Description |
|--------|-------------|
| `id` | Booking ID |
| `customer_id` | Nova customer ID |
| `billing_account_id` | Billing account |
| `aes_status` | AES (installer) status |
| `aes_job_number` | AES job reference |
| `mop_status` | MOP agent status |
| `slot_start_date_time` | Appointment start |
| `slot_end_date_time` | Appointment end |
| `installed_datetime` | When installation completed |
| `failed_datetime` | When installation failed |
| `failure_reason` | Reason for failure |
| `cancel_reason` | Reason for cancellation |
| `fuel_type` | ELEC, GAS, DUAL |
| `installation_type` | Type of installation |
| `source` | Booking source (App, Web, Agent) |
| `mpan` | Electricity meter point |
| `mprn` | Gas meter point |

### meter_reading (Nova)

| Column | Description |
|--------|-------------|
| `id` | Reading ID |
| `meter_id` | Meter FK |
| `source` | Reading source (customer, smart, estimate) |
| `status` | Reading status |
| `workflow_status` | Processing workflow status |
| `reading_dttm` | When reading was taken |
| `consumption` | Consumption value |
| `submission_processed` | Has been processed |

### w_actual_meterreads (Junifer model)

| Column | Description |
|--------|-------------|
| `Account_Number` | Junifer account |
| `MPXN` | Meter point (MPAN/MPRN) |
| `MSN` | Meter serial number |
| `Read_Date` | Date of reading |
| `Read_Source` | Source of reading |
| `Reading` | Meter reading value |
| `Consumption` | Calculated consumption |
| `Status` | Reading status |

### digital_journey_performance

| Column | Description |
|--------|-------------|
| `Account_number` | Customer account |
| `Mpxn` | Meter point |
| `KPI_name` | Journey/KPI type |
| `Channel` | App or Web |
| `DB_Source` | Source database |
| `Created_date` | Event date |
| `Success_status` | Success or Failed |

---

## Linking Operations Data

### Smart meter bookings with customer details

```sql
SELECT
  smb.id AS booking_id,
  smb.aes_status,
  smb.fuel_type,
  c.first_name,
  c.last_name,
  ba.account_number
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.smart_meter_bookings` smb
JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.customer` c
  ON smb.customer_id = c.id
  AND c.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.billing_account` ba
  ON smb.billing_account_id = CAST(ba.id AS STRING)
  AND ba.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
WHERE smb.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
```
