# Incremental Loading Design — FactSales

## 1. Objective and Scope

Implement incremental inserts and updates for `dw.FactSales`, preserving
the grain `(SalesOrderID, SalesOrderDetailID)` and the existing measure
and dimension-resolution contracts.

The full snapshot pipeline remains available for baseline loading.
Incremental processing uses a separate delta staging table and applies
changes without truncating the fact.

Physical source deletions and changes originating only in dimensions
are outside this incremental contract.

## 2. Source Watermarks

The orchestrator is `etl.LoadFactSalesIncremental`.

Two rows in `audit.ETLWatermark` track the source streams:

| ProcessName | SourceObject | Business key |
|---|---|---|
| `etl.LoadFactSalesIncremental.Header` | `AdventureWorks2022.Sales.SalesOrderHeader` | SalesOrderID |
| `etl.LoadFactSalesIncremental.Detail` | `AdventureWorks2022.Sales.SalesOrderDetail` | SalesOrderDetailID |

These ProcessName values identify control streams, not separate procedures.

Each stream uses the ordered pair `(ModifiedDate, BusinessKey)`.
Watermark timestamps preserve source precision through `DATETIME2(7)`.
HIGH is selected from an actual source row ordered by both columns.

Development profiling found unique business keys in both sources.
The observed maximum pairs were:

| Source | ModifiedDate | BusinessKey | Rows sharing timestamp |
|---|---|---|---|
| Header | 2014-07-07 00:00:00.0000000 | 75123 | 40 |
| Detail | 2014-06-30 00:00:00.0000000 | 121317 | 96 |

These values are profiling evidence, not seed values.

## 3. Initialization

Both control rows start in Ready state with null LOW and HIGH pairs.

The first incremental execution captures source HIGH boundaries and
processes all available lines within those boundaries.

Existing fact lines are compared before updating; missing lines are inserted.
LOW advances only after successful fact processing.

A previously completed full load does not automatically initialize these
watermarks. The initial incremental replay establishes verified progress.

## 4. Delta Selection

Each active source stream selects rows within its own composite interval:

`LOW < (ModifiedDate, BusinessKey) <= HIGH`

A null LOW means there is no lower boundary. Pair comparisons use timestamp
first and business key as the tie-breaker.

Candidate fact grains are the union of:

- All detail lines belonging to headers selected by the Header interval.
- Detail lines selected directly by the Detail interval.

UNION removes overlap when both sources select the same line.
The resulting grains are joined to header and detail to build the normalized
delta projection, with one row per `(SalesOrderID, SalesOrderDetailID)`.

The counterpart source row does not need to fall within its own interval:
a changed header must refresh its lines even when their detail timestamps
have not changed, and vice versa.

## 5. Coordinated Batch State

### 5.1 Execution Ownership

The orchestrator acquires an exclusive application lock for the sales
incremental process and retains it through acquisition, loading, finalization,
and failure handling.

Both control rows are inspected together under transaction locks.
An InProgress row blocks a new run; abandoned executions require explicit
recovery after confirming that their owner is no longer running.

### 5.2 New Batch

When both streams are Ready, capture each source's candidate HIGH.

A stream is active only when HIGH exists and either LOW is null
or HIGH is greater than LOW. Persist HIGH, InProgress, and the same parent ExecutionID
for all active streams in one transaction.

Inactive streams remain Ready and unchanged. Do not persist HIGH = LOW.

If neither stream is active, clear delta staging and record a successful
zero-row execution without changing LOW.

### 5.3 Failed Batch Retry

If any stream is Failed, retry the pending batch before acquiring new work.

Failed streams reuse their persisted HIGH and unchanged LOW.
When both streams are Failed, their CurrentExecutionID values must match.

Ready streams remain inactive throughout that retry. Do not capture new
HIGH values for them. Their committed LOW represents their previous progress;
new source changes are deferred until the pending batch succeeds.

All retried active streams receive the new parent ExecutionID together.

### 5.4 Success and Failure

After successful fact processing, finalize all active streams together:
advance LOW to HIGH, clear HIGH and CurrentExecutionID, set Ready, and record
LastSuccessfulExecutionID.

Watermark finalization and parent success auditing share one transaction.
Inactive streams remain unchanged.

On failure before finalization, preserve LOW and the frozen HIGH values.
Mark the streams owned by the current execution as Failed and record the
parent failure together in a transaction after rolling back active work.

Fact application commits before watermark finalization. If finalization fails,
the pending intervals are replayed through idempotent fact processing.

## 6. Delta Application

The incremental components are listed below; their implementation status
is recorded in Section 9.

| Object | Responsibility |
|---|---|
| `stg.SalesOrderLineDelta` | Normalized candidate lines for the current batch |
| `etl.LoadSalesOrderLineDeltaStage` | Extract and deduplicate bounded source changes |
| `etl.LoadFactSalesDelta` | Resolve keys, derive measures, and apply fact changes |
| `etl.LoadFactSalesIncremental` | Coordinate ownership, watermarks, and execution |

Delta staging preserves the full staging projection, with HeaderModifiedDate
and DetailModifiedDate stored as DATETIME2(7).

Fact processing resolves dimensions and derives measures using the existing
FactSales contracts. Required date resolution is validated before applying
target changes.

Within one fact transaction, update existing grains only when their projected
values differ and insert missing grains. Preserve fact rows outside the delta.
Use explicit UPDATE and INSERT operations.

Report actual inserted and updated row counts. An unchanged replay produces
zero inserts and updates. A failed fact transaction rolls back all its changes.

The original full snapshot staging and loading procedures retain their
existing purpose and remain separate from delta processing.

## 7. Source Change Assumptions

Every relevant source insert or update must produce a composite pair greater
than that stream's committed LOW to be detected by this strategy.

The business key resolves timestamp ties within an ordered extraction.
It does not detect later modifications whose pair is at or below LOW.

Unchanged or backdated ModifiedDate values, late commits behind LOW, and
physical deletes are not covered by this watermark-only design.

Development runs require stable source data during boundary capture and
extraction, and stable dimensions during fact resolution.
The application lock coordinates ETL executions; it does not freeze OLTP writes.
Full snapshot and incremental fact loads must not run concurrently.

Persisted HIGH values retain extraction intervals, not historical source
versions. Failed-batch recovery requires source data to remain unchanged until
the retry completes if the same candidate rows and values must be reproduced.

## 8. Required Validation Scenarios

- Initial replay from null LOW reconciles with the existing full snapshot.
- A subsequent no-change run leaves the fact unchanged and delta staging empty.
- Header-only changes refresh all affected order lines.
- Detail-only changes refresh the affected detail lines.
- Changes in both sources produce one candidate per fact grain.
- New orders and new lines are inserted without duplicate grains.
- Timestamp ties and fractional seconds respect composite interval boundaries.
- Unchanged candidate values produce zero fact updates.
- A fact-application failure preserves the previous fact contents and both LOWs.
- Failed active streams retain HIGH and retry without capturing new boundaries.
- A Ready stream remains inactive during another stream's failed-batch retry.
- Replay after fact commit but before watermark finalization is idempotent.
- Concurrent orchestrator execution cannot acquire the same active batch.
- Successful finalization advances all active streams atomically.

## 9. Implementation Progress and Extraction Evidence

### 9.1 Implemented Components

The following scripts have been deployed:

- `database/05_seed/004_SeedFactSalesWatermarks.sql`
- `database/03_staging/007_CreateStagingSalesOrderLineDelta.sql`
- `database/04_procedures/etl.LoadSalesOrderLineDeltaStage.sql`

Both watermark streams were initialized as Ready with null boundaries
and execution references.

Delta staging contains 19 columns. HeaderModifiedDate, DetailModifiedDate,
and ExtractedAt use DATETIME2(7).

The extractor validates interval parameters, selects unique candidate grains,
and replaces delta staging transactionally. Successful staging changes and
their execution audit are committed together.

The extractor does not advance watermarks.

### 9.2 Development Execution Evidence

| ExecutionID | Scenario | Inserted rows | Audit status |
|---|---|---|---|
| 63 | Both sources active, null LOW, current source HIGH | 121317 | Succeeded |
| 64 | Header-only interval selecting order 75123 | 3 | Succeeded |
| 65 | Detail-only interval selecting detail 121317 | 1 | Succeeded |
| 67 | Overlapping Header and Detail selection | 3 | Succeeded |
| 68 | Both sources inactive; previous delta cleared | 0 | Succeeded |
| 69 | Active Header interval with HIGH equal to LOW | 0 | Failed, expected error 51112 |

Execution identifiers describe these development runs, not fixed expectations.

The initial extraction matched all 18 source-derived columns in both
directions with zero differences. All rows shared one ExtractedAt value.

The Header-only test excluded key 75122 and selected all three lines of
order 75123. The Detail-only test excluded key 121316 and selected only
detail 121317. Both tests used equal LOW and HIGH timestamps.

The overlap test retained one copy of detail 121317. The inactive-source
test cleared the previous three rows and left no open transaction.

The invalid-interval test failed before replacing staging, which remained
empty, and left no open transaction.

### 9.3 Fact Delta Application

`etl.LoadFactSalesDelta` is implemented and deployed through:

`database/04_procedures/etl.LoadFactSalesDelta.sql`

The procedure builds the 19-column fact projection, validates required dates
and projection row counts, updates changed existing grains, and inserts
missing grains. Fact rows outside the delta are preserved.

Comparison uses EXCEPT across the 17 non-key columns, including nullable
ShipDateKey. RowsRead, RowsInserted, and RowsUpdated are BIGINT output
parameters. Successful fact changes and their audit entry commit together.

On failure, the procedure rolls back its transaction, resets inserted and
updated counters to zero, records Failed, and rethrows the original error.
It rejects an outer transaction and does not advance watermarks.

| ExecutionID | Scenario | RowsRead | RowsInserted | RowsUpdated | Status |
|---|---|---|---|---|---|
| 70 | Empty delta | 0 | 0 | 0 | Succeeded |
| 72 | Three unchanged lines | 3 | 0 | 0 | Succeeded |
| 73 | Restore a deliberately nulled ShipDateKey | 3 | 0 | 1 | Succeeded |
| 74 | Reinsert a deliberately removed fact line | 3 | 1 | 0 | Succeeded |
| 75 | INSERT failure after a preceding UPDATE | 3 | 0 | 0 | Failed, expected |

Execution 71 extracted the three-line delta for order 75123 used by the
subsequent tests. Execution identifiers are development evidence only.

The empty and unchanged tests preserved all 121317 fact rows exactly.
The successful update and insert tests restored the original fact contents,
with zero differences across all 19 columns in both directions.

For execution 75, detail 121315 had its ShipDateKey temporarily nulled,
and detail 121317 was temporarily removed. A test CHECK constraint then
rejected reinsertion of detail 121317 with error 547.

The loader rolled back the preceding UPDATE as well as the failed INSERT.
All 121316 prepared rows remained identical, and TransactionCountAtCatch
was zero. Cleanup removed the constraint and restored all 121317 original
rows with zero differences and no open transactions.

The executed rollback test body is preserved in
`database/06_validation/006_ValidateFactSalesDeltaRollback.sql`,
with an added descriptive header and development prerequisites.

### 9.4 Incremental Orchestration

`etl.LoadFactSalesIncremental` is implemented and deployed through:

`database/04_procedures/etl.LoadFactSalesIncremental.sql`

The orchestrator acquires an exclusive session application lock, coordinates
both watermark controls, and invokes extraction and fact application.
Active stream acquisition is transactional. Watermark finalization and
parent success auditing also share one transaction.

Failure handling preserves pending boundaries and records owned streams
and the parent execution as Failed together. Parent audit counters retain
committed fact changes if a later finalization step fails.

Initial development execution evidence:

| ExecutionID | Process | RowsRead | RowsInserted | RowsUpdated | Status |
|---|---|---|---|---|---|
| 76 | Orchestrator, initial batch | 121317 | 0 | 0 | Succeeded |
| 77 | Delta extraction | 121317 | 121317 | 0 | Succeeded |
| 78 | Fact delta application | 121317 | 0 | 0 | Succeeded |
| 79 | Orchestrator, no new changes | 0 | 0 | 0 | Succeeded |
| 80 | Empty delta extraction | 0 | 0 | 0 | Succeeded |

Execution 76 advanced both streams from null LOW boundaries to:

- Header: (2014-07-07 00:00:00.0000000, 75123).
- Detail: (2014-06-30 00:00:00.0000000, 121317).

Both controls returned to Ready with null HIGH and CurrentExecutionID,
and LastSuccessfulExecutionID = 76.

Execution 79 preserved both controls, including LastSuccessfulExecutionID.
Its extractor cleared delta staging to zero rows; fact application was
not invoked. All five audit entries recorded no error.

These identifiers and boundaries describe development evidence only.

### 9.5 Controlled Header Failure and Retry

The executed test body is preserved in:

`database/06_validation/007_ValidateFactSalesIncrementalRetry.sql`

The test temporarily moved the Header LOW key from 75123 to 75122,
preserving its date, and nulled ShipDateKey for detail 121317.
A temporary CHECK constraint rejected the loader's attempt to restore
that value. Source data remained unchanged.

| ExecutionID | Scenario | Status | RowsRead | RowsInserted | RowsUpdated |
|---|---|---|---|---|---|
| 81 | Forced fact UPDATE failure | Failed | 3 | 0 | 0 |
| 84 | Retry after removing the constraint | Succeeded | 3 | 0 | 1 |

Execution 81 captured error 547 from `etl.LoadFactSalesDelta`.
The parent audit recorded FactCommitted = 0 and BatchFinalized = 0.
The fact matched the prepared snapshot exactly after rollback, and
TransactionCountAtCatch was zero.

Header retained LOW key 75122 and HIGH key 75123 at the original
Header date, with status Failed and CurrentExecutionID = 81.
Its previous LastSuccessfulExecutionID was preserved.
Every column of the inactive Detail control remained unchanged.

After removing the constraint, execution 84 restored the pending fact
value. All 19 fact columns matched the original snapshot in both directions.
Header returned to Ready, advanced LOW to the retained HIGH, cleared its
pending state, and recorded LastSuccessfulExecutionID = 84.
Detail remained identical to its original state throughout the retry.

Test cleanup then restored the original watermark rows, including their
execution references and UpdatedAt values, and restored delta staging.
The final state contained 121317 fact rows, zero delta rows, no validation
constraint, and no open transaction. Audit entries were retained.

The test passed all assertions. Execution identifiers describe development
evidence only. The saved copy adds script identification to the tested body.

### 9.6 Remaining Validation

Initial orchestration, no-change processing, and controlled Header failure
and retry with unchanged sources have passed.

Retry behavior when new source changes appear after failure still requires
validation, including preservation of frozen HIGH boundaries and deferral
of new work from a Ready stream. Recovery after fact commit, concurrency,
and the remaining Section 8 scenarios also remain pending.

The standalone insertion test used an existing source line missing from
the target. End-to-end ingestion of newly created source data remains
part of subsequent incremental pipeline validation.
