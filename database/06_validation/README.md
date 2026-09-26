# FactSales Validation

Scripts 001-005 validate the full snapshot loader. Scripts 006-009 provide
standalone development tests for fact delta rollback, incremental retry,
recovery after fact commit, and deferral of new source changes.

Run from the repository root against the development databases
`AdventureWorks_EDW` and `AdventureWorks2022`, after staging, dimension,
and initial fact loading.

Keep source, staging, and dimension data unchanged during the suite.
Do not run concurrent ETL activity or wrap the scripts in an outer transaction.

## Full Snapshot Execution Order

| Script | Purpose | Persistent effects |
|---|---|---|
| `001_ValidateFactSalesGrain.sql` | Counts, grain, and coverage | None |
| `002_ValidateFactSalesMeasures.sql` | Row-level measures and totals | None |
| `003_ValidateFactSalesDimensions.sql` | Keys, attributes, and special members | None |
| `004_ValidateFactSalesIdempotence.sql` | Repeat-load equality and success audit | Reloads fact; creates audit entry |
| `005_ValidateFactSalesRollback.sql` | Rollback and failure audit | Temporary CHECK constraint; creates Failed audit entry |

The rollback script removes its temporary constraint during normal execution
and handled errors. If execution is interrupted, inspect
`dw.CK_FactSales_Validation_ForceFailure` before resuming ETL.

## Result Interpretation

Each script reports its observations and raises an error if an assertion fails.
`sqlcmd -b` and shell `pipefail` propagate those failures to the runner.

The full snapshot suite requires populated tables. It compares current data rather than
hard-coding the development row count, monetary totals, or execution IDs.

Unknown-member counts are informational; dimensional mapping rules determine
whether the assignments are valid.

Script 005 must capture error 547 naming its temporary CHECK constraint,
preserve every fact row, remove the constraint, and verify a Failed audit entry.
It succeeds only when those expected failure-handling checks pass.

The original development results and subsequent saved-script execution evidence
are documented in
[FactSales design, Section 17](../../docs/design/facts/fact-sales.md).

## Run the Full Snapshot Suite

Run from the repository root using the existing `.env`, SQL Server command-line tools, and `column` for formatting.

```bash
(
    set -e
    set -o pipefail

    set -a
    source .env
    set +a

    export SQLCMDPASSWORD="${SQL_SERVER_PASSWORD}"

    for validation_script in \
        database/06_validation/001_ValidateFactSalesGrain.sql \
        database/06_validation/002_ValidateFactSalesMeasures.sql \
        database/06_validation/003_ValidateFactSalesDimensions.sql \
        database/06_validation/004_ValidateFactSalesIdempotence.sql \
        database/06_validation/005_ValidateFactSalesRollback.sql
    do
        printf '\nRunning: %s\n' "$validation_script"

        if /opt/mssql-tools18/bin/sqlcmd \
            -S "${SQL_SERVER_HOST},${SQL_SERVER_PORT}" \
            -U "${SQL_SERVER_USER}" \
            -C \
            -b \
            -W \
            -w 65535 \
            -s "|" \
            -d "AdventureWorks_EDW" \
            -i "$validation_script" \
            2>&1 |
            column -t -s "|" -o " | "
        then
            printf 'PASS: %s\n' "$validation_script"
        else
            printf 'FAIL: %s\n' "$validation_script"
            exit 1
        fi
    done

    printf '\nAll five FactSales validation scripts passed.\n'
)
```

## Standalone Fact Delta Rollback Test

`006_ValidateFactSalesDeltaRollback.sql` tests `etl.LoadFactSalesDelta`.
Run it explicitly in development; it is not included in the runner above.

Prerequisites:

- Deploy `etl.LoadSalesOrderLineDeltaStage` and `etl.LoadFactSalesDelta`.
- Start with a validated fact matching the unchanged source snapshot.
- Delta staging must contain exactly the three original lines of order 75123,
  including detail 121317.
- Another staged line from that order must have a non-null fact ShipDateKey.
- Keep source, staging, and dimensions stable, with no concurrent ETL.
- Use a separate session without an outer transaction.

Prepare delta staging through `etl.LoadSalesOrderLineDeltaStage`, with only
Header active. Use order 75123's source ModifiedDate for both date boundaries,
75122 as the exclusive LOW key, and 75123 as the inclusive HIGH key.
These fixture values apply to the development snapshot used by this test.

Execute the saved script with `sqlcmd -b`, following the connection options
above and setting `-i` to its path.

The test temporarily nulls one fact ShipDateKey, removes detail 121317,
and adds `CK_FactSales_DeltaValidation_ForceFailure` to reject reinsertion.
It expects error 547 after the loader's preceding UPDATE.

Assertions verify complete rollback to the prepared state, a Failed audit
entry with zero committed inserts and updates, and no transaction left open.
Cleanup restores the original fact rows and removes the temporary constraint.
A final comparison checks all 19 fact columns in both directions.

This script intentionally uses a specific three-line development fixture.
It does not hard-code the total fact row count or execution identifier.

If the session is interrupted, inspect the temporary constraint and both
test rows before resuming ETL. Handled-error cleanup does not guarantee
recovery after a disconnected or terminated session.

Development execution 75 passed. The expected Failed audit status represents
successful failure-handling validation. Evidence is recorded in
[Incremental design, Section 9.3](../../docs/design/facts/fact-sales-incremental.md#93-fact-delta-application).

## Standalone Incremental Failure and Retry Test

`007_ValidateFactSalesIncrementalRetry.sql` validates a controlled Header-only
failure and retry through `etl.LoadFactSalesIncremental`.
Run it explicitly; it is not included in the full snapshot runner.

Prerequisites:

- Deploy the incremental orchestrator, extractor, and fact delta loader.
- Complete initial incremental processing so both controls are Ready
  with initialized LOW boundaries and no pending batch.
- Start with a validated fact matching the source snapshot.
- Header LOW must match the source date and key of order 75123.
- Order 75122 must share that Header modification date.
- Order 75123 must have its three original lines in source and fact,
  including detail 121317 with a non-null fact ShipDateKey.
- Neither source may contain a composite pair above its committed LOW.
- Keep source and dimensions stable, with no concurrent ETL or outer transaction.

Execute with `sqlcmd -b` and the connection options shown above, setting
`-i` to `database/06_validation/007_ValidateFactSalesIncrementalRetry.sql`.

The test temporarily rewinds Header LOW, nulls one fact ShipDateKey,
and adds `CK_FactSales_IncrementalRetry_ForceFailure`.
It expects error 547, preserved batch boundaries, unchanged prepared fact
contents, and an untouched Detail control.

After removing the constraint, the retry must read three lines, update one,
and finalize Header at the retained HIGH. Detail must remain unchanged.

Cleanup restores the original fact value, both watermark rows including
execution references and timestamps, and the original delta staging contents.
Audit entries from the failed attempt and successful retry are retained.
Bidirectional comparisons verify complete restoration.

Run to completion. A disconnected or terminated session can interrupt cleanup;
inspect the test constraint, fact line, and watermark state before resuming ETL.

Development executions 81 and 84 passed. This test keeps source data unchanged
between attempts; retry behavior with newly arriving changes requires separate
validation. Evidence is recorded in
[Incremental design, Section 9.5](../../docs/design/facts/fact-sales-incremental.md#95-controlled-header-failure-and-retry).

## Standalone Finalization Recovery Test

`008_ValidateFactSalesFinalizationRecovery.sql` validates recovery when
fact changes commit but watermark finalization fails.
Run it explicitly; it is not included in the full snapshot runner.

Use the same prerequisites and Header-only fixture as test 007.
Keep source and dimensions stable, with no concurrent ETL or outer transaction.

Execute with `sqlcmd -b` and the connection options shown above, setting
`-i` to `database/06_validation/008_ValidateFactSalesFinalizationRecovery.sql`.

The test temporarily rewinds Header LOW and nulls the fact ShipDateKey
for detail 121317. A temporary CHECK constraint named
`CK_ETLWatermark_FactSales_FinalizationFailure` on `audit.ETLWatermark`
prevents Header from returning to Ready.

The failed attempt must read three lines and commit one fact update,
then capture error 547 with FactCommitted = 1 and BatchFinalized = 0.
The fact must match its original snapshot, Header must retain its pending
boundaries, and the inactive Detail control must remain unchanged.

After removing the constraint, the retry must read three lines with
zero inserts and zero updates, then finalize Header at the retained HIGH.
Detail must remain unchanged.

Cleanup restores the original fact value, watermark rows including
execution references and timestamps, and delta staging contents.
Bidirectional comparisons verify restoration. Audit entries are retained.

Run to completion. A disconnected or terminated session can interrupt cleanup;
inspect the test constraint, fact line, and watermark state before resuming ETL.

Development executions 87 and 90 passed. Source changes between attempts
and concurrent execution are outside this test's scope.
Evidence is recorded in
[Incremental design, Section 9.6](../../docs/design/facts/fact-sales-incremental.md#96-recovery-after-fact-commit).

## Standalone Retry With New Source Changes Test

`009_ValidateFactSalesRetryNewChanges.sql` validates frozen-boundary retry
and deferral of new work from an inactive Ready stream.
Run it explicitly; it is not included in the full snapshot runner.

Prerequisites:

- Meet the initial fixture and watermark prerequisites of test 007.
- Header order 75122 must have its two original detail lines.
- Detail 121310 must belong to order 75121.
- All three additional candidate grains must already exist in the fact.
- Both standard source triggers must exist and be enabled, with no
  additional triggers on the two source tables.
- Use a development connection with source ALTER and UPDATE permissions,
  as well as the permissions needed for test 007 in AdventureWorks_EDW.
- Keep dimensions stable and allow no concurrent source writes or ETL.
- Run without an outer transaction.

The development run used an administrative connection in Azure Data Studio.
Execute the complete script in a fresh query session.
For command-line execution, use `sqlcmd -b` with a suitably privileged
connection and set `-i` to
`database/06_validation/009_ValidateFactSalesRetryNewChanges.sql`.

After forcing the Header-only fact failure, the test changes only
ModifiedDate for Header order 75122 and Detail 121310 of order 75121.
Each date is moved one day above its stream's original LOW.
The failed order 75123 remains unchanged in source.

Source triggers are disabled inside the source-edit transaction and
enabled before commit. Cleanup uses the same transactional mechanism
to restore the original dates without business-trigger side effects.

The retry must extract exactly the three lines of order 75123, update
one fact row, finalize Header at the retained HIGH, and preserve every
column of the inactive Detail control.

The next execution must extract exactly the three deferred candidates,
perform zero fact inserts and updates, and finalize both streams at
their new boundaries.

Cleanup restores source dates, the test fact value, both watermark rows,
and delta staging. Assertions verify restoration and enabled source
triggers. Audit entries are retained.

Run to completion. If execution is disconnected or terminated, inspect
source dates, trigger states, the test constraint, fact, and watermarks
before resuming ETL; cleanup may have been interrupted.

Development executions 93, 96, and 99 produced the expected results.
This test covers date-only changes on rows outside the failed batch.
Frozen boundaries do not provide a historical source snapshot.
Evidence is recorded in
[Incremental design, Section 9.7](../../docs/design/facts/fact-sales-incremental.md#97-frozen-boundary-retry-with-new-source-changes).

## Manual Concurrent Execution Rejection Test

Run in development without unrelated ETL or source writes.

1. In session A, acquire an Exclusive application lock in AdventureWorks_EDW
   using `sys.sp_getapplock`, resource `etl.LoadFactSalesIncremental`,
   owner `Session`, timeout 0, and database principal `public`.
2. Keep A connected. In session B, snapshot fact, delta staging, watermarks,
   and the audit row count, then call `etl.LoadFactSalesIncremental`.
3. Expect error 51201, no new audit entries, unchanged snapshots in both
   comparison directions, and zero open transactions in B.
4. Release the lock in the same session A using `sys.sp_releaseapplock`
   with the same resource, owner, and principal. Confirm NoLock using
   `APPLOCK_MODE`, even if the checks in B fail.

Development sessions 53 and 59 passed these checks.
This covers application-lock rejection, not every possible concurrency race.
Evidence is recorded in
[Incremental design, Section 9.8](../../docs/design/facts/fact-sales-incremental.md#98-concurrent-execution-rejection).
