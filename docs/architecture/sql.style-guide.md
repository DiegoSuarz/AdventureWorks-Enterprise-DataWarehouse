# SQL Style Guide

## 1. Purpose

This document defines the SQL coding standards used throughout the AdventureWorks Enterprise Data Warehouse.

The objective is to produce SQL code that is:

- readable;
- maintainable;
- consistent;
- deterministic;
- easy to review;
- easy to troubleshoot.

These standards apply to every SQL object in the repository.

---

# 2. General Principles

The project follows these principles:

- Readability is preferred over brevity.
- Explicit code is preferred over implicit behavior.
- Consistency is more important than personal preference.
- SQL should explain itself before comments become necessary.
- Every script should be deterministic and repeatable.

---

# 3. Reserved Keywords

SQL keywords are always written in uppercase.

Example:

```sql
SELECT
    ProductID,
    Name
FROM Production.Product
WHERE ListPrice > 100;
```

---

# 4. Object Names

Database objects use PascalCase.

Examples:

```text
DimProduct
FactSales
LoadDimCustomer
```

Schema names remain lowercase.

```text
dw
stg
etl
audit
```

---

# 5. Variables

Variables use camelCase.

Example:

```sql
DECLARE @executionId BIGINT;

DECLARE @loadDateTime DATETIME2(7);
```

---

# 6. SELECT Formatting

One column per line.

Example:

```sql
SELECT
    ProductID,
    ProductName,
    ListPrice,
    StandardCost
FROM stg.Product;
```

Avoid:

```sql
SELECT ProductID, ProductName, ListPrice FROM stg.Product;
```

---

# 7. FROM and JOIN Formatting

Every JOIN begins on a new line.

Example:

```sql
FROM Production.Product AS p

INNER JOIN Production.ProductSubcategory AS ps
    ON p.ProductSubcategoryID = ps.ProductSubcategoryID

INNER JOIN Production.ProductCategory AS pc
    ON ps.ProductCategoryID = pc.ProductCategoryID
```

---

# 8. Aliases

Aliases must be meaningful.

Preferred:

```text
p
ps
pc
c
soh
sod
```

Avoid:

```text
a
b
t1
t2
```

unless required by recursive queries.

---

# 9. WHERE Clause

Each logical condition begins on its own line.

Example:

```sql
WHERE
    p.ListPrice > 0
    AND p.SellEndDate IS NULL
    AND p.Color IS NOT NULL;
```

---

# 10. CASE Formatting

Each branch appears on a separate line.

Example:

```sql
CASE
    WHEN IsCurrent = 1 THEN N'Current'
    ELSE N'Historical'
END
```

---

# 11. CTE Formatting

CTEs should be preferred when they improve readability.

Example:

```sql
WITH ProductSales AS
(
    ...
)

SELECT
...
FROM ProductSales;
```

Avoid deeply nested subqueries when a CTE expresses the intent more clearly.

---

# 12. Temporary Tables

Use temporary tables when:

- intermediate results are reused;
- indexing improves performance;
- execution plans benefit from materialization.

Prefer CTEs for single-use transformations.

---

# 13. MERGE Statement

`MERGE` is not the default approach.

The preferred pattern is:

```text
INSERT

UPDATE

DELETE
```

using explicit statements.

`MERGE` should only be used when its behavior is fully understood and tested.

---

# 14. Transactions

Warehouse modifications should execute inside explicit transactions.

```sql
BEGIN TRANSACTION;

...

COMMIT;
```

On failure:

```sql
ROLLBACK;
```

---

# 15. Error Handling

Every ETL procedure follows:

```sql
BEGIN TRY

...

END TRY

BEGIN CATCH

...

THROW;

END CATCH
```

Errors should never be silently ignored.

---

# 16. Comments

Prefer comments explaining *why*, not *what*.

Good:

```sql
-- Preserve historical versions for SCD Type 2 attributes.
```

Poor:

```sql
-- Update Product table.
```

The SQL already communicates *what* it updates.

---

# 17. Unicode Strings

Always use Unicode string literals.

Example:

```sql
N'Current'

N'Unknown Customer'
```

instead of:

```sql
'Current'
```

---

# 18. Deterministic Conversions

Every conversion used for hashing must be deterministic.

Example:

```sql
CONVERT
(
    NVARCHAR(30),
    SellStartDate,
    126
)
```

Never rely on language-dependent date formats.

---

# 19. Procedure Structure

Warehouse procedures should follow this order:

```text
Header

↓

SET options

↓

Variable declarations

↓

Audit initialization

↓

TRY

↓

Transaction

↓

ETL logic

↓

Commit

↓

Audit success

↓

CATCH

↓

Rollback

↓

Audit failure

↓

THROW
```

Every ETL procedure should preserve this structure.

---

# 20. GO Statements

`GO` should separate logical batches.

Avoid unnecessary batch separators.

---

# 21. Script Idempotency

Deployment scripts should be rerunnable.

Examples:

```sql
IF OBJECT_ID(...)
```

instead of blindly dropping objects.

---

# 22. NULL Handling

Use explicit NULL handling.

Preferred:

```sql
COALESCE()

NULLIF()
```

Avoid relying on implicit NULL behavior.

---

# 23. Formatting Philosophy

The project values consistency above personal formatting preferences.

Every SQL script should appear as though it was written by a single developer.

---

# 24. Code Review Checklist

Before committing SQL code, verify:

- Reserved keywords are uppercase.
- Naming conventions are respected.
- Indentation is consistent.
- One column per SELECT line.
- Meaningful aliases.
- Explicit transactions where required.
- TRY/CATCH implemented.
- Idempotency preserved.
- Comments explain intent.
- Formatting matches the project standard.

---

# 25. Related Documentation

```text
docs/architecture/naming-conventions.md

docs/architecture/etl-pattern.md

docs/architecture/scd-strategies.md
```

---

# 26. Architecture Status

```text
Architecture: Approved
Applies To: Entire SQL Codebase
Current Release: v1.1.0
```