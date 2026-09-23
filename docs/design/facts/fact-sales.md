# Design Specification — `dw.FactSales`

## 1. Objective

Design `dw.FactSales` as the central transactional fact table for the AdventureWorks sales business process.

The fact table represents sales at sales-order-detail grain and integrates with the conformed dimensions already implemented in the Enterprise Data Warehouse.

The design must support:

- sales analysis by date;
- product analysis;
- customer analysis;
- territory analysis;
- sales-person analysis;
- shipping-method analysis;
- online versus sales-person-assisted channel analysis;
- order-level drill-through and source reconciliation;
- additive sales measures suitable for analytical tools such as Power BI.

This document defines the logical and physical design of `dw.FactSales`.

The physical table structure, data types, nullability, primary key, foreign keys, and domain constraints are defined in this specification. Staging, surrogate-key resolution, historical lookup semantics, and incremental loading remain deferred to subsequent phases.

---

## 2. Business Process

`dw.FactSales` represents the AdventureWorks sales-order-line transaction process.

The analytical event occurs at the individual sales order detail level.

Primary transactional source:

- `AdventureWorks2022.Sales.SalesOrderDetail`

Order-level context is obtained from:

- `AdventureWorks2022.Sales.SalesOrderHeader`

The two sources are related through `SalesOrderID`.

---

## 3. Grain

One row in `dw.FactSales` represents:

> One sales order detail line.

The validated source grain is identified by:

`(SalesOrderID, SalesOrderDetailID)`

The grain must not be described as one product per order because product identity does not define the physical source grain.

The current source snapshot does not contain duplicate `(SalesOrderID, ProductID)` combinations, but that observed behavior is not treated as a source-system contract.

---

## 4. Source Tables

### 4.1 SalesOrderDetail

Primary source:

- `AdventureWorks2022.Sales.SalesOrderDetail`

Relevant fields:

- `SalesOrderID`
- `SalesOrderDetailID`
- `ProductID`
- `OrderQty`
- `UnitPrice`
- `UnitPriceDiscount`
- `LineTotal`
- `ModifiedDate`

### 4.2 SalesOrderHeader

Enrichment source:

- `AdventureWorks2022.Sales.SalesOrderHeader`

Relevant fields:

- `SalesOrderID`
- `OrderDate`
- `DueDate`
- `ShipDate`
- `Status`
- `OnlineOrderFlag`
- `SalesOrderNumber`
- `CustomerID`
- `SalesPersonID`
- `TerritoryID`
- `ShipMethodID`
- `ModifiedDate`

Source profiling confirmed that all current detail rows have a corresponding header row.

---

## 5. Dimensional Relationships

`dw.FactSales` references warehouse surrogate keys rather than source-system business keys.

### 5.1 Product

- Fact key: `ProductKey`
- Source business key: `SalesOrderDetail.ProductID`
- Dimension: `dw.DimProduct`

Current source coverage:

- 266 distinct ProductID values used by sales
- 0 orphan references

### 5.2 Customer

- Fact key: `CustomerKey`
- Source business key: `SalesOrderHeader.CustomerID`
- Dimension: `dw.DimCustomer`

Current source coverage:

- 19,119 distinct CustomerID values used by sales
- 0 orphan references

### 5.3 Territory

- Fact key: `TerritoryKey`
- Source business key: `SalesOrderHeader.TerritoryID`
- Dimension: `dw.DimTerritory`

Current source coverage:

- 10 distinct TerritoryID values used by sales
- 0 orphan references

### 5.4 Sales Person

- Fact key: `SalesPersonKey`
- Source business key: `SalesOrderHeader.SalesPersonID`
- Dimension: `dw.DimSalesPerson`

Current observed behavior:

- sales-person-assisted orders contain `SalesPersonID`;
- online orders contain `SalesPersonID = NULL`;
- 17 distinct non-null SalesPersonID values are used;
- 0 non-null orphan references exist;
- 27,659 valid NULL SalesPersonID values exist.

A NULL caused by an online transaction is a valid business condition and must not automatically be interpreted as an unresolved lookup.

Special-member handling is deferred to surrogate-key resolution design.

### 5.5 Ship Method

- Fact key: `ShipMethodKey`
- Source business key: `SalesOrderHeader.ShipMethodID`
- Dimension: `dw.DimShipMethod`

Current source coverage:

- 2 distinct ShipMethodID values used by sales
- 0 orphan references

---

## 6. Role-Playing Date Dimension

`dw.DimDate` is reused through three analytical roles.

### 6.1 OrderDateKey

Source:

- `SalesOrderHeader.OrderDate`

Business meaning:

> Date on which the sales order was created.

### 6.2 DueDateKey

Source:

- `SalesOrderHeader.DueDate`

Business meaning:

> Date by which the order is expected to be fulfilled.

### 6.3 ShipDateKey

Source:

- `SalesOrderHeader.ShipDate`

Business meaning:

> Date on which the order was actually shipped.

`ShipDate` is nullable in the source schema even though the current snapshot contains no NULL values.

An unavailable ship date is physically represented by `NULL` in `ShipDateKey`.

This preserves the distinction between a shipment date that has not occurred and a date dimension member that cannot be resolved.

---

## 7. Degenerate Transaction Identifiers

Transactional identifiers with analytical or reconciliation value are retained directly in the fact table.

### 7.1 SalesOrderID

Logical column:

`SalesOrderID`

Purpose:

- source reconciliation;
- order-level drill-through;
- distinct-order counting;
- grouping all lines belonging to the same order.

### 7.2 SalesOrderDetailID

Logical column:

`SalesOrderDetailID`

Purpose:

- exact source-line traceability;
- grain validation;
- duplicate detection;
- ETL reconciliation.

Together:

`(SalesOrderID, SalesOrderDetailID)`

represent the validated source grain and form the physical clustered primary key of `dw.FactSales`.

No separate `FactSalesKey` surrogate key is introduced because the source grain already provides a stable and deterministic row identity.

### 7.3 SalesOrderNumber

Logical column:

`SalesOrderNumber`

Source:

`SalesOrderHeader.SalesOrderNumber`

Purpose:

- business-friendly order identification;
- analytical drill-through;
- reporting;
- source reconciliation.

No separate `DimSalesOrder` is required for the current analytical scope.

---

## 8. Transaction Attributes

### 8.1 OrderStatusCode

Logical column:

`OrderStatusCode`

Source:

`SalesOrderHeader.Status`

AdventureWorks status domain:

- `1` = In process
- `2` = Approved
- `3` = Backordered
- `4` = Rejected
- `5` = Shipped
- `6` = Cancelled

The current snapshot contains only:

`5 = Shipped`

This observed behavior must not be treated as a permanent source-system constraint.

The status is retained directly in the fact instead of introducing a separate status dimension for the current project scope.

### 8.2 IsOnlineOrder

Logical column:

`IsOnlineOrder`

Source:

`SalesOrderHeader.OnlineOrderFlag`

Business meaning:

- `0` = order placed through a sales person;
- `1` = order placed online by the customer.

This attribute supports direct sales-channel analysis.

A separate sales-channel dimension is not required for the current scope.

---

## 9. Measures

### 9.1 OrderQuantity

Logical column:

`OrderQuantity`

Source:

`SalesOrderDetail.OrderQty`

Meaning:

> Number of units sold on the order line.

Aggregation behavior:

`Additive`

### 9.2 UnitPrice

Logical column:

`UnitPrice`

Source:

`SalesOrderDetail.UnitPrice`

Meaning:

> Unit selling price before line discount.

Aggregation behavior:

`Not additive by simple summation`

`UnitPrice` is retained because it describes the economics of the transaction and supports measure reconciliation.

### 9.3 DiscountRate

Logical column:

`DiscountRate`

Source:

`SalesOrderDetail.UnitPriceDiscount`

Meaning:

> Fractional discount rate applied to the unit selling price.

Source profiling confirmed that this field behaves as a rate rather than a monetary amount.

Observed current range:

`0.0000 to 0.4000`

Aggregation behavior:

`Not additive by simple summation`

### 9.4 GrossAmount

Logical column:

`GrossAmount`

Derivation:

`OrderQuantity * UnitPrice`

Meaning:

> Sales amount before discount.

Aggregation behavior:

`Additive`

### 9.5 DiscountAmount

Logical column:

`DiscountAmount`

Derivation:

`OrderQuantity * UnitPrice * DiscountRate`

Meaning:

> Monetary discount applied to the order line.

Aggregation behavior:

`Additive`

### 9.6 NetSalesAmount

Logical column:

`NetSalesAmount`

Derivation:

`GrossAmount - DiscountAmount`

Equivalent source expression:

`SalesOrderDetail.LineTotal`

Source profiling validated across all current detail rows:

`LineTotal = OrderQty * UnitPrice * (1 - UnitPriceDiscount)`

Aggregation behavior:

`Additive`

`LineTotal` is not retained as a second analytical measure because it duplicates the semantics of `NetSalesAmount`.

It remains useful during ETL validation and source reconciliation.

---

## 10. Logical Column Set

The logical `dw.FactSales` design consists of the following columns:

| Category | Column | Source / Derivation |
|---|---|---|
| Date key | `OrderDateKey` | `SalesOrderHeader.OrderDate` |
| Date key | `DueDateKey` | `SalesOrderHeader.DueDate` |
| Date key | `ShipDateKey` | `SalesOrderHeader.ShipDate` |
| Dimension key | `ProductKey` | `SalesOrderDetail.ProductID` |
| Dimension key | `CustomerKey` | `SalesOrderHeader.CustomerID` |
| Dimension key | `TerritoryKey` | `SalesOrderHeader.TerritoryID` |
| Dimension key | `SalesPersonKey` | `SalesOrderHeader.SalesPersonID` |
| Dimension key | `ShipMethodKey` | `SalesOrderHeader.ShipMethodID` |
| Degenerate identifier | `SalesOrderID` | `SalesOrderDetail.SalesOrderID` |
| Degenerate identifier | `SalesOrderDetailID` | `SalesOrderDetail.SalesOrderDetailID` |
| Degenerate identifier | `SalesOrderNumber` | `SalesOrderHeader.SalesOrderNumber` |
| Transaction attribute | `OrderStatusCode` | `SalesOrderHeader.Status` |
| Transaction attribute | `IsOnlineOrder` | `SalesOrderHeader.OnlineOrderFlag` |
| Measure | `OrderQuantity` | `SalesOrderDetail.OrderQty` |
| Numeric transaction attribute | `UnitPrice` | `SalesOrderDetail.UnitPrice` |
| Numeric transaction attribute | `DiscountRate` | `SalesOrderDetail.UnitPriceDiscount` |
| Measure | `GrossAmount` | Derived |
| Measure | `DiscountAmount` | Derived |
| Measure | `NetSalesAmount` | Derived / equivalent to `LineTotal` |

The logical column set intentionally separates dimensional context, transaction identifiers, transaction attributes, and analytical measures.

### 10.1 Physical Column Specification

The physical implementation of `dw.FactSales` contains 19 columns.

| Column | Data Type | Nullability | Physical Role |
|---|---|---|---|
| `OrderDateKey` | `INT` | `NOT NULL` | Role-playing FK to `dw.DimDate` |
| `DueDateKey` | `INT` | `NOT NULL` | Role-playing FK to `dw.DimDate` |
| `ShipDateKey` | `INT` | `NULL` | Role-playing FK to `dw.DimDate`; NULL when shipment has not occurred |
| `ProductKey` | `BIGINT` | `NOT NULL` | FK to `dw.DimProduct` |
| `CustomerKey` | `BIGINT` | `NOT NULL` | FK to `dw.DimCustomer` |
| `TerritoryKey` | `BIGINT` | `NOT NULL` | FK to `dw.DimTerritory` |
| `SalesPersonKey` | `BIGINT` | `NOT NULL` | FK to `dw.DimSalesPerson` |
| `ShipMethodKey` | `BIGINT` | `NOT NULL` | FK to `dw.DimShipMethod` |
| `SalesOrderID` | `INT` | `NOT NULL` | Degenerate identifier and first clustered PK column |
| `SalesOrderDetailID` | `INT` | `NOT NULL` | Degenerate identifier and second clustered PK column |
| `SalesOrderNumber` | `NVARCHAR(25)` | `NOT NULL` | Degenerate business identifier |
| `OrderStatusCode` | `TINYINT` | `NOT NULL` | Transaction status code |
| `IsOnlineOrder` | `BIT` | `NOT NULL` | Sales channel flag |
| `OrderQuantity` | `SMALLINT` | `NOT NULL` | Additive quantity measure |
| `UnitPrice` | `DECIMAL(19,4)` | `NOT NULL` | Non-additive transaction price |
| `DiscountRate` | `DECIMAL(10,4)` | `NOT NULL` | Non-additive discount rate |
| `GrossAmount` | `DECIMAL(19,4)` | `NOT NULL` | Additive derived measure |
| `DiscountAmount` | `DECIMAL(19,4)` | `NOT NULL` | Additive derived measure |
| `NetSalesAmount` | `DECIMAL(19,4)` | `NOT NULL` | Additive derived measure |

The date surrogate keys use `INT` to match `dw.DimDate.DateKey`.

The non-date surrogate keys use `BIGINT` to match the physical surrogate-key types of their corresponding conformed dimensions.

`SalesOrderNumber` uses `NVARCHAR(25)`, preserving the source character capacity represented by a maximum storage length of 50 bytes.

Monetary values use `DECIMAL(19,4)` rather than the source `money` type to maintain explicit precision and scale in the warehouse.

---


### 10.2 Primary Key and Row Identity

`dw.FactSales` does not use a separate surrogate fact key.

The physical row identity is:

`(SalesOrderID, SalesOrderDetailID)`

implemented as:

`PRIMARY KEY CLUSTERED (SalesOrderID, SalesOrderDetailID)`

This primary key:

- enforces the validated sales-order-line grain;
- prevents duplicate fact rows;
- supports deterministic source reconciliation;
- protects ETL idempotence at the source grain;
- avoids introducing a redundant `FactSalesKey`.

### 10.3 Domain Constraints

The physical table implements seven `CHECK` constraints.

| Constraint | Rule |
|---|---|
| `CK_FactSales_OrderStatusCode` | `OrderStatusCode BETWEEN 1 AND 6` |
| `CK_FactSales_OrderQuantity` | `OrderQuantity > 0` |
| `CK_FactSales_UnitPrice` | `UnitPrice >= 0` |
| `CK_FactSales_DiscountRate` | `DiscountRate BETWEEN 0 AND 1` |
| `CK_FactSales_GrossAmount` | `GrossAmount >= 0` |
| `CK_FactSales_DiscountAmount` | `DiscountAmount >= 0 AND DiscountAmount <= GrossAmount` |
| `CK_FactSales_NetSalesAmount` | `NetSalesAmount >= 0 AND NetSalesAmount <= GrossAmount` |

These constraints protect stable domain invariants without encoding observations that are only true for the current source snapshot.

Exact measure-formula equality is intentionally not implemented as a database constraint because rounding and numeric precision are better validated in the ETL and reconciliation layers.

### 10.4 Referential Integrity

`dw.FactSales` contains eight foreign-key relationships.

| Foreign Key | Fact Column | Referenced Object | Referenced Column |
|---|---|---|---|
| `FK_FactSales_OrderDate` | `OrderDateKey` | `dw.DimDate` | `DateKey` |
| `FK_FactSales_DueDate` | `DueDateKey` | `dw.DimDate` | `DateKey` |
| `FK_FactSales_ShipDate` | `ShipDateKey` | `dw.DimDate` | `DateKey` |
| `FK_FactSales_Product` | `ProductKey` | `dw.DimProduct` | `ProductKey` |
| `FK_FactSales_Customer` | `CustomerKey` | `dw.DimCustomer` | `CustomerKey` |
| `FK_FactSales_Territory` | `TerritoryKey` | `dw.DimTerritory` | `TerritoryKey` |
| `FK_FactSales_SalesPerson` | `SalesPersonKey` | `dw.DimSalesPerson` | `SalesPersonKey` |
| `FK_FactSales_ShipMethod` | `ShipMethodKey` | `dw.DimShipMethod` | `ShipMethodKey` |

No cascading update or delete behavior is configured.

Deployment validation confirmed that all eight foreign keys are enabled and trusted:

- `is_disabled = 0`
- `is_not_trusted = 0`

The table is intentionally empty after physical deployment. Fact population is deferred to the FactSales ETL implementation phase.

---

## 11. Explicit Exclusions

### 11.1 Header-Level Monetary Values

The following source fields are excluded from the core logical fact:

- `SubTotal`
- `TaxAmt`
- `Freight`
- `TotalDue`

These measures exist at sales-order-header grain.

Repeating them once per detail line would create incorrect results when aggregating the fact table.

Source profiling confirmed:

`TotalDue = SubTotal + TaxAmt + Freight`

for all current orders.

Source profiling also confirmed:

`SUM(SalesOrderDetail.LineTotal) = SalesOrderHeader.SubTotal`

when both values are normalized to four decimal places.

### 11.2 Operational Attributes

The following fields are excluded from the core analytical fact:

- `RevisionNumber`
- `PurchaseOrderNumber`
- `AccountNumber`
- `CarrierTrackingNumber`
- `Comment`
- `CreditCardID`
- `CreditCardApprovalCode`
- `CurrencyRateID`
- `rowguid`

Some of these fields may still be preserved in staging for source traceability, ETL processing, or future analytical requirements.

Exclusion from `FactSales` does not imply removal from the ETL pipeline.

### 11.3 SpecialOfferID

`SpecialOfferID` is intentionally deferred.

Promotion analysis may justify a future promotion or special-offer dimension, but introducing that analytical domain is outside the current `FactSales` implementation scope.

### 11.4 Source ModifiedDate

Both source tables contain `ModifiedDate`.

These timestamps are relevant to extraction, change detection, and incremental-load processing but are not business measures or analytical dimensions of `FactSales`.

The definitive multi-source incremental strategy is deferred to the incremental-loading phase.

---

## 12. Source Profiling Observations

Source profiling established:

`SalesOrderHeader`

- 31,465 rows

`SalesOrderDetail`

- 121,317 rows

All current detail rows have a corresponding order header.

The current source snapshot contains only shipped orders, but the supported order-status domain includes additional states.

Current dimensional source coverage is complete for:

- Product
- Customer
- Territory
- SalesPerson when applicable
- ShipMethod
- OrderDate
- DueDate
- ShipDate

No orphan business-key references were found for the dimensions required by the current sales model.

`SalesPersonID = NULL` is a valid business condition for online orders.

The current snapshot contains:

- 3,806 sales-person-assisted orders;
- 27,659 online orders.

`ModifiedDate` exhibits many timestamp ties in both source tables and therefore cannot by itself provide a deterministic incremental source position.

Observed source behavior informs the design but must not be promoted into stronger source-system contracts unless supported by schema or documented business semantics.

---

## 13. Measure Semantics

The principal additive measures are:

`OrderQuantity`

`GrossAmount`

`DiscountAmount`

`NetSalesAmount`

They may be aggregated across the dimensional context represented by the fact table.

The following numeric values must not be treated as additive measures:

`UnitPrice`

`DiscountRate`

Summing prices or discount rates across transaction rows does not produce a meaningful analytical result.

Appropriate aggregations such as averages or weighted calculations belong to the semantic or reporting layer.

---

## 14. Deferred Implementation Decisions

The following decisions remain intentionally deferred beyond the current physical table design:

- Unknown-member key values
- Not Applicable member handling
- Historical SCD lookup semantics
- Additional nonclustered indexes
- Compression
- Partitioning
- Technical audit columns
- CreatedAt or UpdatedAt metadata
- Physical staging structure
- Incremental-load implementation

The core physical FactSales structure is already resolved, including:

- no separate `FactSalesKey`;
- clustered primary key on `(SalesOrderID, SalesOrderDetailID)`;
- physical data types and numeric precision;
- NULL / NOT NULL rules;
- seven domain `CHECK` constraints;
- eight foreign-key constraints.

The remaining items belong to staging, surrogate-key resolution, incremental-loading, and later performance-hardening phases.

---

## 15. Design Summary

`dw.FactSales` represents one sales order detail line.

The validated source grain is:

`(SalesOrderID, SalesOrderDetailID)`

Its analytical dimensional context is provided by:

- `dw.DimDate`
- `dw.DimProduct`
- `dw.DimCustomer`
- `dw.DimTerritory`
- `dw.DimSalesPerson`
- `dw.DimShipMethod`

`dw.DimDate` plays three roles:

- Order Date
- Due Date
- Ship Date

Transactional identifiers retained directly in the fact are:

- `SalesOrderID`
- `SalesOrderDetailID`
- `SalesOrderNumber`

The principal additive measures are:

- `OrderQuantity`
- `GrossAmount`
- `DiscountAmount`
- `NetSalesAmount`

`UnitPrice` and `DiscountRate` are retained as non-additive transaction-level numeric attributes.

Header-level monetary amounts are intentionally excluded because their grain differs from the fact-table grain.

The physical implementation contains 19 columns, uses no separate fact surrogate key, enforces the validated source grain through a clustered composite primary key, and protects data integrity with seven `CHECK` constraints and eight trusted foreign keys.

This specification now defines the logical and physical design of `dw.FactSales`. Subsequent phases will implement staging, surrogate-key resolution, fact loading, incremental processing, and performance hardening.
