# Weekly Deflection Funnel Report

A comprehensive weekly report tracking contact deflection effectiveness across all channels.

---

## Report Overview

This report tracks the complete customer journey from initial contact through deflection outcome:

```
CONTACT IN → INTENT DETECTED → ELIGIBLE FOR DEFLECTION → OFFERED → TAKEN/REJECTED
                                                                        ↓
                                              PAGE VISITED → ACTION COMPLETED
                                                                        ↓
                                              CALLBACK? → CALLBACK OUTCOME
```

---

## Quick Summary Query (Weekly)

Run this for a high-level cross-channel summary:

```sql
-- WEEKLY DEFLECTION SUMMARY - Cross-Channel
-- Update dates for your reporting week
WITH
voice_summary AS (
  SELECT
    'VOICE' AS channel,
    COUNT(*) AS total_contacts,
    SUM(CASE WHEN attributes_intent IS NOT NULL THEN 1 ELSE 0 END) AS intent_detected,
    SUM(CASE WHEN attributes_intent IN ('RenewalIntent', 'MovingInIntent', 'MovingOutIntent',
         'SubmitMeterReadingIntent', 'MakeACardPaymentIntent', 'DirectDebitIntent') THEN 1 ELSE 0 END) AS deflection_eligible,
    SUM(CASE WHEN attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
         'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline') THEN 1 ELSE 0 END) AS deflection_taken,
    SUM(CASE WHEN attributes_selfservice = 'rejected' THEN 1 ELSE 0 END) AS deflection_rejected,
    SUM(CASE WHEN agent_connectedtoagentts IS NOT NULL THEN 1 ELSE 0 END) AS spoke_to_agent
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'VOICE' AND initiationmethod = 'INBOUND'
    AND DATE(initiationtimestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) AND DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
),

email_summary AS (
  SELECT
    'EMAIL' AS channel,
    COUNT(*) AS total_contacts,
    SUM(CASE WHEN attributes_intent IS NOT NULL THEN 1 ELSE 0 END) AS intent_detected,
    SUM(CASE WHEN attributes_intent IN ('MovingInIntent', 'RenewalIntent', 'MakeACardPaymentIntent',
         'DirectDebitIntent', 'FinalBillIntent', 'PaymentIntent') THEN 1 ELSE 0 END) AS deflection_eligible,
    SUM(CASE WHEN attributes_intent IN ('MovingInIntent', 'RenewalIntent', 'MakeACardPaymentIntent',
         'DirectDebitIntent', 'FinalBillIntent', 'PaymentIntent')
         AND disconnectreason = 'CONTACT_FLOW_DISCONNECT' AND queue_name IS NULL THEN 1 ELSE 0 END) AS deflection_taken,
    0 AS deflection_rejected,
    SUM(CASE WHEN agent_connectedtoagentts IS NOT NULL THEN 1 ELSE 0 END) AS spoke_to_agent
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'EMAIL' AND initiationmethod = 'INBOUND'
    AND DATE(initiationtimestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) AND DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
),

chat_summary AS (
  SELECT
    'CHAT' AS channel,
    COUNT(*) AS total_contacts,
    SUM(CASE WHEN attributes_intent IS NOT NULL THEN 1 ELSE 0 END) AS intent_detected,
    SUM(CASE WHEN attributes_intent IN ('RenewalIntent', 'MovingInIntent', 'MovingOutIntent',
         'SubmitMeterReadingIntent', 'MakeACardPaymentIntent', 'DirectDebitIntent') THEN 1 ELSE 0 END) AS deflection_eligible,
    SUM(CASE WHEN attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
         'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline') THEN 1 ELSE 0 END) AS deflection_taken,
    0 AS deflection_rejected,
    SUM(CASE WHEN agent_connectedtoagentts IS NOT NULL THEN 1 ELSE 0 END) AS spoke_to_agent
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'CHAT' AND initiationmethod = 'API'
    AND DATE(initiationtimestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) AND DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
)

SELECT
  channel,
  total_contacts,
  intent_detected,
  ROUND(intent_detected * 100.0 / total_contacts, 1) AS intent_rate_pct,
  deflection_eligible,
  deflection_taken,
  ROUND(deflection_taken * 100.0 / NULLIF(deflection_eligible, 0), 1) AS take_rate_pct,
  deflection_rejected,
  spoke_to_agent
FROM (
  SELECT * FROM voice_summary UNION ALL
  SELECT * FROM email_summary UNION ALL
  SELECT * FROM chat_summary
)
ORDER BY total_contacts DESC
```

### Typical Results

| Channel | Total | Intent | Eligible | Taken | Take Rate | Rejected | Agent |
|---------|------:|-------:|---------:|------:|----------:|---------:|------:|
| CHAT | 12,602 | 8,130 | 2,011 | 132 | **6.6%** | 0 | 910 |
| VOICE | 8,271 | 6,414 | 1,524 | 392 | **25.7%** | 244 | 4,546 |
| EMAIL | 7,367 | 5,729 | 633 | 271 | **42.8%** | 0 | 3,739 |

---

## Detailed Breakdown by Intent

```sql
-- WEEKLY: Deflection by Intent and Channel
SELECT
  channel,
  attributes_intent AS intent,
  COUNT(*) AS total_with_intent,
  SUM(CASE
    WHEN channel = 'VOICE' AND attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
         'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline') THEN 1
    WHEN channel = 'EMAIL' AND disconnectreason = 'CONTACT_FLOW_DISCONNECT' AND queue_name IS NULL THEN 1
    WHEN channel = 'CHAT' AND attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
         'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline') THEN 1
    ELSE 0
  END) AS deflection_taken,
  SUM(CASE WHEN channel = 'VOICE' AND attributes_selfservice = 'rejected' THEN 1 ELSE 0 END) AS deflection_rejected,
  SUM(CASE WHEN agent_connectedtoagentts IS NOT NULL THEN 1 ELSE 0 END) AS spoke_to_agent
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE ((channel = 'VOICE' AND initiationmethod = 'INBOUND')
       OR (channel = 'EMAIL' AND initiationmethod = 'INBOUND')
       OR (channel = 'CHAT' AND initiationmethod = 'API'))
  AND DATE(initiationtimestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) AND DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  AND attributes_intent IN ('RenewalIntent', 'MovingInIntent', 'MovingOutIntent',
       'SubmitMeterReadingIntent', 'MakeACardPaymentIntent', 'DirectDebitIntent',
       'FinalBillIntent', 'PaymentIntent')
GROUP BY channel, attributes_intent
ORDER BY channel, total_with_intent DESC
```

---

## Post-Deflection Tracking (Voice Only)

Voice is the only channel where we can reliably track post-deflection behavior (via phone → account linkage).

### Complete Funnel with Page Visits, Completions, and Callbacks

```sql
-- WEEKLY: Voice Deflection Complete Funnel
WITH voice_deflected AS (
  SELECT
    contactid,
    customerendpoint_address AS phone,
    DATE(initiationtimestamp) AS contact_date,
    initiationtimestamp,
    CASE attributes_selfservice
      WHEN 'renewalOnline' THEN 'Renewal'
      WHEN 'submitMeterReadingOnline' THEN 'MeterReading'
      WHEN 'makeACardPaymentOnline' THEN 'CardPayment'
      WHEN 'directDebitOnline' THEN 'DirectDebit'
      WHEN 'moveInOnline' THEN 'MovingIn'
      WHEN 'moveOutOnline' THEN 'MovingOut'
    END AS deflection_type
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'VOICE' AND initiationmethod = 'INBOUND'
    AND attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
         'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline')
    AND DATE(initiationtimestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
                                      AND DATE_SUB(CURRENT_DATE(), INTERVAL 8 DAY)  -- Last week with buffer for tracking
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

deflected_with_account AS (
  SELECT d.*, p.acct_num
  FROM voice_deflected d
  LEFT JOIN phone_to_account p ON d.phone = p.phone
),

-- GA4 page visits
page_visits AS (
  SELECT user_id AS account_number, PARSE_DATE('%Y%m%d', event_date) AS visit_date
  FROM `soe-prod-data-core-7529.analytics_382914461.events_*`
  WHERE _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 21 DAY))
    AND (event_name LIKE 'Renewal%' OR event_name LIKE 'Submit Read%'
         OR event_name LIKE 'Payment%' OR event_name LIKE 'Direct Debit%')
    AND user_id IS NOT NULL
),

-- Journey completions
self_serve_completions AS (
  SELECT Account_number, Created_date
  FROM `soe-prod-data-core-7529.soe_junifer_model.digital_journey_performance`
  WHERE Channel = 'Self Serve' AND Success_status = 'Y'
    AND Created_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 21 DAY)
),

agent_completions AS (
  SELECT Account_number, Created_date
  FROM `soe-prod-data-core-7529.soe_junifer_model.digital_journey_performance`
  WHERE Channel = 'Agent' AND Success_status = 'Y'
    AND Created_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 21 DAY)
),

-- Link accounts to email addresses (for cross-channel repeat detection)
account_to_email AS (
  SELECT DISTINCT attributes_accountnumbers AS acct_num, customerendpoint_address AS email_addr
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE channel = 'EMAIL' AND attributes_accountnumbers IS NOT NULL
    AND customerendpoint_address IS NOT NULL
    AND initiationtimestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 365 DAY)
),

deflected_with_email AS (
  SELECT d.*, ae.email_addr
  FROM deflected_with_account d
  LEFT JOIN account_to_email ae ON d.acct_num = ae.acct_num
),

-- Cross-channel repeat contacts (>30 mins to exclude system-generated)
repeat_contacts AS (
  SELECT
    d.contactid AS original_contactid,
    MAX(CASE WHEN c.contactid != d.contactid
             AND c.initiationtimestamp > TIMESTAMP_ADD(d.initiationtimestamp, INTERVAL 30 MINUTE)
             AND c.initiationtimestamp <= TIMESTAMP_ADD(d.initiationtimestamp, INTERVAL 3 DAY)
             AND (c.customerendpoint_address = d.phone OR c.customerendpoint_address = d.email_addr)
        THEN 1 ELSE 0 END) AS had_repeat_contact,
    MAX(CASE WHEN c.contactid != d.contactid
             AND c.initiationtimestamp > TIMESTAMP_ADD(d.initiationtimestamp, INTERVAL 30 MINUTE)
             AND c.initiationtimestamp <= TIMESTAMP_ADD(d.initiationtimestamp, INTERVAL 3 DAY)
             AND c.customerendpoint_address = d.phone AND c.channel = 'VOICE'
        THEN 1 ELSE 0 END) AS repeat_voice,
    MAX(CASE WHEN c.contactid != d.contactid
             AND c.initiationtimestamp > TIMESTAMP_ADD(d.initiationtimestamp, INTERVAL 30 MINUTE)
             AND c.initiationtimestamp <= TIMESTAMP_ADD(d.initiationtimestamp, INTERVAL 3 DAY)
             AND c.customerendpoint_address = d.email_addr AND c.channel = 'EMAIL'
        THEN 1 ELSE 0 END) AS repeat_email,
    MAX(CASE WHEN c.contactid != d.contactid
             AND c.initiationtimestamp > TIMESTAMP_ADD(d.initiationtimestamp, INTERVAL 30 MINUTE)
             AND c.initiationtimestamp <= TIMESTAMP_ADD(d.initiationtimestamp, INTERVAL 3 DAY)
             AND c.customerendpoint_address = d.phone AND c.channel = 'CHAT'
        THEN 1 ELSE 0 END) AS repeat_chat
  FROM deflected_with_email d
  LEFT JOIN `soe-prod-data-curated.amazon_connect_enriched.ctr_events` c
    ON (c.customerendpoint_address = d.phone OR c.customerendpoint_address = d.email_addr)
    AND ((c.channel = 'VOICE' AND c.initiationmethod = 'INBOUND')
         OR (c.channel = 'EMAIL' AND c.initiationmethod = 'INBOUND')
         OR (c.channel = 'CHAT' AND c.initiationmethod = 'API'))
  GROUP BY d.contactid
),

outcomes AS (
  SELECT
    d.deflection_type,
    d.acct_num IS NOT NULL AS is_trackable,

    -- Page visited within 7 days
    MAX(CASE WHEN pv.visit_date BETWEEN d.contact_date AND DATE_ADD(d.contact_date, INTERVAL 7 DAY) THEN 1 ELSE 0 END) AS visited_page,

    -- Completed self-serve within 7 days
    MAX(CASE WHEN ss.Created_date BETWEEN d.contact_date AND DATE_ADD(d.contact_date, INTERVAL 7 DAY) THEN 1 ELSE 0 END) AS completed_self_serve,

    -- Repeat contact within 3 days (cross-channel, >30 mins after deflection)
    rc.had_repeat_contact,
    rc.repeat_voice,
    rc.repeat_email,
    rc.repeat_chat,

    -- Completed via agent within 7 days
    MAX(CASE WHEN ac.Created_date BETWEEN d.contact_date AND DATE_ADD(d.contact_date, INTERVAL 7 DAY) THEN 1 ELSE 0 END) AS completed_via_agent

  FROM deflected_with_email d
  JOIN repeat_contacts rc ON d.contactid = rc.original_contactid
  LEFT JOIN page_visits pv ON d.acct_num = pv.account_number
  LEFT JOIN self_serve_completions ss ON d.acct_num = ss.Account_number
  LEFT JOIN agent_completions ac ON d.acct_num = ac.Account_number
  GROUP BY d.contactid, d.deflection_type, d.acct_num, d.contact_date,
           rc.had_repeat_contact, rc.repeat_voice, rc.repeat_email, rc.repeat_chat
)

SELECT
  deflection_type,
  COUNT(*) AS total_deflected,
  SUM(CASE WHEN is_trackable THEN 1 ELSE 0 END) AS trackable,

  -- Page visit rate (of trackable)
  SUM(visited_page) AS visited_page,
  ROUND(SUM(visited_page) * 100.0 / NULLIF(SUM(CASE WHEN is_trackable THEN 1 ELSE 0 END), 0), 1) AS visited_page_pct,

  -- Self-serve completion rate (of trackable)
  SUM(completed_self_serve) AS completed_self_serve,
  ROUND(SUM(completed_self_serve) * 100.0 / NULLIF(SUM(CASE WHEN is_trackable THEN 1 ELSE 0 END), 0), 1) AS self_serve_pct,

  -- Repeat contact rate (cross-channel, of all deflected)
  SUM(had_repeat_contact) AS repeat_contact,
  ROUND(SUM(had_repeat_contact) * 100.0 / COUNT(*), 1) AS repeat_rate_pct,
  SUM(repeat_voice) AS repeat_via_voice,
  SUM(repeat_email) AS repeat_via_email,
  SUM(repeat_chat) AS repeat_via_chat,

  -- Containment (no repeat contact)
  ROUND((COUNT(*) - SUM(had_repeat_contact)) * 100.0 / COUNT(*), 1) AS containment_pct,

  -- Agent completion rate (of trackable)
  SUM(completed_via_agent) AS completed_via_agent,
  ROUND(SUM(completed_via_agent) * 100.0 / NULLIF(SUM(CASE WHEN is_trackable THEN 1 ELSE 0 END), 0), 1) AS agent_completion_pct,

  -- Total completed (self-serve + agent)
  SUM(CASE WHEN completed_self_serve = 1 OR completed_via_agent = 1 THEN 1 ELSE 0 END) AS total_completed,
  ROUND(SUM(CASE WHEN completed_self_serve = 1 OR completed_via_agent = 1 THEN 1 ELSE 0 END) * 100.0 /
        NULLIF(SUM(CASE WHEN is_trackable THEN 1 ELSE 0 END), 0), 1) AS total_completion_pct

FROM outcomes
GROUP BY deflection_type
ORDER BY total_deflected DESC
```

### Typical Results (Voice Post-Deflection)

| Deflection Type | Deflected | Page Visit | Self-Serve | Repeat Contact | Containment | Via Agent |
|-----------------|----------:|-----------:|-----------:|---------------:|------------:|----------:|
| CardPayment | 150 | 3% | 12% | 21% | **79%** | 55% |
| MeterReading | 145 | 1% | 19% | 24% | **76%** | 45% |
| Renewal | 58 | 34% | 25% | 26% | **74%** | 50% |
| DirectDebit | 28 | 0% | 14% | 25% | **75%** | 64% |

**Repeat contact breakdown (cross-channel):**

| Deflection Type | Via Voice | Via Email | Via Chat |
|-----------------|----------:|----------:|---------:|
| CardPayment | 31 | 0 | 15 |
| MeterReading | 29 | 7 | 25 |
| Renewal | 14 | 3 | 10 |
| DirectDebit | 7 | 0 | 5 |

---

## Key Metrics Definitions

### Funnel Stages

| Stage | Definition | Calculation |
|-------|------------|-------------|
| **Total Contacts** | All inbound contacts | Count of CTR records |
| **Intent Detected** | Bot/IVR understood customer need | `attributes_intent IS NOT NULL` |
| **Deflection Eligible** | Intent is deflectable for channel | Intent in deflectable list |
| **Deflection Offered** | Customer reached offer point | Eligible AND (selfservice OR agent OR queue) |
| **Deflection Taken** | Customer accepted self-service | `attributes_selfservice` has value (Voice/Chat) or auto-response sent (Email) |
| **Deflection Rejected** | Customer chose agent | `attributes_selfservice = 'rejected'` (Voice only) |

### Post-Deflection Metrics

| Metric | Definition | Data Source |
|--------|------------|-------------|
| **Page Visited** | Customer visited self-service page within 7 days | GA4 events matching deflection type |
| **Completed Self-Serve** | Customer finished the action online within 7 days | `digital_journey_performance` Self Serve |
| **Repeat Contact** | Customer contacted again (any channel) within 3 days | CTR with same phone/email, >30 mins after deflection |
| **Containment** | No repeat contact within 3 days | 100% - Repeat Rate |
| **Completed Via Agent** | Action completed by agent within 7 days | `digital_journey_performance` Agent |
| **Total Completion** | Action completed (any channel) | Self-Serve OR Agent completion |

**Note:** Repeat contacts within 30 minutes are excluded as they're typically system-generated (e.g., automatic chat triggers, SMS delivery records).

### Channel-Specific Notes

| Channel | Deflection Mechanism | Trackable Post-Deflection? |
|---------|---------------------|---------------------------|
| **VOICE** | IVR offers SMS with link | Yes (via phone → account linkage) |
| **EMAIL** | Auto-response with instructions | Yes (has account number directly) |
| **CHAT** | Bot shows self-service link | **No** (anonymous, no identifier) |

---

## Deflectable Intents by Channel

### Voice & Chat

| Intent | Self-Service Action |
|--------|---------------------|
| `RenewalIntent` | `renewalOnline` |
| `MovingInIntent` | `moveInOnline` |
| `MovingOutIntent` | `moveOutOnline` |
| `SubmitMeterReadingIntent` | `submitMeterReadingOnline` |
| `MakeACardPaymentIntent` | `makeACardPaymentOnline` |
| `DirectDebitIntent` | `directDebitOnline` |

### Email

| Intent | Auto-Response Type |
|--------|-------------------|
| `MovingInIntent` | Conversational |
| `RenewalIntent` | One-shot |
| `MakeACardPaymentIntent` | One-shot |
| `DirectDebitIntent` | Conversational |
| `FinalBillIntent` | Conversational |
| `PaymentIntent` | Conversational |

---

## Weekly Report Template

### Executive Summary

```
Week of [DATE]:

DEFLECTION VOLUME
├── Voice:  [X] deflected ([Y]% take rate of eligible)
├── Email:  [X] deflected ([Y]% take rate of eligible)
└── Chat:   [X] deflected ([Y]% take rate of eligible)

VOICE POST-DEFLECTION (trackable only)
├── Page Visit Rate:     [X]%
├── Self-Serve Complete: [X]%
├── Callback Rate:       [X]%
└── Total Completion:    [X]%

WEEK-OVER-WEEK CHANGE
├── Deflection volume: [+/-X]%
├── Take rate:         [+/-X]pp
└── Completion rate:   [+/-X]pp
```

### Recommended Monitoring Thresholds

| Metric | Green | Amber | Red |
|--------|-------|-------|-----|
| Intent Detection Rate | >75% | 60-75% | <60% |
| Voice Take Rate | >25% | 15-25% | <15% |
| Email Take Rate | >40% | 25-40% | <25% |
| Page Visit Rate | >40% | 25-40% | <25% |
| Containment Rate | >75% | 60-75% | <60% |
| Repeat Contact Rate | <25% | 25-40% | >40% |
| Total Completion | >50% | 35-50% | <35% |

---

## Week-over-Week Trend Query

```sql
-- TREND: Weekly deflection metrics over past 8 weeks
SELECT
  DATE_TRUNC(DATE(initiationtimestamp), WEEK(MONDAY)) AS week_start,
  channel,
  COUNT(*) AS total_contacts,
  SUM(CASE WHEN attributes_intent IS NOT NULL THEN 1 ELSE 0 END) AS intent_detected,
  SUM(CASE
    WHEN channel = 'VOICE' AND attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
         'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline') THEN 1
    WHEN channel = 'EMAIL' AND attributes_intent IN ('MovingInIntent', 'RenewalIntent', 'MakeACardPaymentIntent',
         'DirectDebitIntent', 'FinalBillIntent', 'PaymentIntent')
         AND disconnectreason = 'CONTACT_FLOW_DISCONNECT' AND queue_name IS NULL THEN 1
    WHEN channel = 'CHAT' AND attributes_selfservice IN ('renewalOnline', 'moveInOnline', 'moveOutOnline',
         'submitMeterReadingOnline', 'makeACardPaymentOnline', 'directDebitOnline') THEN 1
    ELSE 0
  END) AS deflection_taken
FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
WHERE ((channel = 'VOICE' AND initiationmethod = 'INBOUND')
       OR (channel = 'EMAIL' AND initiationmethod = 'INBOUND')
       OR (channel = 'CHAT' AND initiationmethod = 'API'))
  AND DATE(initiationtimestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 8 WEEK)
GROUP BY week_start, channel
ORDER BY week_start DESC, channel
```

---

## Data Quality Notes

1. **Phone-to-Account Linkage**: ~50-60% of voice deflected customers can be linked to accounts
2. **GA4 User ID**: Requires customer to be logged in; anonymous visits not tracked
3. **Email Accounts**: ~78% of deflected emails have account numbers
4. **Chat Anonymity**: Cannot track post-deflection for chat customers
5. **Completion Attribution**: 7-day window; some completions may be unrelated to deflection

---

## Related Documentation

- `contact-deflection.md` - Detailed deflection logic and daily queries
- `CLAUDE.md` - Quick reference for deflection fields and filters
