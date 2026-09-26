# FactSales Star Schema Validation

## 1. Scope

Micromodule 6.12 validates analytical use of the completed star schema.

Script: `database/06_validation/012_ValidateFactSalesStarSchema.sql`

The script reads persistent tables and uses local temporary tables.
Run with stable fact and dimension data and no concurrent ETL.

## 2. Join Rules

Dimensions are joined through the surrogate keys stored in FactSales.
No IsCurrent filter is applied to those analytical joins.

DimDate is used in three roles: order date, due date, and ship date.
A null ShipDateKey is permitted and grouped into a no-date bucket.

Assertions verify that all required dimension references resolve and
that joins preserve the fact row count and unique line grain.

## 3. Recorded Baseline

| Metric | Result |
|---|---:|
| Fact rows | 121317 |
| Distinct orders | 31465 |
| Quantity | 274914 |
| Gross amount | 110373889.3134 |
| Discount amount | 527507.8884 |
| Net sales amount | 109846381.4250 |

## 4. Grouped Reconciliation

| Scenario | Groups | Result |
|---|---:|---|
| Order month / territory | 364 | Passed |
| Product category / customer type | 7 | Passed |
| Salesperson / ship method | 18 | Passed |
| Due month | 38 | Passed |
| Ship month, including no-date handling | 38 | Passed |

Every scenario preserved all baseline rows, quantities, and monetary totals.
Reconciliation used all groups, including those not printed in the samples.

The script supports null ship dates; this result does not establish that
the current dataset contains such rows.

## 5. Aggregation Semantics

Quantity, gross amount, discount amount, and net sales amount are summed.

Distinct orders are calculated within each group. Group-level distinct
order counts must not be summed across arbitrary groups, because one order
can contain lines belonging to several product categories.

These checks validate the implemented dimensional relationships and
aggregate consistency. They do not establish historical source snapshot
replay or performance under a production workload.

## 6. Execution Result

The development run returned:

`PASS: Star joins and five analytical groupings reconcile with FactSales.`

Micromodule 6.12 — Star Schema Validation: complete.

Next: 6.13 — Documentation & Module Closure.
