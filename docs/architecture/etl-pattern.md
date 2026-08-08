# ETL Architecture Pattern

## 1. Purpose

This document defines the standard ETL architecture used throughout the AdventureWorks Enterprise Data Warehouse.

Every ETL process implemented in this project must follow the same execution pattern to ensure consistency, maintainability, observability, auditability, and predictable behavior.

The standard applies to:

- Staging loads
- Dimension loads
- Fact loads
- Incremental loads
- Future CDC-based loads

---

## 2. ETL Pipeline Architecture

Every ETL process follows the same high-level pipeline.

```text
AdventureWorks2022
        │
        ▼
Extraction
        │
        ▼
Staging
        │
        ▼
Validation
        │
        ▼
Transformation
        │
        ▼
Warehouse
        │
        ▼
Audit
```

Each stage has a clearly defined responsibility.

---

## 3. Standard ETL Flow

Every ETL stored procedure should follow this sequence.

```text
Start Audit
      │
      ▼
Capture ExecutionID
      │
      ▼
Extract Source
      │
      ▼
Validate Data
      │
      ▼
Load Staging
      │
      ▼
Transform
      │
      ▼
Load Warehouse
      │
      ▼
Update Audit
```

---

## 4. Layer Responsibilities

### Source Layer

Responsibilities:

- Read-only access
- No transformations
- Preserve source integrity

---

### Staging Layer

Responsibilities:

- Temporary landing zone
- Current source snapshot
- Data normalization
- RowHash generation
- SourceModifiedDate preservation

No business history is stored.

---

### Warehouse Layer

Responsibilities:

- Historical dimensions
- Fact tables
- Surrogate keys
- Business rules
- SCD processing
- Referential integrity

---

### Audit Layer

Responsibilities:

- Execution tracking
- Performance metrics
- Error logging
- Operational monitoring

---

## 5. Procedure Structure

Every ETL procedure should follow this template:

```text
Initialize

↓

Audit Start

↓

Capture ExecutionID

↓

Extract

↓

Transform

↓

Load

↓

Audit Success

↓

Return
```

Any failure:

```text
TRY

↓

Failure

↓

ROLLBACK

↓

Audit Failure

↓

THROW
```

---

## 6. Transactions

Warehouse modifications should execute inside explicit transactions.

```text
BEGIN TRANSACTION

Warehouse Changes

COMMIT
```

If any error occurs:

```text
ROLLBACK
```

The warehouse must never be left in a partially updated state.

---

## 7. Error Handling

Standard pattern:

```sql
BEGIN TRY

...

END TRY

BEGIN CATCH

...

THROW;

END CATCH
```

Errors must always be propagated after audit logging.

---

## 8. Audit Framework

Every ETL execution must create an audit record.

Mandatory metrics include:

```text
ExecutionID
Status
RowsRead
RowsInserted
RowsUpdated
RowsRejected
StartTime
EndTime
ErrorMessage
```

Audit records provide operational traceability.

---

## 9. Idempotency

Every ETL process must be idempotent.

Repeated execution without source changes must not produce additional modifications.

Expected behavior:

```text
Run 1

504 inserted

↓

Run 2

0 inserted
0 updated
```

---

## 10. RowHash Strategy

Where appropriate:

```text
Extract

↓

Normalize

↓

Generate SHA2-256

↓

Compare

↓

Determine change
```

Hash generation rules are defined in:

```text
docs/architecture/scd-strategies.md
```

---

## 11. SourceModifiedDate

Every staging object should preserve the latest meaningful source modification timestamp.

This enables:

- incremental loading;
- future watermark loading;
- CDC integration;
- troubleshooting.

---

## 12. Validation

Before warehouse loading, ETL processes should validate:

- duplicate business keys;
- mandatory columns;
- invalid dates;
- referential consistency;
- business-rule compliance.

Invalid records should not silently enter the warehouse.

---

## 13. Naming Convention

Stored procedures:

```text
etl.Load<Product>Stage
etl.LoadDim<Product>
etl.LoadFact<FactName>
```

Examples:

```text
etl.LoadProductStage
etl.LoadDimProduct
etl.LoadCustomerStage
etl.LoadDimCustomer
```

---

## 14. Logging Philosophy

The audit layer represents the operational truth of ETL execution.

Warehouse data should never be interpreted without corresponding execution metadata.

---

## 15. Future Evolution

The ETL architecture has been designed to support:

```text
Full Load

↓

Watermark

↓

CDC

↓

Azure Data Factory

↓

Apache Airflow

↓

Microsoft Fabric Pipelines
```

The ETL standard remains unchanged regardless of orchestration technology.

---

## 16. Architecture Principles

1. Every ETL is auditable.
2. Every ETL is repeatable.
3. Every ETL is transactional.
4. Every ETL is idempotent.
5. Warehouse integrity takes priority over ETL completion.
6. Business rules belong in the warehouse layer.
7. Every warehouse object must have a deterministic loading process.
8. Future cloud orchestration must reuse the same logical pattern.

---

## 17. Related Documentation

Dimensional Model

```text
docs/architecture/dimensional-model.md
```

SCD Standards

```text
docs/architecture/scd-strategies.md
```

Dimension Specifications

```text
docs/design/dimensions/
```

---

## 18. Architecture Status

```text
Architecture: Approved
Current Pattern: Full Load
Future Pattern: Incremental + CDC
Current Release: v1.1.0
```