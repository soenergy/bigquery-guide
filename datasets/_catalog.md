# Dataset Catalog

Complete inventory of BigQuery datasets organized by business domain.

**Project ID**: `soe-prod-data-core-7529`

---

## Critical: How to Query Enriched Tables

**All `*_enriched` tables are slowly-changing dimension (SCD Type 2) tables.** To get current state:

```sql
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
```

Without this filter, you'll get historical versions of each record.

---

## Dataset Naming Convention

| Suffix | Meaning |
|--------|---------|
| `*_raw` | Raw data from source systems, unprocessed |
| `*_enriched` | Cleaned, typed, with SCD2 history tracking |
| `soe_*` | "Single Source of Everything" - analytics/reporting layer |

---

# Business Domains

## 1. Customer

Customer profiles, contacts, preferences, and lifecycle.

| Dataset | Key Tables | Description |
|---------|------------|-------------|
| `nova_be_customers_enriched` | `customer`, `contact`, `address`, `billing_account`, `customer_preferences` | Nova CRM - primary customer master |
| `junifer_enriched` | `customer`, `account` | Billing system customer records |
| `nova_be_customers_enriched` | `cancellations` | Customer cancellation records |
| `nova_be_customers_enriched` | `customer_referrals` | Referral program data |

**Key links:**
- `nova_be_customers_enriched.billing_account.account_number` → `junifer_enriched.account.number`
- `nova_be_customers_enriched.customer.id` → most Nova tables via `customer_id`

---

## 2. Meter Supply Point

Meter points (MPAN/MPRN), meter assets, and supply configuration.

| Dataset | Key Tables | Description |
|---------|------------|-------------|
| `junifer_enriched` | `mpan`, `mprn` | Meter Point Administration Numbers |
| `junifer_enriched` | `meter`, `meter_point` | Meter hardware and configuration |
| `junifer_enriched` | `meter_register` | Meter register details |
| `nova_be_assets_enriched` | `meter` | Nova meter records |
| `smart_dcc` | Various | Smart meter DCC communications |

**Key links:**
- MPAN (13-digit) for electricity, MPRN (10-digit) for gas
- `meter.meter_point_fk` → `meter_point.id`

---

## 3. Meter Consumption

Meter readings, consumption data, and smart meter telemetry.

| Dataset | Key Tables | Description |
|---------|------------|-------------|
| `nova_be_assets_enriched` | `meter_reading` | Customer-submitted and smart readings (~4.1M) |
| `soe_junifer_model` | `w_actual_meterreads` | Validated actual meter reads (~110M) |
| `junifer_enriched` | `meter_reading_manual` | Manually entered readings |
| `junifer_enriched` | `meter_reading_validated` | Validated readings |
| `soe_dataflows` | `Elec_D0010` | Industry meter readings (electricity) |
| `soe_dataflows` | `Gas_MBR`, `Gas_MRI` | Industry meter data (gas) |

**Note:** Consider also CentreStage/xreads data if available for extended consumption history.

---

## 4. Products / Tariffs / Pricing

Product catalog, tariff structures, and pricing.

| Dataset | Key Tables | Description |
|---------|------------|-------------|
| `nova_be_products_enriched` | `product`, `product_rate` | Product catalog and rates |
| `nova_be_products_enriched` | `quote` | Customer quotes |
| `junifer_enriched` | `product`, `price_plan` | Billing product configuration |
| `junifer_enriched` | `product_bundle`, `product_bundle_dfn` | Customer tariff assignments |
| `junifer_enriched` | `product_bundle.contracted_to_dttm` | Renewal dates |

**Key queries:**
- Current tariff: `product_bundle` WHERE `meta_effective_to_timestamp = '9999-01-01'`
- Renewals due: Filter `contracted_to_dttm` for upcoming dates

---

## 5. Billing

Bills, invoices, billing periods, and bill delivery.

| Dataset | Key Tables | Description |
|---------|------------|-------------|
| `junifer_enriched` | `bill` | Generated bills (~25.6M) |
| `junifer_enriched` | `bill_period` | Billing periods (~24.3M) |
| `junifer_enriched` | `bill_line` | Bill line items |
| `junifer_enriched` | `server_exception` | Billing exceptions/errors (~8.3M) |
| `soe_operations_report` | `bill_delivery` | Bill delivery method tracking |

**Key fields:**
- `bill.status`: ACCEPTED, PENDING, etc.
- `bill.gross_amount`: Total bill amount

---

## 6. Payments / Balances / Debt

Payments, direct debits, account balances, debt, and collections.

| Dataset | Key Tables | Description |
|---------|------------|-------------|
| `junifer_enriched` | `payment` | Payment transactions |
| `junifer_enriched` | `direct_debit`, `direct_debit_inst` | DD setup and instructions |
| `soe_junifer_model` | `w_monthly_active_payment_attributes_d` | **Best for DD status** - monthly snapshot with DD status, amounts, payment history |
| `junifer_enriched` | `account_balance` | Account balances |
| `junifer_enriched` | `dunning_inst` | Dunning instances |
| `nova_be_tickets_enriched` | `dca_account_allocation` | DCA allocations |
| `dca_enriched` | `pastdue`, `conexus`, `coeo_payment`, etc. | DCA-specific data |
| `debt_provisioning` | `debt_provision_analysis`, `customer_level_balance_forecast` | Debt analytics |
| `transunion_enriched` | Various | Credit check data |

**DCAs tracked:** PastDue, Conexus, Coeo, Digital DRA, First Locate, OPOS

---

## 7. Customer Interaction

Support cases, calls, complaints, and communications.

| Dataset | Key Tables | Description |
|---------|------------|-------------|
| `amazon_connect_enriched` | `case_events` | **PRIMARY** - Support cases/tickets |
| `amazon_connect_enriched` | `ctr_events` | Call records (CTR = Contact Trace Record) |
| `amazon_connect_enriched` | `contact_events` | Contact center events |
| `customer_contact_model` | `contact_detail` | **Looker dashboard source** - curated contact view (~1.9M) |
| `nova_be_communications_enriched` | Various | Customer communications |
| `dotdigital_enriched` | Various | Marketing email data |
| `freshdesk_enriched` | `tickets` | ⚠️ **DEPRECATED** - historical only |

**Amazon Connect key fields:**
- Cases: `detail_case_fields_status`, `detail_case_fields_level_1/2/3`
- Complaints: `detail_case_fields_is_complaint = TRUE`
- Link to customer: `case_events.account` = Junifer account number

**Looker Dashboard Model (`customer_contact_model.contact_detail`):**
- Curated view joining CTR + contact events
- Key fields: `contact_channel`, `contact_initiation_method`, `ce_agent_connect_time`
- Email metrics: `twd_status`, `email_reply_check`, `first_agent_email_reply_timestamp`
- Used by: Looker Studio dashboards, email response time reporting

---

## 8. Marketing / Growth

Acquisition, referrals, campaigns, and digital engagement.

| Dataset | Key Tables | Description |
|---------|------------|-------------|
| `soe_junifer_model` | `digital_user_engagement` | Customer digital engagement metrics |
| `soe_junifer_model` | `digital_journey_performance` | Journey KPIs (DD setup, payments, etc.) |
| `analytics_382914461` | `events_*` | Google Analytics 4 (date-sharded) |
| `nova_be_customers_enriched` | `customer_referrals` | Referral program |
| `dotdigital_enriched` | Various | Email marketing |

**GA4 notes:**
- Tables are date-sharded: `events_YYYYMMDD`
- Use `_TABLE_SUFFIX` for date filtering
- `UNNEST(event_params)` to extract custom parameters

**⚠️ Mixpanel is deprecated** - use Google Analytics instead.

---

## 9. Field Services

Smart meter installations, appointments, and field work.

| Dataset | Key Tables | Description |
|---------|------------|-------------|
| `nova_be_customers_enriched` | `smart_meter_bookings` | Smart meter installation bookings (~159K) |
| `smart_dcc` | Various | DCC smart meter comms |

**Key fields in smart_meter_bookings:**
- `aes_status`, `mop_status`: Installation status
- `installed_datetime`: When installed
- `failed_datetime`, `failure_reason`: Failed installs
- `source`: Booking channel (App, Web, Agent)

**Note:** MDS/Calisen data may exist for extended field service tracking.

---

## 10. Settlement / Industry Data

Industry dataflows, settlement, and regulatory data.

| Dataset | Key Tables | Description |
|---------|------------|-------------|
| `soe_dataflows` | `w_df_ftp_info_d` | **FTP file health** - all incoming files (~160M) |
| `soe_dataflows` | `Elec_D0010` | Meter readings from industry (~25M) |
| `soe_dataflows` | `Elec_D0030` | Settlement data (AA/EAC) (~9M) |
| `soe_dataflows` | `Elec_D0300`, `Elec_D0301` | Change of supplier |
| `soe_dataflows` | `Elec_D0086` | Settlement run results |
| `soe_dataflows` | `Gas_MRI`, `Gas_RET`, `Gas_NOSI` | Gas industry flows |
| `soe_trading` | Various | Trading and hedging |

**49 dataflow tables total** - see `use-cases/industry-dataflows.md` for complete reference.

**Operational health:** Query `w_df_ftp_info_d` first - failed files indicate upstream issues.

---

## 11. Finance

Financial reporting and reconciliation.

| Dataset | Key Tables | Description |
|---------|------------|-------------|
| `soe_finance_report` | Various | Finance reporting views |
| `bloomberg` | Various | Market data |
| `soe_trading` | Various | Trading positions |

**Note:** Access (accounting system) data may exist for extended finance tracking.

---

# Supporting Datasets

## Analytics & Reporting Layer

| Dataset | Description |
|---------|-------------|
| `soe_flat` | Flattened views for reporting |
| `soe_junifer_model` | Junifer analytical models |
| `soe_operations_report` | Operations KPIs |

## Error & Diagnostic Data

| Dataset | Key Tables | Description |
|---------|------------|-------------|
| `nova_customers_enriched` | `event_logs` | App events with `is_error` flag (~16.9M) |
| `junifer_enriched` | `server_exception` | Billing system exceptions (~8.3M) |
| `gcp_logging` | Various | GCP infrastructure logs |

## External Data

| Dataset | Description |
|---------|-------------|
| `uk_gov` | UK government data (postcodes, etc.) |
| `hibob_enriched` | HR data from HiBob |

---

# Quick Reference

## Most Used Tables

| Need | Table |
|------|-------|
| Customer list | `nova_be_customers_enriched.customer` |
| Account balances | `junifer_enriched.account` |
| Support cases | `amazon_connect_enriched.case_events` |
| Complaints | `amazon_connect_enriched.case_events` WHERE `detail_case_fields_is_complaint = TRUE` |
| Bills | `junifer_enriched.bill` |
| Payments | `junifer_enriched.payment` |
| Tariffs | `junifer_enriched.product_bundle` |
| Meter readings | `soe_junifer_model.w_actual_meterreads` |
| Smart installs | `nova_be_customers_enriched.smart_meter_bookings` |
| Debt/DCA | `nova_be_tickets_enriched.dca_account_allocation` |
| DD status | `soe_junifer_model.w_monthly_active_payment_attributes_d` |
| App errors | `nova_customers_enriched.event_logs` |
| Dataflow health | `soe_dataflows.w_df_ftp_info_d` |

## Deprecated / Do Not Use

| Dataset | Replacement |
|---------|-------------|
| `freshdesk_enriched` | `amazon_connect_enriched` |
| Mixpanel | `analytics_382914461` (GA4) |

---

# Known Gaps

The following data sources mentioned in domain discussions may not yet be documented:

| Domain | Potential Sources |
|--------|-------------------|
| Meter Consumption | xreads, CentreStage (extended history) |
| Field Services | MDS, Calisen (field workforce) |
| Finance | Access (accounting system) |

If you need data from these sources, check with the data team for availability.
