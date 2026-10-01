# AdventureWorks Power BI Analytics

## 1. Scope

Module 7 provides an analytical report over AdventureWorks_EDW.

Report: [AdventureWorks.pbix](AdventureWorks.pbix).

The report uses Import mode. Power BI stores a copy of the warehouse data;
Refresh retrieves updated data from SQL Server.

## 2. Prerequisites

- Power BI Desktop on Windows.
- A reachable SQL Server instance containing AdventureWorks_EDW.
- Warehouse objects deployed and dimensions and FactSales populated.
- Credentials with read access to the required warehouse tables.

The PBIX includes imported demonstration data. Opening it does not verify
connectivity to SQL Server; a successful refresh is required.

## 3. Connection and Refresh

1. Open AdventureWorks.pbix in Power BI Desktop.
2. Review Data source settings.
3. Change the server to your SQL Server instance if necessary, keeping
   AdventureWorks_EDW as the database.
4. Configure credentials for your environment.
5. Configure encryption and certificate trust for your SQL Server instance.
6. Refresh and wait for all imported tables to finish loading.
7. Compare unfiltered measures with SQL results from the same warehouse.

The development connection used an unencrypted-connection workaround.
This is environment-specific, not a deployment recommendation. Other
environments should use correctly configured TLS and trusted certificates.

Do not commit passwords or connection secrets.

## 4. Imported Tables

| Table | Purpose |
|---|---|
| dw.FactSales | Sales order detail grain and measures |
| dw.DimDate | Order, due and ship dates |
| dw.DimProduct | Products, subcategories and categories |
| dw.DimCustomer | Customers and customer types |
| dw.DimTerritory | Sales territories |
| dw.DimSalesPerson | Salespeople |
| dw.DimShipMethod | Shipping methods |

Keep historical dimension versions available for the surrogate keys in
FactSales. Do not filter dimension imports to current rows only.

## 5. Report Pages

| Page | Purpose |
|---|---|
| Sales Overview | Indicators, monthly trend and territory comparison |
| Product Analysis | Category comparison and product hierarchy |
| Customer & Territory Analysis | Customer types and territory detail |
| Validation | Technical reconciliation of measures and date roles |

Validation is retained for maintenance. Its intended presentation state
is hidden from normal navigation. Hiding a page is not a security control.

Order Month uses the active OrderDate relationship. Ship Date and Due Date
measures explicitly use their corresponding inactive relationships.

## 6. Warehouse Loading Versus Power BI Refresh

1. Complete required upstream dimension loads.
2. Run the appropriate FactSales loading process.
3. Verify its audit result.
4. Refresh Power BI Desktop.
5. Reconcile Power BI with SQL using the same filters and data state.
6. Save the PBIX.

For an already initialized incremental pipeline:

```sql
USE AdventureWorks_EDW;
GO
EXEC etl.LoadFactSalesIncremental;
GO
```

Power BI Refresh does not execute this procedure.
Completing the ETL does not automatically refresh an open PBIX.

Initial full loading and incremental initialization must follow the
warehouse procedures and their prerequisites.

Related documentation:

- [FactSales design](../docs/design/facts/fact-sales.md)
- [Incremental loading](../docs/design/facts/fact-sales-incremental.md)
- [Warehouse validation](../database/06_validation/README.md)

## 7. Validated Baseline

These values describe the restored development snapshot without filters.
They are execution evidence, not fixed expectations for future source changes.

| Measure | Value |
|---|---:|
| Sales Order Lines | 121317 |
| Sales Orders | 31465 |
| Units Sold | 274914 |
| Gross Sales | 110373889.3134 |
| Discount Amount | 527507.8884 |
| Net Sales | 109846381.4250 |
| Average Order Value, displayed | 3491.07 |
| Effective Discount Rate, displayed | 0.48% |

Sales Orders is a distinct count; do not sum it across product groups.
Average Order Value is Net Sales divided by Sales Orders.
Effective Discount Rate is Discount Amount divided by Gross Sales.
Both ratios are evaluated in the current filter context.

Net Sales excludes order-level tax and freight.

## 8. Refresh Validation

ExecutionID 113 succeeded without source changes: zero rows read,
inserted, updated or rejected.

The controlled insertion test used ExecutionID 115:
one new source detail produced one new FactSales row.

Power BI retained its previous values before Refresh and matched SQL
after Refresh. Test data was restored, and a final refresh returned
Power BI to the original totals.

See [manual test and evidence](../database/06_validation/manual_powerbi_753/README.md).

## 9. Working Copy and Repository Copy

The Windows PBIX is the development editing copy.
powerbi/AdventureWorks.pbix is the repository deliverable.

After changing the report:

1. Save and close the Windows working copy.
2. Copy the updated PBIX into the repository.
3. Verify that both copies match.
4. Update documentation and evidence.
5. Review and commit the intended changes.

Avoid independently editing both copies. The PBIX is binary; accompanying
documentation records technical decisions in reviewable text.

## 10. Pending Work

Power BI Service publication, gateway configuration and automatic refresh
remain pending before formal Module 7 closure.

Desktop refresh evidence does not demonstrate scheduled refresh in the Service.

## 11. Technical Documentation

- [Semantic model and relationships](semantic-model.md)
- [DAX measure catalog](dax-measures.md)
- [Controlled refresh test](../database/06_validation/manual_powerbi_753/README.md)
