# Amazon Connect Data

Amazon Connect is the **primary system for customer support cases and contact center data**. Use this instead of Freshdesk for all support metrics.

## amazon_connect_enriched

### Key Tables

| Table | Description | Rows |
|-------|-------------|------|
| `case_events` | Support cases/tickets | ~6.6M |
| `contact_events` | Customer contacts (calls, chats, emails) | ~15M |
| `ctr_events` | Contact Trace Records (detailed call data) | ~1.9M |
| `agent_dim` | Agent information | - |
| `queue_dim` | Queue information | - |

---

## case_events - Support Cases

This is the main table for support tickets/cases. Replaces Freshdesk tickets.

### Core Fields

| Column | Type | Description |
|--------|------|-------------|
| `id` | STRING | Case ID |
| `account` | INTEGER | So Energy account number |
| `detail_case_createddatetime` | TIMESTAMP | When case was created |
| `detail_case_fields_status` | STRING | Case status |
| `detail_case_fields_title` | STRING | Case title |
| `detail_case_fields_description` | STRING | Case description |
| `detail_case_fields_summary` | STRING | Case summary |

### Categorization Fields

| Column | Description |
|--------|-------------|
| `detail_case_fields_level_1` | Top-level category |
| `detail_case_fields_level_2` | Sub-category |
| `detail_case_fields_level_3` | Specific issue type |
| `detail_case_fields_case_reason` | Intent from Lexbot |

### Assignment Fields

| Column | Description |
|--------|-------------|
| `detail_case_fields_assigned_user` | Agent assigned |
| `detail_case_fields_assigned_agent_name` | Agent name |
| `detail_case_fields_assigned_queue` | Queue assigned |
| `detail_case_fields_queue_name` | Queue name |

### Complaint Fields

| Column | Description |
|--------|-------------|
| `detail_case_fields_is_complaint` | Boolean - is this a complaint? |
| `detail_case_fields_complaint_status` | Complaint stage (Raised, Closed, Re-Open, etc.) |
| `detail_case_fields_complaint_type` | Type: Exec, Ombudsman, CAB, EHU, Trustpilot, Inbound, OS |
| `detail_case_fields_complaint_subject` | Area: Billing, Metering, Registrations, Customer Service |
| `detail_case_fields_complaint_subject_2` | Sub-category of complaint subject |
| `detail_case_fields_complaint_reason` | Complaint reason |
| `detail_case_fields_complaint_goodwill_amount` | Goodwill awarded |
| `detail_case_fields_complaint_resolved` | Is complaint resolved? |
| `detail_case_fields_ombudsman_case` | Escalated to ombudsman? |

### Timing Fields

| Column | Description |
|--------|-------------|
| `detail_case_fields_original_creation_date` | Original creation date |
| `detail_case_fields_last_updated_datetime` | Last update |
| `detail_case_fields_last_closed_datetime` | When closed |
| `detail_case_fields_last_reopened_datetime` | When reopened |
| `detail_case_fields_due_date` | 2 working days from creation |
| `detail_case_fields_is_overdue` | Has been open > 2 working days |

---

## Common Queries

### Case volume by day
```sql
SELECT
  DATE(detail_case_createddatetime) AS date,
  COUNT(*) AS cases_created
FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
WHERE detail_event_type = 'CASE.CREATED'
  AND detail_case_createddatetime >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY date
ORDER BY date DESC
```

### Open cases (current backlog)
```sql
SELECT COUNT(DISTINCT id) AS open_cases
FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
WHERE detail_case_fields_status NOT IN ('Closed', 'Resolved')
  AND meta_enriched_landed_date = (
    SELECT MAX(meta_enriched_landed_date)
    FROM `soe-prod-data-core-7529.amazon_connect_enriched.case_events`
  )
```

### Complaints
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
  AND detail_case_createddatetime >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
GROUP BY subject
ORDER BY count DESC
```

### Cases by category (Level 1)
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

---

## ctr_events - Contact Trace Records

Detailed call/contact data with agent interaction times, hold durations, transcripts, and CSAT scores.

### Key Fields

| Column | Description |
|--------|-------------|
| `contactid` | Contact ID |
| `channel` | VOICE, CHAT, TASK, EMAIL |
| `initiationmethod` | How contact was initiated |
| `initiationtimestamp` | When contact started |
| `disconnecttimestamp` | When contact ended |
| `agent_username` | Agent username |
| `agent_connectedtoagentts` | When connected to agent |
| `agent_agentinteractionduration` | Seconds agent interacted |
| `agent_customerholdduration` | Seconds customer on hold |
| `queue_name` | Queue name |
| `queue_duration` | Seconds in queue |
| `attributes_intent` | Customer intent |
| `attributes_caseid` | Linked case ID |
| `disconnectreason` | Why contact ended |

### CSAT Fields (in ctr_events)

| Column | Description |
|--------|-------------|
| `attributes_csatresults_agentrating` | Agent rating |
| `attributes_csatresults_resolutionrating` | Resolution rating |

---

## contact_events - Contact Events

Lower-level contact event data. Useful for detailed contact flow analysis.

### Key Fields

| Column | Description |
|--------|-------------|
| `detail_contactId` | Contact ID |
| `detail_channel` | VOICE, CHAT, etc. |
| `detail_eventType` | Event type |
| `detail_initiationTimestamp` | When initiated |
| `detail_disconnectTimestamp` | When disconnected |
| `detail_agentInfo_agentArn` | Agent ARN |

---

## Linking to Accounts

Amazon Connect cases link to Junifer accounts via:
- `case_events.account` - The account number
- `ctr_events.attributes_accountnumbers` - Account numbers from call
- `ctr_events.attributes_juniferid` - Junifer customer ID
