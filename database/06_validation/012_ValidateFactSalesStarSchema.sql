/* M6.12 - Analytical star-schema validation.
Read-only on persistent tables; local temp tables are used and removed.
Run with stable fact/dimensions and no concurrent ETL.
Join each dimension by the surrogate key stored in fact; do not filter IsCurrent.
Orders are DISTINCT per group and are not additive across arbitrary groups.
*/
USE AdventureWorks_EDW;
GO
SET NOCOUNT ON;
IF @@TRANCOUNT <> 0 THROW 51700, 'Run without an outer transaction.', 1;
DROP TABLE IF EXISTS #M612Fact;
DROP TABLE IF EXISTS #M612Star;
DROP TABLE IF EXISTS #M612Baseline;
DROP TABLE IF EXISTS #M612Groups;
DROP TABLE IF EXISTS #M612Reconciliation;

SELECT * INTO #M612Fact FROM dw.FactSales;
IF NOT EXISTS (SELECT 1 FROM #M612Fact) THROW 51701, 'FactSales must be populated.', 1;
IF EXISTS (SELECT SalesOrderID,SalesOrderDetailID FROM #M612Fact
           GROUP BY SalesOrderID,SalesOrderDetailID HAVING COUNT_BIG(*)<>1)
    THROW 51702, 'The baseline fact contains duplicate grains.', 1;

SELECT f.*, od.YearMonth AS OrderMonth, dd.YearMonth AS DueMonth,
       COALESCE(sd.YearMonth,'No date') AS ShipMonth,
       p.CategoryName AS ProductCategory, c.CustomerType,
       t.TerritoryName, sp.SalesPersonName, sm.ShipMethodName,
       CASE WHEN od.DateKey IS NULL OR dd.DateKey IS NULL
              OR (f.ShipDateKey IS NOT NULL AND sd.DateKey IS NULL)
              OR p.ProductKey IS NULL OR c.CustomerKey IS NULL
              OR t.TerritoryKey IS NULL OR sp.SalesPersonKey IS NULL
              OR sm.ShipMethodKey IS NULL THEN 1 ELSE 0 END AS MissingDimension
INTO #M612Star
FROM #M612Fact f
LEFT JOIN dw.DimDate od ON od.DateKey=f.OrderDateKey
LEFT JOIN dw.DimDate dd ON dd.DateKey=f.DueDateKey
LEFT JOIN dw.DimDate sd ON sd.DateKey=f.ShipDateKey
LEFT JOIN dw.DimProduct p ON p.ProductKey=f.ProductKey
LEFT JOIN dw.DimCustomer c ON c.CustomerKey=f.CustomerKey
LEFT JOIN dw.DimTerritory t ON t.TerritoryKey=f.TerritoryKey
LEFT JOIN dw.DimSalesPerson sp ON sp.SalesPersonKey=f.SalesPersonKey
LEFT JOIN dw.DimShipMethod sm ON sm.ShipMethodKey=f.ShipMethodKey;

IF EXISTS (SELECT 1 FROM #M612Star WHERE MissingDimension=1)
    THROW 51703, 'A fact key has no matching dimensional member.', 1;
IF (SELECT COUNT_BIG(*) FROM #M612Fact)<>(SELECT COUNT_BIG(*) FROM #M612Star)
 OR EXISTS (SELECT SalesOrderID,SalesOrderDetailID FROM #M612Star
            GROUP BY SalesOrderID,SalesOrderDetailID HAVING COUNT_BIG(*)<>1)
    THROW 51704, 'Dimensional joins multiplied fact rows.', 1;

SELECT COUNT_BIG(*) AS FactRows,
       COUNT_BIG(DISTINCT SalesOrderID) AS DistinctOrders,
       SUM(CONVERT(BIGINT,OrderQuantity)) AS Quantity,
       SUM(CONVERT(DECIMAL(38,4),GrossAmount)) AS GrossAmount,
       SUM(CONVERT(DECIMAL(38,4),DiscountAmount)) AS DiscountAmount,
       SUM(CONVERT(DECIMAL(38,4),NetSalesAmount)) AS NetSalesAmount
INTO #M612Baseline FROM #M612Fact;

CREATE TABLE #M612Groups (
    Scenario NVARCHAR(60) NOT NULL,
    Group1 NVARCHAR(200) NULL, Group2 NVARCHAR(200) NULL,
    FactRows BIGINT NOT NULL, DistinctOrders BIGINT NOT NULL, Quantity BIGINT NOT NULL,
    GrossAmount DECIMAL(38,4) NOT NULL, DiscountAmount DECIMAL(38,4) NOT NULL,
    NetSalesAmount DECIMAL(38,4) NOT NULL);

INSERT INTO #M612Groups
SELECT N'Order month / territory',OrderMonth,TerritoryName,
       COUNT_BIG(*),COUNT_BIG(DISTINCT SalesOrderID),SUM(CONVERT(BIGINT,OrderQuantity)),
       SUM(CONVERT(DECIMAL(38,4),GrossAmount)),SUM(CONVERT(DECIMAL(38,4),DiscountAmount)),
       SUM(CONVERT(DECIMAL(38,4),NetSalesAmount))
FROM #M612Star GROUP BY OrderMonth,TerritoryName;

INSERT INTO #M612Groups
SELECT N'Product category / customer type',ProductCategory,CustomerType,
       COUNT_BIG(*),COUNT_BIG(DISTINCT SalesOrderID),SUM(CONVERT(BIGINT,OrderQuantity)),
       SUM(CONVERT(DECIMAL(38,4),GrossAmount)),SUM(CONVERT(DECIMAL(38,4),DiscountAmount)),
       SUM(CONVERT(DECIMAL(38,4),NetSalesAmount))
FROM #M612Star GROUP BY ProductCategory,CustomerType;

INSERT INTO #M612Groups
SELECT N'Salesperson / ship method',SalesPersonName,ShipMethodName,
       COUNT_BIG(*),COUNT_BIG(DISTINCT SalesOrderID),SUM(CONVERT(BIGINT,OrderQuantity)),
       SUM(CONVERT(DECIMAL(38,4),GrossAmount)),SUM(CONVERT(DECIMAL(38,4),DiscountAmount)),
       SUM(CONVERT(DECIMAL(38,4),NetSalesAmount))
FROM #M612Star GROUP BY SalesPersonName,ShipMethodName;

INSERT INTO #M612Groups
SELECT N'Due month',DueMonth,NULL,
       COUNT_BIG(*),COUNT_BIG(DISTINCT SalesOrderID),SUM(CONVERT(BIGINT,OrderQuantity)),
       SUM(CONVERT(DECIMAL(38,4),GrossAmount)),SUM(CONVERT(DECIMAL(38,4),DiscountAmount)),
       SUM(CONVERT(DECIMAL(38,4),NetSalesAmount))
FROM #M612Star GROUP BY DueMonth;

INSERT INTO #M612Groups
SELECT N'Ship month (including no date)',ShipMonth,NULL,
       COUNT_BIG(*),COUNT_BIG(DISTINCT SalesOrderID),SUM(CONVERT(BIGINT,OrderQuantity)),
       SUM(CONVERT(DECIMAL(38,4),GrossAmount)),SUM(CONVERT(DECIMAL(38,4),DiscountAmount)),
       SUM(CONVERT(DECIMAL(38,4),NetSalesAmount))
FROM #M612Star GROUP BY ShipMonth;

SELECT Scenario,COUNT_BIG(*) AS GroupCount,SUM(FactRows) AS FactRows,
       SUM(Quantity) AS Quantity,SUM(GrossAmount) AS GrossAmount,
       SUM(DiscountAmount) AS DiscountAmount,SUM(NetSalesAmount) AS NetSalesAmount
INTO #M612Reconciliation FROM #M612Groups GROUP BY Scenario;
IF (SELECT COUNT(*) FROM #M612Reconciliation)<>5
 OR EXISTS (SELECT 1 FROM #M612Reconciliation r CROSS JOIN #M612Baseline b
            WHERE r.FactRows<>b.FactRows OR r.Quantity<>b.Quantity
               OR r.GrossAmount<>b.GrossAmount OR r.DiscountAmount<>b.DiscountAmount
               OR r.NetSalesAmount<>b.NetSalesAmount)
    THROW 51705, 'One analytical grouping did not reconcile with the baseline fact.', 1;

SELECT * FROM #M612Baseline;
SELECT * FROM #M612Reconciliation ORDER BY Scenario;
-- A small analytical sample; reconciliation above uses ALL groups.
SELECT TOP (12) Group1 AS OrderMonth,Group2 AS TerritoryName,
       FactRows,DistinctOrders,Quantity,NetSalesAmount
FROM #M612Groups WHERE Scenario=N'Order month / territory'
ORDER BY NetSalesAmount DESC,Group1,Group2;
SELECT Group1 AS ProductCategory,Group2 AS CustomerType,
       FactRows,DistinctOrders,Quantity,NetSalesAmount
FROM #M612Groups WHERE Scenario=N'Product category / customer type'
ORDER BY Group1,Group2;
SELECT N'PASS: Star joins and five analytical groupings reconcile with FactSales.' AS Result;

DROP TABLE #M612Reconciliation;
DROP TABLE #M612Groups;
DROP TABLE #M612Baseline;
DROP TABLE #M612Star;
DROP TABLE #M612Fact;
