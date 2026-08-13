# Design Specification — `dw.DimSalesPerson`

## 1. Objective

Design and implement the `dw.DimSalesPerson` dimension to provide a consistent analytical representation of AdventureWorks sales personnel.

The dimension must consolidate personal, employment, and commercial attributes from multiple OLTP sources while preserving historically relevant changes through Slowly Changing Dimension Type 2 behavior.

The dimension will support future analysis of sales by:

- sales person
- job title
- employment status
- sales quota
- bonus
- commission percentage
- tenure and hire date

---

## 2. Sources

### Primary source

- `AdventureWorks2022.Sales.SalesPerson`

### Additional sources

- `AdventureWorks2022.Person.Person`
- `AdventureWorks2022.HumanResources.Employee`

### Source relationships

```text
Sales.SalesPerson
        │
        │ BusinessEntityID
        ├────────────────────► Person.Person
        │                         │
        │                         └── Personal identity
        │
        └────────────────────► HumanResources.Employee
                                  │
                                  └── Employment attributes
```

All 17 current `Sales.SalesPerson` records were successfully matched to both contributing tables during source profiling.

---

## 3. Source Profiling Summary

Current AdventureWorks data contains:

```text
Sales Persons                 : 17
Distinct BusinessEntityID     : 17
Matched Person records        : 17
Matched Employee records      : 17

Sales Representatives         : 14
Sales Managers                : 3

Sales Persons with Territory  : 14
Sales Persons without Territory: 3
```

The three sales persons without a territory are:

```text
North American Sales Manager
Pacific Sales Manager
European Sales Manager
```

These records also currently contain:

```text
TerritoryID    = NULL
SalesQuota     = NULL
Bonus          = 0
CommissionPct  = 0
```

This is treated as an observed source pattern rather than a hard-coded business rule.

---

## 4. Grain

One row represents one analytical version of a sales person identified by `BusinessEntityID`.

Historical versions may coexist when Type 2 attributes change.

Conceptually:

```text
BusinessEntityID = 275

Version 1
JobTitle = Sales Representative

Version 2
JobTitle = Senior Sales Representative
```

Each version receives a different `SalesPersonKey`.

---

## 5. Business Key

```text
BusinessEntityID
```

`BusinessEntityID` identifies the sales person consistently across:

```text
Sales.SalesPerson
Person.Person
HumanResources.Employee
```

Source profiling confirmed that it is unique for all current sales-person records.

---

## 6. Surrogate Key

```text
SalesPersonKey
```

Recommended definition:

```sql
BIGINT IDENTITY(1,1)
```

Future fact tables will reference `SalesPersonKey` instead of `BusinessEntityID`.

This allows facts to remain associated with the correct historical version of a sales person.

---

## 7. Columns

| Column | Data Type | Nullable | Purpose |
|---|---|:---:|---|
| `SalesPersonKey` | `BIGINT` | No | Warehouse surrogate key |
| `BusinessEntityID` | `INT` | No | Source business key |
| `SalesPersonName` | `NVARCHAR(200)` | No | Consolidated business-friendly name |
| `FirstName` | `NVARCHAR(50)` | No | First name |
| `MiddleName` | `NVARCHAR(50)` | Yes | Middle name or initial |
| `LastName` | `NVARCHAR(50)` | No | Last name |
| `JobTitle` | `NVARCHAR(100)` | No | Current job title for the dimensional version |
| `HireDate` | `DATE` | No | Employee hire date |
| `CurrentFlag` | `BIT` | No | Indicates whether the employee is currently active |
| `SalesQuota` | `DECIMAL(19,4)` | Yes | Assigned sales quota |
| `Bonus` | `DECIMAL(19,4)` | No | Sales bonus |
| `CommissionPct` | `DECIMAL(10,4)` | No | Sales commission percentage |
| `EffectiveStartDateTime` | `DATETIME2(7)` | No | Beginning of dimensional version validity |
| `EffectiveEndDateTime` | `DATETIME2(7)` | No | End of dimensional version validity |
| `IsCurrent` | `BIT` | No | Identifies the current version |
| `RowHash` | `VARBINARY(32)` | No | Detects Type 2 attribute changes |
| `SourceModifiedDate` | `DATETIME2(0)` | No | Latest relevant source modification |
| `CreatedAt` | `DATETIME2(7)` | No | EDW row creation timestamp |

---

## 8. SalesPersonName Rule

`SalesPersonName` provides a single business-friendly representation of the sales person.

Recommended derivation:

```sql
CONCAT_WS
(
    N' ',
    NULLIF(LTRIM(RTRIM(p.FirstName)), N''),
    NULLIF(LTRIM(RTRIM(p.MiddleName)), N''),
    NULLIF(LTRIM(RTRIM(p.LastName)), N'')
)
```

This prevents duplicated spaces when `MiddleName` is `NULL`.

Example:

```text
FirstName  = Jillian
MiddleName = NULL
LastName   = Carson

SalesPersonName
→ Jillian Carson
```

---

## 9. Territory Assignment

`Sales.SalesPerson.TerritoryID` will **not be stored in `dw.DimSalesPerson`**.

It will be retained in:

```text
stg.SalesPerson
```

for:

- source lineage
- profiling
- validation
- change analysis

The dimensional model intentionally keeps SalesPerson and Territory independent.

Future `FactSales` will contain relationships conceptually similar to:

```text
FactSales
│
├── SalesPersonKey ─────► dw.DimSalesPerson
│
└── TerritoryKey ───────► dw.DimTerritory
```

This avoids a snowflake relationship such as:

```text
DimSalesPerson
      ↓
DimTerritory
```

and distinguishes two separate analytical concepts:

```text
Who performed the sale?
→ DimSalesPerson

Where did the sale occur?
→ DimTerritory
```

The territory currently assigned to a salesperson does not necessarily represent the territorial context of every historical sale.

---

## 10. Excluded Source Attributes

The following source attributes are intentionally excluded from `dw.DimSalesPerson`.

### From `Sales.SalesPerson`

```text
TerritoryID
SalesYTD
SalesLastYear
rowguid
```

`TerritoryID` is handled independently through `DimTerritory`.

`SalesYTD` and `SalesLastYear` are accumulated measures from the OLTP system and should not be stored as descriptive dimensional attributes.

`rowguid` is technical metadata without current analytical value.

### From `HumanResources.Employee`

```text
NationalIDNumber
LoginID
OrganizationNode
OrganizationLevel
BirthDate
MaritalStatus
Gender
SalariedFlag
VacationHours
SickLeaveHours
rowguid
```

These attributes are excluded because they either:

- Do not serve the current analytical requirements
- Represent operational HR information
- Introduce unnecessary personal information
- Are redundant with selected analytical attributes
- Or belong to another potential analytical subject area

The project will not introduce attributes without an explicit analytical requirement.

### From `Person.Person`

```text
PersonType
NameStyle
Title
Suffix
EmailPromotion
AdditionalContactInfo
Demographics
rowguid
```

`PersonType` was useful for source profiling but all current SalesPerson records are already constrained to the Sales Person domain.

The remaining attributes do not currently justify inclusion in the dimension.

---

## 11. SCD Strategy

The dimension uses a combination of:

```text
Type 0
Type 1
Type 2
```

### Type 0

Immutable or historically fixed attributes:

```text
BusinessEntityID
HireDate
```

These values are not expected to change after the dimensional member is created.

---

### Type 1

Descriptive identity corrections:

```text
FirstName
MiddleName
LastName
SalesPersonName
```

Changes overwrite the current value.

Typical examples include:

- spelling corrections
- formatting corrections
- name corrections

Historical versions are not created for these changes.

---

### Type 2

Historically relevant employment and commercial attributes:

```text
JobTitle
CurrentFlag
SalesQuota
Bonus
CommissionPct
```

Changes generate a new dimensional version.

These attributes influence the business context in which the sales person operated.

Examples:

```text
Sales Representative
        ↓
Sales Manager
```

or:

```text
SalesQuota
250000
   ↓
300000
```

Such changes may be analytically relevant when examining historical sales performance.

---

## 12. Why Commercial Attributes Use Type 2

`SalesQuota`, `Bonus`, and `CommissionPct` represent commercial conditions associated with the sales person.

Overwriting these values would cause historical analysis to use the salesperson's current commercial conditions instead of those that were valid when previous sales occurred.

Therefore:

```text
SalesQuota
Bonus
CommissionPct
```

are historically tracked.

---

## 13. RowHash Strategy

`RowHash` will contain only Type 2 attributes:

```text
JobTitle
CurrentFlag
SalesQuota
Bonus
CommissionPct
```

Hash algorithm:

```text
SHA2-256
```

Conceptual behavior:

```text
RowHash unchanged
        ↓
No Type 2 change

RowHash changed
        ↓
Expire current version
        ↓
Insert new version
```

Type 1 attributes are compared separately.

---

## 14. NULL Handling in RowHash

`SalesQuota` legitimately contains `NULL` values for the three current Sales Managers.

NULL values must therefore have an explicit deterministic representation during hashing.

Conceptually:

```text
SalesQuota = NULL
→ <NULL>
```

This prevents ambiguity between:

```text
NULL
0
empty value
```

which represent different business states.

---

## 15. SourceModifiedDate Rule

`dw.DimSalesPerson` contains attributes from three source entities.

Therefore:

```text
SourceModifiedDate =
MAX
(
    Sales.SalesPerson.ModifiedDate,
    Person.Person.ModifiedDate,
    HumanResources.Employee.ModifiedDate
)
```

Current profiling shows:

```text
Employee.ModifiedDate = 2014-06-30
```

as the latest source modification for all 17 current records.

The ETL must nevertheless evaluate all three timestamps because future changes may originate from any contributing source.

---

## 16. Historical Validity

Type 2 versions use:

```text
EffectiveStartDateTime
EffectiveEndDateTime
IsCurrent
```

Validity follows the half-open interval convention:

```text
[EffectiveStartDateTime, EffectiveEndDateTime)
```

When a Type 2 change occurs:

```text
Current version
        ↓
EffectiveEndDateTime = load timestamp
IsCurrent = 0

        +

New version
        ↓
EffectiveStartDateTime = same load timestamp
IsCurrent = 1
```

This prevents temporal gaps and overlaps.

---

## 17. Keys and Constraints

### Primary Key

```text
PK_DimSalesPerson
(SalesPersonKey)
```

### Current-version uniqueness

Only one current dimensional member may exist for each `BusinessEntityID`.

Recommended filtered unique index:

```sql
CREATE UNIQUE INDEX UX_DimSalesPerson_Current
ON dw.DimSalesPerson(BusinessEntityID)
WHERE IsCurrent = 1;
```

This guarantees:

```text
BusinessEntityID = 275

Historical → allowed
Historical → allowed
Current    → exactly one
```

---

## 18. Indexes

Initial indexes:

```text
PK_DimSalesPerson
→ SalesPersonKey

UX_DimSalesPerson_Current
→ BusinessEntityID
→ WHERE IsCurrent = 1
```

Additional indexes will only be introduced after observing actual ETL or analytical query patterns.

---

## 19. Staging Object

The corresponding staging table will be:

```text
stg.SalesPerson
```

It will contain the consolidated current-state representation of each `Sales.SalesPerson.BusinessEntityID`.

Staging will not preserve history.

Proposed staging-specific lineage attribute:

```text
TerritoryID
```

This attribute will remain available for source validation even though it will not propagate into `dw.DimSalesPerson`.

Expected source count:

```text
17 Sales Persons
```

---

## 20. ETL Objects

Planned procedures:

```text
etl.LoadSalesPersonStage
etl.LoadDimSalesPerson
```

Expected flow:

```text
Sales.SalesPerson
        │
        ├── Person.Person
        │
        └── HumanResources.Employee
        │
        ▼
stg.SalesPerson
        │
        ▼
Type 1 + Type 2 detection
        │
        ▼
dw.DimSalesPerson
```

---

## 21. ETL Behavior

### New Sales Person

```text
BusinessEntityID not found
        ↓
INSERT
```

### No Change

```text
Type 1 attributes unchanged
AND
RowHash unchanged
        ↓
No action
```

### Type 1 Change

```text
RowHash unchanged
AND
identity attribute changed
        ↓
UPDATE current row
```

### Type 2 Change

```text
RowHash changed
        ↓
Expire current version
        ↓
INSERT new current version
```

### Simultaneous Type 1 + Type 2 Change

The historical version must remain unchanged.

The current version is expired first and the new version receives the latest Type 1 and Type 2 values.

---

## 22. Business Rules

1. `BusinessEntityID` is the immutable business key.
2. Every current sales person must have exactly one current dimensional version.
3. Every `Sales.SalesPerson` must resolve to a valid `Person.Person`.
4. Every `Sales.SalesPerson` must resolve to a valid `HumanResources.Employee`.
5. `SalesPersonName` must never be `NULL`.
6. `MiddleName` may legitimately be `NULL`.
7. `SalesQuota` may legitimately be `NULL`.
8. `Bonus` and `CommissionPct` must not be negative.
9. Territory assignment will not be stored in `dw.DimSalesPerson`.
10. Territory will remain an independent analytical dimension.
11. Accumulated OLTP sales measures will not be copied into the dimension.
12. Type 2 historical periods must never overlap.
13. Missing rows in staging will not automatically imply deletion or employee termination.
14. No new personal or HR attributes will be incorporated without an explicit analytical requirement.

---

## 23. Validation Criteria

The implementation will be considered valid when:

- Exactly 17 current source sales persons are represented.
- All `BusinessEntityID` values are unique in staging.
- All SalesPerson records resolve to Person and Employee.
- Exactly one current version exists per `BusinessEntityID`.
- Type 1 changes update the current dimensional row without creating history.
- Type 2 changes generate a new historical version.
- Simultaneous Type 1 + Type 2 changes preserve historical values.
- Repeated loads without source changes are idempotent.
- Historical validity intervals do not overlap.
- `SalesQuota = NULL` is handled deterministically.
- `SourceModifiedDate` represents the latest contributing source modification.
- ETL execution is recorded through `audit.ETLExecutionLog`.

---

## 24. Design Decisions (ADR Summary)

| Decision | Rationale |
|---|---|
| Use `BusinessEntityID` as Business Key | Consistently identifies the sales person across all three source entities |
| Use `SalesPersonKey` as Surrogate Key | Supports historical versions and fact-table references |
| Consolidate Person + Employee + SalesPerson | SalesPerson identity is distributed across the OLTP model |
| Use Type 1 for names | Corrections do not require analytical history |
| Use Type 2 for `JobTitle` | Role changes alter historical business context |
| Use Type 2 for `CurrentFlag` | Employment status is historically relevant |
| Use Type 2 for quota, bonus and commission | Commercial conditions should remain historically accurate |
| Keep `TerritoryID` out of `DimSalesPerson` | Maintains independent dimensions and avoids snowflake modeling |
| Retain `TerritoryID` in staging | Supports lineage and validation |
| Exclude `SalesYTD` and `SalesLastYear` | They are accumulated measures rather than descriptive attributes |
| Use SHA2-256 RowHash | Provides deterministic Type 2 change detection |
| Use filtered unique index | Guarantees one current version per BusinessEntityID |

---

## 25. Status

```text
Design: Approved
Source Profiling: Completed
Implementation: Pending

SCD Strategy:
Type 0 + Type 1 + Type 2

Current Source Count:
17 Sales Persons

Target Release:
v1.2.0 — Dimensional Model Expansion

Micro Module:
4.3 — DimSalesPerson
```