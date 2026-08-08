# Naming Conventions

## 1. Purpose

This document defines the naming conventions used throughout the AdventureWorks Enterprise Data Warehouse.

Consistent naming improves readability, maintainability, collaboration, and long-term scalability.

These conventions apply to:

- Database objects
- ETL procedures
- Source control
- Documentation
- Project structure

---

## 2. General Principles

The project follows these naming principles:

- Be descriptive rather than abbreviated.
- Use consistent terminology across all layers.
- Prefer singular names for entities.
- Avoid unnecessary abbreviations.
- Use PascalCase for SQL object names.
- Use camelCase for T-SQL variables and parameters.
- Use lowercase for folders and Markdown documents.

---

# Database Objects

## 3. Database

Pattern:

```text
<ProjectName>_EDW
```

Example:

```text
AdventureWorks_EDW
```

---

## 4. Schemas

Schemas follow functional responsibilities.

Examples:

```text
stg
dw
etl
audit
```

---

## 5. Tables

Pattern:

```text
<EntityName>
```

Examples:

```text
DimProduct
DimCustomer
DimDate
FactSales
```

Staging:

```text
Product
Customer
SalesOrder
```

Referenced as:

```text
stg.Product
dw.DimProduct
```

---

## 6. Stored Procedures

Pattern:

```text
Load<Object>
```

Examples:

```text
etl.LoadProductStage
etl.LoadDimProduct

etl.LoadCustomerStage
etl.LoadDimCustomer

etl.LoadFactSales
```

---

## 7. Views

Pattern:

```text
vw<Object>
```

Examples:

```text
vwSalesSummary
vwCurrentProducts
```

---

## 8. Functions

Scalar:

```text
fn<Object>
```

Table-valued:

```text
tvf<Object>
```

Examples:

```text
fnCalculateMargin

tvfCurrentProducts
```

---

## 9. Constraints

### Primary Keys

Pattern:

```text
PK_<TableName>
```

Example:

```text
PK_DimProduct
```

---

### Foreign Keys

Pattern:

```text
FK_<Child>_<Parent>
```

Example:

```text
FK_FactSales_DimProduct
```

---

### Default Constraints

Pattern:

```text
DF_<Table>_<Column>
```

Example:

```text
DF_DimProduct_CreatedAt
```

---

### Check Constraints

Pattern:

```text
CK_<Table>_<Rule>
```

Example:

```text
CK_DimProduct_ListPrice
```

---

## 10. Indexes

Clustered:

```text
PK_DimProduct
```

Unique:

```text
UX_DimProduct_Current
```

Nonclustered:

```text
IX_DimProduct_ProductID
```

Filtered:

```text
UX_DimProduct_Current
```

---

# Columns

## 11. Keys

Surrogate Keys:

```text
ProductKey
CustomerKey
DateKey
SalesKey
```

Business Keys:

```text
ProductID
CustomerID
SalesOrderID
```

---

## 12. Audit Columns

Standard names:

```text
CreatedAt

SourceModifiedDate

RowHash

EffectiveStartDateTime

EffectiveEndDateTime

IsCurrent
```

---

## 13. Boolean Columns

Always begin with:

```text
Is
Has
Can
```

Examples:

```text
IsCurrent
IsWeekend

HasWarranty
```

---

## 14. Date Columns

Use complete business meaning.

Examples:

```text
OrderDate

ShipDate

DueDate

SellStartDate

SellEndDate
```

Avoid ambiguous names such as:

```text
Date
Start
End
```

---

# SQL Style

## 15. Variables

Pattern:

```text
@camelCase
```

Examples:

```sql
@executionId

@loadDateTime

@rowsInserted
```

---

## 16. Parameters

Same convention:

```sql
@customerId

@productId
```

---

## 17. Aliases

Use meaningful aliases.

Preferred:

```sql
p
ps
pc

c
```

Avoid:

```sql
a

b

t1

t2
```

unless required for recursive queries.

---

# Files

## 18. SQL Files

Pattern:

```text
NNN_Action.sql
```

Examples:

```text
001_CreateDatabase.sql

002_CreateSchemas.sql

010_CreateDimDate.sql

020_CreateDimProduct.sql
```

Stored procedures:

```text
etl.LoadProductStage.sql

etl.LoadDimProduct.sql
```

---

## 19. Markdown Files

Use lowercase and hyphens.

Examples:

```text
dim-product.md

dim-customer.md

etl-pattern.md

scd-strategies.md
```

---

# Git

## 20. Branches

Feature:

```text
feature/<feature-name>
```

Examples:

```text
feature/product-dimension-scd

feature/dimensional-model-expansion
```

Release:

```text
chore/release-v1.2.0
```

Hotfix:

```text
hotfix/fix-rowhash
```

---

## 21. Commit Messages

Conventional Commits.

Examples:

```text
feat(etl): implement Product SCD Type 2 loading

fix(etl): correct RowHash comparison

docs(design): add DimCustomer specification

chore(release): prepare v1.2.0
```

---

## 22. Pull Requests

Title examples:

```text
feat: implement Customer dimension

docs: add architecture standards

chore: prepare v1.2.0
```

---

## 23. Releases

Pattern:

```text
vMajor.Minor.Patch
```

Examples:

```text
v1.0.0

v1.1.0

v1.2.0
```

Release title:

```text
v1.2.0 – Dimensional Model Expansion
```

---

# Documentation

## 24. Design Specifications

Pattern:

```text
docs/design/dimensions/

docs/design/facts/
```

Example:

```text
dim-product.md

fact-sales.md
```

---

## 25. Architecture Documents

Pattern:

```text
docs/architecture/
```

Examples:

```text
dimensional-model.md

etl-pattern.md

scd-strategies.md

naming-conventions.md
```

---

## 26. ADR Documents

Pattern:

```text
ADR-001-short-description.md
```

Examples:

```text
ADR-001-datekey-format.md

ADR-007-product-scd-type2.md
```

ADR numbering is global across the project.

---

## 27. Summary

The project follows these conventions:

- PascalCase for SQL objects.
- camelCase for T-SQL variables.
- lowercase with hyphens for documentation.
- Conventional Commits.
- Semantic Versioning.
- Functional schema separation.
- Descriptive object names.
- Consistent terminology across every project layer.

---

## 28. Architecture Status

```text
Architecture: Approved
Applies To: Entire Repository
Current Release: v1.1.0
```