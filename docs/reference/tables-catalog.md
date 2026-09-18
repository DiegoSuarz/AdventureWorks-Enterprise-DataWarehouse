# AdventureWorks Enterprise Data Warehouse — Tables Catalog

## 1. Purpose

This document provides a centralized catalog of the tables currently implemented in the **AdventureWorks Enterprise Data Warehouse**.

The catalog describes:

- table purpose
- schema and layer
- grain
- main columns
- dimensional strategy
- role within the ETL architecture

This document evolves as new warehouse objects are implemented.

---

## 2. Current Physical Model

```text
AdventureWorks_EDW
│
├── dw
│   ├── DimDate
│   ├── DimProduct
│   ├── DimCustomer
│   ├── DimTerritory
│   ├── DimSalesPerson
│   └── DimShipMethod
│
├── stg
│   ├── Product
│   ├── Customer
│   ├── Territory
│   ├── SalesPerson
│   └── ShipMethod
│
└── audit
    ├── ETLExecutionLog
    └── ETLWatermark
```

Current table count:

```text
Dimension Tables : 6
Staging Tables   : 5
Audit Tables     : 2
Fact Tables      : 0
--------------------
Total Tables     : 13
```

---

# Dimensional Layer

## 3. `dw.DimDate`

### Purpose

Provides the conformed calendar dimension used for time-based analytical reporting.

### Grain

```text
One row = one calendar day
```

### SCD Strategy

```text
Not Applicable
```

Calendar dates are immutable.

### Columns

| Column | Description |
|---|---|
| `DateKey` | Warehouse date key represented using the `YYYYMMDD` convention. |
| `FullDate` | Actual calendar date. |
| `DayNumberOfWeek` | Numeric representation of the weekday. |
| `DayNameOfWeek` | Descriptive weekday name. |
| `DayNumberOfMonth` | Day number within the month. |
| `DayNumberOfYear` | Day number within the year. |
| `WeekNumberOfYear` | Week number within the year. |
| `MonthNumber` | Numeric month value from 1 through 12. |
| `MonthName` | Descriptive month name. |
| `QuarterNumber` | Calendar quarter number from 1 through 4. |
| `YearNumber` | Calendar year. |
| `IsWeekend` | Indicates whether the date belongs to a weekend. |

### Future Usage

`dw.DimDate` will act as a role-playing dimension for fact tables.

For `FactSales`, planned roles include:

```text
OrderDateKey
DueDateKey
ShipDateKey
```

---

## 4. `dw.DimProduct`

### Purpose

Provides the analytical Product dimension while preserving historically relevant product changes.

### Grain

```text
One row = one historical version of a ProductID
```

### Business Key

```text
ProductID
```

### Surrogate Key

```text
ProductKey
```

### SCD Strategy

```text
Type 0 + Type 1 + Type 2
```

### Columns

| Column | Description |
|---|---|
| `ProductKey` | Warehouse-generated surrogate key identifying a specific product version. |
| `ProductID` | AdventureWorks source-system business key. |
| `ProductName` | Descriptive product name. |
| `ProductNumber` | Product business/code identifier. |
| `Color` | Product color. |
| `Size` | Product size. |
| `StandardCost` | Standard product cost. |
| `ListPrice` | Product list price. |
| `SubcategoryName` | Product subcategory description. |
| `CategoryName` | Higher-level product category description. |
| `SellStartDate` | Date from which the product became available for sale. |
| `SellEndDate` | Date on which product selling ended, when applicable. |
| `DiscontinuedDate` | Product discontinuation date. |
| `EffectiveStartDateTime` | Beginning of validity for this dimensional version. |
| `EffectiveEndDateTime` | End of validity for this dimensional version. |
| `IsCurrent` | Indicates whether the row is the currently valid product version. |
| `RowHash` | SHA2-256 hash used to detect Type 2 attribute changes. |
| `SourceModifiedDate` | Latest relevant modification timestamp from the source. |
| `CreatedAt` | Timestamp at which the dimensional row was created in the EDW. |

### Attribute Classification

```text
Type 0
-------
ProductID

Type 1
-------
ProductName
ProductNumber

Type 2
-------
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

### Integrity Rule

A filtered unique index guarantees that each `ProductID` has at most one current version.

Conceptually:

```text
ProductID
   │
   ├── Historical Version
   ├── Historical Version
   └── Current Version
```

### Current Validated State

```text
Distinct Products    : 504
Current Versions     : 504
Historical Versions  : 2
Total Versions       : 506
```

---

## 5. `dw.DimCustomer`

### Purpose

Provides a consolidated analytical representation of AdventureWorks customers.

The dimension supports both:

```text
Individual Customers
Store Customers
```

### Grain

```text
One row = one analytical version of a CustomerID
```

### Business Key

```text
CustomerID
```

### Surrogate Key

```text
CustomerKey
```

### Current SCD Strategy

```text
SCD Type 1
```

The structure remains prepared for future Type 2 attributes.

### Columns

| Column | Description |
|---|---|
| `CustomerKey` | Warehouse-generated surrogate key. |
| `CustomerID` | AdventureWorks customer business key. |
| `CustomerType` | Analytical classification: `Individual`, `Store`, or `Unknown`. |
| `CustomerName` | Consolidated business-friendly customer name. |
| `FirstName` | First name for Individual customers. |
| `MiddleName` | Middle name for Individual customers when available. |
| `LastName` | Last name for Individual customers. |
| `StoreName` | Business name for Store customers. |
| `AccountNumber` | AdventureWorks customer account identifier. |
| `EffectiveStartDateTime` | Beginning of validity for the dimensional member. |
| `EffectiveEndDateTime` | End of validity for the dimensional member. |
| `IsCurrent` | Indicates the currently valid customer version. |
| `RowHash` | SHA2-256 hash used for Type 1 change detection. |
| `SourceModifiedDate` | Latest relevant source modification timestamp. |
| `CreatedAt` | Timestamp at which the row was created in the EDW. |

### Customer Classification Rule

```text
StoreID IS NOT NULL
        ↓
Store

StoreID IS NULL
AND PersonID IS NOT NULL
        ↓
Individual
```

Source profiling demonstrated that records containing both `PersonID` and `StoreID` represent Store customers with associated Store Contacts.

Store Contact attributes are intentionally excluded from the analytical customer identity.

### Current Validated State

```text
Total Customers      : 19,820
Distinct Customers   : 19,820
Current Versions     : 19,820
Historical Versions  : 0
```

---

## 6. `dw.DimTerritory`

### Purpose

Provides a consistent analytical representation of AdventureWorks sales territories for analysis by territory, country/region, and commercial territory group.

### Grain

```text
One row = one analytical version of a TerritoryID
```

### Business Key

```text
TerritoryID
```

### Surrogate Key

```text
TerritoryKey
```

### SCD Strategy

```text
Type 0 + Type 1 + Type 2
```

### Columns

| Column | Description |
|---|---|
| `TerritoryKey` | Warehouse-generated surrogate key identifying a specific territory version. |
| `TerritoryID` | AdventureWorks territory business key. |
| `TerritoryName` | Sales territory name. |
| `CountryRegionCode` | Source country/region code. |
| `CountryRegionName` | Descriptive country/region name. |
| `TerritoryGroup` | Commercial territory group. |
| `EffectiveStartDateTime` | Beginning of validity for this dimensional version. |
| `EffectiveEndDateTime` | End of validity for this dimensional version. |
| `IsCurrent` | Indicates whether the row is the current territory version. |
| `RowHash` | SHA2-256 hash used to detect Type 2 changes. |
| `SourceModifiedDate` | Latest relevant source modification timestamp. |
| `CreatedAt` | Timestamp at which the dimensional row was created in the EDW. |

### Attribute Classification

```text
Type 0
-------
TerritoryID

Type 1
-------
TerritoryName
CountryRegionName

Type 2
-------
CountryRegionCode
TerritoryGroup
```

### Analytical Hierarchy

```text
TerritoryGroup
    ↓
CountryRegion
    ↓
Territory
```

### Integrity Rule

A filtered unique index guarantees that each `TerritoryID` has at most one current version.

Historical validity follows the half-open interval:

```text
[EffectiveStartDateTime, EffectiveEndDateTime)
```

### Current Validated State

```text
Distinct Territories : 10
Current Versions      : 10
Historical Versions   : 3
Total Versions        : 13
```

The historical versions were intentionally generated during controlled SCD Type 2 validation.

---

## 7. `dw.DimSalesPerson`

### Purpose

Provides a consolidated analytical representation of AdventureWorks sales personnel using information from the Sales, Person, and Employee source domains.

### Grain

```text
One row = one analytical version of a BusinessEntityID
```

### Business Key

```text
BusinessEntityID
```

### Surrogate Key

```text
SalesPersonKey
```

### SCD Strategy

```text
Type 0 + Type 1 + Type 2
```

### Columns

| Column | Description |
|---|---|
| `SalesPersonKey` | Warehouse-generated surrogate key identifying a specific sales-person version. |
| `BusinessEntityID` | AdventureWorks business key shared across contributing source entities. |
| `SalesPersonName` | Consolidated business-friendly sales-person name. |
| `FirstName` | First name. |
| `MiddleName` | Middle name when available. |
| `LastName` | Last name. |
| `JobTitle` | Employment role. |
| `HireDate` | Employee hire date. |
| `CurrentFlag` | Current employee-state indicator. |
| `SalesQuota` | Sales quota when applicable. |
| `Bonus` | Bonus amount. |
| `CommissionPct` | Commission percentage. |
| `EffectiveStartDateTime` | Beginning of validity for this dimensional version. |
| `EffectiveEndDateTime` | End of validity for this dimensional version. |
| `IsCurrent` | Indicates whether the row is the current sales-person version. |
| `RowHash` | SHA2-256 hash used to detect Type 2 changes. |
| `SourceModifiedDate` | Latest relevant source modification across contributing entities. |
| `CreatedAt` | Timestamp at which the dimensional row was created in the EDW. |

### Attribute Classification

```text
Type 0
-------
BusinessEntityID
HireDate

Type 1
-------
SalesPersonName
FirstName
MiddleName
LastName

Type 2
-------
JobTitle
CurrentFlag
SalesQuota
Bonus
CommissionPct
```

### Territory Modeling Decision

`TerritoryID` is intentionally excluded from `dw.DimSalesPerson`.

SalesPerson and Territory remain independent analytical dimensions:

```text
Who performed the sale?
→ dw.DimSalesPerson

Where did the sale occur?
→ dw.DimTerritory
```

The source `TerritoryID` is retained in `stg.SalesPerson` for lineage, profiling, and validation.

### Integrity Rule

A filtered unique index guarantees that each `BusinessEntityID` has at most one current version.

Historical validity follows:

```text
[EffectiveStartDateTime, EffectiveEndDateTime)
```

### Current Validated State

```text
Distinct Sales Persons : 17
Current Versions        : 17
Historical Versions     : 3
Total Versions          : 20
```

The historical versions were intentionally generated during controlled SCD Type 2 validation.

---

## 8. `dw.DimShipMethod`

### Purpose

Provides the analytical shipping-method dimension while preserving historically relevant tariff changes.

### Grain

```text
One row = one analytical version of a ShipMethodID
```

### Business Key

```text
ShipMethodID
```

### Surrogate Key

```text
ShipMethodKey
```

### SCD Strategy

```text
Type 0 + Type 1 + Type 2
```

### Columns

| Column | Description |
|---|---|
| `ShipMethodKey` | Warehouse-generated surrogate key identifying a specific shipping-method version. |
| `ShipMethodID` | AdventureWorks shipping-method business key. |
| `ShipMethodName` | Shipping company or shipping-method name. |
| `ShipBase` | Minimum shipping charge. |
| `ShipRate` | Shipping charge per pound. |
| `EffectiveStartDateTime` | Beginning of validity for this dimensional version. |
| `EffectiveEndDateTime` | End of validity for this dimensional version. |
| `IsCurrent` | Indicates whether the row is the current shipping-method version. |
| `RowHash` | SHA2-256 hash used to detect tariff changes. |
| `SourceModifiedDate` | Source modification timestamp. |
| `CreatedAt` | Timestamp at which the dimensional row was created in the EDW. |

### Attribute Classification

```text
Type 0
-------
ShipMethodID

Type 1
-------
ShipMethodName

Type 2
-------
ShipBase
ShipRate
```

### Analytical Interpretation

`ShipBase` and `ShipRate` are numerical attributes, but they are not transactional fact measures.

They describe the tariff configuration of a shipping method:

```text
ShipBase = minimum shipping charge
ShipRate = shipping charge per pound
```

Transactional freight amounts belong to individual business events and will be modeled in the future sales fact process.

### Integrity Rule

A filtered unique index guarantees that each `ShipMethodID` has at most one current version.

Historical validity follows:

```text
[EffectiveStartDateTime, EffectiveEndDateTime)
```

### Current Validated State

```text
Distinct Shipping Methods : 5
Current Versions           : 5
Historical Versions        : 3
Total Versions             : 8
```

The historical versions were intentionally generated during controlled SCD Type 2 validation.

---

# Staging Layer

## 9. `stg.Product`

### Purpose

Provides the normalized current-state Product snapshot before dimensional processing.

### Grain

```text
One row = current state of one ProductID
```

### History

```text
No historical versions are maintained in staging.
```

### Columns

| Column | Description |
|---|---|
| `ProductID` | AdventureWorks product identifier and staging business key. |
| `ProductName` | Current product name. |
| `ProductNumber` | Current product code. |
| `Color` | Current product color. |
| `Size` | Current product size. |
| `StandardCost` | Current standard cost. |
| `ListPrice` | Current list price. |
| `SubcategoryName` | Current product subcategory. |
| `CategoryName` | Current product category. |
| `SellStartDate` | Source selling start date. |
| `SellEndDate` | Source selling end date. |
| `DiscontinuedDate` | Source discontinuation date. |
| `SourceModifiedDate` | Relevant source modification timestamp. |
| `ExtractedAt` | Timestamp at which the row was extracted into staging. |
| `RowHash` | SHA2-256 hash generated from Product SCD Type 2 attributes. |

### Pipeline Role

```text
AdventureWorks2022
        ↓
stg.Product
        ↓
dw.DimProduct
```

---

## 10. `stg.Customer`

### Purpose

Provides a consolidated current-state Customer snapshot before dimensional processing.

### Grain

```text
One row = current state of one Sales.Customer.CustomerID
```

### Sources

```text
Sales.Customer
Person.Person
Sales.Store
```

### Columns

| Column | Description |
|---|---|
| `CustomerID` | AdventureWorks Customer business key and staging primary key. |
| `PersonID` | Source reference to `Person.Person`; retained for lineage and validation. |
| `StoreID` | Source reference to `Sales.Store`. |
| `PersonType` | AdventureWorks Person classification such as `IN` or `SC`; used for validation and profiling. |
| `CustomerType` | Derived analytical classification: `Individual`, `Store`, or `Unknown`. |
| `CustomerName` | Consolidated analytical customer name. |
| `FirstName` | Individual customer first name. |
| `MiddleName` | Individual customer middle name. |
| `LastName` | Individual customer last name. |
| `StoreName` | Store business name. |
| `AccountNumber` | AdventureWorks customer account identifier. |
| `SourceModifiedDate` | Latest relevant modification timestamp from contributing source entities. |
| `ExtractedAt` | Timestamp at which the customer was loaded into staging. |
| `RowHash` | SHA2-256 hash used to detect dimensional Type 1 changes. |

### Important Business Rule

For Store customers:

```text
PersonID may exist
```

but:

```text
FirstName  = NULL
MiddleName = NULL
LastName   = NULL
```

because the associated person represents a **Store Contact**, not the analytical customer.

### Validated Staging State

```text
Total Customers     : 19,820
Distinct Customers  : 19,820

Individual          : 18,484
Store               : 1,336
```

---

## 11. `stg.Territory`

### Purpose

Provides the normalized current-state snapshot of AdventureWorks sales territories before dimensional processing.

### Grain

```text
One row = current state of one TerritoryID
```

### Sources

```text
Sales.SalesTerritory
Person.CountryRegion
```

### Columns

| Column | Description |
|---|---|
| `TerritoryID` | AdventureWorks territory business key and staging primary key. |
| `TerritoryName` | Sales territory name. |
| `CountryRegionCode` | Source country/region code. |
| `CountryRegionName` | Descriptive country/region name. |
| `TerritoryGroup` | Commercial territory group. |
| `SourceModifiedDate` | Latest relevant modification timestamp from contributing source entities. |
| `ExtractedAt` | Timestamp at which the row was extracted into staging. |
| `RowHash` | SHA2-256 hash generated from Territory SCD Type 2 attributes. |

### Pipeline Role

```text
Sales.SalesTerritory
        +
Person.CountryRegion
        ↓
stg.Territory
        ↓
dw.DimTerritory
```

### Validated Staging State

```text
Total Territories    : 10
Distinct Territories : 10
```

---

## 12. `stg.SalesPerson`

### Purpose

Provides the consolidated current-state representation of AdventureWorks sales personnel before dimensional processing.

### Grain

```text
One row = current state of one BusinessEntityID
```

### Sources

```text
Sales.SalesPerson
Person.Person
HumanResources.Employee
```

### Columns

| Column | Description |
|---|---|
| `BusinessEntityID` | Sales-person business key and staging primary key. |
| `SalesPersonName` | Consolidated analytical full name. |
| `FirstName` | First name. |
| `MiddleName` | Middle name when available. |
| `LastName` | Last name. |
| `JobTitle` | Current employment role. |
| `HireDate` | Employee hire date. |
| `CurrentFlag` | Current employee-state indicator. |
| `SalesQuota` | Current sales quota when applicable. |
| `Bonus` | Current bonus amount. |
| `CommissionPct` | Current commission percentage. |
| `TerritoryID` | Source territory reference retained for lineage and validation. |
| `SourceModifiedDate` | Latest modification timestamp from contributing source entities. |
| `ExtractedAt` | Timestamp at which the row was extracted into staging. |
| `RowHash` | SHA2-256 hash generated from SalesPerson SCD Type 2 attributes. |

### Important Modeling Rule

`TerritoryID` remains in staging for lineage and validation but is intentionally excluded from `dw.DimSalesPerson`.

### Validated Staging State

```text
Total Sales Persons    : 17
Distinct Sales Persons : 17
```

---

## 13. `stg.ShipMethod`

### Purpose

Provides the normalized shipping-method delta for the current bounded incremental batch.

### Grain

```text
One row = one ShipMethodID selected by the current LOW/HIGH batch boundary
```

### Source

```text
Purchasing.ShipMethod
```

### Columns

| Column | Description |
|---|---|
| `ShipMethodID` | Shipping-method business key and staging primary key. |
| `ShipMethodName` | Shipping company or shipping-method name. |
| `ShipBase` | Minimum shipping charge. |
| `ShipRate` | Shipping charge per pound. |
| `SourceModifiedDate` | Source modification timestamp. |
| `ExtractedAt` | Timestamp at which the row was extracted into staging. |
| `RowHash` | SHA2-256 hash generated from Type 2 tariff attributes. |

### Pipeline Role

```text
Purchasing.ShipMethod
        ↓
composite LOW < row <= HIGH
        ↓
stg.ShipMethod
        ↓
dw.DimShipMethod
```

### Incremental Staging Behavior

The table contains only the rows belonging to the current incremental batch.

```text
Initial batch : 5 rows validated
Delta batch   : 3 rows validated
No-op batch   : 0 rows validated
```

Batch cardinality is intentionally variable and must not be interpreted as a
complete source snapshot.

---

# Audit Layer

## 14. `audit.ETLExecutionLog`

### Purpose

Provides centralized operational auditing and observability for ETL executions.

### Grain

```text
One row = one ETL process execution
```

### Columns

| Column | Description |
|---|---|
| `ExecutionID` | Unique identifier for the ETL execution. |
| `ProcessName` | Name of the executed ETL process or stored procedure. |
| `SourceObject` | Source object used by the ETL process. |
| `TargetObject` | Destination object populated or modified by the ETL process. |
| `StartTime` | Execution start timestamp. |
| `EndTime` | Execution completion timestamp. |
| `Status` | Execution status such as `Running`, `Succeeded`, or `Failed`. |
| `RowsRead` | Number of source rows read during execution. |
| `RowsInserted` | Number of destination rows inserted. |
| `RowsUpdated` | Number of destination rows updated. |
| `RowsRejected` | Number of rows rejected during processing. |
| `ErrorMessage` | Diagnostic message when an ETL execution fails. |
| `ExecutedBy` | SQL Server principal that executed the process. |

### Example

```text
ExecutionID : 43
ProcessName : etl.LoadDimShipMethod
Status      : Succeeded
RowsRead    : 5
RowsInserted: 1
RowsUpdated : 1
RowsRejected: 0
```

### Role

The audit layer provides evidence for:

- ETL execution status;
- data reconciliation;
- idempotency testing;
- Type 1 and Type 2 processing;
- error diagnosis;
- operational monitoring.

### Current ETL Health

At Module 4 closure, the latest execution of each implemented ETL process was validated successfully:

```text
ETL Processes       : 11
Healthy Processes   : 11
Unhealthy Processes : 0
```

---

## 15. `audit.ETLWatermark`

### Purpose

Persists the durable control state required by incremental ETL processes using
composite LOW and HIGH watermark boundaries.

### Grain

```text
One row = one incremental ETL process
```

### Columns

| Column | Description |
|---|---|
| `WatermarkID` | Surrogate identifier for the watermark-control record. |
| `ProcessName` | Unique incremental process name. |
| `SourceObject` | Source object monitored by the process. |
| `LowModifiedDate` | Timestamp component of the last successfully committed LOW position. |
| `LowBusinessKey` | Business-key component of the last successfully committed LOW position. |
| `HighModifiedDate` | Timestamp component of the currently frozen HIGH boundary. |
| `HighBusinessKey` | Business-key component of the currently frozen HIGH boundary. |
| `Status` | Current process state: `Ready`, `InProgress`, or `Failed`. |
| `LastSuccessfulExecutionID` | Parent execution that last advanced LOW successfully. |
| `CurrentExecutionID` | Execution currently owning or last failing the frozen batch. |
| `CreatedAt` | Watermark-record creation timestamp. |
| `UpdatedAt` | Timestamp of the latest watermark-state transition. |

### Composite Watermark Contract

```text
LOW < source row <= HIGH
```

LOW is exclusive and HIGH is inclusive.

A NULL LOW represents the initial incremental batch.

### Batch State Machine

```text
Ready
  ↓ capture HIGH
InProgress
  ↓ success
Ready

InProgress
  ↓ failure
Failed
  ↓ retry same HIGH
InProgress
  ↓ success
Ready
```

LOW advances only after the complete batch succeeds.

Failed batches retain HIGH so retries process exactly the same source interval.

### Current Pilot

```text
ProcessName   : etl.LoadShipMethodIncremental
SourceObject  : AdventureWorks2022.Purchasing.ShipMethod
Composite Key : (ModifiedDate, ShipMethodID)
```

---

# 16. Layer Summary

| Schema | Table | Type | Purpose |
|---|---|---|---|
| `dw` | `DimDate` | Dimension | Calendar analysis |
| `dw` | `DimProduct` | Dimension | Product analysis and historical tracking |
| `dw` | `DimCustomer` | Dimension | Customer analysis |
| `dw` | `DimTerritory` | Dimension | Geographic and commercial territory analysis |
| `dw` | `DimSalesPerson` | Dimension | Sales-person and commercial-context analysis |
| `dw` | `DimShipMethod` | Dimension | Shipping method and tariff analysis |
| `stg` | `Product` | Staging | Product source snapshot |
| `stg` | `Customer` | Staging | Customer source snapshot |
| `stg` | `Territory` | Staging | Territory source snapshot |
| `stg` | `SalesPerson` | Staging | Consolidated sales-person source snapshot |
| `stg` | `ShipMethod` | Staging | Current incremental shipping-method batch delta |
| `audit` | `ETLExecutionLog` | Audit | ETL observability and execution tracking |
| `audit` | `ETLWatermark` | Audit / Control | Persisted incremental watermark state |

---

# 17. Current Architecture

```text
AdventureWorks2022
        │
        ▼
┌────────────────────────┐
│     Staging Layer      │
│                        │
│ stg.Product            │
│ stg.Customer           │
│ stg.Territory          │
│ stg.SalesPerson        │
│ stg.ShipMethod         │
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│   Dimensional Layer    │
│                        │
│ dw.DimDate             │
│ dw.DimProduct          │
│ dw.DimCustomer         │
│ dw.DimTerritory        │
│ dw.DimSalesPerson      │
│ dw.DimShipMethod       │
└───────────┬────────────┘
            │
            ▼
      Future FactSales

            │
            ▼
┌────────────────────────┐
│      Audit Layer       │
│                        │
│ audit.ETLExecutionLog  │
│ audit.ETLWatermark     │
└────────────────────────┘
```

---

# 18. Planned Tables

The next major warehouse table planned after the dimensional-model expansion is:

```text
dw.FactSales
```

Fact-table implementation remains future warehouse scope and is not part of Module 5.

---

## Catalog Status

```text
Catalog: Active
Database: AdventureWorks_EDW
Current Stable Release: v1.2.0
Current Module: Module 5 — Composite + High Watermark Incremental Loading
Next Module: Module 6 — Data Quality & ETL Reliability
```
