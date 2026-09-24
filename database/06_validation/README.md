# FactSales Validation

These scripts validate the implemented full snapshot loader.

Run from the repository root against the development databases
`AdventureWorks_EDW` and `AdventureWorks2022`, after staging, dimension,
and initial fact loading.

Keep source, staging, and dimension data unchanged during the suite.
Do not run concurrent ETL activity or wrap the scripts in an outer transaction.

## Execution Order

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

The suite requires populated tables. It compares current data rather than
hard-coding the development row count, monetary totals, or execution IDs.

Unknown-member counts are informational; dimensional mapping rules determine
whether the assignments are valid.

Script 005 must capture error 547 naming its temporary CHECK constraint,
preserve every fact row, remove the constraint, and verify a Failed audit entry.
It succeeds only when those expected failure-handling checks pass.

The original development results and subsequent saved-script execution evidence
are documented in
[FactSales design, Section 17](../../docs/design/facts/fact-sales.md).

## Run the Suite

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
