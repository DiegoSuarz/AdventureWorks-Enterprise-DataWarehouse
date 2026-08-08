# Dimensional Modeling Architecture

## 1. Purpose

This document defines the dimensional modeling principles used throughout the AdventureWorks Enterprise Data Warehouse.

The goal is to provide a consistent analytical architecture for dimensions and fact tables while preserving historical accuracy, maintainability, scalability, and clear separation between operational and analytical workloads.

---

## 2. Modeling Approach

The Enterprise Data Warehouse follows a **Star Schema** modeling approach.

Fact tables represent measurable business processes, while dimension tables provide descriptive analytical context.

Conceptually:

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

The star schema is preferred because it:

- simplifies analytical queries;
- provides predictable relationships;
- supports efficient aggregations;
- integrates naturally with Power BI;
- separates descriptive attributes from measurable events.

---

## 3. Fact Table Design

Fact tables represent measurable business processes.

Before designing a fact table, its grain must be explicitly defined.

The grain answers:

> What does one row in this fact table represent?

For the planned `dw.FactSales` table:

```text
One row = one sales order line
```

The source grain corresponds primarily to:

```text
AdventureWorks2022.Sales.SalesOrderDetail
```

Each fact row will reference the dimensional context applicable to that transaction.

---

## 4. Dimension Design

Dimensions provide descriptive context for business events.

Examples include:

```text
dw.DimDate
dw.DimProduct
dw.DimCustomer
dw.DimTerritory
dw.DimSalesPerson
dw.DimShipMethod
```

Each dimension must define:

- its grain;
- its business key;
- its surrogate key strategy;
- descriptive attributes;
- Slowly Changing Dimension strategy;
- validation rules;
- indexing requirements.

Every dimension must have a corresponding Design Specification under:

```text
docs/design/dimensions/
```

---

## 5. Surrogate Keys

Fact tables reference dimensions using warehouse-generated surrogate keys rather than source-system business keys.

Example:

```text
Source system

ProductID = 514

        ↓

Data Warehouse

ProductKey = 505
```

The surrogate key represents a specific dimensional member or historical version.

Advantages include:

- independence from source-system identifiers;
- support for historical versions;
- consistent fact-to-dimension relationships;
- protection against business-key changes;
- easier integration of multiple source systems in the future.

---

## 6. Business Keys

Business keys identify entities in the source system.

Examples:

```text
DimProduct
Business Key → ProductID

DimCustomer
Business Key → CustomerID
```

Business keys are retained in dimensional tables for:

- source reconciliation;
- ETL matching;
- troubleshooting;
- auditability.

Fact tables should normally reference surrogate keys rather than business keys.

---

## 7. Slowly Changing Dimensions

The project supports multiple Slowly Changing Dimension strategies.

### Type 0

Attributes are treated as immutable.

Example:

```text
ProductID
```

### Type 1

Changes overwrite the current value.

No history is preserved.

Example:

```text
DimProduct.ProductName
```

### Type 2

Changes generate a new dimensional version.

Historical values remain available.

Example:

```text
DimProduct.ListPrice
```

Detailed SCD rules are defined in:

```text
docs/architecture/scd-strategies.md
```

---

## 8. Historical Validity Model

Dimensions supporting historical versions use:

```text
EffectiveStartDateTime
EffectiveEndDateTime
IsCurrent
```

Validity follows a half-open interval:

```text
[EffectiveStartDateTime, EffectiveEndDateTime)
```

Example:

```text
Version 1
2026-01-01 00:00
        ↓
2026-03-01 00:00

Version 2
2026-03-01 00:00
        ↓
9999-12-31 23:59:59.9999999
```

The end timestamp of one version equals the start timestamp of the next version.

This prevents temporal gaps and overlaps.

---

## 9. Current-Version Integrity

Dimensions capable of historical versioning must guarantee that a business key has at most one current version.

The preferred implementation is a filtered unique index.

Example:

```sql
CREATE UNIQUE INDEX UX_DimProduct_Current
ON dw.DimProduct(ProductID)
WHERE IsCurrent = 1;
```

This protects dimensional integrity even if the ETL process contains an error.

---

## 10. Unknown Members

Dimensions may require a special member representing missing or unresolved dimensional relationships.

Conceptually:

```text
Unknown
Not Applicable
Missing
```

Unknown-member handling will be introduced where required by fact-loading requirements.

The design must prevent fact rows from failing solely because a dimensional lookup cannot be resolved.

---

## 11. Role-Playing Dimensions

A physical dimension may represent multiple analytical roles.

`dw.DimDate` will be reused by `FactSales` as:

```text
OrderDateKey
DueDateKey
ShipDateKey
```

All three foreign keys reference the same physical date dimension while representing different business meanings.

---

## 12. Degenerate Dimensions

Transactional identifiers that provide analytical value but do not require their own descriptive dimension may be stored directly in the fact table.

Examples:

```text
SalesOrderID
SalesOrderDetailID
```

These identifiers support:

- drill-through;
- reconciliation;
- distinct order counting;
- traceability to the source transaction.

A separate `DimOrder` will not be created unless a future analytical requirement justifies it.

---

## 13. Conformed Dimensions

Dimensions intended to be shared across multiple fact tables are treated as conformed dimensions.

Examples include:

```text
DimDate
DimProduct
DimCustomer
DimTerritory
```

A conformed dimension must preserve consistent:

- business definitions;
- keys;
- attribute meanings;
- SCD behavior.

This ensures that metrics from different fact tables remain analytically comparable.

---

## 14. Separation of Business Concepts

Each dimension should represent a clearly defined analytical concept.

For example:

```text
DimCustomer
→ Customer identity

DimTerritory
→ Sales geography

DimProduct
→ Product characteristics
```

Attributes should not be duplicated across dimensions without a justified analytical requirement.

This principle is the reason customer geography is not stored directly in `DimCustomer`.

---

## 15. Fact-to-Dimension Historical Lookup

When loading facts against a Type 2 dimension, the ETL must resolve the dimensional version valid at the time of the business event.

Conceptually:

```text
BusinessKey matches

AND

FactDate >= EffectiveStartDateTime

AND

FactDate < EffectiveEndDateTime
```

Example:

```text
Sale Date = 2025-04-10
ProductID = 514

        ↓

Resolve ProductKey that was valid
on 2025-04-10
```

The current dimensional version must not automatically be assigned to historical transactions.

---

## 16. Model Integrity Principles

The dimensional model follows these rules:

1. Fact table grain must be defined before implementation.
2. Dimensions use surrogate keys.
3. Source business keys are retained for reconciliation.
4. Fact tables reference dimensional surrogate keys.
5. Historical dimensions use non-overlapping validity intervals.
6. A business key may have at most one current dimensional version.
7. SCD strategy is selected per attribute based on analytical requirements.
8. Dimensions should represent clearly separated business concepts.
9. Analytical relationships must not depend directly on OLTP keys.
10. Database constraints and indexes should enforce integrity whenever practical.

---

## 17. Current Dimensional Model

### Implemented

```text
dw.DimDate
dw.DimProduct
```

### Designed

```text
dw.DimCustomer
```

### Planned

```text
dw.DimTerritory
dw.DimSalesPerson
dw.DimShipMethod
dw.FactSales
```

---

## 18. Related Documentation

Object-specific design specifications:

```text
docs/design/dimensions/dim-date.md
docs/design/dimensions/dim-product.md
docs/design/dimensions/dim-customer.md
```

Future fact-table specification:

```text
docs/design/facts/fact-sales.md
```

Related architecture documentation:

```text
docs/architecture/etl-pattern.md
docs/architecture/scd-strategies.md
docs/architecture/naming-conventions.md
```

---

## 19. Architecture Status

```text
Architecture: Approved
Modeling Pattern: Star Schema
Primary Warehouse: AdventureWorks_EDW
Current Release: v1.1.0
Next Target Release: v1.2.0
```