# AdventureWorks Enterprise Data Warehouse — Tables Catalog

## 1. Purpose

This document provides a centralized catalog of the tables currently implemented in the **AdventureWorks Enterprise Data Warehouse**.

The catalog describes:

- table purpose;
- schema and layer;
- grain;
- main columns;
- dimensional strategy;
- role within the ETL architecture.

This document evolves as new warehouse objects are implemented.

---

## 2. Current Physical Model

```text
AdventureWorks_EDW
│
├── dw
│   ├── DimDate
│   ├── DimProduct
│   └── DimCustomer
│
├── stg
│   ├── Product
│   └── Customer
│
└── audit
    └── ETLExecutionLog
```

Current table count:

```text
Dimension Tables : 3
Staging Tables   : 2
Audit Tables     : 1
Fact Tables      : 0
--------------------
Total Tables     : 6
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

# Staging Layer

## 6. `stg.Product`

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

## 7. `stg.Customer`

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

# Audit Layer

## 8. `audit.ETLExecutionLog`

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
ExecutionID : 19
ProcessName : etl.LoadDimCustomer
Status      : Succeeded
RowsRead    : 19820
RowsInserted: 0
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

---

# 9. Layer Summary

| Schema | Table | Type | Purpose |
|---|---|---|---|
| `dw` | `DimDate` | Dimension | Calendar analysis |
| `dw` | `DimProduct` | Dimension | Product analysis and historical tracking |
| `dw` | `DimCustomer` | Dimension | Customer analysis |
| `stg` | `Product` | Staging | Product source snapshot |
| `stg` | `Customer` | Staging | Customer source snapshot |
| `audit` | `ETLExecutionLog` | Audit | ETL observability and execution tracking |

---

# 10. Current Architecture

```text
AdventureWorks2022
        │
        ▼
┌──────────────────────┐
│    Staging Layer     │
│                      │
│ stg.Product          │
│ stg.Customer         │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Dimensional Layer    │
│                      │
│ dw.DimDate           │
│ dw.DimProduct        │
│ dw.DimCustomer       │
└──────────┬───────────┘
           │
           ▼
     Future FactSales

           │
           │
           ▼

┌──────────────────────┐
│     Audit Layer      │
│                      │
│ ETLExecutionLog      │
└──────────────────────┘
```

---

# 11. Planned Tables

The following objects have not yet been implemented:

```text
dw.DimTerritory
dw.DimSalesPerson
dw.DimShipMethod
dw.FactSales
```

They will be added to this catalog when their corresponding micro modules are completed.

---

## Catalog Status

```text
Catalog: Active
Database: AdventureWorks_EDW
Current Stable Release: v1.1.0
Target Release: v1.2.0
Current Module: Module 4 — Dimensional Model Expansion
```