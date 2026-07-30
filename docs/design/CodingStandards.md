# Coding Standards

## AdventureWorks Enterprise Data Warehouse

## 1. Purpose

This document defines the coding standards for the AdventureWorks Enterprise Data Warehouse project.

The objective is to produce code that is:

* Correct.
* Readable.
* Maintainable.
* Testable.
* Secure.
* Performant.
* Auditable.
* Consistent.
* Easy to review.

These standards apply primarily to T-SQL and Git-based development.

---

## 2. General Engineering Standards

All code must:

* Serve a clearly defined purpose.
* Follow the project naming conventions.
* Be stored in source control.
* Be reviewed before merging into `main`.
* Avoid undocumented manual database changes.
* Include appropriate error handling.
* Avoid unnecessary complexity.
* Be tested using representative data.
* Preserve data integrity.
* Favor deterministic and repeatable behavior.

---

## 3. SQL Formatting

### 3.1 Keywords

Write SQL keywords in uppercase.

```sql
SELECT
    CustomerKey,
    CustomerName
FROM dw.DimCustomer;
```

### 3.2 Indentation

Use four spaces for indentation.

Do not use tabs.

```sql
SELECT
    CustomerKey,
    CustomerName
FROM dw.DimCustomer
WHERE IsCurrent = 1;
```

### 3.3 One Column per Line

Place selected columns on separate lines when a query contains multiple fields.

```sql
SELECT
    CustomerKey,
    CustomerID,
    CustomerName,
    TerritoryKey,
    IsCurrent
FROM dw.DimCustomer;
```

### 3.4 Commas

Place commas at the end of each line.

```sql
SELECT
    CustomerKey,
    CustomerID,
    CustomerName
FROM dw.DimCustomer;
```

### 3.5 Semicolons

Terminate SQL statements with semicolons.

```sql
SELECT
    ProductKey,
    ProductName
FROM dw.DimProduct;
```

### 3.6 Schema Qualification

Always qualify database objects with their schema.

Preferred:

```sql
SELECT *
FROM dw.DimCustomer;
```

Avoid:

```sql
SELECT *
FROM DimCustomer;
```

### 3.7 Aliases

Use short but meaningful aliases.

```sql
SELECT
    c.CustomerKey,
    c.CustomerName,
    t.TerritoryName
FROM dw.DimCustomer AS c
INNER JOIN dw.DimTerritory AS t
    ON c.TerritoryKey = t.TerritoryKey;
```

Avoid aliases that are difficult to interpret.

```sql
FROM dw.DimCustomer AS a
INNER JOIN dw.DimTerritory AS b
```

---

## 4. SELECT Statements

### 4.1 Avoid `SELECT *`

Specify only required columns.

Preferred:

```sql
SELECT
    CustomerKey,
    CustomerName,
    TerritoryKey
FROM dw.DimCustomer;
```

Avoid:

```sql
SELECT *
FROM dw.DimCustomer;
```

Exceptions may be acceptable during temporary investigation but should not remain in production scripts, views, procedures, or ETL logic.

### 4.2 Use Explicit Column Aliases

Derived expressions must have meaningful aliases.

```sql
SELECT
    SUM(NetSalesAmount) AS TotalNetSalesAmount
FROM dw.FactSales;
```

### 4.3 Preserve SARGability

Avoid wrapping indexed filter columns in functions when an equivalent range predicate can be used.

Preferred:

```sql
WHERE OrderDate >= '2026-01-01'
  AND OrderDate < '2027-01-01';
```

Avoid:

```sql
WHERE YEAR(OrderDate) = 2026;
```

The preferred form gives the optimizer a better opportunity to use an index seek.

---

## 5. JOIN Standards

### 5.1 Use Explicit JOIN Syntax

Preferred:

```sql
SELECT
    s.SalesKey,
    c.CustomerName
FROM dw.FactSales AS s
INNER JOIN dw.DimCustomer AS c
    ON s.CustomerKey = c.CustomerKey;
```

Avoid comma-separated joins.

```sql
FROM dw.FactSales AS s,
     dw.DimCustomer AS c
WHERE s.CustomerKey = c.CustomerKey;
```

### 5.2 Qualify Join Columns

Always qualify columns participating in joins.

```sql
ON s.ProductKey = p.ProductKey
```

### 5.3 Choose the Correct Join Type

Use:

* `INNER JOIN` when matching rows are required.
* `LEFT JOIN` when unmatched left-side rows must be preserved.
* `CROSS JOIN` only when a Cartesian product is intentional.

Do not use `LEFT JOIN` automatically without considering the business meaning.

### 5.4 Avoid Accidental Many-to-Many Joins

Before joining tables, confirm:

* The expected relationship.
* The join key.
* The uniqueness of the parent side.
* The intended result grain.

---

## 6. Filtering and Aggregation

### 6.1 Use `WHERE` Before Aggregation

Use `WHERE` to filter rows before grouping.

```sql
SELECT
    TerritoryKey,
    SUM(NetSalesAmount) AS TotalNetSalesAmount
FROM dw.FactSales
WHERE OrderDateKey >= 20260101
GROUP BY
    TerritoryKey;
```

### 6.2 Use `HAVING` for Aggregate Filters

```sql
SELECT
    CustomerKey,
    SUM(NetSalesAmount) AS TotalNetSalesAmount
FROM dw.FactSales
GROUP BY
    CustomerKey
HAVING SUM(NetSalesAmount) > 100000;
```

### 6.3 Avoid Unnecessary `DISTINCT`

Do not use `DISTINCT` to hide incorrect joins.

Investigate and correct the cause of duplicate rows.

---

## 7. Data Types

### 7.1 Use the Smallest Appropriate Type

Select types based on business range and precision requirements.

### 7.2 Monetary Values

Use `DECIMAL` or `NUMERIC`.

Example:

```sql
NetSalesAmount DECIMAL(19, 4)
```

Avoid approximate floating-point types for financial values.

### 7.3 Unicode

Use `NVARCHAR` when Unicode text support is required.

### 7.4 Dates

Use:

* `DATE` for dates without time.
* `DATETIME2` for timestamps.
* `TIME` for time-only values.

Prefer `DATETIME2` over legacy `DATETIME`.

### 7.5 Boolean Values

Use `BIT`.

### 7.6 Avoid Oversized Columns

Do not use `NVARCHAR(MAX)` unless the expected data genuinely requires it.

---

## 8. Nullability

Declare columns as `NOT NULL` whenever the business rule requires a value.

Use `NULL` only when absence of a value has a defined meaning.

Do not use empty strings, zero, or arbitrary dates as undocumented substitutes for null.

---

## 9. Keys

### 9.1 Surrogate Keys

Dimension tables should use integer surrogate keys.

Example:

```sql
CustomerKey INT IDENTITY(1, 1) NOT NULL
```

### 9.2 Business Keys

Source-system identifiers should be retained for matching and lineage.

Example:

```sql
CustomerID INT NOT NULL
```

### 9.3 Foreign Keys

Foreign keys should be enforced in the dimensional warehouse when operational requirements permit.

### 9.4 Date Keys

The date dimension uses an integer key in `YYYYMMDD` format.

Example:

```text
20260729
```

---

## 10. Table Creation

Table definitions should:

1. Declare columns.
2. Declare nullability.
3. Define default values.
4. Define primary keys.
5. Define unique constraints.
6. Define check constraints.
7. Define foreign keys.

Example:

```sql
CREATE TABLE dw.DimTerritory
(
    TerritoryKey INT IDENTITY(1, 1) NOT NULL,
    TerritoryID INT NOT NULL,
    TerritoryName NVARCHAR(100) NOT NULL,
    CountryRegionCode NVARCHAR(3) NOT NULL,
    TerritoryGroup NVARCHAR(50) NOT NULL,
    IsCurrent BIT NOT NULL
        CONSTRAINT DF_DimTerritory_IsCurrent DEFAULT (1),
    EffectiveStartDate DATE NOT NULL,
    EffectiveEndDate DATE NOT NULL,

    CONSTRAINT PK_DimTerritory
        PRIMARY KEY CLUSTERED (TerritoryKey),

    CONSTRAINT CK_DimTerritory_ValidEffectiveDates
        CHECK (EffectiveEndDate >= EffectiveStartDate)
);
```

---

## 11. Idempotent Deployment Scripts

Deployment scripts should be safe to execute in a controlled repeatable process.

For database creation:

```sql
IF DB_ID(N'AdventureWorks_EDW') IS NULL
BEGIN
    CREATE DATABASE AdventureWorks_EDW;
END;
```

For schemas:

```sql
IF SCHEMA_ID(N'dw') IS NULL
BEGIN
    EXEC sys.sp_executesql N'CREATE SCHEMA dw';
END;
```

Avoid dropping production objects automatically unless the script is specifically intended for destructive environment initialization.

---

## 12. Stored Procedures

### 12.1 Use `CREATE OR ALTER`

```sql
CREATE OR ALTER PROCEDURE etl.LoadDimCustomer
AS
BEGIN
    SET NOCOUNT ON;

    -- Procedure logic
END;
```

### 12.2 Use `SET NOCOUNT ON`

This prevents row-count messages from interfering with client applications and orchestration tools.

### 12.3 Validate Parameters

Validate required parameters near the beginning of the procedure.

```sql
IF @batchID IS NULL
BEGIN
    THROW 50001, 'BatchID is required.', 1;
END;
```

### 12.4 Avoid Hidden Behavior

A procedure name and parameters should clearly communicate its responsibility.

### 12.5 Return Useful Execution Information

Where appropriate, ETL procedures should expose:

* Execution status.
* Rows inserted.
* Rows updated.
* Rows rejected.
* Error details.

---

## 13. Error Handling

Use `TRY...CATCH` for operations that may fail.

```sql
BEGIN TRY
    BEGIN TRANSACTION;

    -- Data modification logic

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;
END CATCH;
```

### Standards

* Roll back active transactions after failure.
* Preserve the original error using `THROW`.
* Record error details in audit tables when appropriate.
* Do not suppress errors using only `PRINT`.
* Do not continue processing after an unrecoverable failure.

---

## 14. Transactions

Use transactions when multiple operations must succeed or fail as one unit.

Keep transactions:

* As short as possible.
* Focused on one logical unit of work.
* Free from unnecessary user interaction.
* Free from long-running external operations.

Use:

```sql
SET XACT_ABORT ON;
```

when appropriate so runtime errors automatically terminate and roll back transactions.

---

## 15. Temporary Objects

Use CTEs when:

* The result is referenced once.
* The logic benefits from readable decomposition.
* Recursive processing is required.

Use temporary tables when:

* Intermediate results are reused.
* Indexes are beneficial.
* Statistics may improve the execution plan.
* The intermediate result is large or complex.
* Processing occurs in multiple phases.

Use table variables only for small datasets and after considering optimizer behavior.

---

## 16. Common Table Expressions

CTEs should improve readability rather than merely move complexity elsewhere.

```sql
WITH CustomerSales AS
(
    SELECT
        CustomerKey,
        SUM(NetSalesAmount) AS TotalNetSalesAmount
    FROM dw.FactSales
    GROUP BY
        CustomerKey
)
SELECT
    CustomerKey,
    TotalNetSalesAmount
FROM CustomerSales
WHERE TotalNetSalesAmount > 100000;
```

Always provide column aliases for calculated expressions.

Recursive CTEs must include a valid termination condition.

---

## 17. Slowly Changing Dimensions

### Type 1

Use Type 1 when previous values do not need to be retained.

Updates overwrite the current record.

### Type 2

Use Type 2 when historical changes must be preserved.

Type 2 logic must:

1. Identify the current dimension record.
2. Compare tracked attributes.
3. Expire the current record when a change exists.
4. Insert a new current version.
5. Preserve the same business key.
6. Assign a new surrogate key.

Current records should use:

```text
IsCurrent = 1
```

Expired records should use:

```text
IsCurrent = 0
```

Date ranges must not overlap for the same business key.

---

## 18. Fact Table Loading

Fact-table loads must respect the declared grain.

Before insertion:

* Resolve all required surrogate keys.
* Use unknown-member keys when permitted.
* Validate required measures.
* Prevent unintended duplicate grain.
* Capture rejected records.
* Record source-to-target row counts.

Dimension lookups should use business keys and the correct historical date context where Type 2 dimensions are involved.

---

## 19. Incremental Loads

Incremental loads should use a documented change-detection strategy, such as:

* Last modified date.
* High-watermark column.
* Change Tracking.
* Change Data Capture.
* Source-generated sequence.
* Hash comparison.

Watermarks must be updated only after a successful load.

A failed batch must not advance the watermark.

---

## 20. MERGE Statement

Use the SQL Server `MERGE` statement cautiously.

For critical ETL logic, separate `UPDATE` and `INSERT` operations are often easier to test and troubleshoot.

Any use of `MERGE` must be justified, tested for concurrency behavior, and reviewed carefully.

---

## 21. Dynamic SQL

Use dynamic SQL only when the SQL structure genuinely needs to be generated at runtime.

Use:

```sql
sys.sp_executesql
```

with typed parameters.

Avoid string concatenation of untrusted values.

Preferred:

```sql
DECLARE @sql NVARCHAR(MAX);

SET @sql = N'
SELECT
    CustomerKey,
    CustomerName
FROM dw.DimCustomer
WHERE TerritoryKey = @territoryKey;';

EXEC sys.sp_executesql
    @sql,
    N'@territoryKey INT',
    @territoryKey = @territoryKey;
```

---

## 22. Security

### 22.1 Do Not Store Secrets

Never commit:

* Passwords.
* Connection strings containing credentials.
* Access tokens.
* Private keys.
* Azure secrets.

### 22.2 Use Least Privilege

Database principals should receive only required permissions.

### 22.3 Prevent SQL Injection

Use parameters instead of concatenating external values into dynamic SQL.

### 22.4 Avoid `sa` for Application Access

Use dedicated users, roles, managed identities, or service principals.

---

## 23. Performance Standards

### 23.1 Measure Before Optimizing

Use execution plans and runtime statistics.

Useful commands include:

```sql
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
```

### 23.2 Prefer Set-Based Operations

Avoid cursors and row-by-row processing unless a measured requirement justifies them.

### 23.3 Index Intentionally

Create indexes to support:

* Business-key lookups.
* Foreign-key joins.
* Incremental extraction.
* Common analytical filters.
* Fact-table access paths.

Do not add indexes solely because a column appears in a query.

### 23.4 Consider Write Costs

Every index increases:

* Storage.
* Insert cost.
* Update cost.
* Delete cost.
* Maintenance work.

### 23.5 Review Data Type Consistency

Join columns should use compatible data types to avoid implicit conversions.

---

## 24. Comments

Comments should explain why a decision exists, not restate obvious syntax.

Useful:

```sql
-- Use the unknown member when the source customer cannot be resolved,
-- allowing the sales row to remain measurable for data-quality reporting.
```

Not useful:

```sql
-- Select customers
SELECT CustomerKey
FROM dw.DimCustomer;
```

Complex business rules should be documented near the relevant code.

---

## 25. Script Headers

Major SQL scripts should include a concise header.

```sql
/*
    File: load-dim-customer.sql
    Purpose: Loads the customer dimension using SCD Type 2 logic.
    Database: AdventureWorks_EDW
    Schema: etl
    Author: Diego
    Version: 0.1.0
*/
```

Do not include information that will become inaccurate quickly unless it is maintained.

Git history remains the primary source for change history.

---

## 26. Testing Standards

Each implemented object should be tested for:

* Successful execution.
* Expected output.
* Empty-source behavior.
* Null handling.
* Duplicate handling.
* Invalid input.
* Rerun behavior.
* Transaction rollback.
* Historical-change behavior.
* Referential integrity.
* Fact-table grain.

Tests should be stored in:

```text
tests/
```

Test scripts must avoid permanently altering shared environments unless explicitly designed to do so.

---

## 27. Data Reconciliation

Each ETL process should reconcile:

* Source rows read.
* Staging rows loaded.
* Target rows inserted.
* Target rows updated.
* Rows rejected.
* Final target row count.

Differences must be explainable.

---

## 28. Git Development Standards

### 28.1 Branch Before Changing Code

Create a feature branch from an updated `main`.

```bash
git switch main
git pull --ff-only
git switch -c feature/solution-documentation
```

### 28.2 Make Small Commits

Each commit should represent one logical change.

### 28.3 Review Changes Before Commit

```bash
git status
git diff
git diff --staged
```

### 28.4 Use Meaningful Commit Messages

```text
docs: add architecture and coding standards
```

### 28.5 Push the Feature Branch

```bash
git push -u origin feature/solution-documentation
```

### 28.6 Open a Pull Request

The Pull Request must explain:

* What changed.
* Why it changed.
* How it was validated.
* Any relevant risks or future work.

### 28.7 Protect `main`

Direct commits to `main` should be avoided.

---

## 29. Code Review Checklist

Before approving a change, confirm:

* The code follows naming conventions.
* The declared business grain is preserved.
* Data types are appropriate.
* Nullability is intentional.
* Errors are handled.
* Transactions are safe.
* Security risks are addressed.
* Tests are included.
* Performance implications were considered.
* Documentation is updated.
* No secrets are committed.
* The change can be reproduced from source control.

---

## 30. Definition of Done

A feature is complete when:

1. The implementation works.
2. The code follows project standards.
3. Tests pass.
4. Documentation is updated.
5. No secrets or temporary artifacts are committed.
6. The feature branch has been pushed.
7. A Pull Request has been reviewed.
8. The change has been merged into `main`.
9. The branch has been removed when no longer needed.
