# Power BI Semantic Model

## 1. Scope and Grain

The model imports the FactSales star schema from AdventureWorks_EDW.

FactSales grain: one sales order detail line.
The business grain is identified by SalesOrderID and SalesOrderDetailID.

Dimensions provide filtering and grouping attributes.
Explicit DAX measures provide analytical calculations.

## 2. Relationships

All eight relationships use many-to-one cardinality from FactSales
to the dimension and single-direction filtering from dimension to fact.

| FactSales column | Dimension column | Status |
|---|---|---|
| CustomerKey | DimCustomer.CustomerKey | Active |
| ProductKey | DimProduct.ProductKey | Active |
| TerritoryKey | DimTerritory.TerritoryKey | Active |
| SalesPersonKey | DimSalesPerson.SalesPersonKey | Active |
| ShipMethodKey | DimShipMethod.ShipMethodKey | Active |
| OrderDateKey | DimDate.DateKey | Active |
| DueDateKey | DimDate.DateKey | Inactive |
| ShipDateKey | DimDate.DateKey | Inactive |

Dimension-side keys must be unique. Historical dimension versions are
retained because FactSales references their surrogate keys.

Filtering imported dimensions to current versions only would remove
historical rows required by existing facts.

## 3. Date Table

DimDate is marked as the date table using FullDate.

YearMonth is sorted by YearMonthNumber to preserve chronological order.

DimDate serves three date roles:
- Order date: default active relationship.
- Due date: inactive relationship used by the corresponding measure.
- Ship date: inactive relationship used by the corresponding measure.

An Order Month slicer uses DimDate.YearMonth.
Standard sales measures therefore follow OrderDate.

Measures using USERELATIONSHIP for ShipDate or DueDate interpret the
selected calendar period through that alternative relationship.

## 4. Measure Organization

Explicit measures are organized in the dedicated _Measures table.
Its placeholder column is hidden.

Display folders organize measures by purpose:
- Sales amounts.
- Volume.
- Ratios.
- Alternative date roles.

A display folder organizes fields; it does not change calculations.
The _Measures table does not require a relationship to FactSales.

## 5. Aggregation Rules

Gross Sales, Discount Amount, Net Sales and Units Sold are additive
across disjoint groups of fact rows.

Sales Orders counts distinct SalesOrderID values. A single order can
contain products from multiple categories, so category-level order
counts must not be added to obtain the overall order count.

Average Order Value is calculated as Net Sales / Sales Orders.
Effective Discount Rate is Discount Amount / Gross Sales.

Ratios are recalculated in the current filter context rather than
summed or averaged from displayed subgroup ratios.

Net Sales excludes order-level tax and freight.

## 6. Analytical Hierarchies

Product Analysis:
CategoryName > SubcategoryName > ProductName.

Customer & Territory Analysis:
TerritoryName > CustomerType.

These describe the drill paths used in report matrices; they do not
imply additional relationships between dimension tables.

## 7. Validation References

Unfiltered measures were reconciled with the warehouse snapshot.

Additional checks covered:
- Order month and territory filtering.
- Customer type breakdown.
- Order, ship and due date measures.
- A no-change incremental run.
- A controlled source insertion, refresh and restoration.

See:
- [Report guide](README.md)
- [Manual refresh test](../database/06_validation/manual_powerbi_753/README.md)

This document records the configured model from the guided development
session. It is not an automated extraction of PBIX metadata.
