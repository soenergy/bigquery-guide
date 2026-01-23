# Freshdesk Support Data

> ⚠️ **DEPRECATED**: Freshdesk has been retired. Use **Amazon Connect** (`amazon_connect_enriched`) for all customer support and contact center data. Only query Freshdesk for historical analysis if explicitly requested.

See [Amazon Connect documentation](./amazon-connect.md) for the current support data source.

---

## Legacy Reference (for historical queries only)

### freshdesk_enriched.tickets

~2.5M rows | Historical data only

| Column | Type | Description |
|--------|------|-------------|
| `id` | STRING | Ticket ID |
| `subject` | STRING | Ticket subject |
| `status` | INTEGER | 2=Open, 3=Pending, 4=Resolved, 5=Closed |
| `priority` | INTEGER | 1=Low, 2=Medium, 3=High, 4=Urgent |
| `source` | INTEGER | 1=Email, 2=Portal, 3=Phone, 7=Chat |
| `created_at` | TIMESTAMP | When created |
| `custom_fields.cf_complaint` | STRING | Complaint flag |
