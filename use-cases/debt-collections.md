# Debt & Collections Metrics

Data for understanding customer debt, debt treatments, dunning processes, and DCA (Debt Collection Agency) performance.

---

## Key Tables

| Table | Dataset | Description |
|-------|---------|-------------|
| `dca_account_allocation` | `nova_be_tickets_enriched` | Accounts allocated to DCAs with status |
| `dunning_inst` | `junifer_enriched` | Dunning instances (debt recovery process) |
| `pastdue` | `dca_enriched` | PastDue Credit Solutions accounts |
| `conexus` | `dca_enriched` | Conexus accounts |
| `pastdue_payment` | `dca_enriched` | PastDue payment records |
| `conexus_payment` | `dca_enriched` | Conexus payment records |
| `coeo_payment` | `dca_enriched` | Coeo payment records |
| `debt_provision_analysis` | `debt_provisioning` | Debt provisioning analysis |

---

## DCA Allocation Overview

### Accounts currently with DCAs

```sql
SELECT
  dca_id,
  account_status,
  COUNT(DISTINCT junifer_account_number) AS accounts
FROM `soe-prod-data-core-7529.nova_be_tickets_enriched.dca_account_allocation`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
GROUP BY dca_id, account_status
ORDER BY dca_id, accounts DESC
```

### Accounts by DCA and occupier status

```sql
SELECT
  dca_id,
  occupier_status,
  COUNT(DISTINCT junifer_account_number) AS accounts
FROM `soe-prod-data-core-7529.nova_be_tickets_enriched.dca_account_allocation`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
GROUP BY dca_id, occupier_status
ORDER BY dca_id, accounts DESC
```

### DCA allocations over time

```sql
SELECT
  DATE(job_run_date) AS allocation_date,
  dca_id,
  COUNT(DISTINCT junifer_account_number) AS accounts_allocated
FROM `soe-prod-data-core-7529.nova_be_tickets_enriched.dca_account_allocation`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND job_run_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY allocation_date, dca_id
ORDER BY allocation_date DESC, dca_id
```

### PSR (Priority Services Register) customers in debt

```sql
SELECT
  dca_id,
  psr,
  COUNT(DISTINCT junifer_account_number) AS accounts
FROM `soe-prod-data-core-7529.nova_be_tickets_enriched.dca_account_allocation`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
GROUP BY dca_id, psr
ORDER BY dca_id
```

---

## DCA Performance (PastDue Example)

### PastDue accounts by status

```sql
SELECT
  status,
  COUNT(DISTINCT account_number) AS accounts,
  SUM(outstanding_balance) AS total_outstanding
FROM `soe-prod-data-core-7529.dca_enriched.pastdue`
WHERE meta_enriched_landed_date = (
  SELECT MAX(meta_enriched_landed_date)
  FROM `soe-prod-data-core-7529.dca_enriched.pastdue`
)
GROUP BY status
ORDER BY accounts DESC
```

### PastDue payments received

```sql
SELECT
  DATE(meta_enriched_landed_date) AS date,
  COUNT(*) AS payments,
  SUM(CAST(amount AS FLOAT64)) AS total_collected
FROM `soe-prod-data-core-7529.dca_enriched.pastdue_payment`
WHERE meta_enriched_landed_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY date
ORDER BY date DESC
```

---

## Dunning Process (Junifer)

### Active dunning instances

```sql
SELECT
  COUNT(*) AS active_dunning_instances
FROM `soe-prod-data-core-7529.junifer_enriched.dunning_inst`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND cancel_fl != 'Y'
```

### Dunning by due date

```sql
SELECT
  due_dt,
  COUNT(*) AS instances
FROM `soe-prod-data-core-7529.junifer_enriched.dunning_inst`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND cancel_fl != 'Y'
  AND due_dt >= CURRENT_DATE()
  AND due_dt <= DATE_ADD(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY due_dt
ORDER BY due_dt
```

---

## Debt Provisioning

### Debt provision analysis

```sql
SELECT *
FROM `soe-prod-data-core-7529.debt_provisioning.debt_provision_analysis`
LIMIT 100
```

### Customer level balance forecast

```sql
SELECT *
FROM `soe-prod-data-core-7529.debt_provisioning.customer_level_balance_forecast`
LIMIT 100
```

---

## Key Fields Reference

### dca_account_allocation

| Column | Description |
|--------|-------------|
| `junifer_account_number` | Junifer account number |
| `account_id` | Account ID |
| `dca_id` | DCA identifier |
| `account_status` | Account status in DCA |
| `occupier_status` | Occupier status |
| `supply_status` | Supply status |
| `psr` | Is customer on PSR (Boolean) |
| `job_run_date` | When allocation was processed |
| `current_placement` | Current placement number |
| `ticket_definition_code` | Type of debt ticket |

### pastdue (DCA)

| Column | Description |
|--------|-------------|
| `account_number` | Account number |
| `debt_id` | Debt ID |
| `date_placed` | When placed with DCA |
| `status` | Current status |
| `outstanding_balance` | Amount outstanding |

### dunning_inst (Junifer)

| Column | Description |
|--------|-------------|
| `id` | Dunning instance ID |
| `account_transaction_fk` | Related transaction |
| `due_dt` | Due date |
| `cancel_fl` | Cancelled flag |

---

## DCAs Reference

| DCA ID/Name | Dataset Tables |
|-------------|----------------|
| PastDue | `dca_enriched.pastdue`, `pastdue_payment` |
| Conexus | `dca_enriched.conexus`, `conexus_payment` |
| Coeo | `dca_enriched.coeo_payment` |
| Digital DRA | `dca_enriched.digital_dra_payment` |
| First Locate | `dca_enriched.first_locate_payment` |
| OPOS | `dca_enriched.opos_payment` |

---

## Linking Debt Data to Customers

### Get customer details for accounts with DCA

```sql
SELECT
  dca.junifer_account_number,
  dca.dca_id,
  dca.account_status,
  c.first_name,
  c.last_name
FROM `soe-prod-data-core-7529.nova_be_tickets_enriched.dca_account_allocation` dca
JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.billing_account` ba
  ON dca.junifer_account_number = ba.account_number
  AND ba.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.customer` c
  ON ba.customer_id = c.id
  AND c.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
WHERE dca.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
```
