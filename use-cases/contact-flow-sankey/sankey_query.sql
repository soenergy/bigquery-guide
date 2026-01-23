-- Sankey Contact Flow Query
-- Purpose: Extract customer contact flow data for Sankey diagram visualization
-- Channel: VOICE only
-- Date: Parameterized (default: yesterday)
--
-- To change the date, modify the DECLARE statement below

DECLARE report_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);

-- Define deflectable intents (intents that can be handled by auto-resolution bot)
WITH deflectable_intents AS (
  SELECT intent FROM UNNEST([
    'RenewalIntent',
    'MovingOutIntent',
    'SubmitMeterReadingIntent',
    'MakeACardPaymentIntent',
    'DirectDebitIntent'
  ]) AS intent
),

-- Get previous contacts (last 5 days) to identify return callers
previous_contacts AS (
  SELECT DISTINCT
    customerendpoint_address AS phone_number
  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE DATE(initiationtimestamp) BETWEEN DATE_SUB(report_date, INTERVAL 5 DAY) AND DATE_SUB(report_date, INTERVAL 1 DAY)
    AND channel = 'VOICE'
    AND initiationmethod = 'INBOUND'
),

-- Main contact classification - assigns each contact to nodes at each stage
contacts_classified AS (
  SELECT
    ctr.contactid,
    ctr.customerendpoint_address AS phone_number,
    ctr.attributes_intent,
    ctr.attributes_accountvalid,
    ctr.queue_name,
    ctr.agent_connectedtoagentts,
    ctr.disconnectreason,

    -- Stage 1: Contact Type (Return vs New)
    CASE
      WHEN pc.phone_number IS NOT NULL THEN 'Return contact'
      ELSE 'New contact'
    END AS stage1_contact_type,

    -- Stage 2: Routing Decision (based on intent)
    CASE
      WHEN ctr.attributes_intent IN (SELECT intent FROM deflectable_intents)
        THEN 'Routed to auto-resolution'
      ELSE 'Routed to ID&V'
    END AS stage2_routing,

    -- Stage 3: Deflection Outcomes (for auto-resolution path)
    CASE
      WHEN ctr.attributes_intent NOT IN (SELECT intent FROM deflectable_intents) THEN 'N/A'
      WHEN ctr.queue_name IS NULL
           AND ctr.agent_connectedtoagentts IS NULL
           AND ctr.disconnectreason = 'CONTACT_FLOW_DISCONNECT'
        THEN 'Disconnected pre-queue'
      WHEN ctr.attributes_accountvalid IS NOT NULL THEN 'Proceeded to ID&V'
      WHEN ctr.queue_name IS NOT NULL THEN 'Proceeded to queue'
      ELSE 'Other deflection outcome'
    END AS stage3_deflection,

    -- Stage 4: ID&V & Queue Status
    CASE
      WHEN ctr.attributes_accountvalid IN ('true', 'false') THEN 'ID&V completed'
      WHEN ctr.queue_name IS NOT NULL AND ctr.attributes_accountvalid IS NULL THEN 'Queued (no ID&V)'
      WHEN ctr.queue_name IS NULL AND ctr.agent_connectedtoagentts IS NULL THEN 'Abandoned pre-queue'
      ELSE 'Other'
    END AS stage4_idv_status,

    -- Stage 5: Final Outcome
    CASE
      WHEN ctr.agent_connectedtoagentts IS NOT NULL THEN 'Answered by agent'
      WHEN ctr.queue_name IS NOT NULL
           AND ctr.agent_connectedtoagentts IS NULL
        THEN 'Abandoned from queue'
      WHEN ctr.disconnectreason = 'CONTACT_FLOW_DISCONNECT' THEN 'Disconnected in IVR'
      ELSE 'Other outcome'
    END AS stage5_final

  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events` ctr
  LEFT JOIN previous_contacts pc ON ctr.customerendpoint_address = pc.phone_number
  WHERE DATE(ctr.initiationtimestamp) = report_date
    AND ctr.channel = 'VOICE'
    AND ctr.initiationmethod = 'INBOUND'
),

-- Generate Sankey links between stages
-- Link 1: Stage 1 (Contact Type) → Stage 2 (Routing)
link1 AS (
  SELECT stage1_contact_type AS source, stage2_routing AS target, COUNT(*) AS value, 1 AS stage
  FROM contacts_classified
  GROUP BY 1, 2
),

-- Link 2a: Routed to ID&V → Stage 4 (ID&V Status)
link2a AS (
  SELECT stage2_routing AS source, stage4_idv_status AS target, COUNT(*) AS value, 2 AS stage
  FROM contacts_classified
  WHERE stage2_routing = 'Routed to ID&V'
  GROUP BY 1, 2
),

-- Link 2b: Routed to auto-resolution → Stage 3 (Deflection Outcomes)
link2b AS (
  SELECT stage2_routing AS source, stage3_deflection AS target, COUNT(*) AS value, 2 AS stage
  FROM contacts_classified
  WHERE stage2_routing = 'Routed to auto-resolution' AND stage3_deflection != 'N/A'
  GROUP BY 1, 2
),

-- Link 3: Stage 3 (Deflection) → Stage 4 (for those proceeding)
link3 AS (
  SELECT stage3_deflection AS source, stage4_idv_status AS target, COUNT(*) AS value, 3 AS stage
  FROM contacts_classified
  WHERE stage3_deflection IN ('Proceeded to ID&V', 'Proceeded to queue')
  GROUP BY 1, 2
),

-- Link 4: Stage 4 (ID&V/Queue) → Stage 5 (Final Outcome)
link4 AS (
  SELECT stage4_idv_status AS source, stage5_final AS target, COUNT(*) AS value, 4 AS stage
  FROM contacts_classified
  WHERE stage4_idv_status IN ('ID&V completed', 'Queued (no ID&V)')
  GROUP BY 1, 2
),

-- Combine all links
all_links AS (
  SELECT * FROM link1
  UNION ALL SELECT * FROM link2a
  UNION ALL SELECT * FROM link2b
  UNION ALL SELECT * FROM link3
  UNION ALL SELECT * FROM link4
)

-- Final output for Sankey visualization
SELECT source, target, value, stage
FROM all_links
WHERE value > 0
ORDER BY stage, value DESC;
