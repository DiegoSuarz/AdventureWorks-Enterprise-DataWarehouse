# Design Specification — `dw.DimProduct`

## 1. Objective

Design and implement the `dw.DimProduct` dimension to provide a historical analytical representation of AdventureWorks products.

The dimension preserves attribute history using Slowly Changing Dimension Type 2 (SCD Type 2) while supporting Type 1 updates for selected attributes.

---

## 2. Source

### Primary source

- `AdventureWorks2022.Production.Product`

### Additional sources

- `AdventureWorks2022.Production.ProductSubcategory`
- `AdventureWorks2022.Production.ProductCategory`

### Source relationships

```text
Production.Product
        │
        └── ProductSubcategoryID
                  │
                  ▼
Production.ProductSubcategory
                  │
                  ▼
Production.ProductCategory
```

---

## 3. Grain

One row represents one historical version of a product identified by `ProductID`.

Whenever a Type 2 attribute changes, a new dimensional version is created.

---

## 4. Business Key

```text
ProductID
```

`ProductID` uniquely identifies a product in AdventureWorks.

---

## 5. Surrogate Key

```text
ProductKey
```

Recommended definition:

```sql
BIGINT IDENTITY(1,1)
```

Fact tables reference `ProductKey` rather than `ProductID`.

---

## 6. Columns

| Column | Data Type | Nullable | Purpose |
|---|---|:---:|---|
| `ProductKey` | BIGINT | No | Surrogate key |
| `ProductID` | INT | No | Business key |
| `ProductName` | NVARCHAR(200) | No | Product name |
| `ProductNumber` | NVARCHAR(25) | No | Product code |
| `Color` | NVARCHAR(15) | Yes | Product color |
| `Size` | NVARCHAR(10) | Yes | Product size |
| `StandardCost` | MONEY | No | Product standard cost |
| `ListPrice` | MONEY | No | Product list price |
| `SubcategoryName` | NVARCHAR(100) | Yes | Product subcategory |
| `CategoryName` | NVARCHAR(100) | Yes | Product category |
| `SellStartDate` | DATETIME | Yes | Sales availability start |
| `SellEndDate` | DATETIME | Yes | Sales availability end |
| `DiscontinuedDate` | DATETIME | Yes | Product discontinuation |
| `EffectiveStartDateTime` | DATETIME2(7) | No | Version start |
| `EffectiveEndDateTime` | DATETIME2(7) | No | Version end |
| `IsCurrent` | BIT | No | Current version indicator |
| `RowHash` | VARBINARY(32) | No | Change detection |
| `SourceModifiedDate` | DATETIME2(0) | No | Source modification |
| `CreatedAt` | DATETIME2(7) | No | ETL creation timestamp |

---

## 7. SCD Strategy

### Type 1 Attributes

The following attributes overwrite the current version:

- `ProductName`
- `ProductNumber`

### Type 2 Attributes

The following attributes create a new historical version:

- `Color`
- `Size`
- `StandardCost`
- `ListPrice`
- `SubcategoryName`
- `CategoryName`
- `SellStartDate`
- `SellEndDate`
- `DiscontinuedDate`

---

## 8. RowHash Strategy

`RowHash` is calculated **only** using Type 2 attributes.

Included columns:

```text
Color
Size
StandardCost
ListPrice
SubcategoryName
CategoryName
SellStartDate
SellEndDate
DiscontinuedDate
```

Hash algorithm:

```text
SHA2-256
```

Purpose:

- Detect historical changes.
- Avoid unnecessary comparisons.
- Keep Type 1 and Type 2 processing independent.

---

## 9. Versioning Strategy

When a Type 2 change is detected:

```text
Expire current version
        ↓
Insert new version
        ↓
Set IsCurrent = 1
```

Validity interval:

```text
[EffectiveStartDateTime,
 EffectiveEndDateTime)
```

The end timestamp is exclusive.

---

## 10. Keys and Constraints

### Primary Key

```text
PK_DimProduct
(ProductKey)
```

### Current-version uniqueness

```sql
CREATE UNIQUE INDEX UX_DimProduct_Current
ON dw.DimProduct(ProductID)
WHERE IsCurrent = 1;
```

Guarantees that only one current version exists per product.

---

## 11. Indexes

Initial indexes:

```text
PK_DimProduct
→ ProductKey

UX_DimProduct_Current
→ ProductID
→ WHERE IsCurrent = 1
```

Additional indexes will be introduced based on analytical workload.

---

## 12. Business Rules

1. `ProductID` is immutable.
2. Only one current version may exist.
3. Historical versions are preserved.
4. Type 1 changes never create history.
5. Type 2 changes always create history.
6. Missing products are not automatically treated as deleted.
7. Historical validity periods must never overlap.

---

## 13. Staging Object

```text
stg.Product
```

The staging table stores the current consolidated state extracted from AdventureWorks.

No history is stored in staging.

---

## 14. ETL Objects

```text
etl.LoadProductStage
etl.LoadDimProduct
```

Expected flow:

```text
AdventureWorks2022
        ↓
stg.Product
        ↓
RowHash comparison
        ↓
Type 1 detection
        ↓
Type 2 detection
        ↓
dw.DimProduct
```

---

## 15. Validation Criteria

Implementation is considered complete when:

- Initial full load succeeds.
- Consecutive executions are idempotent.
- Type 1 changes update the current row.
- Type 2 changes create new historical versions.
- Returning a previous value creates a new version.
- Exactly one current version exists for each product.
- No overlapping validity periods exist.
- ETL execution is audited.

---

## 16. Status

```text
Design: Approved
Implementation: Completed
Release: v1.1.0
Module: Dimension History Management
```

## 17. Design Decisions (ADR Summary)

## 17. Design Decisions (ADR Summary)

| ID | Decision | Rationale |
|----|----------|-----------|
| ADR-001 | Product uses SCD Type 2 | Preserve historical product attributes. |
| ADR-002 | RowHash includes only Type 2 attributes | Separate Type 1 and Type 2 processing. |
| ADR-003 | Missing products are not treated as deleted | Deletions will be handled by a future lifecycle strategy. |
| ADR-004 | Current versions protected by filtered unique index | Guarantee one active version per ProductID. |
| ADR-005 | Validity interval uses [Start, End) | Prevent overlapping historical periods. |