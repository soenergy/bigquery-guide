# Junifer Billing Data

Junifer is the core billing and energy platform. Contains accounts, bills, payments, meter points, and energy data.

## Getting Current State

**Always filter for current records:**
```sql
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
```

**Note**: Many Junifer tables require a partition filter on `meta_enriched_landed_timestamp`.

---

## junifer_enriched

### Account & Customer Tables

#### `account` - Billing accounts
~1M rows | Clustered by `id`, `meta_effective_to_timestamp`

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `number` | STRING | Account number (matches Nova billing_account.account_number) |
| `name` | STRING | Account name |
| `customer_fk` | INTEGER | FK to junifer customer |
| `account_type_fk` | INTEGER | Account type |
| `from_dttm` | TIMESTAMP | Account start date |
| `to_dttm` | TIMESTAMP | Account end date |
| `cancel_fl` | STRING | Cancelled flag (Y/N) |
| `closed_dttm` | TIMESTAMP | When closed |

**Common query - Active accounts:**
```sql
SELECT id, number, name, from_dttm
FROM `soe-prod-data-core-7529.junifer_enriched.account`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND cancel_fl != 'Y'
  AND (to_dttm IS NULL OR to_dttm > CURRENT_TIMESTAMP())
```

#### `customer` - Junifer customer record
~990K rows

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `number` | STRING | Customer number |
| `forename` | STRING | First name |
| `surname` | STRING | Last name |
| `state` | STRING | Customer state |
| `deceased_fl` | STRING | Deceased flag |

---

### Billing Tables

#### `bill` - Generated bills
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `account_fk` | INTEGER | FK to account |
| `bill_period_fk` | INTEGER | FK to bill_period |
| `status` | STRING | Bill status |
| `total_amount` | NUMERIC | Bill total |
| `created_dttm` | TIMESTAMP | When generated |

#### `bill_period` - Billing periods
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `from_dttm` | TIMESTAMP | Period start |
| `to_dttm` | TIMESTAMP | Period end |

#### `bill_breakdown_line` - Bill line items
| Column | Type | Description |
|--------|------|-------------|
| `bill_fk` | INTEGER | FK to bill |
| `line_type_fk` | INTEGER | Line type |
| `amount` | NUMERIC | Line amount |
| `description` | STRING | Description |

---

### Payment Tables

#### `payment` - Payments received
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `account_fk` | INTEGER | FK to account |
| `amount` | NUMERIC | Payment amount |
| `payment_method_fk` | INTEGER | Payment method |
| `created_dttm` | TIMESTAMP | When received |

#### `direct_debit` - DD setup
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `account_fk` | INTEGER | FK to account |
| `status` | STRING | DD status |
| `amount` | NUMERIC | DD amount |

#### `account_transaction` - All account transactions
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `account_fk` | INTEGER | FK to account |
| `transaction_type_fk` | INTEGER | Transaction type |
| `amount` | NUMERIC | Amount |
| `created_dttm` | TIMESTAMP | Transaction date |

---

### Metering Tables

#### `meter_point` - Supply points (MPAN/MPRN)
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `meter_point_service_type_fk` | INTEGER | Elec or Gas |

#### `mpan` - Electricity meter points
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `meter_point_fk` | INTEGER | FK to meter_point |
| `mpan_core` | STRING | MPAN identifier |
| `profile_class` | STRING | Profile class |

#### `mprn` - Gas meter points
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `meter_point_fk` | INTEGER | FK to meter_point |
| `mprn` | STRING | MPRN identifier |

#### `meter` - Physical meters
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `meter_point_fk` | INTEGER | FK to meter_point |
| `serial_number` | STRING | Meter serial |
| `meter_type_fk` | INTEGER | Meter type |

#### `meter_reading_manual` - Manual meter reads
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `meter_fk` | INTEGER | FK to meter |
| `reading_dttm` | TIMESTAMP | When read |

---

### Product & Pricing Tables

#### `product` - Billing products
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `name` | STRING | Product name |
| `code` | STRING | Product code |

#### `price_plan` - Pricing configuration
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `name` | STRING | Price plan name |

#### `product_bundle` - Bundled products
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `name` | STRING | Bundle name |

---

## Common Queries

### Account balance
```sql
SELECT
  a.number AS account_number,
  SUM(CASE WHEN t.transaction_type_fk IN (/* debit types */) THEN t.amount ELSE 0 END) AS debits,
  SUM(CASE WHEN t.transaction_type_fk IN (/* credit types */) THEN t.amount ELSE 0 END) AS credits
FROM `soe-prod-data-core-7529.junifer_enriched.account` a
JOIN `soe-prod-data-core-7529.junifer_enriched.account_transaction` t
  ON a.id = t.account_fk
  AND t.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
WHERE a.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
GROUP BY a.number
```

### Link account to meter point
```sql
-- Account → Product → Meter Point relationship
-- (Requires joining through product tables)
```
