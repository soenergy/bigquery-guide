# Chatbot Contact Flow - Sankey Diagram

Interactive visualization showing the flow of chat contacts through the chatbot and agent escalation paths.

## Overview

This Sankey diagram visualizes how CHAT channel contacts flow through four stages:

1. **Chat Entry** - Web/App initiated vs Reconnection attempts
2. **Intent Classification** - Bot-resolvable, billing, sales, complex issues, etc.
3. **Bot/Agent Routing** - Bot conversation, customer left, escalated to queue
4. **Final Outcome** - Bot completed, agent resolved, abandoned

## Key Insight: Bot Containment

The chat channel is **heavily bot-centric**:
- Only **10%** of chats escalate to an agent queue
- **25%** complete successfully with the bot
- **55%** of customers leave the chatbot before completion
- **11%** fail due to connection issues

## Files

| File | Description |
|------|-------------|
| `sankey_query.sql` | BigQuery SQL query to extract Sankey link data |
| `chat_flow_sankey.html` | Interactive HTML visualization (standalone) |
| `README.md` | This documentation |

## Usage

### View the Visualization

```bash
open chat_flow_sankey.html
```

### Update Data for a Different Date

1. Modify the `report_date` in `sankey_query.sql`
2. Run the query in BigQuery
3. Update the `sankeyData` object in the HTML with new results

## Key Metrics (Sample Data: 2025-01-22)

| Metric | Value |
|--------|-------|
| Total Chats | 2,229 |
| Bot Completed | 25% |
| Agent Resolved | 5% |
| Escalation Rate | 10% |
| Customer Abandoned Bot | 55% |
| Connection Failed | 11% |

## Chat Flow Characteristics

### Entry Types
- **Web/App chat**: Initiated via website widget or mobile app (97%)
- **Reconnection attempt**: Customer trying to reconnect after disconnect (3%)

### Intent Categories
- **No intent captured**: Bot couldn't determine intent (32%)
- **Bot-resolvable intent**: Meter readings, payments, direct debit, etc. (18%)
- **Sales/Switching**: Solar, new/existing customer switching (8%)
- **Billing query**: Disputes, refunds, general billing (8%)
- **Agent requested**: Customer explicitly asked for agent (6%)
- **Complex issue**: Debt, complaints (5%)
- **Fallback intent**: Bot confusion/fallback (7%)

### Routing Outcomes
- **Customer left chatbot**: Left before resolution (55%)
- **Bot conversation ended**: Bot completed interaction (25%)
- **Escalated to agent queue**: Transferred to human agent (10%)
- **Connection failed**: Technical failure (11%)

### Bot-Resolvable Intents
These intents are designed for full bot self-service:
- `SubmitMeterReadingIntent`
- `MakeACardPaymentIntent`
- `DirectDebitIntent`
- `RenewalIntent`
- `MovingOutIntent`
- `MovingInIntent`

## Color Scheme

| Stage | Color | Hex |
|-------|-------|-----|
| Chat Entry | Cyan | #00d4ff |
| Intent Classification | Purple | #7c3aed |
| Bot/Agent Routing | Orange | #f59e0b |
| Positive Outcomes | Green | #10b981 |
| Negative Outcomes | Red | #ef4444 |

## Technical Notes

- Built with [Plotly.js](https://plotly.com/javascript/) v2.27.0
- Standalone HTML - no server required
- Responsive design
- Dark theme with cyan/purple gradient
