# FactSales Validation

Scripts 001-005 validate the full snapshot loader. Scripts 006-007 provide
standalone development tests for fact delta rollback and incremental retry.

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
