# Naming Conventions

## AdventureWorks Enterprise Data Warehouse

## 1. Purpose

This document defines the naming conventions used throughout the AdventureWorks Enterprise Data Warehouse project.

Consistent naming improves:

* Readability.
* Maintainability.
* Searchability.
* Collaboration.
* Code review.
* Troubleshooting.
* Automation.
* Technical documentation.

These conventions apply to database objects, SQL code, ETL components, repository files, Git branches, and commits.

---

## 2. General Principles

Names must be:

* Clear.
* Descriptive.
* Consistent.
* Written in English.
* Free of ambiguous abbreviations.
* Appropriate for the business meaning.
* Stable enough to remain valid as the project evolves.

Avoid:

* Spaces in database object names.
* Reserved SQL keywords.
* Unexplained acronyms.
* Names based only on implementation details.
* Generic names such as `Data`, `Table1`, `Temp`, or `NewTable`.
* Hungarian notation.
* Environment-specific names inside reusable objects.

---

## 3. Language

All technical artifacts must be written in English, including:

* Database objects.
* Column names.
* Stored procedures.
* Views.
* Variables.
* Git branches.
* Commit messages.
* Documentation.
* Comments.
* File names.

Conversation and learning explanations may remain in Spanish.

---

## 4. Capitalization

### Database Objects

Use PascalCase.

Examples:

```text
DimCustomer
FactSales
LoadDimProduct
ETLExecution
```

### Columns

Use PascalCase.

Examples:

```text
CustomerKey
CustomerID
OrderDate
NetSalesAmount
```

### SQL Keywords

Use uppercase.

Example:

```sql
SELECT
    CustomerKey,
    CustomerName
FROM dw.DimCustomer
WHERE IsCurrent = 1;
```

### File and Folder Names

Use lowercase with hyphens for general repository files when practical.

Examples:

```text
solution-architecture.md
data-quality-tests.sql
load-dim-customer.sql
```

Existing principal documents may retain PascalCase when consistently referenced, such as:

```text
SolutionArchitecture.md
NamingConventions.md
CodingStandards.md
```

---

## 5. Database Names

Use PascalCase with underscores only when separating major logical terms.

Approved database name:

```text
AdventureWorks_EDW
```

Avoid:

```text
adventureworksedw
AdventureWorks EDW
AWDW
NewDatabase
```

---

## 6. Schema Names

Use short lowercase names that clearly represent the layer or responsibility.

Approved schemas:

| Schema  | Responsibility                            |
| ------- | ----------------------------------------- |
| `stg`   | Staging and extracted source data         |
| `dw`    | Dimensions, facts, and analytical objects |
| `etl`   | ETL control and processing objects        |
| `audit` | Logging, rejected records, and monitoring |

Examples:

```text
stg.SalesOrderHeader
dw.DimCustomer
etl.LoadDimCustomer
audit.ETLExecution
```

---

## 7. Table Names

### 7.1 Dimension Tables

Use the prefix:

```text
Dim
```

Followed by a singular business entity.

Examples:

```text
DimDate
DimProduct
DimCustomer
DimSalesPerson
DimTerritory
```

Avoid:

```text
DimensionsCustomers
CustomerDimension
Customers
TblDimCustomer
```

### 7.2 Fact Tables

Use the prefix:

```text
Fact
```

Followed by the represented business process.

Examples:

```text
FactSales
FactInventory
FactPurchase
```

Avoid:

```text
SalesFacts
FactTable
Transactions
TblFactSales
```

### 7.3 Staging Tables

Staging tables should generally retain recognizable source-system names.

Examples:

```text
stg.SalesOrderHeader
stg.SalesOrderDetail
stg.Product
stg.Customer
```

When multiple source systems are introduced, include a source-system identifier only when necessary.

Example:

```text
stg.AW_SalesOrderHeader
```

### 7.4 Audit Tables

Use descriptive singular names.

Examples:

```text
audit.ETLExecution
audit.ETLExecutionStep
audit.RejectedRecord
audit.DataQualityResult
```

### 7.5 ETL Control Tables

Examples:

```text
etl.PipelineConfiguration
etl.LoadWatermark
etl.SourceSystem
```

---

## 8. Column Names

### 8.1 Surrogate Keys

Use:

```text
<Entity>Key
```

Examples:

```text
CustomerKey
ProductKey
SalesPersonKey
TerritoryKey
SalesKey
```

Surrogate keys should normally use an integer data type.

### 8.2 Business Keys

Retain the recognizable source-system identifier and use:

```text
<Entity>ID
```

Examples:

```text
CustomerID
ProductID
SalesOrderID
BusinessEntityID
```

Use `ID` for source or natural identifiers.

Use `Key` for warehouse surrogate keys.

### 8.3 Foreign Keys

Foreign-key columns must use the same name as the referenced surrogate key.

Example:

```text
dw.FactSales.CustomerKey
```

references:

```text
dw.DimCustomer.CustomerKey
```

### 8.4 Boolean Columns

Use names that read naturally as true-or-false statements.

Examples:

```text
IsCurrent
IsActive
IsDeleted
HasPromotion
```

Avoid:

```text
Flag
ActiveFlag
CurrentIndicator
BoolValue
```

The `Is` prefix is preferred for state attributes.

### 8.5 Date and Time Columns

Use names ending in:

```text
Date
DateTime
Time
```

Examples:

```text
OrderDate
ShipDate
EffectiveStartDate
EffectiveEndDate
CreatedDateTime
ExecutionStartDateTime
```

### 8.6 Monetary Columns

Include the business meaning and use the suffix:

```text
Amount
```

Examples:

```text
GrossSalesAmount
DiscountAmount
NetSalesAmount
TaxAmount
FreightAmount
TotalCostAmount
```

### 8.7 Quantities and Counts

Use descriptive suffixes.

Examples:

```text
OrderQuantity
ProductCount
RowsInserted
RowsRejected
```

### 8.8 Percentage and Rate Columns

Use:

```text
Percentage
Rate
```

Examples:

```text
DiscountPercentage
TaxRate
MarginPercentage
```

The stored unit must be documented.

### 8.9 Slowly Changing Dimension Columns

Standard Type 2 columns:

```text
EffectiveStartDate
EffectiveEndDate
IsCurrent
```

Optional technical columns:

```text
RowHash
CreatedDateTime
UpdatedDateTime
```

### 8.10 Audit Columns

Recommended audit-column names:

```text
BatchID
SourceSystem
CreatedDateTime
UpdatedDateTime
CreatedBy
UpdatedBy
```

---

## 9. Primary Key Constraints

Use:

```text
PK_<TableName>
```

Examples:

```text
PK_DimCustomer
PK_DimProduct
PK_FactSales
```

Example:

```sql
CONSTRAINT PK_DimCustomer
    PRIMARY KEY CLUSTERED (CustomerKey)
```

---

## 10. Foreign Key Constraints

Use:

```text
FK_<ChildTable>_<ParentTable>
```

Examples:

```text
FK_FactSales_DimCustomer
FK_FactSales_DimProduct
FK_FactSales_DimDate
```

When multiple relationships exist between the same tables, include the relationship role.

Examples:

```text
FK_FactSales_DimDate_OrderDate
FK_FactSales_DimDate_ShipDate
FK_FactSales_DimDate_DueDate
```

---

## 11. Unique Constraints

Use:

```text
UQ_<TableName>_<ColumnName>
```

Examples:

```text
UQ_DimDate_FullDate
UQ_DimProduct_ProductID_IsCurrent
```

For multiple columns:

```text
UQ_DimCustomer_CustomerID_IsCurrent
```

---

## 12. Check Constraints

Use:

```text
CK_<TableName>_<BusinessRule>
```

Examples:

```text
CK_DimCustomer_ValidEffectiveDates
CK_FactSales_NonnegativeOrderQuantity
CK_DimProduct_ValidCurrentFlag
```

---

## 13. Default Constraints

Use:

```text
DF_<TableName>_<ColumnName>
```

Examples:

```text
DF_DimCustomer_IsCurrent
DF_ETLExecution_StartDateTime
DF_FactSales_CreatedDateTime
```

---

## 14. Indexes

### 14.1 Clustered Indexes

Use:

```text
CIX_<TableName>_<ColumnList>
```

Example:

```text
CIX_FactSales_SalesKey
```

Primary-key-backed clustered indexes may use the primary-key constraint name instead.

### 14.2 Nonclustered Indexes

Use:

```text
IX_<TableName>_<ColumnList>
```

Examples:

```text
IX_DimCustomer_CustomerID
IX_DimProduct_ProductID_IsCurrent
IX_FactSales_OrderDateKey
```

### 14.3 Unique Indexes

Use:

```text
UX_<TableName>_<ColumnList>
```

Examples:

```text
UX_DimDate_FullDate
UX_DimCustomer_CustomerID_IsCurrent
```

Do not include every indexed column when the resulting name becomes excessively long. Preserve the most important lookup columns.

---

## 15. Stored Procedures

Use an action-oriented PascalCase name.

Recommended ETL pattern:

```text
etl.Load<Entity>
```

Examples:

```text
etl.LoadDimDate
etl.LoadDimCustomer
etl.LoadDimProduct
etl.LoadFactSales
etl.InitializeBatch
etl.CompleteBatch
etl.FailBatch
```

Avoid the prefix:

```text
sp_
```

SQL Server reserves `sp_` for system stored procedures and may search the `master` database first.

---

## 16. Views

Use descriptive business names.

Analytical views may use the prefix:

```text
vw
```

Examples:

```text
dw.vwSalesSummary
dw.vwCurrentCustomer
dw.vwProductPerformance
```

The project may omit the prefix when a team standard favors plain business names. One convention must be selected and used consistently.

For this project, the initial standard is:

```text
vw<EntityOrPurpose>
```

---

## 17. Functions

### Scalar Functions

Use:

```text
ufn<BusinessPurpose>
```

Example:

```text
dw.ufnCalculateMarginPercentage
```

### Table-Valued Functions

Use:

```text
tvf<BusinessPurpose>
```

Example:

```text
dw.tvfSalesByDateRange
```

Functions should be used carefully because some implementations can negatively affect query performance.

---

## 18. Sequences

Use:

```text
SEQ_<EntityName>
```

Example:

```text
SEQ_ETLBatch
```

Sequences should only be introduced when an identity column is not appropriate.

---

## 19. Temporary Tables

Use a meaningful singular or plural business name prefixed with `#`.

Examples:

```text
#CustomerChanges
#ProductLookup
#StagedSales
```

Avoid:

```text
#Temp
#Temp1
#Data
```

---

## 20. Common Table Expressions

Use a descriptive PascalCase name.

Examples:

```text
CustomerSales
ProductRevenue
EmployeeHierarchy
RankedCustomers
```

Recursive CTEs should reflect the represented hierarchy.

---

## 21. Variables

Use camelCase and prefix variables with `@`.

Examples:

```sql
@batchID
@startDateTime
@rowsInserted
@errorMessage
```

Procedure parameters may follow the same convention.

Avoid unnecessary type prefixes such as:

```text
@intCustomerID
@strCustomerName
```

The data type is already declared in the parameter definition.

---

## 22. Transactions and Savepoints

Transaction names should describe the unit of work.

Examples:

```text
LoadDimCustomerTransaction
LoadFactSalesTransaction
```

Use names only when they improve diagnostics or nested transaction handling.

---

## 23. ETL Pipeline Names

Use a structured convention:

```text
PL_<Source>_<Target>_<Purpose>
```

Examples:

```text
PL_AdventureWorks_Staging_FullLoad
PL_Staging_EDW_Dimensions
PL_Staging_EDW_FactSales
```

Azure Data Factory activities may use:

```text
<ActivityType>_<Source>_<Target>
```

Examples:

```text
Copy_SalesOrderHeader_Staging
Lookup_LoadWatermark
StoredProcedure_LoadDimCustomer
```

---

## 24. Repository Folders

Use lowercase names.

Examples:

```text
docs/
database/
etl/
tests/
azure/
powerbi/
fabric/
```

Nested folders should clearly express their responsibility.

Examples:

```text
database/initialization/
database/dimensions/
database/facts/
database/indexes/
docs/architecture/
docs/design/
docs/adr/
```

---

## 25. SQL File Names

Use an ordered prefix when execution order matters.

Examples:

```text
00-create-database.sql
01-create-schemas.sql
02-create-audit-tables.sql
03-create-staging-tables.sql
04-create-dimensions.sql
05-create-facts.sql
```

For individual objects:

```text
create-dim-customer.sql
load-dim-customer.sql
create-fact-sales.sql
load-fact-sales.sql
```

Use lowercase and hyphens.

---

## 26. Git Branch Names

Use lowercase and hyphens.

Pattern:

```text
feature/<short-description>
```

Examples:

```text
feature/repository-foundation
feature/solution-documentation
feature/database-initialization
feature/dim-date
feature/fact-sales
```

Additional branch types may be introduced later:

```text
fix/<short-description>
docs/<short-description>
refactor/<short-description>
```

Avoid:

```text
DiegoBranch
new-changes
test
branch1
```

---

## 27. Commit Messages

Use Conventional Commit-style messages.

Pattern:

```text
<type>: <short imperative description>
```

Common types:

| Type       | Purpose                                      |
| ---------- | -------------------------------------------- |
| `feat`     | Adds a new capability                        |
| `fix`      | Corrects a defect                            |
| `docs`     | Changes documentation                        |
| `refactor` | Improves structure without changing behavior |
| `test`     | Adds or updates tests                        |
| `chore`    | Performs maintenance or repository setup     |
| `perf`     | Improves performance                         |

Examples:

```text
docs: add solution architecture standards
chore: initialize repository structure
feat: create date dimension
feat: implement customer type 2 history
fix: prevent duplicate fact sales rows
test: add fact sales grain validation
```

The description should:

* Start with a lowercase verb.
* Be concise.
* Describe one logical change.
* Avoid a final period.

---

## 28. Pull Request Titles

Use the same convention as commit messages.

Examples:

```text
docs: establish architecture and coding standards
feat: create initial dimensional model
fix: correct customer surrogate key lookup
```

---

## 29. Version Tags

Use Semantic Versioning.

Pattern:

```text
vMAJOR.MINOR.PATCH
```

Examples:

```text
v0.1.0
v0.2.0
v1.0.0
```

Meaning:

* `MAJOR`: incompatible or major architectural change.
* `MINOR`: new backward-compatible capability.
* `PATCH`: backward-compatible correction.

---

## 30. Approved Examples

```text
dw.DimCustomer
dw.FactSales
stg.SalesOrderDetail
etl.LoadDimCustomer
audit.ETLExecution
PK_DimCustomer
FK_FactSales_DimCustomer
IX_DimCustomer_CustomerID
feature/dim-customer
docs: define dimensional modeling standards
```

---

## 31. Prohibited Patterns

Avoid the following unless explicitly justified:

```text
tblCustomer
sp_LoadCustomer
Customer_Table
dim_customer
COLUMN1
TempTable
NewProcedure
FinalVersion
FinalVersion2
Test123
```

---

## 32. Exceptions

Any exception to these conventions must:

1. Have a clear technical or business reason.
2. Be documented in the relevant code or architecture decision.
3. Be applied consistently.
4. Be reviewed before merging into `main`.
