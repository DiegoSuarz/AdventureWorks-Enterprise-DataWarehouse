# Slowly Changing Dimension Strategies

## 1. Purpose

This document defines the Slowly Changing Dimension (SCD) strategies used throughout the AdventureWorks Enterprise Data Warehouse.

The objective is to provide consistent rules for handling changes in dimensional attributes while preserving analytical accuracy, historical traceability, ETL idempotency, and dimensional integrity.

---

## 2. General Principle

Not every dimensional attribute requires the same historical treatment.

Each attribute must be explicitly classified according to its analytical requirements.

The project currently supports:

```text
SCD Type 0
SCD Type 1
SCD Type 2
```

The selected strategy is defined per attribute rather than automatically per dimension.

---

## 3. SCD Type 0 — Retain Original Value

Type 0 attributes are treated as immutable.

Once loaded into the Data Warehouse, their values are not changed by the ETL process.

Typical use cases include:

- immutable source identifiers;
- permanent classifications;
- attributes whose original value must always be preserved.

Example:

```text
dw.DimProduct.ProductID
```

`ProductID` represents the immutable source-system business key.

### Behavior

```text
Source value changes
        ↓
No dimensional update
```

Changes to a Type 0 attribute should normally be treated as a source-system anomaly and investigated rather than automatically propagated.

---

## 4. SCD Type 1 — Overwrite Current Value

Type 1 is used when the latest value is analytically sufficient and historical values are not required.

When a Type 1 attribute changes:

```text
Existing dimensional row
        ↓
UPDATE
        ↓
Previous value is overwritten
```

No new dimensional version is created.

Typical use cases include:

- spelling corrections;
- descriptive name corrections;
- non-historical presentation attributes;
- attributes where only the current state matters.

### Example — `DimProduct`

Type 1 attributes:

```text
ProductName
ProductNumber
```

Example:

```text
Before

ProductName = Mountain Bike

        ↓

Source correction

        ↓

After

ProductName = Mountain Bike Pro
```

The existing current row is updated.

No historical row is created.

---

## 5. SCD Type 2 — Preserve Historical Versions

Type 2 is used when historical values are analytically important.

When a Type 2 attribute changes:

```text
Current version
        ↓
Expire current version
        ↓
Insert new version
        ↓
Preserve previous version
```

Each version receives its own surrogate key.

Example:

```text
ProductKey | ProductID | ListPrice | IsCurrent
-----------|-----------|-----------|----------
187        | 514       | 133.34    | 0
505        | 514       | 233.34    | 1
```

Both rows represent the same business entity but different historical states.

---

## 6. Type 2 Attributes in `DimProduct`

The current Product dimension historizes the following attributes:

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

These attributes can affect historical analysis such as:

- product profitability;
- pricing analysis;
- category performance;
- historical product characteristics;
- product lifecycle reporting.

---

## 7. Surrogate Keys and Historical Versions

Every Type 2 version receives a different surrogate key.

Example:

```text
ProductID = 514
```

may correspond to:

```text
ProductKey = 187
ProductKey = 505
ProductKey = 506
```

while still representing the same source-system product.

Fact tables must reference the surrogate key representing the dimensional version valid at the time of the business event.

---

## 8. Historical Validity Columns

Dimensions prepared for Type 2 history use:

```text
EffectiveStartDateTime
EffectiveEndDateTime
IsCurrent
```

### EffectiveStartDateTime

Represents the timestamp when the dimensional version becomes valid.

### EffectiveEndDateTime

Represents the timestamp when the dimensional version stops being valid.

Current versions use:

```text
9999-12-31 23:59:59.9999999
```

as the open-ended validity timestamp.

### IsCurrent

Indicates whether the row represents the currently valid version.

```text
1 → Current
0 → Historical
```

---

## 9. Half-Open Validity Interval

Historical validity follows the interval:

```text
[EffectiveStartDateTime, EffectiveEndDateTime)
```

The start timestamp is inclusive.

The end timestamp is exclusive.

Example:

```text
Version 1

Start = 2026-01-01 00:00
End   = 2026-03-01 00:00

Version 2

Start = 2026-03-01 00:00
End   = 9999-12-31 23:59:59.9999999
```

Therefore:

```text
Version1.End = Version2.Start
```

This prevents temporal gaps and overlaps.

---

## 10. Single Load Timestamp

A Type 2 ETL execution must generate one load timestamp and reuse it throughout the dimensional change.

Example:

```sql
DECLARE @LoadDateTime DATETIME2(7) = SYSUTCDATETIME();
```

The same value must be used to:

```text
Expire previous version
        ↓
EffectiveEndDateTime = @LoadDateTime

Create new version
        ↓
EffectiveStartDateTime = @LoadDateTime
```

This guarantees continuous validity periods.

---

## 11. Current-Version Integrity

A business key must have at most one current dimensional version.

Preferred implementation:

```sql
CREATE UNIQUE INDEX UX_DimProduct_Current
ON dw.DimProduct(ProductID)
WHERE IsCurrent = 1;
```

The filtered unique index acts as both:

- an integrity mechanism;
- an ETL lookup optimization.

Historical rows are excluded from the uniqueness rule.

---

## 12. RowHash Change Detection

The project uses SHA2-256 hashes to detect attribute changes efficiently.

Example:

```sql
HASHBYTES
(
    'SHA2_256',
    ...
)
```

The result is stored as:

```text
VARBINARY(32)
```

Instead of comparing every historical attribute individually, ETL processes can compare:

```text
Source RowHash
        vs
Current Dimension RowHash
```

---

## 13. RowHash and SCD Classification

The hash must contain only the attributes relevant to the corresponding change strategy.

For `DimProduct`, `RowHash` contains only Type 2 attributes.

Example:

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

It intentionally excludes:

```text
ProductName
ProductNumber
```

because those attributes use Type 1 behavior.

This prevents a Type 1 correction from accidentally generating a Type 2 historical version.

---

## 14. NULL Handling in RowHash

Hash generation must distinguish between:

```text
NULL
```

and empty values where appropriate.

The project uses deterministic placeholders such as:

```text
<NULL>
```

Example:

```sql
COALESCE(Color, N'<NULL>')
```

This ensures stable and reproducible hashes between ETL executions.

---

## 15. Data Type Normalization Before Hashing

Values must be converted deterministically before inclusion in `RowHash`.

Examples:

### Decimal values

```sql
CONVERT
(
    NVARCHAR(50),
    CONVERT(DECIMAL(19,4), ListPrice)
)
```

### Date values

```sql
CONVERT
(
    NVARCHAR(30),
    SellStartDate,
    126
)
```

The objective is to guarantee that logically identical values always generate identical hash input strings.

---

## 16. SCD Type 2 Processing Flow

The standard Type 2 ETL flow is:

```text
Staging
   │
   ▼
Find current dimensional row
   │
   ▼
Compare RowHash
   │
   ├───────────────┐
   │               │
   ▼               ▼
Equal           Different
   │               │
No Type 2      Expire current
change             │
                   ▼
              Insert new version
```

New business keys bypass the comparison and are inserted directly as current members.

---

## 17. Type 1 and Type 2 Combined Processing

A dimension may contain both Type 1 and Type 2 attributes.

The ETL must distinguish these changes.

Conceptually:

```text
Business Key exists
        ↓
Check Type 2 RowHash
        │
        ├── Changed
        │      ↓
        │  Expire old version
        │      ↓
        │  Insert new version
        │
        └── Unchanged
               ↓
          Check Type 1 attributes
               ↓
             UPDATE
```

If Type 1 and Type 2 changes occur simultaneously, the new Type 2 version must contain the latest values for all attributes.

The historical row must not be unnecessarily modified before expiration.

---

## 18. Idempotency

Every dimensional ETL process must be idempotent.

Running the same load multiple times without source changes must produce no additional modifications.

Expected behavior:

```text
First execution
RowsInserted > 0

Second execution
RowsInserted = 0
RowsUpdated  = 0
```

For Type 2 dimensions, repeated loads must never create duplicate historical versions.

---

## 19. Historical Value Reappearance

If an attribute returns to a previous value, a new historical version must still be created.

Example:

```text
Version 1
ListPrice = 133.34

Version 2
ListPrice = 233.34

Version 3
ListPrice = 133.34
```

Version 3 is not the same validity period as Version 1.

Therefore, the first version must not be reactivated.

Historical versions represent periods of validity, not unique combinations of attribute values.

---

## 20. Missing Source Records

The absence of a business key from staging does not automatically imply deletion or deactivation.

This rule is especially important because staging may later use incremental loading.

Example:

```text
Record absent from incremental staging
```

may simply mean:

```text
No source change occurred.
```

Therefore:

> Missing staging records must not automatically expire dimensional members.

Logical deletion or lifecycle handling requires an explicit business rule or source indicator.

Examples could include:

```text
IsActive
DiscontinuedDate
Status
```

---

## 21. Future Deletion Strategy

Logical deletion handling will be introduced only when supported by a reliable source-system signal.

Possible strategies include:

```text
Explicit status attribute
Source CDC delete event
Business lifecycle date
Dedicated deletion feed
```

Physical deletion of historical dimensional rows is not allowed as part of normal ETL processing.

---

## 22. Historical Fact Lookup

When facts are loaded against a Type 2 dimension, the ETL must locate the version valid when the business event occurred.

Lookup rule:

```text
BusinessKey matches

AND

FactEventDate >= EffectiveStartDateTime

AND

FactEventDate < EffectiveEndDateTime
```

Example:

```text
Sale:
ProductID = 514
OrderDate = 2026-02-15

        ↓

Resolve ProductKey valid
on 2026-02-15
```

The current dimension member must not automatically be assigned to historical facts.

---

## 23. Audit Requirements

SCD ETL processes must record execution metrics through the common audit framework.

Relevant measures include:

```text
RowsRead
RowsInserted
RowsUpdated
RowsRejected
Status
ErrorMessage
```

For Type 2 changes:

```text
Expired current row
→ RowsUpdated

Inserted new version
→ RowsInserted
```

This allows operational reconciliation of dimensional loads.

---

## 24. Transactional Integrity

Expiration of the previous version and creation of the new version must occur within the same transaction.

Conceptually:

```text
BEGIN TRANSACTION

Expire current version
Insert new version

COMMIT
```

If any operation fails:

```text
ROLLBACK
```

This prevents dimensions from being left without a current version after partial ETL failure.

---

## 25. Validation Requirements

Every Type 2 implementation must validate:

- exactly one current version per business key;
- no overlapping validity periods;
- valid start and end timestamps;
- historical rows have `IsCurrent = 0`;
- current rows use the configured open-ended timestamp;
- Type 1 changes do not create historical versions;
- Type 2 changes create exactly one new version;
- repeated executions are idempotent;
- audit records match actual ETL operations.

---

## 26. Current Implementations

### `dw.DimDate`

```text
SCD Strategy: Not Applicable
Reason: Calendar dates are immutable.
```

### `dw.DimProduct`

```text
Type 0:
ProductID

Type 1:
ProductName
ProductNumber

Type 2:
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

### `dw.DimCustomer`

```text
Current Strategy:
SCD Type 1

Future:
Structurally prepared for selected Type 2 attributes.
```

---

## 27. Design Principles

The project follows these SCD principles:

1. Historical tracking is driven by analytical requirements.
2. SCD strategy is selected per attribute.
3. Type 1 corrections do not create unnecessary history.
4. Type 2 attributes preserve every period of validity.
5. Surrogate keys represent dimensional versions.
6. RowHash contains only attributes relevant to change detection.
7. Validity ranges use half-open intervals.
8. Only one current version may exist per business key.
9. ETL processing must be transactional.
10. ETL processing must be idempotent.
11. Missing staging records do not imply deletion.
12. Database constraints should enforce dimensional integrity whenever possible.

---

## 28. Related Documentation

Dimensional modeling principles:

```text
docs/architecture/dimensional-model.md
```

Dimension specifications:

```text
docs/design/dimensions/dim-date.md
docs/design/dimensions/dim-product.md
docs/design/dimensions/dim-customer.md
```

Related ETL standards:

```text
docs/architecture/etl-pattern.md
```

---

## 29. Architecture Status

```text
Architecture: Approved
Supported Strategies: Type 0, Type 1, Type 2
Change Detection: SHA2-256 RowHash
Temporal Model: Half-open intervals [Start, End)
Current Production Example: dw.DimProduct
Current Release: v1.1.0
```