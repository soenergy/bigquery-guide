# Claude Context: BigQuery Data Guide

This repository contains documentation about BigQuery datasets for team self-service queries.

## When answering data questions, use this knowledge:

### Critical: Enriched Tables Use SCD Type 2

All `*_enriched` tables track history. **To get current state, always filter:**
```sql
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
```

Without this filter, you'll get historical versions of each record.

### Project IDs

| Project | Contents |
|---------|----------|
| `soe-prod-data-core-7529` | Most tables (junifer, nova, soe_junifer_model, soe_dataflows, analytics) |
| `soe-prod-data-curated` | Amazon Connect tables (`amazon_connect_enriched`) |

**⚠️ Important**: For Amazon Connect data (`ctr_events`, `case_events`, `contact_events`), use `soe-prod-data-curated`, not `soe-prod-data-core-7529`.

### Key Table Mappings

| Question Type | Go To |
|--------------|-------|
| Customer data, profiles, contacts | `nova_be_customers_enriched.customer` |
| Customer cancellations | `nova_be_customers_enriched.cancellations` |
| Billing accounts | `junifer_enriched.account` |
| Bills and payments | `junifer_enriched.bill`, `junifer_enriched.payment` |
| **Support cases/tickets** | `amazon_connect_enriched.case_events` |
| **Complaints** | `amazon_connect_enriched.case_events` WHERE `detail_case_fields_is_complaint = TRUE` |
| **Call/contact data** | `amazon_connect_enriched.ctr_events` |
| **Contact deflection (voice)** | `amazon_connect_enriched.ctr_events` - use `attributes_selfservice` for TRUE deflection (not `agent_connectedtoagentts IS NULL`) |
| **Looker dashboard data** | `customer_contact_model.contact_detail` - curated view for dashboards |
| Products/tariffs | `nova_be_products_enriched.product` |
| Meter points | `junifer_enriched.mpan` (elec), `junifer_enriched.mprn` (gas) |
| Smart meter bookings | `nova_be_customers_enriched.smart_meter_bookings` |
| Referrals | `nova_be_customers_enriched.customer_referrals` |
| **Customer tariffs** | `junifer_enriched.product_bundle` + `product_bundle_dfn` |
| **Renewals coming up** | `junifer_enriched.product_bundle.contracted_to_dttm` |
| **Debt / DCA allocations** | `nova_be_tickets_enriched.dca_account_allocation` |
| **DCA performance** | `dca_enriched.pastdue`, `conexus`, etc. |
| **Dunning** | `junifer_enriched.dunning_inst` |
| **Direct debit status** | `soe_junifer_model.w_monthly_active_payment_attributes_d` (use current month_end) |
| **Meter readings** | `nova_be_assets_enriched.meter_reading`, `soe_junifer_model.w_actual_meterreads` |
| **Digital engagement** | `soe_junifer_model.digital_user_engagement` |
| **Digital journey KPIs** | `soe_junifer_model.digital_journey_performance` |
| **Google Analytics (GA4)** | `analytics_382914461.events_*` (date-sharded) |
| **App errors/events** | `nova_customers_enriched.event_logs` (has `is_error` flag) |
| **Billing exceptions** | `junifer_enriched.server_exception` |
| **Marketing consent** | `dotdigital.customer_marketing_master` (`dotdigital_subscription_status`) |
| **Customer interests** | `nova_be_customers_enriched.customer_setting` (EV, smart meter, EV tariff) |
| **Renewal rate by consent** | See `use-cases/marketing-consent-renewal.md` |
| **Tariff cost comparison** | See `use-cases/tariff-cost-comparison.md` |
| **HH electricity consumption** | `soe_xreads.w_xreads_hh_elec_f` (`import_mpan`, `timestamp`, `primary_value`) |
| **Account product/agreement history** | `soe_junifer_model.w_account_product_history_d` (tariffs, contract dates, MPAN) |
| **Industry dataflows** | `soe_dataflows.w_df_ftp_info_d` (file health), `Elec_D0010` (reads), `Elec_D0030` (settlement), `Elec_D0300` (switches), `Gas_RET` (rejections) |
| **Bill delivery** | `soe_operations_report.bill_delivery` |

### ⚠️ IMPORTANT: Freshdesk is Deprecated

**DO NOT use `freshdesk_enriched` for support/ticket data** unless explicitly asked for historical Freshdesk data.

Use `amazon_connect_enriched` instead:
- Support cases → `case_events`
- Complaints → `case_events` WHERE `detail_case_fields_is_complaint = TRUE`
- Call data → `ctr_events`
- Contact events → `contact_events`

### Amazon Connect Key Fields

**Case status**: `detail_case_fields_status`
**Is complaint**: `detail_case_fields_is_complaint` (BOOLEAN)
**Complaint status**: `detail_case_fields_complaint_status`
**Case category**: `detail_case_fields_level_1`, `level_2`, `level_3`
**Created**: `detail_case_createddatetime`
**Account number**: `account`

### ⚠️ Voice Deflection: Abandonment ≠ Deflection

**CRITICAL**: `agent_connectedtoagentts IS NULL` does NOT mean deflection for voice!

| Outcome | How to Identify | Is Deflection? |
|---------|-----------------|----------------|
| **True Deflection** | `attributes_selfservice IN ('makeACardPaymentOnline', 'submitMeterReadingOnline', 'renewalOnline', 'directDebitOnline')` | ✅ YES (~3%) |
| **Abandonment** | No agent + no self-service value | ❌ NO (~50%) |
| **Self-Service Rejected** | `attributes_selfservice = 'rejected'` | ❌ NO |

### ⚠️ Email Deflection: Auto-Response WITH Intent = Deflection

For EMAIL, deflection = contact flow detected intent, sent auto-response, and closed contact:

| Outcome | How to Identify | Is Deflection? |
|---------|-----------------|----------------|
| **Auto-Response (Deflection)** | `CONTACT_FLOW_DISCONNECT` + `attributes_intent IS NOT NULL` | ✅ YES (~4%, ~44/day) |
| **Spam/OOO Filtered** | `queue_name = 'Dropped Emails'` | ❌ NO (junk filtered) |
| **System Notifications** | No Queue + No Intent (e.g., Typeform) | ❌ NO (not customer emails) |
| **Agent Handled** | `agent_connectedtoagentts IS NOT NULL` | ❌ NO (agent worked it) |
| **In Queue (API)** | `queue_name = 'Agent Holding Queue'` AND `disconnectreason = 'API'` | ❌ NO (waiting) |

**⚠️ "No Intent" is NOT deflection** - it's either spam (Dropped Emails) or system notifications (Typeform → fit@so.energy).

### ⚠️ Email Deflection: Only 6 Intents Can Deflect

**Verified from `contactDeflectionHandling` lambda code:**

| Deflectable Intent | Auto-Response Behavior |
|-------------------|------------------------|
| `MovingInIntent` | Conversational (requests more info) |
| `RenewalIntent` | One-shot (reply & close) |
| `MakeACardPaymentIntent` | One-shot (reply & close) |
| `DirectDebitIntent` | Conversational |
| `FinalBillIntent` | Conversational |
| `PaymentIntent` | Conversational |

**All other intents (ComplaintIntent, DebtIntent, etc.) → always routed to agent.**

**KEY FINDING: Customer verification is NOT checked** - deflection happens on intent recognition alone. Safeguards that prevent deflection: HIGH frustration (AI-detected), auto-reply threshold reached (max 1), agent already assigned.

### Cross-Channel Deflection Summary (All Channels)

| Channel | Customer Has Choice? | Deflectable Intents |
|---------|:--------------------:|---------------------|
| **VOICE** | ✅ Press 1=SMS, 2=Agent | Renewal, MovingIn, MovingOut, SubmitMeterReading, MakeACardPayment, DirectDebit |
| **CHAT** | ✅ Bot shows link | Same 6 as voice |
| **EMAIL** | ❌ Automatic | MovingIn, Renewal, MakeACardPayment, DirectDebit, FinalBill, Payment |

**Key difference:** Voice/Chat allow customer to choose deflection or agent. Email deflects automatically with safeguards (AI frustration, threshold, agent assigned).

**Code reference:** `customer-support-center` repo - `lambda/detectDeflection/src/messageCatalog.ts` (voice/chat), `lambda/contactDeflectionHandling` (email).

### CTR Base Filter

For inbound contact analysis (matches wallboard/AWS API):
```sql
-- VOICE and EMAIL
channel = 'VOICE'  -- or 'EMAIL'
AND initiationmethod = 'INBOUND'

-- CHAT uses API, not INBOUND
channel = 'CHAT'
AND initiationmethod = 'API'
```

This excludes OUTBOUND, CALLBACK, TRANSFER (which are counted separately).

### Daily Contact Stats

For daily contact funnel breakdown (voice/email/chat), see `use-cases/contact-deflection.md` → "Daily Contact Stats Queries" section. Includes:
- Contact funnel by channel (agent handled, deflection, dropped in queue, etc.)
- Deflection by intent with take-up rates
- Email safeguard analysis (threshold, frustration)
- Cross-channel daily summary

### Containment Analysis

For measuring if deflected customers call back within 3 days, see `use-cases/contact-deflection.md` → "Containment Analysis" section.

**Key finding**: Deflected customers have ~81% callback rate vs ~28% for agent-handled. Use `customerendpoint_address` (phone) as identifier since deflected contacts lack account numbers.

### Deflection-to-Journey Correlation

For tracking whether deflected customers actually complete the self-service journey, see `use-cases/contact-deflection.md` → "Deflection-to-Journey Correlation" section.

**Key technique**: Link phone → account through historical CTR contacts (where ID&V was completed), then join to `digital_journey_performance`.

**Key finding (Renewals)**: Only ~14% of deflected customers complete online renewal, but ~26% call back and renew via agent. Total renewal rate (~40%) is comparable to agent-handled calls.

### Page Visits as Deflection Success

**Completion isn't the only success metric** - if a customer visits the self-service page, deflection worked. See `use-cases/contact-deflection.md` → "Page Visits as Deflection Success Metric" section.

**Data sources:**
- GA4 (`analytics_382914461.events_*`) for page visits - `user_id` = account number
- `digital_journey_performance` for completions (more reliable than GA4 success events)

**Key findings (Renewals):**
| Channel | Visited Page | Completed |
|---------|-------------:|----------:|
| Voice | **40%** | 14% |
| Email | **43%** | 25% |
| Chat | *Not trackable* | — |

**~40% deflection success** when measured by page visits vs ~14-25% by completions.

### Weekly Deflection Report

For weekly monitoring of deflection performance across all channels, see `use-cases/weekly-deflection-report.md`.

**Report covers:**
- Funnel stages: Contact → Intent → Eligible → Offered → Taken/Rejected
- Post-deflection: Page visits → Completions → Callbacks → Outcomes
- Cross-channel comparison (Voice, Email, Chat)
- By-intent breakdown
- Week-over-week trends

**Key metrics to monitor:**
| Metric | Target |
|--------|--------|
| Voice Take Rate | >25% |
| Email Take Rate | >40% |
| Page Visit Rate | >40% |
| Containment Rate | >75% |
| Repeat Contact Rate | <25% |
| Total Completion | >50% |

**Note:** Repeat contacts are cross-channel (voice, email, chat) and exclude contacts within 30 minutes (system-generated).

### Linking Systems

Nova customer → Junifer account:
- `nova_be_customers_enriched.billing_account.account_number` matches `junifer_enriched.account.number`

Amazon Connect → Junifer:
- `amazon_connect_enriched.case_events.account` is the Junifer account number

### Dataset Documentation

- `datasets/_catalog.md` - Full dataset inventory
- `datasets/nova-platform.md` - Nova CRM data
- `datasets/junifer-billing.md` - Billing/energy data
- `datasets/amazon-connect.md` - Support cases and contact center (PRIMARY)
- `datasets/freshdesk-support.md` - DEPRECATED, historical only

### Use Case Guides

- `use-cases/common-questions.md` - Ready-to-use queries
- `use-cases/commercial-metrics.md` - Tariffs, renewals, fall-through rates
- `use-cases/debt-collections.md` - Debt treatment, DCA allocations, collections
- `use-cases/operations-performance.md` - Smart metering, billing ops, meter readings
- `use-cases/digital-engagement.md` - App/Web engagement, digital journeys, Google Analytics (GA4)
- `use-cases/troubleshooting-errors.md` - Error diagnosis, error→contact correlation
- `use-cases/industry-dataflows.md` - Settlement data, FTP health, D-flows, operational early warnings
- `use-cases/contact-deflection.md` - Email/IVR deflection, intents, self-service correlation, containment analysis
- `use-cases/weekly-deflection-report.md` - Weekly deflection funnel report (all channels, all stages)
- `use-cases/marketing-consent-renewal.md` - Renewal/churn rates by marketing consent, interests breakdown
- `use-cases/tariff-cost-comparison.md` - Compare expected cost across tariffs using HH consumption data

### Common Patterns

**Active customers:**
```sql
FROM nova_be_customers_enriched.customer
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND deleted IS NULL AND state = 'ACTIVE'
```

**Support cases created today:**
```sql
FROM amazon_connect_enriched.case_events
WHERE detail_event_type = 'CASE.CREATED'
  AND DATE(detail_case_createddatetime) = CURRENT_DATE()
```

**Complaints:**
```sql
FROM amazon_connect_enriched.case_events
WHERE detail_case_fields_is_complaint = TRUE
```

**Active billing accounts:**
```sql
FROM junifer_enriched.account
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND cancel_fl != 'Y'
```

**Smart meter installs:**
```sql
FROM nova_be_customers_enriched.smart_meter_bookings
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND installed_datetime IS NOT NULL
```

**Digital journey success rates:**
```sql
FROM soe_junifer_model.digital_journey_performance
WHERE Created_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
-- KPI_name: 'Direct Debit Setup', 'Submit a read', 'Make a Card Payment', etc.
-- Channel: 'App' or 'Web'
-- Success_status: 'Success' or 'Failed'
```

**Digitally engaged customers:**
```sql
FROM soe_junifer_model.digital_user_engagement
WHERE event_date = (SELECT MAX(event_date) FROM soe_junifer_model.digital_user_engagement)
  AND digitally_engaged_in_last_three_month = 'Y'
```

**Google Analytics (GA4) events:**
```sql
FROM analytics_382914461.events_*
WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
  AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
-- Use UNNEST(event_params) to extract custom parameters
```

**App errors (for troubleshooting):**
```sql
FROM nova_customers_enriched.event_logs
WHERE is_error = TRUE
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
-- billing_account_id links to customer/support data
```

**Dataflow health check (failed files):**
```sql
FROM soe_dataflows.w_df_ftp_info_d
WHERE Status != 'SUCCESS'
  AND ReceivedDate >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
-- Check log_message for error details
```

**Direct debit status (current month):**
```sql
FROM soe_junifer_model.w_monthly_active_payment_attributes_d
WHERE month_end = DATE_TRUNC(CURRENT_DATE(), MONTH) + INTERVAL 1 MONTH - INTERVAL 1 DAY
-- dd_status_at_month_end: 'Active Fixed', 'Active Fixed - Seasonal', 'Active Variable', 'Cancelled', 'Never DD', 'Failed'
```
