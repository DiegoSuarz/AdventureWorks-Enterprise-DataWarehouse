# ADR-001 — Use Star Schema

## Status

**Accepted**

---

## Date

2026-08-07

---

## Context

The AdventureWorks Enterprise Data Warehouse requires a dimensional modeling approach capable of supporting analytical workloads, historical tracking, and business intelligence reporting.

Several dimensional modeling alternatives were considered.

The primary candidates were:

- Star Schema
- Snowflake Schema

The selected approach must balance simplicity, query performance, maintainability, and compatibility with reporting tools such as Power BI.

---

## Decision Drivers

The selected architecture should:

- maximize analytical performance;
- minimize query complexity;
- simplify ETL implementation;
- integrate naturally with Power BI;
- remain scalable for future dimensions and fact tables.

## Decision

The project adopts the **Star Schema** as the standard dimensional modeling architecture.

Fact tables store measurable business events.

Dimension tables provide descriptive analytical context.

The dimensional model follows the structure:

```text
                 DimDate
                    │
                    │
DimCustomer ─── FactSales ─── DimProduct
                    │
          ┌─────────┼─────────┐
          │         │         │
   DimSalesPerson   │   DimShipMethod
                    │
              DimTerritory
```

Every new analytical model introduced into the warehouse should follow this pattern unless a justified architectural exception exists.

---

## Alternatives Considered

### Option 1 — Star Schema (Selected)

Advantages:

- Simple query model.
- Fewer joins.
- Excellent Power BI compatibility.
- Faster analytical queries.
- Easier ETL implementation.
- Easier understanding for future contributors.

Disadvantages:

- Some controlled redundancy inside dimensions.

---

### Option 2 — Snowflake Schema

Advantages:

- Reduced redundancy.
- Higher normalization.

Disadvantages:

- More joins.
- More complex ETL.
- More difficult Power BI model.
- Reduced readability.
- Higher maintenance cost.

---

## Consequences

### Positive

- Simplified analytical queries.
- Predictable dimensional relationships.
- Consistent modeling strategy.
- Better reporting performance.
- Easier onboarding for future contributors.
- Better educational value for the project.

### Negative

- Slight increase in storage requirements due to denormalized dimensions.
- Some duplicated descriptive attributes across dimensions.

The advantages outweigh the disadvantages for an analytical warehouse.

---

## Related Documents

```text
docs/architecture/dimensional-model.md

docs/design/dimensions/

docs/design/facts/
```

---

## References

- Ralph Kimball — The Data Warehouse Toolkit
- Microsoft Dimensional Modeling Guidance

---

## Decision Owner

AdventureWorks Enterprise Data Warehouse Architecture

---

## Review Status

Current Status:

```text
Accepted
```

This ADR remains valid unless the project adopts a fundamentally different warehouse architecture.