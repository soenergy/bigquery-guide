# Marketing Consent Renewal Rate Dashboard

**Jira Ticket:** PVB-412

A BigQuery-powered dashboard tracking renewal rates by marketing consent status, replacing manual weekly data entry.

## Quick Start

1. **Run the combined query**: Execute `dashboard_query.sql` in BigQuery
2. **View results**: Open `marketing_consent_dashboard.html` in a browser
3. **Update data**: Copy query results to update the dashboard's `dashboardData` object

## Files

| File | Purpose |
|------|---------|
| `dashboard_query.sql` | Combined query for all dashboard metrics |
| `marketing_consent_dashboard.html` | Interactive HTML dashboard with Chart.js |
| `renewal_rate_by_consent.sql` | Core renewal rate comparison query |
| `interests_bucket_analysis.sql` | Customer interests breakdown |
| `churn_rate_by_consent.sql` | Churn analysis by consent status |

## Key Metrics

| Metric | Definition |
|--------|------------|
| **Opt-In Rate** | `COUNT(Subscribed) / COUNT(All Active)` |
| **Renewal Rate** | `COUNT(Renewed) / COUNT(Contracts Ended)` |
| **Churn Rate** | `COUNT(Churned) / COUNT(Active at Period Start)` |
| **Renewal Delta** | `Opted-In Rate - Opted-Out Rate` |

## Data Sources

```
dotdigital.customer_marketing_master
├── dotdigital_subscription_status  (consent)
├── ele_rnwl_status / gas_rnwl_status  (renewal)
├── ele_cur_tarif_end / gas_cur_tarif_end  (contract dates)
└── account_number → billing_account → customer_setting (interests)
```

## Updating the Dashboard

The HTML dashboard uses static sample data. To update with real data:

1. Run `dashboard_query.sql` in BigQuery
2. Export results as JSON or copy values
3. Update the `dashboardData` object in the HTML file
4. Refresh the browser

## Analysis Period

Default analysis uses **90-day** lookback:
- Contracts that ended in the last 90 days
- Accounts active at the start of the 90-day period
- Week-over-week trend for 12 weeks

Adjust the `INTERVAL X DAY` values in SQL to change the period.

## Related Documentation

- `../weekly-deflection-report.md` - Similar dashboard pattern
- `../../CLAUDE.md` - BigQuery table mappings and patterns
