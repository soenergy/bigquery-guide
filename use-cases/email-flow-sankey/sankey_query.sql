-- EMAIL Channel Sankey Flow Query
-- Purpose: Extract email contact flow data for Sankey diagram visualization
-- Channel: EMAIL only
-- Date: Parameterized (default: yesterday)

DECLARE report_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);

WITH contacts_classified AS (
  SELECT
    contactid,
    customerendpoint_address,
    attributes_intent,
    queue_name,
    agent_connectedtoagentts,
    disconnectreason,
    initiationmethod,

    -- Stage 1: Email Origin
    CASE
      WHEN initiationmethod = 'INBOUND' THEN 'Inbound email'
      WHEN initiationmethod = 'OUTBOUND' THEN 'Outbound email'
      WHEN initiationmethod = 'AGENT_REPLY' THEN 'Agent reply'
      WHEN initiationmethod = 'TRANSFER' THEN 'Transfer'
      ELSE 'System/Flow'
    END AS stage1_origin,

    -- Stage 2: Intent Classification
    CASE
      WHEN attributes_intent IS NULL THEN 'Unclassified'
      WHEN attributes_intent = 'FallbackIntent' THEN 'Fallback intent'
      WHEN attributes_intent IN ('BillDisputeIntent', 'GeneralBillingIntent', 'FinalBillIntent', 'RefundIntent') THEN 'Billing related'
      WHEN attributes_intent IN ('SubmitMeterReadingIntent', 'GeneralMeterReadingIntent', 'FaultyMeterIntent',
                                  'FaultySmartMeterIntent', 'SmartMeterIntent', 'SmartMeterInstallation') THEN 'Metering related'
      WHEN attributes_intent IN ('MovingOutIntent', 'MovingInIntent', 'MovingHomeIntent') THEN 'Moving home'
      WHEN attributes_intent IN ('DirectDebitIntent', 'PaymentIntent', 'DebtIntent') THEN 'Payments related'
      WHEN attributes_intent = 'SolarIntent' THEN 'Solar'
      WHEN attributes_intent = 'ComplaintIntent' THEN 'Complaints'
      ELSE 'Other intent'
    END AS stage2_intent,

    -- Stage 3: Queue Routing
    CASE
      WHEN queue_name IS NULL THEN 'No queue'
      WHEN queue_name = 'Dropped Emails' THEN 'Dropped Emails queue'
      WHEN queue_name = 'Customer Care - Email' THEN 'Customer Care queue'
      WHEN queue_name = 'Agent Holding Queue' THEN 'Agent Holding queue'
      WHEN queue_name LIKE '%Solar%' THEN 'Solar queue'
      WHEN queue_name LIKE '%Collection%' THEN 'Collections queue'
      ELSE 'Specialist queue'
    END AS stage3_queue,

    -- Stage 4: Final Outcome
    CASE
      WHEN agent_connectedtoagentts IS NOT NULL AND disconnectreason IN ('AGENT_DISCONNECT', 'OTHER') THEN 'Agent handled'
      WHEN queue_name = 'Dropped Emails' THEN 'Dropped'
      WHEN disconnectreason = 'DISCARDED' THEN 'Discarded'
      WHEN disconnectreason = 'TRANSFERRED' THEN 'Transferred'
      WHEN disconnectreason = 'API' THEN 'API processed'
      WHEN disconnectreason = 'CONTACT_FLOW_DISCONNECT' AND queue_name IS NULL THEN 'Flow terminated'
      ELSE 'Other outcome'
    END AS stage4_outcome

  FROM `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
  WHERE DATE(initiationtimestamp) = report_date
    AND channel = 'EMAIL'
),

-- Link 1: Origin -> Intent
link1 AS (
  SELECT stage1_origin AS source, stage2_intent AS target, COUNT(*) AS value, 1 AS stage
  FROM contacts_classified
  GROUP BY 1, 2
),

-- Link 2: Intent -> Queue
link2 AS (
  SELECT stage2_intent AS source, stage3_queue AS target, COUNT(*) AS value, 2 AS stage
  FROM contacts_classified
  GROUP BY 1, 2
),

-- Link 3: Queue -> Outcome
link3 AS (
  SELECT stage3_queue AS source, stage4_outcome AS target, COUNT(*) AS value, 3 AS stage
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
