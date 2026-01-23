-- CHAT Channel Sankey Flow Query
-- Purpose: Extract chatbot contact flow data for Sankey diagram visualization
-- Channel: CHAT only
-- Date: Parameterized (default: yesterday)

DECLARE report_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);

-- Define bot-resolvable intents (self-service capable)
WITH bot_resolvable_intents AS (
  SELECT intent FROM UNNEST([
    'SubmitMeterReadingIntent',
    'MakeACardPaymentIntent',
    'DirectDebitIntent',
    'RenewalIntent',
    'MovingOutIntent',
    'MovingInIntent'
  ]) AS intent
),

contacts_classified AS (
  SELECT
    contactid,
    customerendpoint_address,
    attributes_intent,
    queue_name,
    agent_connectedtoagentts,
    disconnectreason,
    initiationmethod,

    -- Stage 1: Chat Entry Point
    CASE
      WHEN initiationmethod = 'API' THEN 'Web/App chat'
      WHEN initiationmethod = 'DISCONNECT' THEN 'Reconnection attempt'
      ELSE 'Other'
    END AS stage1_entry,

    -- Stage 2: Intent Classification
    CASE
      WHEN attributes_intent IS NULL THEN 'No intent captured'
      WHEN attributes_intent = 'FallbackIntent' THEN 'Fallback intent'
      WHEN attributes_intent = 'SpeakToAnAdvisorIntent' THEN 'Agent requested'
      WHEN attributes_intent IN (SELECT intent FROM bot_resolvable_intents) THEN 'Bot-resolvable intent'
      WHEN attributes_intent IN ('GeneralBillingIntent', 'BillDisputeIntent', 'RefundIntent') THEN 'Billing query'
      WHEN attributes_intent IN ('DebtIntent', 'ComplaintIntent') THEN 'Complex issue'
      WHEN attributes_intent IN ('SolarIntent', 'NewCustomerSwitchingIntent', 'ExistingCustomerSwitchingIntent') THEN 'Sales/Switching'
      ELSE 'Other intent'
    END AS stage2_intent,

    -- Stage 3: Bot vs Agent Routing
    CASE
      WHEN disconnectreason = 'CUSTOMER_CONNECTION_NOT_ESTABLISHED' THEN 'Connection failed'
      WHEN queue_name IS NOT NULL THEN 'Escalated to agent queue'
      WHEN disconnectreason = 'CONTACT_FLOW_DISCONNECT' AND queue_name IS NULL THEN 'Bot conversation ended'
      WHEN disconnectreason = 'CUSTOMER_DISCONNECT' AND queue_name IS NULL THEN 'Customer left chatbot'
      ELSE 'Other routing'
    END AS stage3_routing,

    -- Stage 4: Final Outcome
    CASE
      WHEN disconnectreason = 'CUSTOMER_CONNECTION_NOT_ESTABLISHED' THEN 'Connection failed'
      WHEN agent_connectedtoagentts IS NOT NULL AND disconnectreason = 'AGENT_DISCONNECT' THEN 'Agent resolved'
      WHEN agent_connectedtoagentts IS NOT NULL AND disconnectreason = 'CUSTOMER_DISCONNECT' THEN 'Customer ended with agent'
      WHEN queue_name IS NOT NULL AND agent_connectedtoagentts IS NULL THEN 'Abandoned in queue'
      WHEN disconnectreason = 'CONTACT_FLOW_DISCONNECT' AND queue_name IS NULL THEN 'Bot completed'
      WHEN disconnectreason = 'CUSTOMER_DISCONNECT' AND queue_name IS NULL THEN 'Customer abandoned bot'
      ELSE 'Other outcome'
    END AS stage4_outcome

  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE DATE(initiationtimestamp) = report_date
    AND channel = 'CHAT'
),

-- Link 1: Entry -> Intent
link1 AS (
  SELECT stage1_entry AS source, stage2_intent AS target, COUNT(*) AS value, 1 AS stage
  FROM contacts_classified
  GROUP BY 1, 2
),

-- Link 2: Intent -> Routing
link2 AS (
  SELECT stage2_intent AS source, stage3_routing AS target, COUNT(*) AS value, 2 AS stage
  FROM contacts_classified
  GROUP BY 1, 2
),

-- Link 3: Routing -> Outcome
link3 AS (
  SELECT stage3_routing AS source, stage4_outcome AS target, COUNT(*) AS value, 3 AS stage
  FROM contacts_classified
  GROUP BY 1, 2
),

all_links AS (
  SELECT * FROM link1
  UNION ALL SELECT * FROM link2
  UNION ALL SELECT * FROM link3
)

SELECT source, target, value, stage
FROM all_links
WHERE value > 0
ORDER BY stage, value DESC;
