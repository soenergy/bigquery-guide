# Contact Deflection & Self-Service Analysis

Tracking contacts deflected to digital self-service, understanding customer intents, and measuring outcomes.

---

## Key Tables

| Table | Dataset | Project | Description |
|-------|---------|---------|-------------|
| `ctr_events` | `amazon_connect_enriched` | `soe-prod-data-curated` | Contact Trace Records - all contact center interactions |
| `digital_journey_performance` | `soe_junifer_model` | `soe-prod-data-core-7529` | Self-service journey completions (App/Web) |
| `digital_user_engagement` | `soe_junifer_model` | `soe-prod-data-core-7529` | Digital engagement metrics |

**⚠️ IMPORTANT**: Amazon Connect tables are in `soe-prod-data-curated`, not `soe-prod-data-core-7529`.

---

## ⚠️ CRITICAL: Deflection vs Abandonment

**`agent_connectedtoagentts IS NULL` does NOT mean deflection!**

Contacts that don't reach an agent fall into several categories:

| Outcome | How to Identify | Is Deflection? |
|---------|-----------------|----------------|
| **True Deflection** | `attributes_selfservice` has success value | ✅ YES |
| **Self-Service Rejected** | `attributes_selfservice = 'rejected'` | ❌ NO (failed attempt) |
| **Self-Service Error** | `attributes_selfservice = 'error'` | ❌ NO (system error) |
| **Early Abandonment** | No intent captured, short duration | ❌ NO (hung up early) |
| **IVR Abandonment** | Has intent but no self-service value | ❌ NO (gave up in IVR) |
| **Queue Abandonment** | `queue_name IS NOT NULL`, no agent | ❌ NO (gave up waiting) |

---

## Key Fields

### Deflection Indicator (PRIMARY)

| Field | Values | Meaning |
|-------|--------|---------|
| `attributes_selfservice` | `'makeACardPaymentOnline'` | ✅ Deflected to online payment |
| | `'submitMeterReadingOnline'` | ✅ Deflected to online meter read |
| | `'renewalOnline'` | ✅ Deflected to online renewal |
| | `'directDebitOnline'` | ✅ Deflected to online DD setup |
| | `'checkBalanceOnline'` | ✅ Deflected to online balance check |
| | `'rejected'` | ❌ Tried self-service, validation failed |
| | `'error'` | ❌ Self-service encountered error |
| | `NULL` | No self-service attempted |

### Other Useful Fields

| Field | Description |
|-------|-------------|
| `agent_connectedtoagentts` | Timestamp when connected to agent (NULL = no agent) |
| `attributes_intent` | Customer's detected intent |
| `attributes_initialintent` | Customer's initial reason for contact |
| `disconnectreason` | How the contact ended |
| `queue_name` | Queue name if contact reached queue |
| `channel` | Contact channel: VOICE, EMAIL, CHAT, TASK |
| `attributes_accountnumbers` | Account number for linking to other data |

---

## True Deflection Logic

### Voice - True Deflection:
```sql
channel = 'VOICE'
AND attributes_selfservice IN (
    'makeACardPaymentOnline',
    'submitMeterReadingOnline',
    'renewalOnline',
    'directDebitOnline',
    'checkBalanceOnline'
)
```

### Email - Deflection (Auto-Response Pattern):

Email deflection works differently from voice. Emails are deflected when the contact flow sends an automated response and closes the contact.

```sql
-- Email deflection = auto-response sent, contact closed
channel = 'EMAIL'
AND initiationmethod = 'INBOUND'
AND disconnectreason = 'CONTACT_FLOW_DISCONNECT'
AND (queue_name IS NULL OR queue_name NOT IN ('Dropped Emails'))
```

**This is NOT the same as "Dropped Emails"** (spam/OOO filtering).

---

## Base Filters

### Voice - Use INBOUND only:
```sql
channel = 'VOICE'
AND initiationmethod = 'INBOUND'
```

This matches the wallboard/AWS API definition. It excludes:
- OUTBOUND (agent-initiated calls)
- CALLBACK (scheduled callbacks - counted separately)
- TRANSFER/QUEUE_TRANSFER (internal transfers)

### Chat/Email:
```sql
channel = 'CHAT'  -- or 'EMAIL'
AND initiationmethod = 'INBOUND'
```

### Optional: Additional noise filters
These remove ~1% of contacts (minimal impact):
```sql
-- Exclude spam (optional)
AND (segment_connect_xsesspamverdict_valuestring IS NULL
     OR segment_connect_xsesspamverdict_valuestring != 'FAIL')

-- Exclude failed telecom connections (optional)
AND disconnectreason NOT IN (
    'TELECOM_ORIGINATOR_CANCEL', 'TELECOM_NUMBER_INVALID',
    'TELECOM_UNANSWERED', 'TELECOM_BUSY', 'TELECOM_POTENTIAL_BLOCKING',
    'CUSTOMER_CONNECTION_NOT_ESTABLISHED', 'DISCARDED'
)
```

---

## Queries

### Voice Contact Outcomes (Full Breakdown)

```sql
-- Complete breakdown of what happens to voice contacts
WITH voice_contacts AS (
  SELECT
    contactid,
    agent_connectedtoagentts,
    attributes_selfservice,
    disconnectreason,
    queue_name,
    COALESCE(attributes_intent, attributes_initialintent) AS intent,
    attributes_accountnumbers AS account_number
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
    AND channel = 'VOICE'
    AND initiationmethod = 'INBOUND'
)

SELECT
  CASE
    WHEN agent_connectedtoagentts IS NOT NULL THEN '1. Reached Agent'
    WHEN attributes_selfservice IN ('makeACardPaymentOnline', 'submitMeterReadingOnline',
         'renewalOnline', 'directDebitOnline', 'checkBalanceOnline')
         THEN '2. TRUE DEFLECTION (to self-service)'
    WHEN attributes_selfservice = 'rejected' THEN '3. Self-Service Rejected'
    WHEN attributes_selfservice = 'error' THEN '4. Self-Service Error'
    WHEN intent IS NULL THEN '5. Early Abandonment (no intent)'
    WHEN queue_name IS NOT NULL THEN '6. Queue Abandonment'
    ELSE '7. IVR Abandonment'
  END AS outcome,
  COUNT(*) AS contacts,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct,
  COUNT(DISTINCT account_number) AS unique_accounts
FROM voice_contacts
GROUP BY outcome
ORDER BY outcome
```

### True Voice Deflection Rate

```sql
-- Accurate deflection rate for voice (not abandonment!)
SELECT
  COUNT(*) AS total_voice_contacts,

  -- TRUE deflections only
  COUNTIF(attributes_selfservice IN ('makeACardPaymentOnline', 'submitMeterReadingOnline',
       'renewalOnline', 'directDebitOnline', 'checkBalanceOnline')) AS true_deflections,
  ROUND(COUNTIF(attributes_selfservice IN ('makeACardPaymentOnline', 'submitMeterReadingOnline',
       'renewalOnline', 'directDebitOnline', 'checkBalanceOnline')) * 100.0 / COUNT(*), 1) AS true_deflection_rate_pct,

  -- Reached agent
  COUNTIF(agent_connectedtoagentts IS NOT NULL) AS reached_agent,
  ROUND(COUNTIF(agent_connectedtoagentts IS NOT NULL) * 100.0 / COUNT(*), 1) AS agent_rate_pct,

  -- Abandonments (everything else that didn't reach agent)
  COUNTIF(agent_connectedtoagentts IS NULL
          AND (attributes_selfservice IS NULL OR attributes_selfservice IN ('rejected', 'error'))) AS abandonments,
  ROUND(COUNTIF(agent_connectedtoagentts IS NULL
          AND (attributes_selfservice IS NULL OR attributes_selfservice IN ('rejected', 'error'))) * 100.0 / COUNT(*), 1) AS abandonment_rate_pct

FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
  AND channel = 'VOICE'
  AND initiationmethod = 'INBOUND'
```

### Self-Service Deflection by Type

```sql
-- What self-service options are being used?
SELECT
  attributes_selfservice,
  CASE
    WHEN attributes_selfservice IN ('makeACardPaymentOnline', 'submitMeterReadingOnline',
         'renewalOnline', 'directDebitOnline', 'checkBalanceOnline') THEN 'SUCCESS'
    WHEN attributes_selfservice = 'rejected' THEN 'REJECTED'
    WHEN attributes_selfservice = 'error' THEN 'ERROR'
    ELSE 'OTHER'
  END AS status,
  COUNT(*) AS contacts,
  COUNT(DISTINCT attributes_accountnumbers) AS unique_accounts
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
  AND channel = 'VOICE'
  AND initiationmethod = 'INBOUND'
  AND attributes_selfservice IS NOT NULL
GROUP BY attributes_selfservice
ORDER BY contacts DESC
```

### Daily Voice Deflection Trends (Corrected)

```sql
-- Daily true deflection rate (not abandonment)
SELECT
  DATE(initiationtimestamp) AS date,
  COUNT(*) AS total_contacts,
  COUNTIF(agent_connectedtoagentts IS NOT NULL) AS reached_agent,
  COUNTIF(attributes_selfservice IN ('makeACardPaymentOnline', 'submitMeterReadingOnline',
       'renewalOnline', 'directDebitOnline', 'checkBalanceOnline')) AS true_deflections,
  ROUND(COUNTIF(attributes_selfservice IN ('makeACardPaymentOnline', 'submitMeterReadingOnline',
       'renewalOnline', 'directDebitOnline', 'checkBalanceOnline')) * 100.0 / COUNT(*), 1) AS deflection_rate_pct,
  COUNTIF(agent_connectedtoagentts IS NULL
          AND (attributes_selfservice IS NULL OR attributes_selfservice IN ('rejected', 'error'))) AS abandonments,
  ROUND(COUNTIF(agent_connectedtoagentts IS NULL
          AND (attributes_selfservice IS NULL OR attributes_selfservice IN ('rejected', 'error'))) * 100.0 / COUNT(*), 1) AS abandonment_rate_pct
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND channel = 'VOICE'
  AND initiationmethod = 'INBOUND'
GROUP BY date
ORDER BY date DESC
```

### Abandonment Analysis by Intent

```sql
-- Which intents have highest abandonment? (opportunity for better deflection)
SELECT
  COALESCE(attributes_intent, attributes_initialintent, 'No Intent') AS intent,
  COUNT(*) AS total_contacts,
  COUNTIF(agent_connectedtoagentts IS NOT NULL) AS reached_agent,
  COUNTIF(attributes_selfservice IN ('makeACardPaymentOnline', 'submitMeterReadingOnline',
       'renewalOnline', 'directDebitOnline', 'checkBalanceOnline')) AS deflected,
  COUNTIF(agent_connectedtoagentts IS NULL
          AND (attributes_selfservice IS NULL OR attributes_selfservice IN ('rejected', 'error'))) AS abandoned,
  ROUND(COUNTIF(agent_connectedtoagentts IS NULL
          AND (attributes_selfservice IS NULL OR attributes_selfservice IN ('rejected', 'error'))) * 100.0 / COUNT(*), 1) AS abandonment_rate_pct
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
  AND channel = 'VOICE'
  AND initiationmethod = 'INBOUND'
GROUP BY intent
HAVING COUNT(*) >= 10  -- Filter low volume
ORDER BY abandoned DESC
```

---

## Email Deflection (Auto-Response)

Email deflection happens when the contact flow:
1. Receives an inbound email
2. Classifies the intent
3. Sends an automated response with relevant self-service info
4. Closes the contact (CONTACT_FLOW_DISCONNECT)

**This is different from "Dropped Emails"** which filters spam/OOO auto-replies.

### Email Contact Outcomes

| Outcome | How to Identify | Is Deflection? |
|---------|-----------------|----------------|
| **Agent Handled** | `agent_connectedtoagentts IS NOT NULL` | ❌ NO (agent worked it) |
| **Auto-Response (Deflection)** | `CONTACT_FLOW_DISCONNECT` + `intent IS NOT NULL` + not Dropped Emails | ✅ YES (~44/day) |
| **Dropped (Spam/OOO)** | `queue_name = 'Dropped Emails'` | ❌ NO (filtered junk) |
| **System Notifications Dropped** | No Queue + No Intent (Typeform → fit@so.energy) | ❌ NO (not customer emails) |
| **In Queue (API)** | `queue_name = 'Agent Holding Queue'` AND `disconnectreason = 'API'` | ❌ NO (waiting for agent) |
| **Transferred** | `disconnectreason = 'TRANSFERRED'` | ❌ NO (routed to specialist) |

### Email Categories Breakdown

```sql
-- Full email breakdown by outcome
SELECT
  CASE
    WHEN queue_name = 'Dropped Emails' THEN '1. Spam/OOO (Dropped Emails queue)'
    WHEN agent_connectedtoagentts IS NOT NULL THEN '2. Agent Handled'
    WHEN disconnectreason = 'CONTACT_FLOW_DISCONNECT'
         AND attributes_intent IS NOT NULL AND attributes_intent != ''
         THEN '3. Auto-Response with Intent (TRUE DEFLECTION)'
    WHEN disconnectreason = 'CONTACT_FLOW_DISCONNECT'
         AND (attributes_intent IS NULL OR attributes_intent = '')
         AND (queue_name IS NULL OR queue_name = '')
         THEN '4. System Notifications Dropped (NOT deflection)'
    WHEN queue_name = 'Agent Holding Queue' AND disconnectreason = 'API' THEN '5. In Queue (Waiting)'
    WHEN disconnectreason = 'TRANSFERRED' THEN '6. Transferred'
    ELSE '7. Other'
  END AS outcome,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE channel = 'EMAIL'
  AND initiationmethod = 'INBOUND'
  AND DATE(initiationtimestamp) = CURRENT_DATE() - 1
GROUP BY outcome
ORDER BY outcome
```

### Email Auto-Response by Intent

Certain intents are designed for auto-response (self-service journeys):

```sql
-- Which intents get auto-responded vs agent-routed?
SELECT
  COALESCE(attributes_intent, 'No Intent') AS intent,
  COUNT(*) AS total,
  COUNTIF(agent_connectedtoagentts IS NOT NULL) AS agent_handled,
  COUNTIF(disconnectreason = 'CONTACT_FLOW_DISCONNECT'
          AND (queue_name IS NULL OR queue_name != 'Dropped Emails')) AS auto_responded,
  ROUND(COUNTIF(disconnectreason = 'CONTACT_FLOW_DISCONNECT'
          AND (queue_name IS NULL OR queue_name != 'Dropped Emails')) * 100.0 / COUNT(*), 1) AS auto_response_rate_pct
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE channel = 'EMAIL'
  AND initiationmethod = 'INBOUND'
  AND DATE(initiationtimestamp) = CURRENT_DATE() - 1
GROUP BY intent
ORDER BY total DESC
```

### Intents That Auto-Respond (True Email Deflection)

**Only 6 specific intents can trigger email deflection** (verified from `contactDeflectionHandling` lambda):

| Intent | Behavior | Count (~) |
|--------|----------|-----------|
| `MovingInIntent` | Conversational - requests additional info, can have follow-up | ~6 |
| `RenewalIntent` | One-shot - auto-reply sent, case closed immediately | ~4 |
| `MakeACardPaymentIntent` | One-shot - auto-reply sent, case closed immediately | ~2 |
| `DirectDebitIntent` | Conversational - no extra info needed, can have follow-up | ~11 |
| `FinalBillIntent` | Conversational - no extra info needed, can have follow-up | ~10 |
| `PaymentIntent` | Conversational - no extra info needed, can have follow-up | ~13 |

**⚠️ All other intents (e.g., ComplaintIntent, BillDisputeIntent, DebtIntent) are routed to agents - NO auto-response.**

**⚠️ "No Intent" does NOT get auto-responded** - these are system notifications being dropped (see below).

### Email Deflection Logic (from Code)

**Verified from `customer-support-center` repo - `lambda/contactDeflectionHandling`:**

1. **Customer verification is NOT checked** - deflection happens on intent recognition alone
2. **Only the 6 intents above can trigger deflection** - defined in `lambda-utils/intent.ts`
3. **Deflection safeguards that prevent auto-response:**
   - HIGH frustration detected (Bedrock AI analyzes email tone)
   - Auto-reply threshold reached (max 1 auto-reply per case)
   - Agent already assigned to case
   - Contact previously routed to agent

**Flow:**
```
Email arrives → Intent detected?
  ├─ No intent → Skip (route to queue or drop if system notification)
  └─ Yes, intent detected → Is intent deflectable?
      ├─ No (e.g., ComplaintIntent) → Route to agent queue
      └─ Yes (6 intents above) → Check safeguards
          ├─ HIGH frustration? → Route to agent
          ├─ Already got 1 auto-reply? → Route to agent
          ├─ Agent assigned? → Skip deflection
          └─ All clear → Send auto-response, mark as deflected
```

**Code reference:** `lambda/contactDeflectionHandling/src/index.ts:139-142` - no intent = skip, `lambda/lambdaUtils/src/nodejs/lambda-utils/intent.ts:83-114` - deflectable intents list.

### "No Intent" Bucket Deep Dive (NOT Deflection)

Emails with no detected intent fall into two distinct categories:

| Category | Queue | Count (typical) | What it is |
|----------|-------|-----------------|------------|
| **Spam/OOO/Bounce** | `Dropped Emails` | ~236 | Filtered junk |
| **System Notifications** | No Queue | ~66 | Non-customer emails |

**Dropped Emails breakdown:**

| Sender Type | Example | Description |
|-------------|---------|-------------|
| noreply/no-reply | ~54% | OOO auto-replies from customers |
| other | ~33% | Spam or unrecognized senders |
| mailer-daemon/postmaster | ~10% | Bounce/delivery failure notifications |
| notification | ~3% | System notification emails |

**No Queue breakdown (routing gap):**

```sql
-- Check what's in the No Queue / No Intent bucket
SELECT
  customerendpoint_address AS sender,
  systemendpoint_address AS recipient,
  COUNT(*) AS count
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE channel = 'EMAIL'
  AND initiationmethod = 'INBOUND'
  AND DATE(initiationtimestamp) = CURRENT_DATE() - 1
  AND (attributes_intent IS NULL OR attributes_intent = '')
  AND (queue_name IS NULL OR queue_name = '')
GROUP BY sender, recipient
ORDER BY count DESC
```

**Known routing gap:** Typeform survey notifications (`notifications@followups.typeform.io` → `fit@so.energy`) are being dropped because:
- They can't be classified with a customer intent
- They're form submission alerts, not customer support emails
- No routing rule exists for them

⚠️ **These should be excluded from contact center metrics** or routed to a different system (ticketing, Slack, etc.)

### Account Validation Impact

Auto-response also triggers when account cannot be validated:

```sql
-- Auto-response rate by account validation status
SELECT
  COALESCE(attributes_intent, 'No Intent') AS intent,
  COALESCE(attributes_accountvalid, 'Unknown') AS account_valid,
  COUNT(*) AS total,
  COUNTIF(disconnectreason = 'CONTACT_FLOW_DISCONNECT'
          AND (queue_name IS NULL OR queue_name != 'Dropped Emails')) AS auto_responded
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE channel = 'EMAIL'
  AND initiationmethod = 'INBOUND'
  AND DATE(initiationtimestamp) >= CURRENT_DATE() - 7
GROUP BY intent, account_valid
HAVING total >= 5
ORDER BY intent, account_valid
```

### Daily Email Deflection Trend

```sql
-- Track email deflection rate over time
SELECT
  DATE(initiationtimestamp) AS date,
  COUNT(*) AS total_emails,
  COUNTIF(queue_name = 'Dropped Emails') AS spam_ooo_filtered,
  COUNTIF(agent_connectedtoagentts IS NOT NULL) AS agent_handled,
  COUNTIF(disconnectreason = 'CONTACT_FLOW_DISCONNECT'
          AND (queue_name IS NULL OR queue_name != 'Dropped Emails')) AS auto_responded,
  ROUND(COUNTIF(disconnectreason = 'CONTACT_FLOW_DISCONNECT'
          AND (queue_name IS NULL OR queue_name != 'Dropped Emails')) * 100.0 / COUNT(*), 1) AS deflection_rate_pct
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE channel = 'EMAIL'
  AND initiationmethod = 'INBOUND'
  AND DATE(initiationtimestamp) >= CURRENT_DATE() - 30
GROUP BY date
ORDER BY date DESC
```

---

## Self-Service Correlation

### Did deflected customers complete self-service online?

```sql
-- For customers truly deflected to self-service, did they complete online?
WITH deflected_accounts AS (
  SELECT DISTINCT
    attributes_accountnumbers AS account_number,
    DATE(initiationtimestamp) AS deflection_date,
    attributes_selfservice AS deflection_type,
    COALESCE(attributes_intent, attributes_initialintent) AS intent
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND channel = 'VOICE'
    AND attributes_selfservice IN ('makeACardPaymentOnline', 'submitMeterReadingOnline',
         'renewalOnline', 'directDebitOnline', 'checkBalanceOnline')
    AND attributes_accountnumbers IS NOT NULL
),

self_service_activity AS (
  SELECT
    Account_number,
    Created_date,
    KPI_name,
    Success_status
  FROM `soe-prod-data-core-7529.soe_junifer_model.digital_journey_performance`
  WHERE Created_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
)

SELECT
  d.deflection_type,
  COUNT(DISTINCT d.account_number) AS deflected_accounts,
  COUNT(DISTINCT CASE WHEN ss.Account_number IS NOT NULL THEN d.account_number END) AS completed_online,
  ROUND(COUNT(DISTINCT CASE WHEN ss.Account_number IS NOT NULL THEN d.account_number END) * 100.0 /
        NULLIF(COUNT(DISTINCT d.account_number), 0), 1) AS completion_rate_pct
FROM deflected_accounts d
LEFT JOIN self_service_activity ss
  ON d.account_number = ss.Account_number
  AND ss.Created_date >= d.deflection_date
  AND ss.Success_status = 'Success'
GROUP BY d.deflection_type
ORDER BY deflected_accounts DESC
```

### Did abandoned customers eventually self-serve?

```sql
-- For customers who abandoned (not deflected), did they self-serve later?
WITH abandoned_accounts AS (
  SELECT DISTINCT
    attributes_accountnumbers AS account_number,
    DATE(initiationtimestamp) AS contact_date,
    COALESCE(attributes_intent, attributes_initialintent) AS intent
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND channel = 'VOICE'
    AND initiationmethod = 'INBOUND'
    AND agent_connectedtoagentts IS NULL  -- Didn't reach agent
    AND (attributes_selfservice IS NULL OR attributes_selfservice IN ('rejected', 'error'))  -- Not deflected
    AND attributes_accountnumbers IS NOT NULL
),

self_service AS (
  SELECT DISTINCT Account_number, Created_date
  FROM `soe-prod-data-core-7529.soe_junifer_model.digital_journey_performance`
  WHERE Created_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
    AND Success_status = 'Success'
)

SELECT
  a.intent,
  COUNT(DISTINCT a.account_number) AS abandoned_accounts,
  COUNT(DISTINCT CASE WHEN ss.Account_number IS NOT NULL THEN a.account_number END) AS later_self_served,
  ROUND(COUNT(DISTINCT CASE WHEN ss.Account_number IS NOT NULL THEN a.account_number END) * 100.0 /
        NULLIF(COUNT(DISTINCT a.account_number), 0), 1) AS self_serve_rate_pct
FROM abandoned_accounts a
LEFT JOIN self_service ss
  ON a.account_number = ss.Account_number
  AND ss.Created_date >= a.contact_date
GROUP BY a.intent
HAVING COUNT(DISTINCT a.account_number) >= 10
ORDER BY abandoned_accounts DESC
```

---

## Failed Self-Service Attempts

### Self-service rejections and errors

```sql
-- Why did self-service attempts fail?
SELECT
  attributes_selfservice AS failure_type,
  COALESCE(attributes_intent, attributes_initialintent) AS intent,
  COUNT(*) AS contacts,
  COUNT(DISTINCT attributes_accountnumbers) AS unique_accounts
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND channel = 'VOICE'
  AND initiationmethod = 'INBOUND'
  AND attributes_selfservice IN ('rejected', 'error')
GROUP BY failure_type, intent
ORDER BY contacts DESC
```

### Queue abandonment analysis

```sql
-- Customers who reached queue but abandoned (waited too long)
SELECT
  queue_name,
  COALESCE(attributes_intent, attributes_initialintent) AS intent,
  COUNT(*) AS abandoned,
  ROUND(AVG(queue_duration), 0) AS avg_queue_wait_sec,
  MAX(queue_duration) AS max_queue_wait_sec
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
  AND channel = 'VOICE'
  AND initiationmethod = 'INBOUND'
  AND agent_connectedtoagentts IS NULL
  AND queue_name IS NOT NULL
GROUP BY queue_name, intent
ORDER BY abandoned DESC
```

---

## Self-Service Journeys Reference

The `digital_journey_performance` table tracks these KPIs:

| KPI_name | Description |
|----------|-------------|
| Direct Debit Setup | New DD setups |
| Direct Debit Amount Changes | DD amount modifications |
| Direct Debit Date Changes | DD date modifications |
| Submit a read | Meter reading submissions |
| Smart meter bookings | SMETS2 installation bookings |
| Make a Card Payment | One-off card payments |
| Renewals | Tariff renewal completions |
| Acquisition | New customer sign-ups |
| COT Move Out | Change of tenancy (moving out) |
| COT Move In | Change of tenancy (moving in) |

---

## Linking Fields

| From | To | Join Field |
|------|----|----|
| `ctr_events` (curated) | `digital_journey_performance` (core) | `attributes_accountnumbers` = `Account_number` |
| `ctr_events` (curated) | `case_events` (curated) | `attributes_caseid` = `detail_case_id` |
| `ctr_events` (curated) | `junifer_enriched.account` (core) | `attributes_accountnumbers` = `number` |

---

## Key Takeaways

### Voice Deflection Reality Check

| Metric | Typical Value | Notes |
|--------|---------------|-------|
| True deflection rate | ~3% | Customers directed to online self-service |
| Agent handled rate | ~43% | Successfully reached an agent |
| Abandonment rate | ~50% | Hung up at various stages |
| Self-service rejection | ~4% | Tried self-service but validation failed |

**The old metric of "no agent = deflection" was wrong.** It was actually measuring abandonment (~50%) not true deflection (~3%).

### Email Deflection Reality Check

| Metric | Typical Value | Notes |
|--------|---------------|-------|
| Agent handled rate | ~50% | Agent connected and worked the email |
| **Auto-response (TRUE deflection)** | **~4%** | System sent helpful auto-reply **with intent** (~44/day) |
| Spam/OOO filtered | ~20% | Dropped Emails queue (junk filtered) |
| System notifications dropped | ~5% | Routing gap - Typeform, etc. (NOT customer emails, NOT deflection) |
| In queue (waiting) | ~12% | Agent Holding Queue with API disconnect |
| Transferred | ~5% | Routed to specialist queue |

**Email deflection = auto-response sent WITH detected intent.** Only emails where the system:
1. Detected a customer intent (PaymentIntent, DirectDebitIntent, etc.)
2. Sent an automated reply with relevant self-service info
3. Closed the contact (CONTACT_FLOW_DISCONNECT)

**⚠️ "No Intent" is NOT deflection - it splits into:**
1. **Dropped Emails** (~236/day) - Spam, OOO, bounces (correctly filtered junk)
2. **No Queue** (~66/day) - System notifications like Typeform → `fit@so.energy` (routing gap, not customer emails)

---

## Notes

- **Project paths**: Amazon Connect tables are in `soe-prod-data-curated`, digital journeys in `soe-prod-data-core-7529`
- **ctr_events** is not SCD2 - query directly by `initiationtimestamp`
- **Account matching**: `attributes_accountnumbers` may contain multiple accounts (comma-separated) - consider parsing if needed
- **Time correlation**: When joining to self-service, ensure self-service date >= contact date
- **Data quality**: Always apply filters to exclude spam, outbound replies, and failed telecom connections

### Deflection Definitions by Channel

| Channel | Deflection Indicator | What it means |
|---------|---------------------|---------------|
| **VOICE** | `attributes_selfservice` has success value | Customer directed to online self-service |
| **EMAIL** | `CONTACT_FLOW_DISCONNECT` + has intent + not Dropped Emails | Auto-response sent with helpful info |
| **CHAT** | `agent_connectedtoagentts IS NULL` | Bot handled (no agent needed) |

---

## Cross-Channel Deflection Logic (Verified from Code)

**Source:** `customer-support-center` repo - `lambda/detectDeflection`, `lambda/contactDeflectionHandling`, contact flows

### Deflectable Intents by Channel

| Intent | VOICE | CHAT | EMAIL |
|--------|:-----:|:----:|:-----:|
| `RenewalIntent` | ✅ | ✅ | ✅ |
| `MovingInIntent` | ✅ | ✅ | ✅ |
| `MovingOutIntent` | ✅ | ✅ | ❌ |
| `SubmitMeterReadingIntent` | ✅ | ✅ | ❌ |
| `MakeACardPaymentIntent` | ✅ | ✅ | ✅ |
| `DirectDebitIntent` | ✅ | ✅ | ✅ |
| `FinalBillIntent` | ❌ | ❌ | ✅ |
| `PaymentIntent` | ❌ | ❌ | ✅ |

### How Deflection Works by Channel

| Aspect | VOICE | CHAT | EMAIL |
|--------|-------|------|-------|
| **Customer choice?** | YES (Press 1=SMS, 2=Agent) | YES (Bot shows link) | NO (automatic) |
| **Customer verification checked?** | NO for deflection offer | NO for deflection offer | NO |
| **What triggers deflection?** | Intent recognition | Intent recognition | Intent recognition |
| **How customer is deflected** | SMS with self-service link | Chatbot message with link | Auto-response email sent |
| **`selfService` attribute set?** | YES (e.g., `renewalOnline`) | YES (same values) | NO (not applicable) |

### Voice/Chat Deflection Process

1. Customer contacts via voice/chat
2. IDNV module runs (attempts to identify customer)
3. `detectDeflection` lambda checks if intent is deflectable
4. If deflectable:
   - **VOICE:** Plays deflection prompt, customer presses 1 for SMS link or 2 for agent
   - **CHAT:** Bot displays chatbot message with self-service link
5. If customer chooses self-service → `selfService` attribute set (e.g., `renewalOnline`)
6. If customer chooses agent → routed to queue

**Code reference:** `lambda/detectDeflection/src/messageCatalog.ts` - defines the 6 voice/chat deflectable intents and their SMS/chat messages.

### Email Deflection Process

1. Email arrives at contact center
2. Intent detected by `detectEmailIntent` lambda
3. `contactDeflectionHandling` lambda checks:
   - Is intent in deflectable list? (6 specific intents)
   - Is frustration level HIGH? (Bedrock AI analysis)
   - Has auto-reply threshold been reached? (max 1 per case)
   - Is agent already assigned to case?
4. If all checks pass → Auto-response email sent, contact marked as deflected
5. If any check fails → Route to agent queue

**Code reference:** `lambda/contactDeflectionHandling/src/index.ts`, `lambda/lambdaUtils/src/nodejs/lambda-utils/intent.ts`

### Key Differences Between Channels

| Channel | Customer Has Choice | Safeguards | Auto-Close Case |
|---------|:------------------:|------------|:---------------:|
| **VOICE** | ✅ Press 1 or 2 | None (customer decides) | ❌ |
| **CHAT** | ✅ Click link or continue | None (customer decides) | ❌ |
| **EMAIL** | ❌ Automatic | Frustration AI, threshold, agent assigned | ✅ (one-shot intents) |

### Voice/Chat `selfService` Attribute Values

When customer chooses self-service, these values are set:

| Intent | `selfService` Value |
|--------|---------------------|
| `RenewalIntent` | `renewalOnline` |
| `MovingInIntent` | `moveInOnline` |
| `MovingOutIntent` | `moveOutOnline` |
| `SubmitMeterReadingIntent` | `submitMeterReadingOnline` |
| `MakeACardPaymentIntent` | `makeACardPaymentOnline` |
| `DirectDebitIntent` | `directDebitOnline` |

### Querying Deflection by Channel

**Voice deflection:**
```sql
SELECT *
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE channel = 'VOICE'
  AND initiationmethod = 'INBOUND'
  AND attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
       'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline')
```

**Chat deflection:**
```sql
SELECT *
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE channel = 'CHAT'
  AND initiationmethod = 'INBOUND'
  AND agent_connectedtoagentts IS NULL
  AND attributes_intent IS NOT NULL
```

**Email deflection:**
```sql
SELECT *
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE channel = 'EMAIL'
  AND initiationmethod = 'INBOUND'
  AND disconnectreason = 'CONTACT_FLOW_DISCONNECT'
  AND attributes_intent IN ('MovingInIntent', 'RenewalIntent', 'MakeACardPaymentIntent',
       'DirectDebitIntent', 'FinalBillIntent', 'PaymentIntent')
  AND queue_name IS NULL
```

### Common Mistakes

- **Voice**: `agent_connectedtoagentts IS NULL` ≠ deflection (it's mostly abandonment ~50%)
- **Email**: `Dropped Emails` queue ≠ deflection (it's spam/OOO filtering)
- **Email**: `API` disconnect ≠ auto-response (it's system-managed queue state)
- **Email**: No Queue + No Intent ≠ deflection (it's system notifications like Typeform - routing gap)

### Known Routing Gaps

| Source | Recipient | Issue |
|--------|-----------|-------|
| `notifications@followups.typeform.io` | `fit@so.energy` | Typeform survey notifications being dropped (~66/day) |

These should be excluded from contact center metrics or routed to a different system.

---

## Daily Contact Stats Queries (All Channels)

Ready-to-use queries for daily contact funnel analysis.

### Voice - Daily Contact Funnel

```sql
-- VOICE: Full contact funnel breakdown
WITH voice_contacts AS (
  SELECT
    contactid,
    attributes_intent,
    attributes_selfservice,
    queue_name,
    agent_connectedtoagentts,
    disconnectreason
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'VOICE'
    AND initiationmethod = 'INBOUND'
    AND DATE(initiationtimestamp) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
),

categorized AS (
  SELECT
    contactid,
    CASE
      WHEN agent_connectedtoagentts IS NOT NULL THEN 'Agent Handled'
      WHEN attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
           'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline') THEN 'Deflection Taken'
      WHEN attributes_selfservice = 'rejected' THEN 'Deflection Rejected'
      WHEN queue_name IS NOT NULL AND agent_connectedtoagentts IS NULL THEN 'Dropped in Queue'
      WHEN attributes_intent IS NULL THEN 'Dropped Pre-Intent/IDNV'
      ELSE 'Other/In-Flow Drop'
    END AS category
  FROM voice_contacts
)

SELECT
  category,
  COUNT(*) AS contacts,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM categorized
GROUP BY category
ORDER BY
  CASE category
    WHEN 'Agent Handled' THEN 1
    WHEN 'Deflection Taken' THEN 2
    WHEN 'Deflection Rejected' THEN 3
    WHEN 'Dropped in Queue' THEN 4
    WHEN 'Dropped Pre-Intent/IDNV' THEN 5
    WHEN 'Other/In-Flow Drop' THEN 6
  END
```

### Voice - Deflection by Intent (with Take-up Rate)

```sql
-- VOICE: Deflection offered vs taken by intent
SELECT
  attributes_intent AS intent,
  COUNT(*) AS offered,
  SUM(CASE WHEN attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
       'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline') THEN 1 ELSE 0 END) AS taken,
  SUM(CASE WHEN attributes_selfservice = 'rejected' THEN 1 ELSE 0 END) AS rejected,
  SUM(CASE WHEN agent_connectedtoagentts IS NOT NULL THEN 1 ELSE 0 END) AS spoke_to_agent,
  ROUND(SUM(CASE WHEN attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
       'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline') THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 0) AS take_up_rate_pct
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE channel = 'VOICE'
  AND initiationmethod = 'INBOUND'
  AND DATE(initiationtimestamp) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  AND attributes_intent IN ('RenewalIntent', 'MovingInIntent', 'MovingOutIntent',
      'SubmitMeterReadingIntent', 'MakeACardPaymentIntent', 'DirectDebitIntent')
GROUP BY attributes_intent
ORDER BY offered DESC
```

### Email - Daily Contact Funnel

```sql
-- EMAIL: Full contact funnel breakdown
WITH email_contacts AS (
  SELECT
    contactid,
    attributes_intent,
    queue_name,
    agent_connectedtoagentts,
    disconnectreason
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'EMAIL'
    AND initiationmethod = 'INBOUND'
    AND DATE(initiationtimestamp) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
),

categorized AS (
  SELECT
    contactid,
    CASE
      WHEN agent_connectedtoagentts IS NOT NULL THEN 'Agent Handled'
      WHEN disconnectreason = 'CONTACT_FLOW_DISCONNECT'
           AND attributes_intent IN ('MovingInIntent', 'RenewalIntent', 'MakeACardPaymentIntent',
               'DirectDebitIntent', 'FinalBillIntent', 'PaymentIntent')
           AND queue_name IS NULL THEN 'Deflection (Auto-Response)'
      WHEN queue_name = 'Dropped Emails' THEN 'Spam/OOO Filtered'
      WHEN queue_name IS NOT NULL AND agent_connectedtoagentts IS NULL THEN 'In Queue / Waiting'
      WHEN queue_name IS NULL AND attributes_intent IS NULL
           AND disconnectreason = 'CONTACT_FLOW_DISCONNECT' THEN 'System Notifications Dropped'
      ELSE 'Other'
    END AS category
  FROM email_contacts
)

SELECT
  category,
  COUNT(*) AS contacts,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM categorized
GROUP BY category
ORDER BY
  CASE category
    WHEN 'Agent Handled' THEN 1
    WHEN 'Deflection (Auto-Response)' THEN 2
    WHEN 'In Queue / Waiting' THEN 3
    WHEN 'Spam/OOO Filtered' THEN 4
    WHEN 'System Notifications Dropped' THEN 5
    WHEN 'Other' THEN 6
  END
```

### Email - Deflection by Intent (with Safeguard Analysis)

```sql
-- EMAIL: Deflection decision breakdown by intent
-- Shows which intents were deflected vs blocked by safeguards
WITH deflectable_emails AS (
  SELECT
    contactid,
    attributes_intent,
    attributes_caseid,
    disconnectreason,
    queue_name,
    CASE
      WHEN disconnectreason = 'CONTACT_FLOW_DISCONNECT' AND queue_name IS NULL THEN 'DEFLECTED'
      ELSE 'NOT_DEFLECTED'
    END AS outcome
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'EMAIL'
    AND initiationmethod = 'INBOUND'
    AND DATE(initiationtimestamp) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND attributes_intent IN ('MovingInIntent', 'RenewalIntent', 'MakeACardPaymentIntent',
        'DirectDebitIntent', 'FinalBillIntent', 'PaymentIntent')
),

-- Count inbound emails per case to detect threshold
case_inbound_counts AS (
  SELECT
    attributes_caseid,
    COUNT(*) as inbound_emails_on_case
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'EMAIL'
    AND initiationmethod = 'INBOUND'
    AND attributes_caseid IS NOT NULL
    AND initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY attributes_caseid
)

SELECT
  e.attributes_intent AS intent,
  COUNT(*) AS total,
  SUM(CASE WHEN e.outcome = 'DEFLECTED' THEN 1 ELSE 0 END) AS deflected,
  SUM(CASE WHEN e.outcome = 'NOT_DEFLECTED' AND c.inbound_emails_on_case >= 3 THEN 1 ELSE 0 END) AS blocked_by_threshold,
  SUM(CASE WHEN e.outcome = 'NOT_DEFLECTED' AND c.inbound_emails_on_case < 3 THEN 1 ELSE 0 END) AS blocked_by_other_safeguard,
  ROUND(SUM(CASE WHEN e.outcome = 'DEFLECTED' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 0) AS deflection_rate_pct
FROM deflectable_emails e
LEFT JOIN case_inbound_counts c ON e.attributes_caseid = c.attributes_caseid
GROUP BY e.attributes_intent
ORDER BY total DESC
```

### Chat - Daily Contact Funnel

```sql
-- CHAT: Full contact funnel breakdown
-- Note: Chat uses initiationmethod = 'API', not 'INBOUND'
WITH chat_contacts AS (
  SELECT
    contactid,
    attributes_intent,
    attributes_selfservice,
    queue_name,
    agent_connectedtoagentts,
    disconnectreason
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'CHAT'
    AND initiationmethod = 'API'
    AND DATE(initiationtimestamp) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
),

categorized AS (
  SELECT
    contactid,
    CASE
      WHEN agent_connectedtoagentts IS NOT NULL THEN 'Agent Handled'
      WHEN attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
           'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline') THEN 'Deflection Taken'
      WHEN attributes_intent IS NOT NULL AND queue_name IS NULL
           AND disconnectreason = 'CONTACT_FLOW_DISCONNECT' THEN 'Bot Resolved (KB Answer)'
      WHEN disconnectreason = 'CUSTOMER_CONNECTION_NOT_ESTABLISHED' THEN 'Connection Failed'
      WHEN queue_name IS NOT NULL AND agent_connectedtoagentts IS NULL THEN 'Dropped in Queue'
      WHEN attributes_intent IS NOT NULL AND disconnectreason = 'CUSTOMER_DISCONNECT'
           AND queue_name IS NULL THEN 'Left During Bot Chat'
      WHEN attributes_intent IS NULL AND disconnectreason = 'CUSTOMER_DISCONNECT' THEN 'Left Pre-Intent'
      WHEN attributes_intent IS NULL AND disconnectreason = 'CONTACT_FLOW_DISCONNECT' THEN 'Bot Ended (Timeout/No Input)'
      ELSE 'Other'
    END AS category
  FROM chat_contacts
)

SELECT
  category,
  COUNT(*) AS contacts,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM categorized
GROUP BY category
ORDER BY contacts DESC
```

### Chat - Deflection by Intent

```sql
-- CHAT: Deflection breakdown by intent
-- Includes both explicit deflection (self-service link) and bot resolved (KB answer)
SELECT
  attributes_intent AS intent,
  COUNT(*) AS total_with_intent,
  SUM(CASE WHEN attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
       'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline') THEN 1 ELSE 0 END) AS deflection_taken,
  SUM(CASE WHEN queue_name IS NULL AND agent_connectedtoagentts IS NULL
       AND disconnectreason = 'CONTACT_FLOW_DISCONNECT' THEN 1 ELSE 0 END) AS bot_resolved,
  SUM(CASE WHEN agent_connectedtoagentts IS NOT NULL THEN 1 ELSE 0 END) AS spoke_to_agent
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE channel = 'CHAT'
  AND initiationmethod = 'API'
  AND DATE(initiationtimestamp) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  AND attributes_intent IN ('RenewalIntent', 'MovingInIntent', 'MovingOutIntent',
      'SubmitMeterReadingIntent', 'MakeACardPaymentIntent', 'DirectDebitIntent')
GROUP BY attributes_intent
ORDER BY total_with_intent DESC
```

### Cross-Channel Daily Summary

```sql
-- ALL CHANNELS: Daily summary comparison
SELECT
  channel,
  COUNT(*) AS total_contacts,

  -- Agent handled
  SUM(CASE WHEN agent_connectedtoagentts IS NOT NULL THEN 1 ELSE 0 END) AS agent_handled,
  ROUND(SUM(CASE WHEN agent_connectedtoagentts IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS agent_handled_pct,

  -- Deflection (channel-specific logic)
  SUM(CASE
    WHEN channel = 'VOICE' AND attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
         'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline') THEN 1
    WHEN channel = 'EMAIL' AND disconnectreason = 'CONTACT_FLOW_DISCONNECT'
         AND attributes_intent IN ('MovingInIntent', 'RenewalIntent', 'MakeACardPaymentIntent',
             'DirectDebitIntent', 'FinalBillIntent', 'PaymentIntent')
         AND queue_name IS NULL THEN 1
    WHEN channel = 'CHAT' AND agent_connectedtoagentts IS NULL AND queue_name IS NULL
         AND disconnectreason = 'CONTACT_FLOW_DISCONNECT' AND attributes_intent IS NOT NULL THEN 1
    ELSE 0
  END) AS deflected,

  -- Dropped in queue
  SUM(CASE WHEN queue_name IS NOT NULL AND agent_connectedtoagentts IS NULL
       AND channel != 'EMAIL' THEN 1 ELSE 0 END) AS dropped_in_queue

FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE DATE(initiationtimestamp) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  AND ((channel = 'VOICE' AND initiationmethod = 'INBOUND')
       OR (channel = 'EMAIL' AND initiationmethod = 'INBOUND')
       OR (channel = 'CHAT' AND initiationmethod = 'API'))
GROUP BY channel
ORDER BY total_contacts DESC
```

---

## Containment Analysis (Do Deflected Customers Call Back?)

Containment measures whether deflected customers successfully resolved their issue or contacted again within 3 days. Higher containment = more effective deflection.

**⚠️ Key Finding**: Deflected customers have ~81% callback rate vs ~28% for agent-handled contacts. This suggests deflection is not fully resolving customer issues.

### Voice - Containment by Outcome

```sql
-- VOICE: Compare containment rate for deflected vs agent-handled
-- Containment = customer did NOT contact again within 3 days
WITH voice_contacts AS (
  SELECT
    contactid,
    customerendpoint_address AS phone,  -- Use phone as identifier (deflected contacts lack account numbers)
    initiationtimestamp,
    CASE
      WHEN agent_connectedtoagentts IS NOT NULL THEN 'Agent Handled'
      WHEN attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
           'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline') THEN 'Deflected'
    END AS outcome
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'VOICE'
    AND initiationmethod = 'INBOUND'
    AND DATE(initiationtimestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 21 DAY)
                                      AND DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY)  -- Allow 3 days for callback
),

-- Get all contacts for callback detection
all_voice AS (
  SELECT customerendpoint_address AS phone, initiationtimestamp
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'VOICE'
    AND initiationmethod = 'INBOUND'
    AND initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
),

-- Check for callbacks within 3 days
callbacks AS (
  SELECT DISTINCT
    vc.contactid,
    vc.outcome,
    CASE WHEN EXISTS (
      SELECT 1 FROM all_voice av
      WHERE av.phone = vc.phone
        AND av.initiationtimestamp > vc.initiationtimestamp
        AND av.initiationtimestamp <= TIMESTAMP_ADD(vc.initiationtimestamp, INTERVAL 3 DAY)
    ) THEN 1 ELSE 0 END AS called_back
  FROM voice_contacts vc
  WHERE vc.outcome IS NOT NULL
)

SELECT
  outcome,
  COUNT(*) AS contacts,
  SUM(called_back) AS called_back_within_3_days,
  ROUND(SUM(called_back) * 100.0 / COUNT(*), 1) AS callback_rate_pct,
  ROUND((COUNT(*) - SUM(called_back)) * 100.0 / COUNT(*), 1) AS containment_rate_pct
FROM callbacks
GROUP BY outcome
ORDER BY outcome
```

### Voice - Containment by Deflection Intent

```sql
-- VOICE: Containment breakdown by deflected intent
WITH deflected_contacts AS (
  SELECT
    contactid,
    customerendpoint_address AS phone,
    initiationtimestamp,
    CASE attributes_selfservice
      WHEN 'renewalOnline' THEN 'Renewal'
      WHEN 'moveInOnline' THEN 'MovingIn'
      WHEN 'moveOutOnline' THEN 'MovingOut'
      WHEN 'submitMeterReadingOnline' THEN 'SubmitMeterReading'
      WHEN 'makeACardPaymentOnline' THEN 'MakeACardPayment'
      WHEN 'directDebitOnline' THEN 'DirectDebit'
    END AS deflection_type
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'VOICE'
    AND initiationmethod = 'INBOUND'
    AND attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
         'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline')
    AND DATE(initiationtimestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 21 DAY)
                                      AND DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY)
),

all_voice AS (
  SELECT customerendpoint_address AS phone, initiationtimestamp
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'VOICE'
    AND initiationmethod = 'INBOUND'
    AND initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
),

callbacks AS (
  SELECT
    dc.contactid,
    dc.deflection_type,
    CASE WHEN EXISTS (
      SELECT 1 FROM all_voice av
      WHERE av.phone = dc.phone
        AND av.initiationtimestamp > dc.initiationtimestamp
        AND av.initiationtimestamp <= TIMESTAMP_ADD(dc.initiationtimestamp, INTERVAL 3 DAY)
    ) THEN 1 ELSE 0 END AS called_back
  FROM deflected_contacts dc
)

SELECT
  deflection_type,
  COUNT(*) AS deflected,
  SUM(called_back) AS called_back,
  ROUND(SUM(called_back) * 100.0 / COUNT(*), 1) AS callback_rate_pct,
  ROUND((COUNT(*) - SUM(called_back)) * 100.0 / COUNT(*), 1) AS containment_rate_pct
FROM callbacks
GROUP BY deflection_type
ORDER BY deflected DESC
```

### Chat - Containment for Bot-Resolved Contacts

```sql
-- CHAT: Containment for bot-resolved contacts (KB answered the question)
WITH chat_bot_resolved AS (
  SELECT
    contactid,
    customerendpoint_address AS phone,
    initiationtimestamp
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'CHAT'
    AND initiationmethod = 'API'
    AND agent_connectedtoagentts IS NULL
    AND queue_name IS NULL
    AND disconnectreason = 'CONTACT_FLOW_DISCONNECT'
    AND attributes_intent IS NOT NULL
    AND DATE(initiationtimestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 21 DAY)
                                      AND DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY)
),

-- Check any channel callback (customer may switch channels)
all_contacts AS (
  SELECT customerendpoint_address AS phone, initiationtimestamp
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE initiationmethod IN ('INBOUND', 'API')
    AND initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
),

callbacks AS (
  SELECT
    cb.contactid,
    CASE WHEN EXISTS (
      SELECT 1 FROM all_contacts ac
      WHERE ac.phone = cb.phone
        AND ac.initiationtimestamp > cb.initiationtimestamp
        AND ac.initiationtimestamp <= TIMESTAMP_ADD(cb.initiationtimestamp, INTERVAL 3 DAY)
    ) THEN 1 ELSE 0 END AS called_back
  FROM chat_bot_resolved cb
)

SELECT
  'Chat Bot Resolved' AS outcome,
  COUNT(*) AS contacts,
  SUM(called_back) AS called_back_within_3_days,
  ROUND(SUM(called_back) * 100.0 / COUNT(*), 1) AS callback_rate_pct,
  ROUND((COUNT(*) - SUM(called_back)) * 100.0 / COUNT(*), 1) AS containment_rate_pct
FROM callbacks
```

### Notes on Containment Analysis

- **Why phone number?** Deflected contacts exit before full ID&V, so `attributes_accountnumbers` is often NULL. Phone number (`customerendpoint_address`) is the reliable identifier.
- **3-day window**: Standard industry metric. Adjust to 7 days for less strict measurement.
- **Cross-channel callbacks**: Chat containment query checks all channels since customers may switch.
- **Email note**: Email containment is misleading because conversational deflection types (MovingIn, DirectDebit, etc.) expect replies to the same case. These same-case replies shouldn't count as "callbacks."

---

## Deflection-to-Journey Correlation (Did They Complete Self-Service?)

Containment tells you if customers called back. This section goes deeper: **did deflected customers actually complete the self-service journey?**

### Linking Deflected Calls to Digital Journeys

The challenge is that deflected contacts don't have account numbers (they exit before ID&V). Solution: link phone → account through historical contacts where ID&V was completed.

```sql
-- Link deflected contact phones to accounts
WITH phone_to_account AS (
  SELECT
    customerendpoint_address AS phone,
    FIRST_VALUE(attributes_accountnumbers) OVER (
      PARTITION BY customerendpoint_address ORDER BY initiationtimestamp DESC
    ) AS acct_num
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE attributes_accountnumbers IS NOT NULL
    AND attributes_accountnumbers != ''
    AND initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 365 DAY)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY customerendpoint_address ORDER BY initiationtimestamp DESC) = 1
)
-- Join deflected contacts to this CTE to get their account numbers
```

### Renewal Deflection Full Funnel

Track whether customers deflected to "renewalOnline" actually renewed (and how):

```sql
-- Renewal deflection funnel: deflected → self-serve vs agent renewal
WITH deflected_renewals AS (
  SELECT
    contactid,
    customerendpoint_address AS phone,
    DATE(initiationtimestamp) AS deflection_date,
    initiationtimestamp AS deflection_ts
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'VOICE'
    AND initiationmethod = 'INBOUND'
    AND attributes_selfservice = 'renewalOnline'
    AND DATE(initiationtimestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 21 DAY)
                                      AND DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY)
),

phone_to_account AS (
  SELECT
    customerendpoint_address AS phone,
    FIRST_VALUE(attributes_accountnumbers) OVER (
      PARTITION BY customerendpoint_address ORDER BY initiationtimestamp DESC
    ) AS acct_num
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE attributes_accountnumbers IS NOT NULL AND attributes_accountnumbers != ''
    AND initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 365 DAY)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY customerendpoint_address ORDER BY initiationtimestamp DESC) = 1
),

deflected_with_account AS (
  SELECT dr.*, pa.acct_num
  FROM deflected_renewals dr
  JOIN phone_to_account pa ON dr.phone = pa.phone
),

renewal_journeys AS (
  SELECT Account_number, Created_date, Success_status, Channel
  FROM `soe-prod-data-core-7529.soe_junifer_model.digital_journey_performance`
  WHERE KPI_name = 'Renewals'
    AND Created_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
),

callback_check AS (
  SELECT customerendpoint_address AS phone, initiationtimestamp AS callback_ts
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'VOICE' AND initiationmethod = 'INBOUND'
    AND agent_connectedtoagentts IS NOT NULL
    AND initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
),

outcomes AS (
  SELECT
    dwa.contactid,
    MAX(CASE WHEN rj.Channel = 'Self Serve' AND rj.Success_status = 'Y'
             AND rj.Created_date BETWEEN dwa.deflection_date AND DATE_ADD(dwa.deflection_date, INTERVAL 7 DAY)
        THEN 1 ELSE 0 END) AS renewed_self_serve,
    MAX(CASE WHEN rj.Channel = 'Agent' AND rj.Success_status = 'Y'
             AND rj.Created_date BETWEEN dwa.deflection_date AND DATE_ADD(dwa.deflection_date, INTERVAL 7 DAY)
        THEN 1 ELSE 0 END) AS renewed_via_agent,
    MAX(CASE WHEN cb.callback_ts > dwa.deflection_ts
             AND cb.callback_ts <= TIMESTAMP_ADD(dwa.deflection_ts, INTERVAL 7 DAY)
        THEN 1 ELSE 0 END) AS called_back
  FROM deflected_with_account dwa
  LEFT JOIN renewal_journeys rj ON dwa.acct_num = rj.Account_number
  LEFT JOIN callback_check cb ON dwa.phone = cb.phone
  GROUP BY dwa.contactid
)

SELECT
  COUNT(*) AS trackable_deflected,
  SUM(called_back) AS called_back,
  ROUND(SUM(called_back) * 100.0 / COUNT(*), 1) AS callback_rate_pct,
  SUM(renewed_self_serve) AS renewed_self_serve,
  ROUND(SUM(renewed_self_serve) * 100.0 / COUNT(*), 1) AS self_serve_rate_pct,
  SUM(renewed_via_agent) AS renewed_via_agent,
  ROUND(SUM(renewed_via_agent) * 100.0 / COUNT(*), 1) AS agent_rate_pct,
  SUM(CASE WHEN renewed_self_serve = 1 OR renewed_via_agent = 1 THEN 1 ELSE 0 END) AS total_renewed,
  ROUND(SUM(CASE WHEN renewed_self_serve = 1 OR renewed_via_agent = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS total_renewal_rate_pct
FROM outcomes
```

### Key Findings from Renewal Analysis

| Metric | Typical Value | Interpretation |
|--------|---------------|----------------|
| Self-serve rate | ~14% | Only 14% complete the intended online journey |
| Agent renewal rate | ~26% | 26% call back and renew through agent |
| Total renewal rate | ~40% | Overall renewal success is good |
| Journey success rate | ~100% | Those who attempt online renewal succeed |

**Insight**: The self-serve journey works well (100% success rate for those who try). The issue is adoption - most customers (86%) don't attempt the online journey at all, preferring to call back for agent help.

---

## Page Visits as Deflection Success Metric

**Completion isn't the only success metric** - if a customer visits the self-service page, deflection has worked. Whether they complete is their choice (maybe the tariff wasn't right).

### GA4 Renewal Funnel Events

GA4 tracks detailed renewal journey events:

| Event | Description | Typical Volume |
|-------|-------------|----------------|
| `Renewal - Summary` | Viewed renewal summary page | ~72K/month |
| `Renewal - Tariff Selection` | Reached tariff selection | ~13K/month |
| `Renewal - Successful` | Completed renewal | ~3.6K/month |
| `Renewal - Unsuccessful` | Abandoned/failed | ~3.2K/month |
| `Renewal - Ineligible` | Contract not up for renewal | ~800/month |

**Note:** GA4 `user_id` = Junifer account number (8 digits).

### Cross-Channel Page Visit Analysis

```sql
-- Deflection success = visited the self-service page (not just completed)
WITH voice_deflected AS (
  SELECT
    contactid,
    customerendpoint_address AS phone,
    DATE(initiationtimestamp) AS deflection_date
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'VOICE' AND initiationmethod = 'INBOUND'
    AND attributes_selfservice = 'renewalOnline'
    AND DATE(initiationtimestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 21 DAY)
                                      AND DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY)
),

phone_to_account AS (
  SELECT customerendpoint_address AS phone,
    FIRST_VALUE(attributes_accountnumbers) OVER (
      PARTITION BY customerendpoint_address ORDER BY initiationtimestamp DESC
    ) AS acct_num
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE attributes_accountnumbers IS NOT NULL AND attributes_accountnumbers != ''
    AND initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 365 DAY)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY customerendpoint_address ORDER BY initiationtimestamp DESC) = 1
),

voice_with_account AS (
  SELECT v.*, p.acct_num FROM voice_deflected v JOIN phone_to_account p ON v.phone = p.phone
),

email_deflected AS (
  SELECT
    contactid,
    attributes_accountnumbers AS acct_num,
    DATE(initiationtimestamp) AS deflection_date
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'EMAIL' AND initiationmethod = 'INBOUND'
    AND attributes_intent = 'RenewalIntent'
    AND disconnectreason = 'CONTACT_FLOW_DISCONNECT'
    AND queue_name IS NULL
    AND DATE(initiationtimestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 21 DAY)
                                      AND DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY)
    AND attributes_accountnumbers IS NOT NULL AND attributes_accountnumbers != ''
),

-- GA4 renewal page visits (any renewal event = visited)
renewal_visits AS (
  SELECT user_id AS account_number, PARSE_DATE('%Y%m%d', event_date) AS visit_date
  FROM `soe-prod-data-core-7529.analytics_382914461.events_*`
  WHERE _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND event_name LIKE 'Renewal%'
    AND user_id IS NOT NULL
),

-- Completions from journey data (more reliable than GA4 Successful event)
renewal_completions AS (
  SELECT Account_number, Created_date
  FROM `soe-prod-data-core-7529.soe_junifer_model.digital_journey_performance`
  WHERE KPI_name = 'Renewals' AND Channel = 'Self Serve' AND Success_status = 'Y'
    AND Created_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
)

SELECT
  'VOICE' AS channel,
  COUNT(DISTINCT v.contactid) AS trackable,
  COUNT(DISTINCT CASE WHEN rv.visit_date BETWEEN v.deflection_date AND DATE_ADD(v.deflection_date, INTERVAL 7 DAY) THEN v.contactid END) AS visited_page,
  ROUND(COUNT(DISTINCT CASE WHEN rv.visit_date BETWEEN v.deflection_date AND DATE_ADD(v.deflection_date, INTERVAL 7 DAY) THEN v.contactid END) * 100.0 / COUNT(DISTINCT v.contactid), 1) AS visited_pct,
  COUNT(DISTINCT CASE WHEN rv.visit_date = v.deflection_date THEN v.contactid END) AS visited_same_day,
  COUNT(DISTINCT CASE WHEN rc.Created_date BETWEEN v.deflection_date AND DATE_ADD(v.deflection_date, INTERVAL 7 DAY) THEN v.contactid END) AS completed
FROM voice_with_account v
LEFT JOIN renewal_visits rv ON v.acct_num = rv.account_number
LEFT JOIN renewal_completions rc ON v.acct_num = rc.Account_number

UNION ALL

SELECT
  'EMAIL' AS channel,
  COUNT(DISTINCT e.contactid) AS trackable,
  COUNT(DISTINCT CASE WHEN rv.visit_date BETWEEN e.deflection_date AND DATE_ADD(e.deflection_date, INTERVAL 7 DAY) THEN e.contactid END) AS visited_page,
  ROUND(COUNT(DISTINCT CASE WHEN rv.visit_date BETWEEN e.deflection_date AND DATE_ADD(e.deflection_date, INTERVAL 7 DAY) THEN e.contactid END) * 100.0 / COUNT(DISTINCT e.contactid), 1) AS visited_pct,
  COUNT(DISTINCT CASE WHEN rv.visit_date = e.deflection_date THEN e.contactid END) AS visited_same_day,
  COUNT(DISTINCT CASE WHEN rc.Created_date BETWEEN e.deflection_date AND DATE_ADD(e.deflection_date, INTERVAL 7 DAY) THEN e.contactid END) AS completed
FROM email_deflected e
LEFT JOIN renewal_visits rv ON e.acct_num = rv.account_number
LEFT JOIN renewal_completions rc ON e.acct_num = rc.Account_number
```

### Typical Results (Renewal Deflection)

| Channel | Trackable | Visited Page | Same Day | Completed |
|---------|----------:|-------------:|---------:|----------:|
| VOICE | ~65 | **~40%** | ~38% | ~14% |
| EMAIL | ~72 | **~43%** | ~31% | ~25% |
| CHAT | ~55 | *Not trackable* | — | — |

**Key insights:**
- **~40% deflection success** when measured by page visits (not just completions)
- **Same-day visits are high** - customers act quickly on deflection
- **Voice visitors complete less** (35% of visitors) vs Email (58% of visitors)
- **Chat is anonymous** - deflected chat customers have no identifiers to track

### Why Customers Don't Visit (the other 60%)

The ~60% who don't visit the self-service page either:
1. **Called back for agent help** (~26% renewed via agent)
2. **Decided not to renew** (maybe not the right time)
3. **Had technical issues** (login problems, app not installed)
4. **Forgot or got distracted** (SMS link not saved)

### Adapt for Other Journey Types

| Journey | GA4 Events to Look For |
|---------|------------------------|
| Meter Reading | `Submit Read%`, `Meter Reading%` |
| Card Payment | `Payment%`, `Card Payment%` |
| Direct Debit | `Direct Debit%`, `DD Setup%` |

---

### Adapt for Other Deflection Types

Replace the deflection type and KPI name to analyze other journeys:

| Deflection | `attributes_selfservice` | `KPI_name` in digital_journey_performance |
|------------|-------------------------|-------------------------------------------|
| Renewal | `'renewalOnline'` | `'Renewals'` |
| Meter Reading | `'submitMeterReadingOnline'` | `'Submit a read'` |
| Card Payment | `'makeACardPaymentOnline'` | `'Make a Card Payment'` |
| Direct Debit | `'directDebitOnline'` | `'Direct Debit Setup'` |
