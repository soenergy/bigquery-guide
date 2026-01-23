# Industry Dataflows & Settlement Data

Industry dataflows are standardized data exchanges between energy market participants (suppliers, distributors, meter operators). Missing or failed dataflows often indicate operational issues before they become customer complaints.

---

## Why Dataflows Matter for Operations

**Early warning system**: Dataflow anomalies often appear before customer-visible problems:
- Missing D0010s → Customers won't receive accurate bills
- Failed D0300s → Switch rejections, customer stuck with old supplier
- Low D0030 volumes → Settlement exposure, incorrect EAC/AA values
- Gas RET spikes → High rejection rate from industry

---

## Key Tables

| Table | Description | Rows | Use Case |
|-------|-------------|------|----------|
| `w_df_ftp_info_d` | **FTP file metadata** - all incoming files | ~160M | Monitor file ingestion health |
| `Elec_D0010` | Meter readings from industry | ~25M | Validate meter read receipt |
| `Elec_D0030` | Settlement data (AA/EAC) | ~9M | Check settlement exposure |
| `Elec_D0300` | Change of supplier readings | ~119K | Monitor switch success |
| `Elec_D0086` | Settlement run results | - | Settlement reconciliation |
| `Gas_MRI` | Meter reading info (gas) | ~662K | Gas meter data |
| `Gas_RET` | Gas rejections | ~24K | Monitor gas process failures |
| `Gas_NOSI` | Notification of supply | - | Gas supply changes |

---

## Monitoring FTP File Health

The `w_df_ftp_info_d` table tracks all incoming dataflow files. This is your first line of defense.

### Recent file ingestion status

```sql
SELECT
  DATE(ReceivedDate) AS date,
  Gas_Elec,
  DataFlow,
  Status,
  COUNT(*) AS files,
  SUM(SizeInByte) / 1024 / 1024 AS total_mb
FROM `soe-prod-data-core-7529.soe_dataflows.w_df_ftp_info_d`
WHERE ReceivedDate >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY date, Gas_Elec, DataFlow, Status
ORDER BY date DESC, Gas_Elec, DataFlow
```

### Failed file processing

```sql
SELECT
  ReceivedDate,
  Gas_Elec,
  DataFlow,
  Received_FileName,
  Status,
  log_message
FROM `soe-prod-data-core-7529.soe_dataflows.w_df_ftp_info_d`
WHERE Status != 'SUCCESS'
  AND ReceivedDate >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
ORDER BY ReceivedDate DESC
```

### Daily file counts by dataflow (trend analysis)

```sql
SELECT
  DATE(ReceivedDate) AS date,
  DataFlow,
  COUNT(*) AS file_count
FROM `soe-prod-data-core-7529.soe_dataflows.w_df_ftp_info_d`
WHERE ReceivedDate >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND Status = 'SUCCESS'
GROUP BY date, DataFlow
ORDER BY DataFlow, date DESC
```

---

## Electricity Dataflows

### D0010 - Meter Readings

Validated meter readings from industry. Low volumes may indicate meter read collection issues.

```sql
SELECT
  DATE(received_date) AS date,
  validation_status,
  COUNT(*) AS readings,
  COUNT(DISTINCT mpan) AS unique_mpans
FROM `soe-prod-data-core-7529.soe_dataflows.Elec_D0010`
WHERE received_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY date, validation_status
ORDER BY date DESC, readings DESC
```

### Failed meter reads with reasons

```sql
SELECT
  failed_read_reason,
  COUNT(*) AS count
FROM `soe-prod-data-core-7529.soe_dataflows.Elec_D0010`
WHERE received_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND failed_read_reason IS NOT NULL
GROUP BY failed_read_reason
ORDER BY count DESC
```

### D0030 - Settlement Data (AA/EAC)

Daily Profiled SPM data for settlement. Used for calculating Annualised Advance (AA) and Estimated Annual Consumption (EAC).

```sql
SELECT
  settlement_date,
  settlement_code,
  COUNT(*) AS records,
  SUM(total) AS total_consumption,
  SUM(aa) AS total_aa,
  SUM(eac) AS total_eac
FROM `soe-prod-data-core-7529.soe_dataflows.Elec_D0030`
WHERE meta_inserted_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY settlement_date, settlement_code
ORDER BY settlement_date DESC
```

### D0030 by Grid Supply Point

```sql
SELECT
  gsp,
  gsp_name,
  COUNT(*) AS records,
  SUM(total) AS total_kwh
FROM `soe-prod-data-core-7529.soe_dataflows.Elec_D0030`
WHERE meta_inserted_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY gsp, gsp_name
ORDER BY total_kwh DESC
```

### D0300 - Change of Supplier Readings

Meter readings exchanged during supplier switches. Rejections here mean switch problems.

```sql
SELECT
  DATE(received_date) AS date,
  from_supplier,
  to_supplier,
  COUNT(*) AS switches
FROM `soe-prod-data-core-7529.soe_dataflows.Elec_D0300`
WHERE received_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY date, from_supplier, to_supplier
ORDER BY date DESC, switches DESC
```

### Switch rejections

```sql
SELECT
  change_supplier_rejection_code,
  COUNT(*) AS rejections
FROM `soe-prod-data-core-7529.soe_dataflows.Elec_D0300`
WHERE received_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND change_supplier_rejection_code IS NOT NULL
GROUP BY change_supplier_rejection_code
ORDER BY rejections DESC
```

---

## Gas Dataflows

### Gas_MRI - Meter Reading Info

Master meter information for gas supply points.

```sql
SELECT
  meter_status,
  COUNT(*) AS meters
FROM `soe-prod-data-core-7529.soe_dataflows.Gas_MRI`
GROUP BY meter_status
ORDER BY meters DESC
```

### Gas_RET - Rejections

Industry rejections for gas processes. High volumes indicate process failures.

```sql
SELECT
  DATE(received_date) AS date,
  reason_for_return,
  record_rejection_acceptance_code,
  COUNT(*) AS rejections
FROM `soe-prod-data-core-7529.soe_dataflows.Gas_RET`
WHERE received_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY date, reason_for_return, record_rejection_acceptance_code
ORDER BY date DESC, rejections DESC
```

### Gas rejection trends

```sql
SELECT
  DATE(received_date) AS date,
  COUNT(*) AS total_rejections
FROM `soe-prod-data-core-7529.soe_dataflows.Gas_RET`
WHERE received_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
GROUP BY date
ORDER BY date DESC
```

---

## All Available Dataflows

### Electricity

| Flow | Table | Purpose |
|------|-------|---------|
| D0004 | `Elec_D0004` | Notification of change |
| D0010 | `Elec_D0010` | **Meter readings** - validated reads from DC |
| D0011 | `Elec_D0011` | Meter reading acknowledgement |
| D0018 | `Elec_D0018_*` | Profile data (multiple variants) |
| D0019 | `Elec_D0019` | Meter Technical Details |
| D0030 | `Elec_D0030` | **Settlement data** - AA/EAC values |
| D0071 | `Elec_D0071` | Aggregated half-hourly data |
| D0086 | `Elec_D0086` | Settlement run results |
| D0095 | `Elec_D0095` | Profile class allocation |
| D0225 | `Elec_D0225` | Supplier purchase matrix |
| D0296 | `Elec_D0296` | Agent appointment notification |
| D0300 | `Elec_D0300` | **Change of supplier** - switch readings |
| D0301 | `Elec_D0301` | Supplier ID notification |
| D0311 | `Elec_D0311` | Metering system ID update |
| S0002-S0015 | `Elec_S00*` | Settlement flows |
| AREGI | `Elec_AREGI` | Agent registration |
| CREGI | `Elec_CREGI` | Change of agent registration |

### Gas

| Flow | Table | Purpose |
|------|-------|---------|
| MRI | `Gas_MRI` | **Meter Reading Info** - meter master data |
| RET | `Gas_RET` | **Rejections** - process failures |
| NOSI | `Gas_NOSI` | Notification of supply interruption |
| COI | `Gas_COI` | Change of shipper info |
| CZI | `Gas_CZI` | Consumption zone info |
| MBR | `Gas_MBR` | Meter reading |
| NRL | `Gas_NRL` | Nomination |
| RD1 | `Gas_RD1` | Read data |
| SAR | `Gas_SAR` | Site address response |
| URN/URS | `Gas_URN`, `Gas_URS` | Unidentified gas |
| UT003-015 | `Gas_UT0*` | Utility flows |
| AREGI | `Gas_AREGI` | Agent registration |
| CREGI | `Gas_CREGI` | Change of agent registration |

---

## Operational Health Dashboard Queries

### Daily dataflow health summary

```sql
WITH file_stats AS (
  SELECT
    DATE(ReceivedDate) AS date,
    Gas_Elec,
    COUNT(*) AS total_files,
    SUM(CASE WHEN Status = 'SUCCESS' THEN 1 ELSE 0 END) AS successful,
    SUM(CASE WHEN Status != 'SUCCESS' THEN 1 ELSE 0 END) AS failed
  FROM `soe-prod-data-core-7529.soe_dataflows.w_df_ftp_info_d`
  WHERE ReceivedDate >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  GROUP BY date, Gas_Elec
)
SELECT
  date,
  Gas_Elec,
  total_files,
  successful,
  failed,
  ROUND(failed * 100.0 / total_files, 2) AS failure_rate_pct
FROM file_stats
ORDER BY date DESC, Gas_Elec
```

### Missing dataflows detection

Compare today's files against expected patterns:

```sql
WITH today_flows AS (
  SELECT DISTINCT DataFlow
  FROM `soe-prod-data-core-7529.soe_dataflows.w_df_ftp_info_d`
  WHERE DATE(ReceivedDate) = CURRENT_DATE()
),
yesterday_flows AS (
  SELECT DISTINCT DataFlow
  FROM `soe-prod-data-core-7529.soe_dataflows.w_df_ftp_info_d`
  WHERE DATE(ReceivedDate) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
)
SELECT y.DataFlow AS missing_today
FROM yesterday_flows y
LEFT JOIN today_flows t ON y.DataFlow = t.DataFlow
WHERE t.DataFlow IS NULL
```

### Volume anomaly detection

Flag dataflows with significantly different volumes than usual:

```sql
WITH daily_volumes AS (
  SELECT
    DataFlow,
    DATE(ReceivedDate) AS date,
    COUNT(*) AS file_count
  FROM `soe-prod-data-core-7529.soe_dataflows.w_df_ftp_info_d`
  WHERE ReceivedDate >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND Status = 'SUCCESS'
  GROUP BY DataFlow, date
),
stats AS (
  SELECT
    DataFlow,
    AVG(file_count) AS avg_count,
    STDDEV(file_count) AS stddev_count
  FROM daily_volumes
  GROUP BY DataFlow
),
today_volumes AS (
  SELECT DataFlow, file_count
  FROM daily_volumes
  WHERE date = CURRENT_DATE()
)
SELECT
  t.DataFlow,
  t.file_count AS today_count,
  ROUND(s.avg_count, 1) AS avg_count,
  ROUND((t.file_count - s.avg_count) / NULLIF(s.stddev_count, 0), 2) AS z_score
FROM today_volumes t
JOIN stats s ON t.DataFlow = s.DataFlow
WHERE ABS((t.file_count - s.avg_count) / NULLIF(s.stddev_count, 0)) > 2  -- More than 2 std devs
ORDER BY ABS((t.file_count - s.avg_count) / NULLIF(s.stddev_count, 0)) DESC
```

---

## Linking Dataflows to Customer Issues

### MPAN lookup in dataflows

```sql
-- Find all dataflow activity for a specific meter point
SELECT
  'D0010' AS source,
  received_date,
  validation_status AS status,
  meter_reading AS value
FROM `soe-prod-data-core-7529.soe_dataflows.Elec_D0010`
WHERE mpan = '1234567890123'  -- Replace with MPAN
  AND received_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)

UNION ALL

SELECT
  'D0300' AS source,
  received_date,
  change_supplier_rejection_code AS status,
  meter_reading AS value
FROM `soe-prod-data-core-7529.soe_dataflows.Elec_D0300`
WHERE mpan = '1234567890123'
  AND received_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)

ORDER BY received_date DESC
```

### MPRN lookup for gas

```sql
SELECT
  'RET' AS source,
  received_date,
  reason_for_return,
  meter_reading
FROM `soe-prod-data-core-7529.soe_dataflows.Gas_RET`
WHERE mprn = '1234567890'  -- Replace with MPRN
  AND received_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
ORDER BY received_date DESC
```

---

## Key Fields Reference

### w_df_ftp_info_d

| Column | Description |
|--------|-------------|
| `ReceivedDate` | When file was loaded to BigQuery |
| `DataFlow` | Flow code (D0010, Gas_MRI, etc.) |
| `Gas_Elec` | Gas or Elec indicator |
| `Status` | Processing status (SUCCESS/FAILED) |
| `log_message` | Error details if failed |
| `SizeInByte` | File size |
| `Received_FileName` | Original filename from FTP |

### Common dataflow fields

| Column | Description |
|--------|-------------|
| `received_date` | When data was received |
| `mpan` | Electricity meter point (13 digits) |
| `mprn` | Gas meter point (10 digits) |
| `meta_inserted_timestamp` | When inserted to BigQuery |
| `meta_source_filename` | Source file reference |

---

## Diagnostic Workflow

1. **Check FTP health first**: Query `w_df_ftp_info_d` for failed files
2. **Identify missing flows**: Compare today vs yesterday
3. **Check volume anomalies**: Are we getting expected file counts?
4. **Drill into specific flows**: D0010 for reads, D0300 for switches
5. **Link to customers**: Use MPAN/MPRN to find affected customers
6. **Correlate with support**: Do support cases mention billing/switching issues?

---

## Notes

- Dataflows are **not SCD2** - query directly by `received_date` or `meta_inserted_timestamp`
- **FTP metadata table** (`w_df_ftp_info_d`) is the master health check
- **Partitioning**: Most tables are partitioned by `received_date` - always include date filters
- **Clustering**: Tables are typically clustered by MPAN/MPRN for efficient lookups
