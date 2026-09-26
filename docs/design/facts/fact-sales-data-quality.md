# FactSales Data Quality and Reconciliation

## 1. Scope

Micromodule 6.11 consolidates the executed FactSales quality checks.
It reuses validation scripts 001-003 and their recorded development results.

The checks cover the validated full snapshot. Snapshot staging must be
aligned with the source and fact when running snapshot reconciliation.
These results are execution evidence, not continuous monitoring.

## 2. Grain and Coverage

Script: `database/06_validation/001_ValidateFactSalesGrain.sql`

| Check | Recorded result | Acceptance criterion |
|---|---:|---|
| Staging rows | 121317 | Equal to fact rows |
| Fact rows | 121317 | Equal to staging rows |
| Missing fact lines | 0 | Zero |
| Unexpected fact lines | 0 | Zero |
| Duplicate fact grains | 0 | Zero |

The fact grain is one sales order detail line, identified by
SalesOrderID and SalesOrderDetailID.

## 3. Measures and Totals

Script: `database/06_validation/002_ValidateFactSalesMeasures.sql`

All 121317 rows were compared. Missing source lines and mismatches in
quantity, unit price, discount rate, gross amount, net sales amount,
discount amount, and arithmetic identity were zero.

| Metric | Source | FactSales |
|---|---:|---:|
| Rows | 121317 | 121317 |
| Quantity | 274914 | 274914 |
| Gross amount | 110373889.3134 | 110373889.3134 |
| Discount amount | 527507.8884 | 527507.8884 |
| Net sales amount | 109846381.4250 | 109846381.4250 |

Acceptance requires row-level agreement and matching totals under the
documented decimal precision and rounding rules.

## 4. Dimensional Mapping and Attributes

Script: `database/06_validation/003_ValidateFactSalesDimensions.sql`

All 121317 rows were compared. Missing staging lines and missing source
headers were zero.

Date keys, product, customer, territory, salesperson, ship method,
sales order number, order status, and online-order attributes had
zero mismatches under the implemented mapping rules.

Unknown-member counts were zero for product, customer, territory,
salesperson, and ship method.

Salesperson Not Applicable rows: 60398.
Expected Not Applicable rows: 60398.
Not Applicable rule mismatches: 0.

Unknown-member counts are diagnostic. Acceptance depends on the documented
mapping rules; a legitimate unknown member is not automatically an error.

## 5. Incremental Validation Relationship

Tests 010 and 011 checked restoration after their source mutations.
Test 011 additionally compared all fact columns for three new order lines
against expected values derived from the previously reconciled reference
fact, with the new source identifiers and order numbers.

These checks supplement the snapshot reconciliation. They do not establish
historical source snapshot replay or test source business-trigger behavior.

## 6. Execution and Failure Interpretation

Run the existing scripts according to
[the validation README](../../../database/06_validation/README.md).

A successful validation requires all assertions to pass. For command-line
execution, sqlcmd -b and shell pipefail propagate SQL failures.

Do not treat an expected Failed audit entry from a controlled failure test
as a quality defect. Evaluate it against that test's assertions.

## 7. Micromodule Status

6.11 — Data Quality & Reconciliation: complete for the documented scope.

The recorded 001-003 executions passed. No additional execution was needed
to consolidate this evidence.

Next: 6.12 — Star Schema Validation, using analytical queries to demonstrate
that dimensional grouping preserves the validated fact totals.
