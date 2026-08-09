# Source Data Dictionary — AdventureWorks2022

## 1. Purpose

This document describes the `AdventureWorks2022` tables used as source data for the `AdventureWorks_EDW` project. Its purpose is to preserve the functional and technical context of the data before it is transformed through ETL into the `stg` and `dw` layers.

This documentation helps the project team to:

- understand what each table represents in the OLTP system;
- identify keys, relationships, and data granularity;
- decide which columns should be loaded into the dimensional model;
- distinguish analytical, technical, operational, and audit attributes;
- document the rationale behind ETL transformations.

> The data types listed here correspond to the standard AdventureWorks2022 SQL Server schema. They should be validated against the actual source instance before automating the data catalog.

## 2. Architecture context

```text
AdventureWorks2022 (OLTP)
        ↓ extraction
stg (prepared and traceable data)
        ↓ dimensional transformation
dw (dimensions and facts)
        ↓ consumption
Power BI / analytical queries
```

The dimensional model follows a star-schema approach. Sales tables act as fact sources, while descriptive tables act as dimension sources.

## 3. Table summary

| Source table | OLTP purpose | Grain | Planned destination |
|---|---|---|---|
| `Production.Product` | Product catalog | One record per product | `dw.DimProduct` |
| `Person.Person` | Person identity and names | One person per record | `dw.DimCustomer` / supporting dimensions |
| `Sales.Customer` | Commercial customer | One customer per record | `dw.DimCustomer` |
| `Sales.SalesTerritory` | Sales territory | One territory per record | `dw.DimTerritory` |
| `Sales.SalesOrderHeader` | Order header | One order per record | `dw.FactSales` |
| `Sales.SalesOrderDetail` | Order lines | One product line per order | `dw.FactSales` |

## 4. Column classification

| Classification | Data warehouse use |
|---|---|
| Business key | Identifies a record in the source system; retained for traceability and incremental loads. |
| Analytical attribute | Used to filter, group, segment, or describe data. |
| Measure | Numeric value that can be analyzed or aggregated in a fact table. |
| Relationship | Identifier connecting the table to another source entity. |
| Technical/audit | Supports change detection, load reconstruction, and lineage. |
| Operational | Important to the OLTP process but not necessarily required in the initial analytical model. |
| Not initially recommended | Excluded from the initial model because it is semi-structured, redundant, operational, or requires a later design decision. |

---

## 5. `Production.Product`

### Purpose and context

Represents the master catalog of products sold or manufactured. It is the main source for `dw.DimProduct`, which implements history through SCD Type 2. Its grain is one record per product.

| Column | Data type | Key | DW use | Description and decision |
|---|---|---|---|---|
| `ProductID` | `int` | PK / business | Include | Stable product identifier and business key. |
| `Name` | `nvarchar(50)` | — | Include | Commercial product name. |
| `ProductNumber` | `nvarchar(25)` | — | Include | Visible product code. |
| `MakeFlag` | `bit` | — | Include | Indicates whether the product is manufactured in-house. |
| `FinishedGoodsFlag` | `bit` | — | Include | Indicates whether the product can be sold as a finished good. |
| `Color` | `nvarchar(15)` | — | Include | Useful product segmentation attribute. |
| `SafetyStockLevel` | `smallint` | — | Optional | Safety stock level; mainly useful for inventory analysis. |
| `ReorderPoint` | `smallint` | — | Optional | Reorder threshold; mainly related to inventory analysis. |
| `StandardCost` | `money` | — | Include | Standard cost; supports margin and profitability analysis. |
| `ListPrice` | `money` | — | Include | Product list price. |
| `Size` | `nvarchar(5)` | — | Optional | Commercial size; include if business users analyze it. |
| `SizeUnitMeasureCode` | `nchar(3)` | FK | Optional | Size unit; requires a unit-of-measure reference. |
| `WeightUnitMeasureCode` | `nchar(3)` | FK | Optional | Weight unit; requires a unit-of-measure reference. |
| `Weight` | `decimal(8,2)` | — | Optional | Physical weight; useful for logistics. |
| `DaysToManufacture` | `int` | — | Optional | Manufacturing lead time. |
| `ProductLine` | `nchar(2)` | — | Include | Product line used for commercial segmentation. |
| `Class` | `nchar(2)` | — | Include | Product classification. |
| `Style` | `nchar(2)` | — | Include | Product style. |
| `ProductSubcategoryID` | `int` | FK | Include later | Enables product subcategory and category analysis. |
| `ProductModelID` | `int` | FK | Optional | Technical product model; depends on analytical scope. |
| `SellStartDate` | `datetime` | — | Include | Product sales start date. |
| `SellEndDate` | `datetime` | — | Include | Product sales end date, when available. |
| `DiscontinuedDate` | `datetime` | — | Include | Product discontinuation date. |
| `rowguid` | `uniqueidentifier` | — | Exclude analytically | Replication identifier; retain only when lineage requires it. |
| `ModifiedDate` | `datetime` | — | Include in staging | Supports watermark, audit, and CDC processes. |

### Dimensional decision

The dimension should retain `ProductID` as the business key and generate `ProductKey` as a surrogate key. Descriptive attributes are compared through `RowHash`; when a controlled attribute changes, the previous version is closed and a new SCD Type 2 row is inserted.

---

## 6. `Person.Person`

### Purpose and context

Contains personal information reused by several system entities. It is related to `Sales.Customer` through `BusinessEntityID = PersonID`. Not every person is a customer, so this table should not automatically be treated as a customer dimension.

| Column | Data type | Key | DW use | Description and decision |
|---|---|---|---|---|
| `BusinessEntityID` | `int` | PK / business | Include | Person identifier used to relate the customer record. |
| `PersonType` | `nchar(2)` | — | Include | Person classification. |
| `NameStyle` | `bit` | — | Optional | Indicates a special name format; low analytical priority. |
| `Title` | `nvarchar(8)` | — | Include | Person title. |
| `FirstName` | `nvarchar(50)` | — | Include | First name. |
| `MiddleName` | `nvarchar(50)` | — | Include | Middle name. |
| `LastName` | `nvarchar(50)` | — | Include | Last name. |
| `Suffix` | `nvarchar(10)` | — | Include | Name suffix, when available. |
| `EmailPromotion` | `int` | — | Optional | Email promotion preference. |
| `AdditionalContactInfo` | `xml` | — | Exclude initially | Semi-structured information requiring parsing. |
| `Demographics` | `xml` | — | Exclude initially | Semi-structured demographic data reserved for a later model. |
| `rowguid` | `uniqueidentifier` | — | Exclude | Replication identifier. |
| `ModifiedDate` | `datetime` | — | Include in staging | Supports traceability, watermark, and CDC. |

### Dimensional decision

Name fields can be used in `DimCustomer`, but only for records linked to `Sales.Customer`. XML fields are excluded from the initial model and may remain in staging when governance or audit requirements justify it.

---

## 7. `Sales.Customer`

### Purpose and context

Represents the commercial customer relationship and is the central source for `dw.DimCustomer`. A customer can represent a person (`PersonID`) or a store (`StoreID`), so both cases must be considered.

| Column | Data type | Key | DW use | Description and decision |
|---|---|---|---|---|
| `CustomerID` | `int` | PK / business | Include | Customer business key. |
| `PersonID` | `int` nullable | FK | Include | Link to personal information. |
| `StoreID` | `int` nullable | FK | Include later | Link to a store or business customer. |
| `TerritoryID` | `int` | FK | Include | Associates the customer with a sales territory. |
| `AccountNumber` | `varchar(10)` | — | Include | Commercial account number. |
| `rowguid` | `uniqueidentifier` | — | Exclude | Replication identifier. |
| `ModifiedDate` | `datetime` | — | Include in staging | Supports incremental loads and CDC. |

### Dimensional decision

`CustomerID`, `TerritoryID`, `AccountNumber`, and descriptive fields from `Person.Person` feed `DimCustomer`. `PersonID` and `StoreID` may be retained as lineage keys without necessarily being exposed to end users.

---

## 8. `Sales.SalesTerritory`

### Purpose and context

Contains the geographic and commercial structure used to assign customers and sales. Its grain is one record per territory.

| Column | Data type | Key | DW use | Description and decision |
|---|---|---|---|---|
| `TerritoryID` | `int` | PK / business | Include | Territory identifier. |
| `Name` | `nvarchar(50)` | — | Include | Territory name. |
| `CountryRegionCode` | `nvarchar(3)` | Logical FK | Include | Country or region code. |
| `Group` | `nvarchar(50)` | — | Include | Geographic or commercial grouping. |
| `SalesYTD` | `money` | — | Optional | Operational year-to-date sales total. |
| `SalesLastYear` | `money` | — | Optional | Operational prior-year sales total. |
| `CostYTD` | `money` | — | Optional | Operational year-to-date cost total. |
| `CostLastYear` | `money` | — | Optional | Operational prior-year cost total. |
| `rowguid` | `uniqueidentifier` | — | Exclude | Replication identifier. |
| `ModifiedDate` | `datetime` | — | Include in staging | Change tracking and lineage. |

### Dimensional decision

`TerritoryID`, `Name`, `CountryRegionCode`, and `Group` are suitable for `DimTerritory` or may be denormalized into `DimCustomer`, depending on the final design. Operational totals should not replace measures calculated from the fact table.

---

## 9. `Sales.SalesOrderHeader`

### Purpose and context

Contains the header of each sales order. Its grain is one record per order and it provides dates, customer, territory, status, and document-level totals.

| Column | Data type | Key | DW use | Description and decision |
|---|---|---|---|---|
| `SalesOrderID` | `int` | PK / business | Include | Order identifier. |
| `RevisionNumber` | `tinyint` | — | Include in staging | Header revision number. |
| `OrderDate` | `datetime` | — | Include | Order date related to `DimDate`. |
| `DueDate` | `datetime` | — | Include | Promised due date. |
| `ShipDate` | `datetime` | — | Include | Actual shipping date. |
| `Status` | `tinyint` | — | Include | Order status; document the translation rule. |
| `OnlineOrderFlag` | `bit` | — | Include | Indicates whether the order was placed online. |
| `SalesOrderNumber` | `nvarchar(25)` | — | Include | Visible document number. |
| `PurchaseOrderNumber` | `nvarchar(25)` nullable | — | Optional | Customer purchase order number. |
| `AccountNumber` | `nvarchar(15)` nullable | — | Optional | Commercial account reference. |
| `CustomerID` | `int` | FK | Include | Relationship to `DimCustomer`. |
| `SalesPersonID` | `int` nullable | FK | Future | Requires a salesperson dimension. |
| `TerritoryID` | `int` nullable | FK | Include | Relationship to territory. |
| `BillToAddressID` | `int` | FK | Future | Requires a location/address dimension. |
| `ShipToAddressID` | `int` | FK | Future | Shipping location. |
| `ShipMethodID` | `int` | FK | Future | Shipping method. |
| `CreditCardID` | `int` nullable | FK | Exclude | Operational and potentially sensitive payment reference. |
| `CreditCardApprovalCode` | `varchar(15)` nullable | — | Exclude | Operational and potentially sensitive payment value. |
| `CurrencyRateID` | `int` nullable | FK | Future | Applied exchange rate. |
| `SubTotal` | `money` | — | Include | Amount before tax and freight. |
| `TaxAmt` | `money` | — | Include | Applied tax. |
| `Freight` | `money` | — | Include | Freight or shipping cost. |
| `TotalDue` | `money` | — | Include | Document total. |
| `Comment` | `nvarchar(128)` nullable | — | Optional | Free-text comment with limited standardization. |
| `rowguid` | `uniqueidentifier` | — | Exclude | Replication identifier. |
| `ModifiedDate` | `datetime` | — | Include in staging | Incremental loads, audit, and CDC. |

### Fact-table decision

The header provides order-level dates, dimensions, and measures. Header totals must be handled carefully with detail rows to prevent double counting when sales are aggregated by product.

---

## 10. `Sales.SalesOrderDetail`

### Purpose and context

Contains the products included in each sales order. Its grain is one product line per order and it is the primary source for `dw.FactSales`.

| Column | Data type | Key | DW use | Description and decision |
|---|---|---|---|---|
| `SalesOrderID` | `int` | PK/FK | Include | Parent order identifier. |
| `SalesOrderDetailID` | `int` | PK | Include | Unique line identifier. |
| `CarrierTrackingNumber` | `nvarchar(25)` nullable | — | Optional | Logistics tracking number. |
| `OrderQty` | `smallint` | — | Include as measure | Quantity sold. |
| `ProductID` | `int` | FK | Include | Relationship to `DimProduct`. |
| `SpecialOfferID` | `int` | FK | Include later | Enables promotion analysis; requires an additional source table. |
| `UnitPrice` | `money` | — | Include as measure | Unit price before discount. |
| `UnitPriceDiscount` | `money` | — | Include as measure | Per-unit discount. |
| `LineTotal` | `numeric(38,6)` computed | — | Include | Line total; can be recalculated and validated. |
| `rowguid` | `uniqueidentifier` | — | Exclude | Replication identifier. |
| `ModifiedDate` | `datetime` | — | Include in staging | Change detection, audit, and CDC. |

### Recommended derived measures

```sql
GrossAmount      = OrderQty * UnitPrice
DiscountAmount   = OrderQty * UnitPrice * UnitPriceDiscount
NetSalesAmount   = GrossAmount - DiscountAmount
```

The grain of `FactSales` must be explicitly defined as **one row per product line within a sales order**. This prevents repeated aggregation of header-level values such as `SubTotal`, `TaxAmt`, `Freight`, and `TotalDue`.

---

## 11. Relevant relationships

| Relationship | Purpose |
|---|---|
| `Sales.Customer.PersonID → Person.Person.BusinessEntityID` | Retrieves customer name and personal information. |
| `Sales.Customer.TerritoryID → Sales.SalesTerritory.TerritoryID` | Associates customers with territories. |
| `Sales.SalesOrderHeader.CustomerID → Sales.Customer.CustomerID` | Associates orders with customers. |
| `Sales.SalesOrderHeader.TerritoryID → Sales.SalesTerritory.TerritoryID` | Associates orders with territories. |
| `Sales.SalesOrderDetail.SalesOrderID → Sales.SalesOrderHeader.SalesOrderID` | Associates lines with order headers. |
| `Sales.SalesOrderDetail.ProductID → Production.Product.ProductID` | Associates lines with products. |

## 12. Technical columns that should not be lost in staging

Even when a column is not loaded into the dimensional model, staging should retain, where applicable:

- original business keys;
- `ModifiedDate`;
- `rowguid`, when source reconciliation is required;
- extraction timestamp (`ExtractedAt`);
- ETL execution identifier (`ExecutionID`);
- row hash when change detection is used.

The `stg` layer should make it possible to reconstruct what was extracted, when it was extracted, and from which source record each DW row was generated.

## 13. Modeling rules

1. AdventureWorks2022 business keys are not used as final dimensional primary keys.
2. Dimensions generate surrogate keys such as `ProductKey` and `CustomerKey`.
3. Dates are related to `dw.DimDate` through integer keys such as `DateKey`.
4. Product descriptive attributes use SCD Type 2 when historical tracking is required.
5. Sales measures are primarily sourced from detail rows; header totals must be handled carefully to avoid duplication.
6. Payment-related sensitive fields are excluded from the initial analytical model.
7. XML fields and free-text comments are initially excluded because they are not standardized.
8. `ModifiedDate` supports incremental loading and CDC even though it is not a business attribute.

## 14. Future extensions

- Add `Production.ProductSubcategory` and `Production.ProductCategory` to complete the product hierarchy.
- Add address tables if detailed geographic analysis is required.
- Add `Sales.SpecialOffer` to analyze promotions.
- Formally define `dw.FactSales` and its strategy for header-level measures.
- Validate data types, nullability, and relationships against the actual SQL Server instance.
- Compare full load, watermark, and CDC strategies using `ModifiedDate` and CDC-enabled source tables.

## 15. Catalog validation query

```sql
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    c.column_id AS ColumnID,
    c.name AS ColumnName,
    ty.name AS DataType,
    c.max_length AS MaxLength,
    c.precision,
    c.scale,
    c.is_nullable AS IsNullable,
    c.is_computed AS IsComputed
FROM AdventureWorks2022.sys.tables AS t
INNER JOIN AdventureWorks2022.sys.schemas AS s
    ON s.schema_id = t.schema_id
INNER JOIN AdventureWorks2022.sys.columns AS c
    ON c.object_id = t.object_id
INNER JOIN AdventureWorks2022.sys.types AS ty
    ON ty.user_type_id = c.user_type_id
WHERE
    (s.name = N'Production' AND t.name = N'Product')
 OR (s.name = N'Person' AND t.name = N'Person')
 OR (s.name = N'Sales' AND t.name IN
    (N'Customer', N'SalesTerritory', N'SalesOrderHeader', N'SalesOrderDetail'))
ORDER BY
    s.name,
    t.name,
    c.column_id;
```

## 16. Change log

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-08-08 | Created the source data dictionary for the six initial source tables. |
