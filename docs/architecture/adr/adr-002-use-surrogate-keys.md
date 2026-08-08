# ADR-002 — Use Surrogate Keys

## Status

**Accepted**

---

## Date

2026-08-07

---

## Context

The Enterprise Data Warehouse integrates data from operational systems into a dimensional model optimized for analytics.

A fundamental design decision is how fact tables should reference dimension members.

Two alternatives were considered:

- Use source-system business keys directly.
- Introduce warehouse-generated surrogate keys.

The chosen approach must support historical tracking, maintain referential integrity, and remain scalable as additional source systems are incorporated.

---

## Decision Drivers

The selected key strategy should:

- support Slowly Changing Dimensions (SCD);
- preserve historical accuracy;
- isolate the warehouse from source-system changes;
- simplify future data integration;
- provide stable and immutable references for fact tables.

---

## Decision

The project adopts **surrogate keys** as the primary identifiers for all dimensional tables.

Each dimension generates its own warehouse-specific key using an `IDENTITY` column.

Business keys from the source systems are retained for reconciliation and ETL matching but are never used as foreign keys in fact tables.

Example:

```text
Source System

ProductID = 514

        │
        ▼

Data Warehouse

ProductKey = 505
```

Fact tables always reference `ProductKey`, not `ProductID`.

---

## Alternatives Considered

### Option 1 — Surrogate Keys (Selected)

Advantages:

- Supports historical versions (SCD Type 2).
- Stable warehouse identifiers.
- Decouples the warehouse from operational systems.
- Simplifies future integration of multiple source systems.
- Prevents issues caused by business key changes.

Disadvantages:

- Introduces an additional lookup during ETL.
- Requires maintaining surrogate key relationships.

---

### Option 2 — Business Keys

Advantages:

- Simpler ETL implementation.
- No surrogate lookup required.
- Fewer columns.

Disadvantages:

- Cannot distinguish historical versions.
- Strong dependency on source-system identifiers.
- Difficult to integrate multiple source systems.
- Business key changes propagate throughout the warehouse.

---

## Consequences

### Positive

- Historical dimension versions receive unique identifiers.
- Fact tables remain historically accurate.
- The warehouse is independent of source-system implementation details.
- Future integrations become significantly easier.
- SCD Type 2 is fully supported.

### Negative

- ETL requires dimension lookups.
- Surrogate keys have no business meaning outside the warehouse.

These trade-offs are acceptable for an analytical data warehouse.

---

## Examples

### `dw.DimProduct`

```text
ProductKey → Surrogate Key
ProductID  → Business Key
```

### `dw.DimCustomer`

```text
CustomerKey → Surrogate Key
CustomerID  → Business Key
```

### `dw.DimDate`

```text
DateKey → Surrogate Key
FullDate → Business Identifier
```

Future fact tables:

```text
FactSales

ProductKey
CustomerKey
DateKey
```

---

## Consequences for ETL

Dimension loading:

```text
Business Key

↓

Lookup Current Member

↓

Generate Surrogate Key (if new)

↓

Load Dimension
```

Fact loading:

```text
Business Key

↓

Lookup Surrogate Key

↓

Load Fact Table
```

This guarantees that facts reference the correct dimensional member.

---

## Related Documents

```text
docs/architecture/dimensional-model.md

docs/architecture/scd-strategies.md

docs/design/dimensions/
```

---

## References

- Ralph Kimball — The Data Warehouse Toolkit
- Microsoft SQL Server Data Warehouse Guidance

---

## Decision Owner

AdventureWorks Enterprise Data Warehouse Architecture

---

## Review Status

Current Status:

```text
Accepted
```

This ADR remains valid unless the project adopts a different dimensional modeling strategy.