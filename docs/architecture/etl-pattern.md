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
- Current source snapshot or bounded incremental batch delta
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
- Persisted incremental-control state

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
- watermark-based extraction;
- future CDC integration;
- troubleshooting.

### 11.1 Composite Watermark Standard

The implemented incremental pilot uses a deterministic composite source
position:

```text
(ModifiedDate, BusinessKey)
```

A timestamp alone is insufficient when multiple rows share the same
`ModifiedDate`. The business-key component provides deterministic ordering.

The extraction contract is:

```text
LOW < source row <= HIGH
```

Where:

```text
LOW  = last successfully committed source position
HIGH = frozen upper boundary for the current batch
```

LOW is exclusive and HIGH is inclusive.

A NULL LOW represents the initial incremental batch.

### 11.2 High Watermark Batch Control

A new batch begins by capturing the maximum composite source position and
persisting it as HIGH.

```text
Ready
  ↓
capture source HIGH
  ↓
persist HIGH
  ↓
InProgress
  ↓
process staging + warehouse
```

HIGH is frozen before downstream processing begins so the batch scope remains
stable even if the source changes while processing is running.

LOW advances only after the complete batch succeeds.

```text
successful batch

LOW = previous HIGH
HIGH = NULL
Status = Ready
```

### 11.3 Failure and Retry Contract

If processing fails after HIGH has been persisted:

```text
LOW    = unchanged
HIGH   = retained
Status = Failed
```

A retry must reuse the persisted HIGH.

It must not capture a newer source HIGH because doing so would change the
boundaries of the failed batch.

```text
Failed
  ↓
reuse persisted HIGH
  ↓
InProgress
  ↓
retry exact batch
  ↓
Ready
```

This provides deterministic batch restartability.

### 11.4 No-Change Execution

If the current source maximum is not greater than LOW, there is no new
incremental batch.

The process:

```text
detects no change
      ↓
clears incremental staging
      ↓
skips downstream dimension processing
      ↓
records a successful no-op execution
```

A no-op does not advance `LastSuccessfulExecutionID` because no watermark
progress was committed.

### 11.5 Concurrency Control

Watermark acquisition uses serialized access to the watermark control record through:

```text
UPDLOCK
HOLDLOCK
```

The lock is held only while reading and transitioning the watermark state.

Long-running staging and dimensional processing do not retain the watermark
transaction lock.

A concurrent execution that encounters:

```text
Status = InProgress
```

is rejected rather than processing the same batch simultaneously.

### 11.6 Multi-Source Incremental Loads

A single composite watermark is appropriate when one ordered source stream
fully represents the relevant changes for an analytical entity.

For entities composed from multiple independent source tables, one universal
watermark should not be assumed.

The preferred pattern is:

```text
source-specific change detection
            ↓
derive affected business keys
            ↓
rebuild complete analytical entity
            ↓
load staging
            ↓
process warehouse changes
```

Each independently changing source may require its own incremental position.

### 11.7 Delete Limitation

A conventional `ModifiedDate` watermark detects source rows that still exist
and whose modification position moves forward.

It does not detect a physical source-row deletion because the deleted row is no
longer available to expose a `ModifiedDate`.

Hard-delete detection requires a separate mechanism such as:

```text
CDC
Change Tracking
soft-delete indicators
source audit tables
periodic reconciliation
snapshot comparison
```

### 11.8 Recovery Limitation

The current SQL error path converts a failed active batch from `InProgress` to
`Failed` and preserves its HIGH boundary.

An abrupt session or process termination that bypasses SQL error handling may
leave a watermark in `InProgress`.

Automated stale-execution detection or lease-based recovery is outside Module 5
and belongs to future ETL reliability work.

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
etl.Load<Product>Incremental
etl.LoadFact<FactName>
```

Examples:

```text
etl.LoadProductStage
etl.LoadDimProduct
etl.LoadCustomerStage
etl.LoadDimCustomer
etl.LoadShipMethodIncremental
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

Composite + High Watermark Incremental Loading

↓

Data Quality & ETL Reliability

↓

Performance & Optimization

↓

Power BI Analytics

↓

Production Polish
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
8. Incremental LOW advances only after complete batch success.
9. Failed batches must retain deterministic retry boundaries.
10. Incremental source suitability must be validated before implementation.

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
Current Pattern: Full Load + Composite/High Watermark Incremental Pilot
Current Stable Release: v1.2.0
Current Module: Module 5 — Composite + High Watermark Incremental Loading
Next Module: Module 6 — Data Quality & ETL Reliability
```