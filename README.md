# BigQuery Data Guide

**Purpose**: This repo contains documentation about our BigQuery datasets so Claude (and team members) can query the right tables without having to discover the data structure each time.

## How to Use

1. Clone this repo
2. When using Claude Code with BigQuery MCP, Claude will reference these docs to understand which tables contain what data
3. Ask natural language questions like "show me customer churn data" and Claude knows where to look

## Dataset Categories

| Category | Datasets | Description |
|----------|----------|-------------|
| **Nova Platform** | `nova_be_*_enriched` | Core platform data - customers, products, tickets, comms |
| **Billing & Energy** | `junifer_enriched` | Billing, meter reads, tariffs, accounts |
| **Customer Support** | `amazon_connect_enriched` | Support cases, calls, contacts (PRIMARY) |
| **Analytics** | `soe_*`, `analytics_*` | Aggregated views, reports, ML datasets |
| **Finance** | `finance_reports`, `revenue_paid` | Financial reporting data |
| **External Data** | `uk_gov`, `bloomberg` | Government and market data |

> ⚠️ **Note**: Freshdesk (`freshdesk_enriched`) is deprecated. Use Amazon Connect for support data.

## Documentation Structure

```
datasets/
  ├── _catalog.md          # Master list of all datasets
  ├── nova-platform.md     # Nova backend services data
  ├── junifer-billing.md   # Billing and energy data
  ├── amazon-connect.md    # Support cases and contact center
  └── freshdesk-support.md # DEPRECATED - historical only

use-cases/
  └── common-questions.md  # Ready-to-use queries for common questions
```

## Quick Reference

| Question | Table |
|----------|-------|
| Customer data | `nova_be_customers_enriched.customer` |
| Support cases | `amazon_connect_enriched.case_events` |
| Complaints | `amazon_connect_enriched.case_events` (where `is_complaint = TRUE`) |
| Billing accounts | `junifer_enriched.account` |
| Products/Tariffs | `nova_be_products_enriched.product` |

## Critical: Querying Enriched Tables

All `*_enriched` tables use SCD Type 2. **To get current state:**

```sql
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
```

## Contributing

When you discover something useful about the data, add it here so the next person doesn't have to rediscover it.
