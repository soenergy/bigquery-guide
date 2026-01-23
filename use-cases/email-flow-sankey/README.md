# Email Contact Flow - Sankey Diagram

Interactive visualization showing the flow of email contacts through the contact center.

## Overview

This Sankey diagram visualizes how EMAIL channel contacts flow through four stages:

1. **Email Origin** - Inbound, Outbound, Agent Reply, Transfer, System/Flow
2. **Intent Classification** - Billing, Metering, Payments, Solar, Complaints, etc.
3. **Queue Routing** - Customer Care, Dropped Emails, Agent Holding, Specialist queues
4. **Final Outcome** - Agent handled, Dropped, Discarded, Transferred, API processed

## Files

| File | Description |
|------|-------------|
| `sankey_query.sql` | BigQuery SQL query to extract Sankey link data |
| `email_flow_sankey.html` | Interactive HTML visualization (standalone) |
| `README.md` | This documentation |

## Usage

### View the Visualization

```bash
open email_flow_sankey.html
```

### Update Data for a Different Date

1. Modify the `report_date` in `sankey_query.sql`
2. Run the query in BigQuery
3. Update the `sankeyData` object in the HTML with new results

## Key Metrics (Sample Data: 2025-01-22)

| Metric | Value |
|--------|-------|
| Total Emails | 3,601 |
| Inbound | 28% |
| Outbound | 37% |
| Agent Handled | 58% |
| Intent Classified | 36% |
| Dropped | 7% |

## Email Flow Characteristics

### Origin Types
- **Inbound email**: Customer-initiated emails
- **Outbound email**: Proactive agent/system emails
- **Agent reply**: Responses to existing threads
- **Transfer**: Emails transferred between queues/agents
- **System/Flow**: Automated system-generated emails

### Intent Categories
Emails are classified into categories based on NLP analysis:
- **Billing related**: Disputes, general billing, final bills, refunds
- **Metering related**: Readings, smart meters, faulty meters
- **Payments related**: Direct debit, payments, debt
- **Moving home**: Move in/out requests
- **Solar**: Solar panel inquiries
- **Complaints**: Customer complaints
- **Unclassified**: No intent detected (64% of emails)

### Queue Routing
- **No queue**: Handled directly without queuing
- **Customer Care queue**: General customer service
- **Dropped Emails queue**: Emails that couldn't be processed
- **Agent Holding queue**: Awaiting agent assignment
- **Specialist queues**: Solar, Collections, etc.

## Color Scheme

| Stage | Color | Hex |
|-------|-------|-----|
| Email Origin | Blue shades | #3498db |
| Intent Classification | Purple shades | #9b59b6 |
| Queue Routing | Orange shades | #f39c12 |
| Positive Outcomes | Green | #2ecc71 |
| Negative Outcomes | Red | #e74c3c |

## Technical Notes

- Built with [Plotly.js](https://plotly.com/javascript/) v2.27.0
- Standalone HTML - no server required
- Responsive design
- Dark theme optimized for dashboard displays
