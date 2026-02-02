# Smart Meter Booking Sankey & Funnel

Sankey and funnel visualizations for measuring smart meter booking intervention effectiveness.

## Intervention Being Measured

1. **Proactive email slot offerings** to customers on the waiting list (`offer_channel = 'EMAIL'`)
2. **Simplified booking journey**
3. **Customer preference collection** on waiting list (`customer_availability` JSON)

## Tables Used

| Table | Project | Description |
|-------|---------|-------------|
| `smartmeter_customer_waiting_list` | `soe-prod-data-curated.nova_be_customers_enriched` | Waiting list entries with preferences |
| `smartmeter_appointment_offerings` | `soe-prod-data-curated.nova_be_customers_enriched` | Slot offers with channel (EMAIL/SMBP) |
| `smart_meter_bookings` | `soe-prod-data-curated.nova_be_customers_enriched` | Bookings and outcomes |

## Key Fields

### Status Field
**Use `COALESCE(aes_status, mop_status)`** - historical data uses `aes_status`, new data uses `mop_status`.

### Appointment Date
**Use `slot_start_date_time`** for the appointment date.

### Status Values → Outcome Mapping
| Raw Status | Normalized Outcome |
|------------|-------------------|
| `COMPLETED`, `Completed`, `Completed - Install & Leave` | Completed |
| `ABORTED`, `Aborted` | Aborted |
| `CANCELLED` | Cancelled |
| `BOOKED`, `RESCHEDULED`, `STARTED`, `ON_SITE`, `ON_ROUTE`, `PAUSED`, `NULL` | Pending |

---

## Queries

### Sankey Queries
| File | Purpose |
|------|---------|
| `sankey_query.sql` | Basic Sankey - `source`, `target`, `value`, `stage` |
| `sankey_with_filters.sql` | **Looker Studio** - includes all filter dimensions |

### Funnel Queries
| File | Purpose |
|------|---------|
| `smbp_funnel.sql` | SMBP no-slots funnel with conversion rates |
| `smbp_funnel_with_filters.sql` | **Looker Studio** - funnel with filter dimensions |

### Summary Stats
| File | Purpose |
|------|---------|
| `conversion_stats.sql` | Conversion rates by entry path and offer channel |

---

## Filter Dimensions

### Time Filters
| Column | Description | Example |
|--------|-------------|---------|
| `first_contact_week` | First interaction with booking system (earliest of registration, offer, booking) | `2026-W03` |
| `first_contact_month` | Month of first contact | `2026-01` |
| `offer_week` | Week slot was offered | `2026-W03` |
| `appointment_week` | Week of scheduled appointment | `2026-W05` |

### Preference Filters
| Column | Values |
|--------|--------|
| `has_preferences` | `Yes`, `No`, `N/A` |
| `flexibility_level` | `Fully Flexible (8-10 slots)`, `Mostly Flexible (5-7 slots)`, `Limited (2-4 slots)`, `Very Limited (1 slot)`, `No Preferences Set` |
| `time_preference` | `AM & PM`, `AM Only`, `PM Only`, `Not Set` |

### Path Filters
| Column | Values |
|--------|--------|
| `offer_channel` | `Email Offer`, `SMBP Offer`, `No Offer Record` |
| `entry_path` | `Waiting List`, `Direct` |

---

## Key Findings

### Conversion Stats (All Time)

| Entry Path | Channel | Customers | Booking Rate | Completion Rate | End-to-End |
|------------|---------|-----------|--------------|-----------------|------------|
| Waiting List | **EMAIL** | 1,467 | 52.6% | 28.5% | 15.0% |
| Waiting List | SMBP | 11,874 | 71.6% | 25.9% | 18.5% |
| Waiting List | No Offer | 999 | 48.1% | 28.7% | 13.8% |

**Key insight**: EMAIL has higher completion rate of booked (28.5% vs 25.9%) but lower booking rate.

### SMBP No-Slots Funnel

For customers who visited SMBP, found no slots, and joined the waiting list:

| Stage | Customers | % of Start | Conversion |
|-------|-----------|------------|------------|
| 1. SMBP No Slots → Waitlist | 1,483 | 100% | — |
| 2. Offered Slot | 804 | 54.2% | 54.2% |
| 3. Booked | 376 | 25.4% | 46.8% |
| 4. Completed | 138 | 9.3% | 36.7% |

---

## Looker Studio Setup

### 1. Create Data Source
- Add BigQuery data source
- Use Custom Query with `sankey_with_filters.sql` or `smbp_funnel_with_filters.sql`
- Project: `soe-prod-data-curated`

### 2. Sankey Chart
- Chart type: Sankey (community visualization)
- **From**: `source`
- **To**: `target`
- **Weight**: `value`

### 3. Funnel Chart
- Dimension: `stage_name`
- Metric: `customers`
- Sort: `stage_number`

### 4. Add Filter Controls
- `first_contact_week` - Filter by when customers first engaged
- `offer_channel` - Compare EMAIL vs SMBP
- `has_preferences` - Segment by preference collection
- `appointment_week` - Filter by appointment timing

---

## SQL Reference

### Status Normalization Pattern
```sql
CASE
  WHEN UPPER(COALESCE(aes_status, mop_status)) = 'COMPLETED'
       OR COALESCE(aes_status, mop_status) = 'Completed - Install & Leave' THEN 'Completed'
  WHEN UPPER(COALESCE(aes_status, mop_status)) = 'ABORTED' THEN 'Aborted'
  WHEN UPPER(COALESCE(aes_status, mop_status)) = 'CANCELLED' THEN 'Cancelled'
  WHEN COALESCE(aes_status, mop_status) IN ('BOOKED', 'RESCHEDULED', 'STARTED', 'ON_SITE', 'ON_ROUTE', 'PAUSED') THEN 'Pending'
  WHEN COALESCE(aes_status, mop_status) IS NULL THEN 'Pending'
  ELSE 'Other'
END AS outcome
```

### First Contact Date Pattern
```sql
LEAST(
  COALESCE(registration_date, DATE '9999-12-31'),
  COALESCE(offer_date, DATE '9999-12-31'),
  COALESCE(booking_date, DATE '9999-12-31')
) AS first_contact_date
```
