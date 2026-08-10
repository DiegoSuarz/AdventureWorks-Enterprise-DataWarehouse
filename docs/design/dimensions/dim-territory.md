# Design Specification — `dw.DimTerritory`

## 1. Objective

Design and implement the `dw.DimTerritory` dimension to provide a consistent analytical representation of AdventureWorks sales territories.

The dimension must support analysis by territory, country/region, and commercial territory group while preserving historically relevant classification changes.

---

## 2. Source

### Primary source

- `AdventureWorks2022.Sales.SalesTerritory`

### Additional source

- `AdventureWorks2022.Person.CountryRegion`

### Source relationship

```text
Sales.SalesTerritory
        │
        │ CountryRegionCode
        ▼
Person.CountryRegion
```

---

## 3. Grain

One row represents one analytical version of a sales territory identified by `TerritoryID`.

A new dimensional version is created when a Type 2 territory attribute changes.

---

## 4. Business Key

```text
TerritoryID
```

`TerritoryID` uniquely identifies the sales territory in the AdventureWorks source system.

---

## 5. Surrogate Key

```text
TerritoryKey
```

Recommended definition:

```sql
BIGINT IDENTITY(1,1)
```

Fact tables will reference `TerritoryKey` rather than the source-system `TerritoryID`.

---

## 6. Columns

| Column | Data Type | Nullable | Purpose |
|---|---|:---:|---|
| `TerritoryKey` | `BIGINT` | No | Surrogate key |
| `TerritoryID` | `INT` | No | Source business key |
| `TerritoryName` | `NVARCHAR(50)` | No | Sales territory name |
| `CountryRegionCode` | `NVARCHAR(3)` | No | Source country/region code |
| `CountryRegionName` | `NVARCHAR(50)` | No | Descriptive country/region name |
| `TerritoryGroup` | `NVARCHAR(50)` | No | Commercial territory group |
| `EffectiveStartDateTime` | `DATETIME2(7)` | No | Beginning of version validity |
| `EffectiveEndDateTime` | `DATETIME2(7)` | No | End of version validity |
| `IsCurrent` | `BIT` | No | Indicates the current dimensional version |
| `RowHash` | `VARBINARY(32)` | No | Detects Type 2 changes |
| `SourceModifiedDate` | `DATETIME2(0)` | No | Latest relevant source modification |
| `CreatedAt` | `DATETIME2(7)` | No | EDW row creation timestamp |

---

## 7. Hierarchy

The natural analytical hierarchy is:

```text
TerritoryGroup
    ↓
CountryRegion
    ↓
Territory
```

Example:

```text
North America
└── United States
    ├── Northwest
    ├── Northeast
    ├── Central
    ├── Southwest
    └── Southeast
```

`TerritoryName` and `CountryRegionName` must remain separate because a territory does not always represent an entire country.

---

## 8. Excluded Source Attributes

The following source columns are intentionally excluded:

```text
SalesYTD
SalesLastYear
CostYTD
CostLastYear
rowguid
```

The sales and cost columns are measures rather than dimensional attributes.

`rowguid` is technical OLTP metadata without analytical value in the current model.

---

## 9. SourceModifiedDate Rule

`SourceModifiedDate` represents the latest relevant modification from the contributing source entities.

Conceptually:

```text
SourceModifiedDate =
MAX(
    SalesTerritory.ModifiedDate,
    CountryRegion.ModifiedDate
)
```

This ensures that changes in either territory classification or country/region description are detectable.

---

## 10. SCD Strategy

### Type 0

```text
TerritoryID
```

The business key is treated as immutable.

### Type 1

```text
TerritoryName
CountryRegionName
```

Changes overwrite the current value because descriptive name corrections do not require historical analysis.

### Type 2

```text
CountryRegionCode
TerritoryGroup
```

Changes create a new historical version because they alter the analytical geographic or commercial classification of the territory.

---

## 11. RowHash Strategy

`RowHash` contains only Type 2 attributes:

```text
CountryRegionCode
TerritoryGroup
```

Hash algorithm:

```text
SHA2-256
```

Behavior:

```text
RowHash unchanged
→ No Type 2 change

RowHash changed
→ Expire current version
→ Insert new version
```

Type 1 attributes are compared separately.

---

## 12. Historical Validity

Historical versions use:

```text
EffectiveStartDateTime
EffectiveEndDateTime
IsCurrent
```

Validity follows:

```text
[EffectiveStartDateTime, EffectiveEndDateTime)
```

Current rows use the configured open-ended end timestamp.

---

## 13. Keys and Constraints

### Primary Key

```text
PK_DimTerritory
(TerritoryKey)
```

### Current-version uniqueness

```sql
CREATE UNIQUE INDEX UX_DimTerritory_Current
ON dw.DimTerritory(TerritoryID)
WHERE IsCurrent = 1;
```

This guarantees at most one current version per territory.

---

## 14. Indexes

Initial indexes:

```text
PK_DimTerritory
→ TerritoryKey

UX_DimTerritory_Current
→ TerritoryID
→ WHERE IsCurrent = 1
```

Additional indexes will be added only if analytical workload justifies them.

---

## 15. Business Rules

1. `TerritoryID` is the immutable business key.
2. One current version may exist per `TerritoryID`.
3. `TerritoryName` and `CountryRegionName` are Type 1 attributes.
4. `CountryRegionCode` and `TerritoryGroup` are Type 2 attributes.
5. Territory and CountryRegion remain separate analytical concepts.
6. Every territory must resolve to a valid CountryRegion.
7. A CountryRegion must belong to one commercial TerritoryGroup within the current source model.
8. Sales and cost measures are excluded from the dimension.
9. Missing staging rows do not automatically imply deletion.
10. Historical validity periods must never overlap.

---

## 16. Staging Object

```text
stg.Territory
```

The staging table will contain one current-state row per `TerritoryID`.

No history is stored in staging.

Expected current source row count:

```text
10
```

---

## 17. ETL Objects

Planned procedures:

```text
etl.LoadTerritoryStage
etl.LoadDimTerritory
```

Expected flow:

```text
Sales.SalesTerritory
        │
        ├── Person.CountryRegion
        │
        ▼
stg.Territory
        │
        ▼
Type 1 + Type 2 detection
        │
        ▼
dw.DimTerritory
```

---

## 18. Validation Criteria

The implementation will be considered valid when:

- Exactly 10 current source territories are represented
- Each `TerritoryID` resolves to a valid country/region
- No duplicate current versions exist
- Type 1 changes update the current row without generating history
- Type 2 changes create a new historical version
- Historical intervals do not overlap
- Repeated loads without source changes are idempotent
- ETL execution is recorded in the audit framework

---

## 19. Design Decisions (ADR Summary)

| Decision | Rationale |
|---|---|
| Use `TerritoryID` as the business key | Stable source-system identifier |
| Use `TerritoryKey` as surrogate key | Supports historical dimensional versions |
| Enrich territory with `Person.CountryRegion` | Provides readable country/region names |
| Separate Territory from CountryRegion | They are not equivalent concepts in the source model |
| Exclude sales/cost metrics | Measures do not belong in a descriptive dimension |
| Use Type 1 for descriptive names | Name corrections do not require history |
| Use Type 2 for classification changes | Country/group changes affect historical analytical context |
| Use filtered unique index | Guarantees one current version per territory |

---

## 20. Status

```text
Design: Approved
Source Profiling: Completed
Implementation: Pending
SCD Strategy: Type 1 + Type 2
Target Release: v1.2.0
Module: 4.2 DimTerritory
```