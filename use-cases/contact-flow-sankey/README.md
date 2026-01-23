# Customer Contact Flow - Sankey Diagram

Interactive visualization showing the flow of customer contacts through the contact center, from initial contact to final outcome.

## Overview

This Sankey diagram visualizes how VOICE channel contacts flow through various stages:

1. **Contact Demand** - New vs Return contacts (called within last 5 days)
2. **Routing Decision** - ID&V path vs Auto-resolution path
3. **Deflection Outcomes** - For auto-resolution: proceed, disconnect, or deflect
4. **ID&V & Queue Status** - ID&V completion and queue entry
5. **Final Outcomes** - Answered by agent, abandoned, or other

## Files

| File | Description |
|------|-------------|
| `sankey_query.sql` | BigQuery SQL query to extract Sankey link data |
| `contact_flow_sankey.html` | Interactive HTML visualization (standalone) |
| `README.md` | This documentation |

## Usage

### View the Visualization

Simply open `contact_flow_sankey.html` in any modern web browser:

```bash
open contact_flow_sankey.html
```

### Update Data for a Different Date

1. Modify the `report_date` in `sankey_query.sql`:
   ```sql
   DECLARE report_date DATE DEFAULT DATE('2025-01-20');  -- Change this date
   ```

2. Run the query in BigQuery

3. Update the `sankeyData` object in `contact_flow_sankey.html` with the new results

## Data Sources

- **Primary**: `soe-prod-data-curated.amazon_connect_enriched.ctr_events`
- **Channel**: VOICE only
- **Contact Type**: INBOUND only

## Color Scheme

| Stage | Color | Hex |
|-------|-------|-----|
| Contact Demand | Purple | #7B68EE |
| Auto-resolution/Deflection | Green | #4CAF50 |
| ID&V/Queue | Brown | #CD853F |
| Negative Outcomes | Red | #DC143C |
| Positive Outcomes | Forest Green | #228B22 |

## Key Metrics (Sample Data: 2025-01-22)

| Metric | Value |
|--------|-------|
| Total Contacts | 1,616 |
| New Contacts | 76% |
| Auto-Resolution Route | 20% |
| Answered by Agent | 53% |
| Queue Abandonment | 17% |

## Deflectable Intents

The following intents are routed to the auto-resolution bot:

- `RenewalIntent`
- `MovingOutIntent`
- `SubmitMeterReadingIntent`
- `MakeACardPaymentIntent`
- `DirectDebitIntent`

## Flow Logic

### Stage Classifications

**Return Contact Detection**:
- Phone number appeared in VOICE contacts within the previous 5 days

**Routing Decision**:
- Routed to auto-resolution if intent matches deflectable intents list
- Otherwise routed to ID&V

**ID&V Status**:
- Completed: `attributes_accountvalid` is 'true' or 'false'
- Queued (no ID&V): Reached queue without ID&V validation
- Abandoned pre-queue: Never reached queue or agent

**Final Outcome**:
- Answered by agent: `agent_connectedtoagentts` is not null
- Abandoned from queue: Queued but never connected to agent
- Disconnected in IVR: `disconnectreason = 'CONTACT_FLOW_DISCONNECT'`

## Technical Notes

- Built with [Plotly.js](https://plotly.com/javascript/) v2.27.0
- Standalone HTML - no server required
- Responsive design for various screen sizes
- Dark theme optimized for dashboard displays
