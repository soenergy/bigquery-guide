# Nova Platform Data

Nova is the CRM and customer management system. Data is split across multiple microservices.

## Getting Current State

**Always filter for current records:**
```sql
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
```

---

## nova_be_customers_enriched

**Purpose**: Core customer data - profiles, contacts, addresses, billing accounts

### Key Tables

#### `customer` - Main customer record
~1.1M rows | Clustered by `id`

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `number` | STRING | Customer reference number |
| `first_name` | STRING | First name |
| `last_name` | STRING | Last name |
| `state` | STRING | Customer state (ACTIVE, CANCELLED, etc.) |
| `class` | STRING | Customer class |
| `type` | STRING | Customer type |
| `created_at` | TIMESTAMP | When customer was created |
| `deleted` | TIMESTAMP | When deleted (NULL if active) |
| `deceased` | BOOLEAN | Deceased flag |

**Common query - Active customers:**
```sql
SELECT id, number, first_name, last_name, state, created_at
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.customer`
WHERE meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND deleted IS NULL
  AND state = 'ACTIVE'
```

#### `contact` - Contact details
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `customer_id` | INTEGER | FK to customer |
| `type` | STRING | Contact type (EMAIL, PHONE, etc.) |
| `value` | STRING | The contact value |

#### `address` - Customer addresses
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `line1`, `line2`, `line3` | STRING | Address lines |
| `postcode` | STRING | Postcode |
| `city` | STRING | City |

#### `billing_account` - Billing account link
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `customer_id` | INTEGER | FK to customer |
| `account_number` | STRING | Billing account number |

### Other Notable Tables

- `cancellation_reasons` - Why customers cancelled
- `cancellations` - Cancellation records
- `customer_referrals` - Referral tracking
- `enrolment` - Customer enrolment records
- `smart_meter_bookings` - Smart meter installation bookings
- `warm_home_discount_application` - WHD applications
- `psr__psr_customer` - Priority Services Register data

---

## nova_be_products_enriched

**Purpose**: Product catalog, tariffs, and quotes

### Key Tables

#### `product` - Products/tariffs
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `name` | STRING | Product name |
| `code` | STRING | Product code |
| `type` | STRING | ELEC, GAS, DUAL |

#### `product_rate` - Pricing
| Column | Type | Description |
|--------|------|-------------|
| `product_id` | INTEGER | FK to product |
| `rate_type` | STRING | Standing charge, unit rate, etc. |
| `value` | NUMERIC | Rate value |

#### `quote` - Customer quotes
| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `customer_id` | INTEGER | FK to customer |
| `product_id` | INTEGER | FK to product |
| `status` | STRING | Quote status |
| `created_at` | TIMESTAMP | When quote was created |

---

## nova_be_tickets_enriched

**Purpose**: Dunning/debt collection workflows

### Key Tables

- `dunning_workflow` - Collection workflow instances
- `dunning_job` - Scheduled dunning jobs
- `dca_account_allocation` - DCA allocations

---

## Linking Nova to Junifer

Nova customer → Junifer account relationship:

```sql
-- Get customer with their Junifer account
SELECT
  c.id AS nova_customer_id,
  c.number AS nova_customer_number,
  c.first_name,
  c.last_name,
  ba.account_number AS junifer_account_number
FROM `soe-prod-data-core-7529.nova_be_customers_enriched.customer` c
LEFT JOIN `soe-prod-data-core-7529.nova_be_customers_enriched.billing_account` ba
  ON c.id = ba.customer_id
  AND ba.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
WHERE c.meta_effective_to_timestamp = TIMESTAMP('9999-01-01')
  AND c.deleted IS NULL
```
