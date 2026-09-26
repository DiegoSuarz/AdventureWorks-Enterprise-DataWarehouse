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

The physical table structure, data types, nullability, primary key, foreign keys, and domain constraints are defined in this specification. Staging, surrogate-key resolution, SCD lookup semantics, measure derivation, and full snapshot fact loading are implemented. Initial full-load validation is complete. Incremental loading is implemented; comprehensive pipeline validation remains pending.

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

Special-member handling follows the Unknown and Not Applicable rules defined in Section 15.

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

Derivation at warehouse precision:

`GrossAmount - NetSalesAmount`

Gross and net amounts are first normalized to `DECIMAL(19,4)`, following Section 13.

Meaning:

> Monetary discount applied to the order line.

Aggregation behavior:

`Additive`

### 9.6 NetSalesAmount

Logical column:

`NetSalesAmount`

Derivation:

`CONVERT(DECIMAL(19,4), OrderQuantity * UnitPrice * (1 - DiscountRate))`

Net sales are calculated before deriving the residual discount, following Section 13.

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

The table was empty after physical deployment. The initial ETL smoke test subsequently loaded 121,317 rows through `etl.LoadFactSales`.

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

They may be aggregated across the dimensional context represented by the fact
table.

The following numeric values must not be treated as additive measures:

`UnitPrice`

`DiscountRate`

Summing prices or discount rates across transaction rows does not produce a
meaningful analytical result. Appropriate aggregations such as averages or
weighted calculations belong to the semantic or reporting layer.

### 13.1 Measure Derivation Contract

FactSales derives monetary measures at sales-order-line grain.

The validated formulas are:

`GrossAmount = OrderQuantity * UnitPrice`

`NetSalesAmount = OrderQuantity * UnitPrice * (1 - DiscountRate)`

`DiscountAmount = GrossAmount - NetSalesAmount`

All three stored monetary measures use:

`DECIMAL(19,4)`

The calculation contract therefore normalizes `GrossAmount` and
`NetSalesAmount` to four decimal places before deriving `DiscountAmount` as the
residual between them.

### 13.2 Rounding Semantics

`DiscountAmount` must not be independently rounded from:

`OrderQuantity * UnitPrice * DiscountRate`

and then used to derive net sales.

Although mathematically equivalent before rounding, independently rounding the
discount introduces line-level differences at the warehouse precision.

Validation identified 378 sales lines where:

`GrossAmount - independently rounded DiscountAmount`

did not equal the normalized source `LineTotal`.

The accumulated difference across those rows was:

`0.0378`

The selected calculation order instead treats normalized net sales as the
source-reconcilable amount and derives discount as the residual.

This guarantees at warehouse precision:

`GrossAmount = DiscountAmount + NetSalesAmount`

### 13.3 Source Reconciliation

`AdventureWorks2022.Sales.SalesOrderDetail.LineTotal` is used as the source
reference for net line sales.

When both values are normalized to `DECIMAL(19,4)`, validation across all
121,317 sales lines produced:

- 0 NetSalesAmount-to-LineTotal mismatches;
- 0 arithmetic identity mismatches;
- 0 measure-domain violations.

The validated aggregate baseline is:

`TotalGrossAmount = 110373889.3134`

`TotalDiscountAmount = 527507.8884`

`TotalNetSalesAmount = 109846381.4250`

These totals provide a reconciliation baseline for the subsequent physical
FactSales load.

---

## 14. Staging and Extraction Design

The sales fact pipeline uses a transaction-grain staging table:

`stg.SalesOrderLine`

Its grain is identical to the validated source and fact-table grain:

`(SalesOrderID, SalesOrderDetailID)`

The staging dataset is produced by joining:

- `AdventureWorks2022.Sales.SalesOrderDetail`
- `AdventureWorks2022.Sales.SalesOrderHeader`

using `SalesOrderID`.

`SalesOrderDetail` is the driving source because it defines the transactional
line grain.

The extraction does not filter the current source to shipped orders. The
current snapshot contains only `Status = 5`, but the staging contract supports
the complete documented order-status domain.

The staging table contains 19 columns covering:

- source grain identifiers;
- the degenerate `SalesOrderNumber`;
- order, due, and ship dates;
- transactional attributes;
- dimension business keys;
- source transaction values;
- separate header and detail modification timestamps;
- extraction metadata.

Dimension surrogate keys are intentionally not stored in staging. Their
resolution belongs to the surrogate-key resolution phase.

Derived fact measures are intentionally not stored in staging. Their
calculation contract is defined in the measure-semantics section and is
applied by `etl.LoadFactSales`.

`HeaderModifiedDate` and `DetailModifiedDate` are retained separately because
the future incremental strategy must account for changes originating from
either source table.

Unlike dimensional staging tables, `stg.SalesOrderLine` does not currently use
a `RowHash`. The transaction grain and the two source modification timestamps
provide the required source lineage for the current full-extraction design.

The physical staging table enforces:

- clustered primary key on `(SalesOrderID, SalesOrderDetailID)`;
- order status between 1 and 6;
- positive order quantity;
- non-negative unit price;
- discount rate between 0 and 1.

The extraction procedure is:

`etl.LoadSalesOrderLineStage`

The current implementation performs a full snapshot load using:

1. source row counting;
2. ETL execution registration;
3. `TRUNCATE TABLE stg.SalesOrderLine`;
4. normalized source extraction inside a transaction;
5. row-count capture;
6. successful or failed execution logging.

The validated full extraction loaded:

- 121,317 source rows;
- 121,317 staging rows;
- 0 missing rows after normalized source-to-stage reconciliation;
- 0 unexpected staging rows.

The multi-source incremental strategy is defined in
[fact-sales-incremental.md](fact-sales-incremental.md).
Separate delta staging, bounded extraction, and incremental fact
application are implemented. Validation covers extraction, unchanged
deltas, fact updates and inserts, and atomic rollback with failure
auditing. Watermark orchestration is implemented and has passed initial
and no-change execution checks. Failure recovery, concurrency, and the
remaining end-to-end incremental scenarios are pending validation.

---

## 15. Surrogate Key Resolution

FactSales resolves dimension business keys from `stg.SalesOrderLine` into
warehouse surrogate keys before fact loading.

The current resolution contract is:

- `OrderDate` -> `dw.DimDate.DateKey`
- `DueDate` -> `dw.DimDate.DateKey`
- `ShipDate` -> `dw.DimDate.DateKey`
- `ProductID` -> `dw.DimProduct.ProductKey`
- `CustomerID` -> `dw.DimCustomer.CustomerKey`
- `TerritoryID` -> `dw.DimTerritory.TerritoryKey`
- `SalesPersonID` -> `dw.DimSalesPerson.SalesPersonKey`
- `ShipMethodID` -> `dw.DimShipMethod.ShipMethodKey`

### 15.1 Special Dimension Members

Deterministic negative surrogate keys are reserved outside the positive
`IDENTITY(1,1)` range used by regular dimension members.

The current convention is:

- `-1` = Unknown
- `-2` = Not Applicable

`Unknown` represents a dimension that should apply to the transaction but whose
business key cannot be resolved.

`Not Applicable` represents a dimension that legitimately does not participate
in the business event.

The `Not Applicable` member is currently required only for
`dw.DimSalesPerson`.

For an online order where:

`SalesPersonID IS NULL`

the fact resolves:

`SalesPersonKey = -2`

This condition is supported by the current source profile, where all 60,398
sales lines without a salesperson belong to online orders.

A non-null salesperson business key that cannot be resolved uses:

`SalesPersonKey = -1`

The other non-date dimensions use `-1` when their business key cannot be
resolved.

The special members are seeded reproducibly by:

`database/05_seed/003_SeedDimensionSpecialMembers.sql`

### 15.2 Date Resolution

Date keys are treated differently from general dimensional fallback members.

`OrderDate` and `DueDate` are mandatory business dates and must resolve directly
against `dw.DimDate`.

A missing mandatory date key is treated as a data-quality failure rather than
being hidden behind an Unknown date member.

`ShipDateKey` remains `NULL` when `ShipDate` itself is `NULL`, representing a
shipping event that has not occurred.

A non-null `ShipDate` that does not resolve against `dw.DimDate` is also a
data-quality failure.

### 15.3 SCD Resolution Semantics

The SCD Type 2 effective timestamps currently represent warehouse processing
time, not historical business-effective time.

The sales transactions occurred between 2011 and 2014, while the dimension
versions were created by the warehouse in 2026.

Therefore, transaction dates must not be compared directly with:

- `EffectiveStartDateTime`
- `EffectiveEndDateTime`

for historical as-of lookup.

For the current initial FactSales backfill, dimensional business keys resolve
against the version where:

`IsCurrent = 1`

This uses the best dimensional representation currently available to the
warehouse without falsely implying historical attribute reconstruction.

Historical transaction-time reconstruction would require source data that
provides actual business-effective validity periods.

### 15.4 Resolution Validation

The surrogate-key resolution prototype preserved all 121,317 staging rows.

Current validation produced:

- 0 missing OrderDate keys;
- 0 missing DueDate keys;
- 0 missing non-null ShipDate keys;
- 0 Unknown Product members;
- 0 Unknown Customer members;
- 0 Unknown Territory members;
- 0 Unknown SalesPerson members;
- 0 Unknown ShipMethod members;
- 60,398 Not Applicable SalesPerson resolutions.

---

## 16. FactSales ETL Implementation

### 16.1 Procedure and Load Contract

The fact-loading procedure is:

`etl.LoadFactSales`

Its version-controlled implementation is:

`database/04_procedures/etl.LoadFactSales.sql`

The procedure reads the existing full snapshot in `stg.SalesOrderLine`.
Source extraction remains a separate step performed by
`etl.LoadSalesOrderLineStage`.

Each successful fact load replaces the target with the transformed staging
snapshot using transactional `TRUNCATE + INSERT`.

The pre-load check confirmed that no foreign keys reference `dw.FactSales`.

### 16.2 Execution Sequence

1. Register the execution in `audit.ETLExecutionLog`.
2. Capture the staging row count as `RowsRead`.
3. Begin the load transaction.
4. Validate OrderDate, DueDate, and non-null ShipDate resolution.
5. Truncate `dw.FactSales`.
6. Insert the complete 19-column projection.
7. Capture inserted rows immediately through `@@ROWCOUNT`.
8. Commit the load transaction.
9. Mark the audit execution as `Succeeded`.

Dimension resolution follows Section 15, including `IsCurrent = 1`,
Unknown members, and Not Applicable SalesPerson handling.

Measure derivation follows Section 13: gross and net amounts are normalized
to four decimals before deriving discount as their residual.

### 16.3 Error Handling

The procedure uses `SET XACT_ABORT ON` and `TRY/CATCH`.

Unresolved required dates raise error 51001 before the target is truncated.
A null source ShipDate remains valid.

When a load error leaves an active transaction, the CATCH block rolls it back.
This includes reversing a transactional TRUNCATE and any uncommitted inserts.

The audit registration occurs before the load transaction. After rollback,
the error handler records `Failed`, stores the error details, and rethrows
the original error with `THROW`.

### 16.4 Initial Execution Evidence

The initial smoke test produced:

| Metric | Observed value |
|---|---|
| Development ExecutionID | 58 |
| Status | Succeeded |
| FactSales rows | 121317 |
| RowsRead | 121317 |
| RowsInserted | 121317 |
| RowsUpdated | 0 |
| RowsRejected | 0 |
| ErrorMessage | NULL |

ExecutionID 58 identifies this development run; it is not a fixed expected
identifier for future executions.

This evidence confirms successful initial execution, target row count, and
success audit logging. It does not establish repeat-run idempotence,
rollback recovery, or complete row-level reconciliation.

Subsequent Module 6.9 validation established row-level reconciliation, repeat-load idempotence, and rollback recovery, as documented in Section 17.

---

## 17. Initial Full-Load Validation

Module 6.9 validated the loaded fact against staging and the original
AdventureWorks2022 source, then exercised repeat loading and rollback.

The results below describe the development snapshot used for validation.
Execution identifiers are evidence references, not fixed test expectations.

### 17.1 Grain and Line Coverage

| Metric | Observed value |
|---|---|
| Staging rows | 121317 |
| Fact rows | 121317 |
| Missing fact lines | 0 |
| Unexpected fact lines | 0 |
| Duplicate fact grains | 0 |

Coverage was compared in both directions using
`(SalesOrderID, SalesOrderDetailID)`.

### 17.2 Measure Reconciliation

All 121317 fact lines matched the original SalesOrderDetail source for
quantity, unit price, discount rate, gross amount, net sales, and residual
discount. No source lines were missing from the comparison.

Net sales were compared with source `LineTotal` normalized to
`DECIMAL(19,4)` per line. Every fact row satisfied
`GrossAmount - DiscountAmount = NetSalesAmount`.

| Aggregate | Source | FactSales |
|---|---|---|
| Rows | 121317 | 121317 |
| Quantity | 274914 | 274914 |
| Gross amount | 110373889.3134 | 110373889.3134 |
| Discount amount | 527507.8884 | 527507.8884 |
| Net sales amount | 109846381.4250 | 109846381.4250 |

Amounts were normalized per line before aggregation.

### 17.3 Dimension Keys and Transaction Attributes

All three date roles matched staging, including nullable ShipDate handling.
All five non-date keys matched the resolution contract in Section 15,
using current dimension versions and the defined special-member rules.

SalesOrderNumber, OrderStatusCode, and IsOnlineOrder matched the original
SalesOrderHeader source for all 121317 lines. No source headers were missing.

The cross-database SalesOrderNumber comparison used
`COLLATE DATABASE_DEFAULT` on both expressions to resolve the differing
database collations without changing stored data or database settings.

No fact rows used Unknown keys in any of the five non-date dimensions.
Exactly 60398 lines used SalesPersonKey = -2, matching online source lines
with no SalesPersonID. Row-level Not Applicable rule mismatches were zero.

### 17.4 Repeat-Load Idempotence

Development execution 59 completed with status Succeeded:
121317 rows read and inserted, zero updated or rejected, and no error.

A temporary copy of all 19 fact columns was captured before reloading.
Both snapshots contained 121317 rows, and bidirectional EXCEPT comparisons
returned zero differences.

This establishes fact-content idempotence for the unchanged staging and
dimension state used in the test. Each invocation creates a new audit entry.

### 17.5 Rollback and Failure Audit

A temporary CHECK constraint,
`CK_FactSales_Validation_ForceFailure`, was added with `WITH NOCHECK`
and the condition `OrderQuantity < 0`.

Existing rows were retained. The subsequent load reached the INSERT after
TRUNCATE and raised error 547 against the validation constraint.

Development execution 60 was recorded as Failed, with 121317 rows read,
zero inserted, updated, or rejected, and the original error details.

After rollback, the fact still contained 121317 rows. Comparing all 19
columns against the pre-test snapshot returned zero differences in both
directions.

The validation constraint was removed, and the session reported zero open
transactions. RowsRejected remained zero because this loader aborts the
whole snapshot rather than processing individual row rejections.

---

### 17.6 Reproducible Validation Scripts

The validation scripts are maintained in `database/06_validation/`.
Execution instructions and prerequisites are documented in that directory's
[README](../../../database/06_validation/README.md).

| Script | Scope |
|---|---|
| `001_ValidateFactSalesGrain.sql` | Row counts, grain uniqueness, and line coverage |
| `002_ValidateFactSalesMeasures.sql` | Source measure reconciliation by line and totals |
| `003_ValidateFactSalesDimensions.sql` | Date roles, dimension keys, attributes, and special members |
| `004_ValidateFactSalesIdempotence.sql` | Repeat-load content equality and success auditing |
| `005_ValidateFactSalesRollback.sql` | Controlled INSERT failure, rollback, cleanup, and failure auditing |

All five saved scripts were executed in order with `sqlcmd -b` and passed.
The shell runner used `pipefail` to preserve SQL failures through output
formatting and stopped on the first unsuccessful script.

The saved idempotence script produced development execution 61 with status
Succeeded. Both fact snapshots contained 121317 rows, with zero differences
across all 19 columns.

The saved rollback script produced development execution 62 with status
Failed and the expected error 547. All 121317 fact rows were restored with
zero differences. TransactionCountAtCatch was zero, confirming that the
procedure had already closed its transaction before returning the error.
The temporary constraint was removed, and no transactions remained open.

Executions 61 and 62 supplement the earlier manual evidence from executions
59 and 60. These identifiers are not hard-coded in the validation scripts.

Scripts 001-003 do not modify persistent data. Scripts 004-005 execute the
loader and create audit entries; script 005 also temporarily changes the
fact table's constraints. Run them explicitly in the development environment,
with stable source, staging, and dimension data and no concurrent ETL activity.

The expected Failed audit entry from script 005 represents a successful
failure-handling test. Unexpected results raise validation errors.

---

## 18. Deferred Implementation Decisions

The following decisions remain intentionally deferred beyond the current physical table design:

- Additional nonclustered indexes
- Compression
- Partitioning
- Technical audit columns
- CreatedAt or UpdatedAt metadata
- Completion of incremental-load validation

The core physical FactSales structure is already resolved, including:

- no separate `FactSalesKey`;
- clustered primary key on `(SalesOrderID, SalesOrderDetailID)`;
- physical data types and numeric precision;
- NULL / NOT NULL rules;
- seven domain `CHECK` constraints;
- eight foreign-key constraints.

The remaining items belong to incremental-loading and later performance-hardening phases.

---

## 19. Design Summary

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

This specification now defines the logical and physical design of `dw.FactSales` together with its implemented staging, full-extraction, special-member, surrogate-key resolution, and measure-derivation contracts. Full snapshot fact loading is implemented through `etl.LoadFactSales` and has passed initial-load reconciliation, dimension and attribute validation, repeat-load idempotence, and a controlled rollback test. Subsequent phases will complete incremental pipeline validation and address performance hardening.
