# Design Specification — `dw.DimCustomer`

## 1. Objective

Design and implement the `dw.DimCustomer` dimension to provide a consistent analytical representation of AdventureWorks customers.

The dimension must support both individual customers and store customers, provide business-friendly descriptive attributes, and remain structurally ready for future Slowly Changing Dimension Type 2 evolution.

---

## 2. Source

### Primary source

- `AdventureWorks2022.Sales.Customer`

### Additional sources

- `AdventureWorks2022.Person.Person`
- `AdventureWorks2022.Sales.Store`

### Source relationships

```text
Sales.Customer
│
├── PersonID → Person.Person.BusinessEntityID
│
└── StoreID  → Sales.Store.BusinessEntityID
```

Source exploration identified three valid customer configurations:

| Configuration | PersonType | Count |
|---|---|---:|
| Person only | `IN` | 18,484 |
| Person + Store | `SC` | 635 |
| Store only | `NULL` | 701 |

This confirms that a customer containing both `PersonID` and `StoreID` represents a **Store customer with an associated Store Contact**, rather than an individual customer.

---

## 3. Grain

One row represents one analytical version of a customer identified by `CustomerID`.

For the current implementation, customer attributes will be maintained primarily using SCD Type 1 behavior.

The table structure remains prepared for future SCD Type 2 historical versions.

---

## 4. Business Key

```text
CustomerID
```

`CustomerID` uniquely identifies a customer in the AdventureWorks Sales domain.

---

## 5. Surrogate Key

```text
CustomerKey
```

Recommended definition:

```sql
BIGINT IDENTITY(1,1)
```

`CustomerKey` will be used by fact tables instead of the source-system `CustomerID`.

---

## 6. Columns

| Column | Data Type | Nullable | Purpose |
|---|---|:---:|---|
| `CustomerKey` | `BIGINT` | No | Surrogate key |
| `CustomerID` | `INT` | No | Source business key |
| `CustomerType` | `NVARCHAR(20)` | No | `Individual`, `Store`, or `Unknown` |
| `CustomerName` | `NVARCHAR(200)` | No | Business-friendly customer name |
| `FirstName` | `NVARCHAR(50)` | Yes | Individual customer first name |
| `MiddleName` | `NVARCHAR(50)` | Yes | Individual customer middle name |
| `LastName` | `NVARCHAR(50)` | Yes | Individual customer last name |
| `StoreName` | `NVARCHAR(200)` | Yes | Store customer name |
| `AccountNumber` | `NVARCHAR(20)` | No | AdventureWorks account identifier |
| `EffectiveStartDateTime` | `DATETIME2(7)` | No | Beginning of version validity |
| `EffectiveEndDateTime` | `DATETIME2(7)` | No | End of version validity |
| `IsCurrent` | `BIT` | No | Identifies the current version |
| `RowHash` | `VARBINARY(32)` | No | Detects customer attribute changes |
| `SourceModifiedDate` | `DATETIME2(0)` | No | Latest relevant source modification |
| `CreatedAt` | `DATETIME2(7)` | No | EDW record creation timestamp |

---

## 7. Customer Type Rules

Customer classification is based primarily on `StoreID`.

### Store Customer

A customer is classified as `Store` whenever:

```sql
StoreID IS NOT NULL
```

This rule has priority over `PersonID`.

AdventureWorks contains customers where both values exist:

```text
PersonID IS NOT NULL
StoreID  IS NOT NULL
PersonType = SC
```

In these cases, `PersonID` represents a **Store Contact**, not the customer itself.

### Individual Customer

A customer is classified as `Individual` when:

```sql
StoreID IS NULL
AND PersonID IS NOT NULL
```

The corresponding `Person.Person.PersonType` is expected to be:

```text
IN
```

### Unknown Customer

If neither relationship exists:

```text
CustomerType = Unknown
CustomerName = Unknown Customer
```

Recommended derivation:

```sql
CASE
    WHEN c.StoreID IS NOT NULL
        THEN N'Store'

    WHEN c.PersonID IS NOT NULL
        THEN N'Individual'

    ELSE N'Unknown'
END
```

---

## 8. Customer Name Rules

### Store Customer

For store customers:

```text
CustomerName = StoreName
```

Recommended implementation:

```sql
COALESCE
(
    NULLIF(LTRIM(RTRIM(s.Name)), N''),
    N'Unknown Customer'
)
```

For stores containing an associated `PersonID`, the person represents a Store Contact and does not determine the analytical customer name.

### Individual Customer

For individual customers:

```text
CustomerName =
FirstName + MiddleName + LastName
```

Null or empty name components must not generate duplicated spaces.

Recommended implementation:

```sql
COALESCE
(
    NULLIF
    (
        CONCAT_WS
        (
            N' ',
            NULLIF(LTRIM(RTRIM(p.FirstName)), N''),
            NULLIF(LTRIM(RTRIM(p.MiddleName)), N''),
            NULLIF(LTRIM(RTRIM(p.LastName)), N'')
        ),
        N''
    ),
    N'Unknown Customer'
)
```

### Unknown Customer

```text
CustomerName = Unknown Customer
```

---

## 9. Person Attribute Rules

`FirstName`, `MiddleName`, and `LastName` represent attributes of an **Individual customer only**.

For Individual customers:

```text
FirstName  = Person.Person.FirstName
MiddleName = Person.Person.MiddleName
LastName   = Person.Person.LastName
StoreName  = NULL
```

For Store customers:

```text
FirstName  = NULL
MiddleName = NULL
LastName   = NULL
StoreName  = Sales.Store.Name
```

Even when a Store customer contains a `PersonID`, the associated person represents a Store Contact and is intentionally excluded from `DimCustomer`.

Store Contact analysis is considered a separate analytical concept and may be modeled independently in the future if required.

---

## 10. SourceModifiedDate Rule

`dw.DimCustomer` combines attributes from multiple source tables.

However, only source entities that contribute actual attributes to the dimensional member should influence `SourceModifiedDate`.

### Individual Customer

Relevant sources:

```text
Sales.Customer.ModifiedDate
Person.Person.ModifiedDate
```

Conceptually:

```text
SourceModifiedDate =
MAX(
    Customer.ModifiedDate,
    Person.ModifiedDate
)
```

### Store Customer

Relevant sources:

```text
Sales.Customer.ModifiedDate
Sales.Store.ModifiedDate
```

Conceptually:

```text
SourceModifiedDate =
MAX(
    Customer.ModifiedDate,
    Store.ModifiedDate
)
```

`Person.Person.ModifiedDate` is intentionally excluded for Store customers because the associated person represents a Store Contact and its attributes are not stored in `DimCustomer`.

This ensures that changes unrelated to the dimensional representation do not trigger unnecessary customer updates.

---

## 11. SCD Strategy

### Current Strategy

```text
SCD Type 1
```

Changes to customer descriptive attributes overwrite the current dimensional version.

Type 1 attributes include:

```text
CustomerType
CustomerName
FirstName
MiddleName
LastName
StoreName
AccountNumber
```

No historical version is generated for these changes in the current release.

### Future Readiness

The table includes:

```text
EffectiveStartDateTime
EffectiveEndDateTime
IsCurrent
```

so selected attributes may later migrate to SCD Type 2 without requiring structural changes to the dimension.

---

## 12. RowHash Strategy

`RowHash` will represent the dimensional attributes maintained using Type 1 behavior.

Included attributes:

```text
CustomerType
CustomerName
FirstName
MiddleName
LastName
StoreName
AccountNumber
```

Hash algorithm:

```text
SHA2-256
```

Behavior:

```text
RowHash unchanged
→ No dimensional update

RowHash changed
→ Apply SCD Type 1 UPDATE
```

For Store customers:

```text
FirstName
MiddleName
LastName
```

will consistently contribute their normalized `NULL` representation rather than Store Contact values.

This prevents Store Contact changes from generating false customer-dimension changes.

---

## 13. Keys and Constraints

### Primary Key

```text
PK_DimCustomer
(CustomerKey)
```

### Current-Version Uniqueness

Only one current dimensional version may exist for each `CustomerID`.

Recommended filtered unique index:

```sql
CREATE UNIQUE INDEX UX_DimCustomer_Current
ON dw.DimCustomer(CustomerID)
WHERE IsCurrent = 1;
```

This protects the dimension against multiple current versions for the same business key.

---

## 14. Indexes

Initial indexes:

```text
PK_DimCustomer
→ CustomerKey

UX_DimCustomer_Current
→ CustomerID
→ WHERE IsCurrent = 1
```

Additional indexes will only be introduced after observing real ETL or analytical access patterns.

---

## 15. Business Rules

1. `CustomerID` is the immutable business key.
2. Every customer must have exactly one current version.
3. `StoreID` takes precedence over `PersonID` when determining `CustomerType`.
4. `StoreID IS NOT NULL` identifies a Store customer.
5. `StoreID IS NULL AND PersonID IS NOT NULL` identifies an Individual customer.
6. A `PersonID` associated with a Store represents a Store Contact and is not part of the customer identity.
7. `CustomerName` must never be `NULL`.
8. Person-name attributes are populated only for Individual customers.
9. `StoreName` is populated only for Store customers.
10. `SourceModifiedDate` must consider only source entities contributing attributes to the dimensional member.
11. Geography will not be stored in `DimCustomer`.
12. Sales geography will be modeled independently through `DimTerritory`.
13. Missing customers in staging will not automatically be treated as deleted.
14. Store Contact data will not be modeled inside `DimCustomer`.
15. No new business attributes will be introduced without an explicit analytical requirement.

---

## 16. Staging Object

The corresponding staging table will be:

```text
stg.Customer
```

It will contain one consolidated current-state representation for every `Sales.Customer.CustomerID`.

Expected number of source business keys based on the current AdventureWorks dataset:

```text
19,820 customers
```

The staging layer will not preserve historical versions.

---

## 17. ETL Objects

Planned procedures:

```text
etl.LoadCustomerStage
etl.LoadDimCustomer
```

Expected flow:

```text
Sales.Customer
      │
      ├── Individual → Person.Person
      │
      └── Store      → Sales.Store
      │
      ▼
stg.Customer
      │
      ▼
RowHash comparison
      │
      ▼
etl.LoadDimCustomer
      │
      ▼
dw.DimCustomer
```

---

## 18. Validation Criteria

The implementation will be considered valid when:

- exactly 19,820 source customers are represented;
- each `CustomerID` appears once as current;
- no duplicate current versions exist;
- all `Person only / IN` customers are classified as `Individual`;
- all customers with `StoreID` are classified as `Store`;
- `Person + Store / SC` customers are never classified as `Individual`;
- Store customers use `Store.Name` as `CustomerName`;
- Individual customers use their consolidated person name;
- Store Contact names are not stored as customer identity attributes;
- `SourceModifiedDate` uses only relevant contributing entities;
- repeated loads without source changes are idempotent;
- Type 1 changes update existing members without inserting new versions;
- ETL executions are recorded in the audit framework.

---

## 19. Design Decisions (ADR Summary)

| Decision | Rationale |
|---|---|
| Use `CustomerKey` as surrogate key | Fact tables remain independent of source-system business keys. |
| Use `CustomerID` as business key | It identifies the customer within the AdventureWorks Sales domain. |
| Give `StoreID` precedence over `PersonID` | Source exploration proved that `Person + Store` records represent Store customers with Store Contacts. |
| Exclude Store Contact attributes from `DimCustomer` | Contact identity and customer identity represent different analytical concepts. |
| Derive `CustomerName` according to customer type | Provides one consistent display attribute for both individuals and stores. |
| Use relevant-source `SourceModifiedDate` | Prevents unrelated Store Contact changes from triggering customer updates. |
| Use SCD Type 1 initially | Current descriptive customer attributes do not currently justify historical versioning. |
| Keep the schema Type 2 ready | Historical attributes can be introduced later without restructuring the dimension. |
| Exclude geography from `DimCustomer` | Geography belongs to `DimTerritory` and should remain analytically independent. |
| Protect current members with a filtered unique index | Guarantees at most one current version per `CustomerID`. |

---

## 20. Status

```text
Design: Approved
Source Profiling: Completed
Implementation: Pending
SCD Strategy: Type 1
Target Release: v1.2.0
Module: Dimensional Model Expansion
```