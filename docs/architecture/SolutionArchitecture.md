# Solution Architecture

## AdventureWorks Enterprise Data Warehouse

| Attribute              | Value                                    |
| ---------------------- | ---------------------------------------- |
| Project                | AdventureWorks Enterprise Data Warehouse |
| Source System          | AdventureWorks2022                       |
| Target Database        | AdventureWorks_EDW                       |
| Architecture Style     | Layered Data Architecture                |
| Data Modeling Approach | Kimball Dimensional Modeling             |
| Repository             | AdventureWorks-Enterprise-DataWarehouse  |
| Status                 | In development                           |
| Version                | 0.1.0                                    |

---

## 1. Purpose

This document describes the solution architecture for the AdventureWorks Enterprise Data Warehouse project.

The solution is designed to extract operational data from the AdventureWorks2022 transactional database, process it through a staging layer, and load it into a dimensional Enterprise Data Warehouse optimized for analytics and reporting.

The project is intended to demonstrate professional Data Engineering practices, including:

* Dimensional data modeling.
* ETL and ELT pipeline development.
* Data quality validation.
* Slowly Changing Dimensions.
* Incremental data loading.
* Auditability and observability.
* Performance optimization.
* Cloud orchestration with Azure Data Factory.
* Analytics consumption through Power BI and Microsoft Fabric.
* Source control using Git and GitHub.

---

## 2. Business Problem

The AdventureWorks2022 database is an Online Transaction Processing system designed to support operational business transactions.

Although it is suitable for recording sales, customers, products, employees, and territories, its normalized structure is not optimized for analytical workloads.

Analytical queries against the transactional database may require:

* Multiple joins across normalized tables.
* Complex business logic.
* Repeated calculations.
* Direct access to production operational data.
* Queries that compete with transactional workloads.

The Enterprise Data Warehouse addresses these limitations by providing:

* A centralized analytical data store.
* Historical business information.
* Consistent dimensions and measures.
* Simplified star-schema reporting.
* Improved analytical query performance.
* Separation between transactional and analytical workloads.

---

## 3. Scope

### 3.1 In Scope

The initial version of the solution includes:

* Sales data extraction from AdventureWorks2022.
* A dedicated staging layer.
* A dimensional Enterprise Data Warehouse.
* A sales fact table.
* Conformed business dimensions.
* Full and incremental ETL processes.
* Slowly Changing Dimension processing.
* Data quality checks.
* ETL execution logging.
* Power BI-ready analytical structures.
* Azure Data Factory orchestration.
* Git and GitHub-based source control.

### 3.2 Out of Scope

The initial version does not include:

* Real-time streaming ingestion.
* Machine Learning model deployment.
* Production-grade high availability.
* Personally identifiable information masking.
* Multi-region disaster recovery.
* Enterprise master data management.
* Production-level security integration with Microsoft Entra ID.

These capabilities may be considered in future project versions.

---

## 4. Architectural Principles

### AP-001 — Separation of Workloads

The Enterprise Data Warehouse must not depend on analytical queries executed directly against the operational source system.

Operational and analytical workloads must remain logically separated.

### AP-002 — Staging Before Transformation

Source data must first be extracted into the staging layer before being transformed and loaded into dimensional tables.

### AP-003 — Reproducible Deployments

Every database object must be created through version-controlled scripts.

Manual changes made directly in the database must be avoided.

### AP-004 — Traceable Data Loads

Every ETL execution must be traceable through audit records containing execution status, processed rows, rejected rows, start time, end time, and error information.

### AP-005 — Idempotent Processing

ETL processes should be designed so they can be safely rerun without generating unintended duplicate records.

### AP-006 — Historical Preservation

Historical attribute changes must be preserved when required by analytical use cases.

### AP-007 — Data Quality by Design

Data quality validations must be included as part of the pipeline rather than treated as a separate manual activity.

### AP-008 — Documented Decisions

Every significant architectural decision must be documented.

### AP-009 — Least Privilege

Database users and services must receive only the permissions required to perform their responsibilities.

### AP-010 — Observable Pipelines

Pipeline executions must provide sufficient information to diagnose failures and measure operational performance.

---

## 5. High-Level Architecture

```text
+---------------------------+
| AdventureWorks2022        |
| Operational Source System |
| OLTP                      |
+-------------+-------------+
              |
              | Extract
              v
+---------------------------+
| Staging Layer             |
| Schema: stg               |
| Raw and standardized data |
+-------------+-------------+
              |
              | Validate and transform
              v
+---------------------------+
| Enterprise Data Warehouse |
| Schema: dw                |
| Dimensions and facts      |
+-------------+-------------+
              |
              | Curated analytical data
              v
+---------------------------+
| Semantic and BI Layer     |
| Power BI / Fabric         |
+---------------------------+

Supporting components:

+---------------------------+
| ETL Control Layer         |
| Schema: etl               |
+---------------------------+

+---------------------------+
| Audit and Monitoring      |
| Schema: audit             |
+---------------------------+
```

---

## 6. Logical Data Flow

The solution follows this logical sequence:

```text
Source
  |
  v
Extract
  |
  v
Stage
  |
  v
Validate
  |
  v
Transform
  |
  v
Load Dimensions
  |
  v
Load Facts
  |
  v
Run Data Quality Checks
  |
  v
Publish for Analytics
```

### 6.1 Extraction

Required source data is extracted from AdventureWorks2022.

Initial development may use full loads. Later versions will introduce incremental extraction based on suitable change-detection columns.

### 6.2 Staging

Source data is loaded into tables in the `stg` schema.

The staging layer:

* Preserves source-system values.
* Provides isolation from the operational database.
* Supports troubleshooting.
* Allows repeatable downstream processing.
* May apply limited technical standardization.
* Does not contain complex analytical business logic.

### 6.3 Transformation

Data is cleaned and transformed before entering the dimensional model.

Transformations may include:

* Data type standardization.
* Null-value handling.
* Business-key validation.
* Duplicate detection.
* Derived attributes.
* Surrogate-key lookup.
* Historical-change detection.
* Rejected-record identification.

### 6.4 Dimension Loading

Dimension tables are loaded before fact tables.

This ensures that the required surrogate keys are available when fact records are processed.

### 6.5 Fact Loading

Fact records are loaded at the declared business grain.

Each fact row references dimension records through surrogate keys.

### 6.6 Publication

Validated dimensional data is made available to Power BI, Microsoft Fabric, or other analytical consumers.

---

## 7. Dimensional Model

### 7.1 Business Process

The initial dimensional model represents the sales business process.

### 7.2 Fact Table Grain

One row in `dw.FactSales` represents one product line sold within one sales order.

The grain must be declared before measures and foreign keys are defined.

### 7.3 Dimensions

The initial conformed dimensions are:

* `dw.DimDate`
* `dw.DimProduct`
* `dw.DimCustomer`
* `dw.DimSalesPerson`
* `dw.DimTerritory`

### 7.4 Fact Table

The initial fact table is:

* `dw.FactSales`

### 7.5 Measures

Candidate measures include:

* Order quantity.
* Unit price.
* Unit price discount.
* Gross sales amount.
* Discount amount.
* Net sales amount.
* Standard cost.
* Total product cost.
* Gross profit.

### 7.6 Keys

Dimension tables use surrogate integer keys as their primary keys.

Source-system identifiers are retained as business keys where required for ETL matching and lineage.

The date dimension uses a smart integer key in `YYYYMMDD` format.

---

## 8. Slowly Changing Dimensions

The solution may use different Slowly Changing Dimension strategies depending on the business requirement.

### Type 0

The original value is preserved and never overwritten.

### Type 1

The existing value is overwritten without preserving history.

### Type 2

A new dimension row is created when a tracked attribute changes.

Type 2 dimensions should contain fields similar to:

* `EffectiveStartDate`
* `EffectiveEndDate`
* `IsCurrent`

The exact SCD strategy must be documented for each dimension.

---

## 9. Database Schemas

### `stg`

Contains extracted source data and technically standardized records.

### `dw`

Contains dimension tables, fact tables, and analytical views.

### `etl`

Contains ETL control objects, configuration tables, and load procedures.

### `audit`

Contains execution logs, row counts, rejected records, and operational metadata.

---

## 10. Physical Database

The initial implementation uses Microsoft SQL Server.

### Target Database

```text
AdventureWorks_EDW
```

### Recovery Model

```text
SIMPLE
```

The SIMPLE recovery model is appropriate for this learning and portfolio environment because point-in-time recovery and transaction-log backup management are outside the initial scope.

A production implementation would evaluate recovery requirements separately.

---

## 11. ETL Architecture

The ETL solution is divided into the following phases:

1. Initialize execution.
2. Extract source data.
3. Load staging tables.
4. Validate staged data.
5. Load dimensions.
6. Load fact tables.
7. Execute quality checks.
8. Record final row counts.
9. Complete or fail the execution.

Each execution should receive a unique batch identifier.

Suggested metadata includes:

* `BatchID`
* `PipelineName`
* `SourceSystem`
* `StartDateTime`
* `EndDateTime`
* `ExecutionStatus`
* `RowsRead`
* `RowsInserted`
* `RowsUpdated`
* `RowsRejected`
* `ErrorMessage`

---

## 12. Error Handling

ETL procedures must use structured error handling.

The expected pattern includes:

* `TRY...CATCH`.
* Explicit transaction management where appropriate.
* Transaction rollback after failures.
* Error information captured in audit tables.
* Meaningful errors propagated to the orchestrator.

Errors must not be silently ignored.

---

## 13. Data Quality

Data quality controls may validate:

* Required business keys.
* Duplicate business keys.
* Referential integrity.
* Accepted value ranges.
* Valid date ranges.
* Nonnegative monetary values.
* Valid source-system mappings.
* Unknown dimension members.
* Fact-table grain uniqueness.
* Source-to-target row counts.

Failed records should be traceable and, where appropriate, stored in rejection tables.

---

## 14. Unknown Dimension Members

Dimension tables should include an unknown member to support fact records whose dimension relationship cannot be resolved during loading.

A conventional unknown surrogate key is:

```text
-1
```

The unknown member prevents unresolved records from creating null foreign keys and allows data-quality issues to remain measurable.

---

## 15. Security

The solution should follow least-privilege principles.

Recommended logical roles include:

* ETL execution role.
* Read-only reporting role.
* Database deployment role.
* Administrative role.

Credentials and secrets must not be stored in source-controlled files.

Future cloud implementations should use managed identities and secure secret stores where possible.

---

## 16. Performance Considerations

Performance design may include:

* Clustered indexes on surrogate primary keys.
* Nonclustered indexes on business keys.
* Indexes supporting surrogate-key lookups.
* Appropriate staging-table indexes.
* Set-based transformations.
* Statistics maintenance.
* Execution-plan analysis.
* Partitioning evaluation for large fact tables.
* Incremental loads instead of repeated full loads.

Indexes must be introduced based on measured workload requirements rather than added indiscriminately.

---

## 17. Deployment Strategy

Database objects must be deployed using ordered SQL scripts.

Suggested execution order:

```text
1. Database creation
2. Schema creation
3. Audit objects
4. ETL control objects
5. Staging tables
6. Dimension tables
7. Fact tables
8. Stored procedures
9. Views
10. Indexes
11. Seed data
12. Validation tests
```

Scripts should be safe, predictable, and clearly documented.

---

## 18. Source Control Strategy

The project uses a simplified GitHub Flow.

Branches:

```text
main
feature/*
```

Development workflow:

```text
Create feature branch
        |
        v
Implement changes
        |
        v
Commit small logical units
        |
        v
Push branch
        |
        v
Open Pull Request
        |
        v
Review and validate
        |
        v
Merge into main
        |
        v
Delete feature branch
```

The `main` branch represents the stable version of the project.

Direct development on `main` should be avoided.

---

## 19. Technology Stack

### Current

* SQL Server.
* T-SQL.
* AdventureWorks2022.
* Git.
* GitHub.
* Visual Studio Code.
* SQL Server Management Studio or compatible SQL tooling.
* Markdown.

### Planned

* Azure Data Factory.
* Azure Data Lake Storage.
* Azure SQL Database or Azure Synapse Analytics.
* Power BI.
* Microsoft Fabric.
* GitHub Actions.

---

## 20. Quality Attributes

### Maintainability

Code and documentation must follow consistent standards.

### Scalability

The architecture should support incremental growth in data volume and pipeline complexity.

### Reliability

Loads must be recoverable, repeatable, and auditable.

### Performance

Analytical queries must be supported by an optimized dimensional design.

### Testability

Transformations and database objects must be verifiable using repeatable tests.

### Traceability

Data and code changes must be traceable through audit records and Git history.

### Portability

The design should be adaptable from local SQL Server development to Azure and Microsoft Fabric services.

---

## 21. Future Enhancements

Future versions may include:

* Metadata-driven pipelines.
* Change Data Capture.
* Azure Data Factory orchestration.
* Azure Data Lake Storage.
* Microsoft Fabric Lakehouse.
* Delta Lake tables.
* CI/CD with GitHub Actions.
* Automated SQL linting.
* Automated database tests.
* Power BI semantic models.
* Row-level security.
* Pipeline alerts and monitoring dashboards.
* Data lineage documentation.
* Infrastructure as Code.

---

## 22. Architecture Decision Records

Significant technical decisions must be recorded in:

```text
docs/adr/
```

Examples include:

* Selection of Kimball dimensional modeling.
* Selection of GitHub Flow.
* Selection of the SQL Server recovery model.
* Selection of the date-key strategy.
* Selection of Slowly Changing Dimension types.
* Selection of incremental loading methods.

---

## 23. Version History

| Version | Date       | Description                   |
| ------- | ---------- | ----------------------------- |
| 0.1.0   | 2026-07-29 | Initial solution architecture |
