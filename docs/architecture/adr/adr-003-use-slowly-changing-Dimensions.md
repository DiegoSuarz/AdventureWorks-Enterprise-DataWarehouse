# ADR-003 — Use Slowly Changing Dimensions

## Status

**Accepted**

---

## Date

2026-08-07

---

## Context

Business entities evolve over time.

Products change price, customers update their information, territories are reorganized, and business classifications may change throughout the lifetime of the Data Warehouse.

A fundamental architectural decision is determining how these changes should be represented analytically.

Two broad alternatives were considered:

- Always overwrite existing values.
- Preserve historical changes when they provide analytical value.

The selected strategy must support accurate historical reporting while maintaining a maintainable and scalable ETL architecture.

---

## Decision Drivers

The selected approach should:

- preserve business history where analytically valuable;
- maintain historical accuracy in reporting;
- support future business growth;
- avoid unnecessary data duplication;
- allow different historical behaviors for different attributes.

---

## Decision

The project adopts **Slowly Changing Dimensions (SCD)** as the standard strategy for managing dimensional changes.

Rather than applying a single historical strategy to an entire dimension, each attribute is evaluated independently and assigned the most appropriate SCD behavior.

The supported strategies are:

```text
Type 0
Type 1
Type 2
```

This provides the flexibility to preserve history only where it delivers analytical value.

---

## Selected Strategies

### Type 0

Immutable attributes.

Examples:

```text
ProductID

CustomerID

DateKey
```

Once loaded, these values are never modified.

---

### Type 1

Current-state attributes.

Changes overwrite the existing value.

Example:

```text
ProductName

ProductNumber
```

Historical values are not preserved.

---

### Type 2

Historical attributes.

Changes generate a new dimensional version.

Example:

```text
ListPrice

StandardCost

CategoryName

Color
```

Previous versions remain available for historical analysis.

---

## Why Attribute-Level Classification?

The project intentionally classifies SCD behavior **per attribute**, not per dimension.

Example:

```text
DimProduct

ProductName
↓

Type 1

ListPrice
↓

Type 2
```

This approach minimizes unnecessary history while preserving meaningful business changes.

---

## Alternatives Considered

### Option 1 — Attribute-Level SCD (Selected)

Advantages:

- Maximum flexibility.
- Historical tracking only where needed.
- Reduced storage growth.
- Better analytical accuracy.
- Easier evolution of dimensions over time.

Disadvantages:

- Slightly more complex ETL implementation.

---

### Option 2 — Entire Dimension Uses One SCD Type

Advantages:

- Simpler implementation.
- Easier to understand initially.

Disadvantages:

- Too rigid.
- Creates unnecessary history.
- Prevents mixing Type 1 and Type 2 attributes.
- Less aligned with real business requirements.

---

## Consequences

### Positive

- Business history is preserved where valuable.
- Current-state attributes remain simple.
- ETL logic remains predictable.
- Historical reporting becomes possible.
- Future dimensions follow a common strategy.

### Negative

- ETL implementation becomes more sophisticated.
- Additional metadata is required.
- Historical dimensions consume more storage.

These trade-offs are appropriate for an Enterprise Data Warehouse.

---

## Implementation Principles

Type 2 dimensions use:

```text
EffectiveStartDateTime

EffectiveEndDateTime

IsCurrent
```

Historical versions are identified using surrogate keys.

Current versions are protected by filtered unique indexes.

Changes are detected using SHA2-256 RowHash values.

---

## Current Implementations

### `dw.DimDate`

```text
No SCD

Dates are immutable.
```

### `dw.DimProduct`

```text
Type 0
ProductID

Type 1
ProductName
ProductNumber

Type 2
Color
Size
StandardCost
ListPrice
CategoryName
SubcategoryName
SellStartDate
SellEndDate
DiscontinuedDate
```

### `dw.DimCustomer`

```text
Current implementation:

Type 1

Future:

Prepared for selected Type 2 attributes.
```

---

## Long-Term Impact

This decision establishes the historical modeling standard for every future dimension.

Examples:

```text
DimCustomer

DimTerritory

DimSalesPerson

DimShipMethod
```

Each new dimension will explicitly define its SCD strategy during the design phase.

---

## Related Documents

```text
docs/architecture/scd-strategies.md

docs/architecture/dimensional-model.md

docs/design/dimensions/dim-product.md

docs/design/dimensions/dim-customer.md
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

This ADR remains valid unless the project adopts a fundamentally different strategy for handling dimensional changes.