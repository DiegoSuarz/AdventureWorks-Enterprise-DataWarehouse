/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 003_ValidateFactSalesDimensions.sql
Author   : Diego Suárez
Purpose  : Validate date roles, dimension keys, transaction attributes, and
           special-member handling.
Notes    : Run after staging and fact loading, without concurrent ETL activity
           or source changes. This script does not modify persistent data.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SET NOCOUNT ON;

DECLARE @FactRows BIGINT;

SELECT
    @FactRows = COUNT_BIG(*)
FROM dw.FactSales;

DECLARE @Results TABLE
(
    SortOrder INT PRIMARY KEY,
    Metric NVARCHAR(64),
    ResultValue BIGINT,
    IsFailureMetric BIT
);

INSERT INTO @Results
(
    SortOrder,
    Metric,
    ResultValue,
    IsFailureMetric
)
SELECT
    v.SortOrder,
    v.Metric,
    SUM(CONVERT(BIGINT, v.MetricValue)),
    v.IsFailureMetric

FROM dw.FactSales AS f

LEFT JOIN stg.SalesOrderLine AS s
    ON s.SalesOrderID = f.SalesOrderID
   AND s.SalesOrderDetailID = f.SalesOrderDetailID

LEFT JOIN AdventureWorks2022.Sales.SalesOrderHeader AS h
    ON h.SalesOrderID = f.SalesOrderID

LEFT JOIN dw.DimDate AS od
    ON od.DateKey = f.OrderDateKey

LEFT JOIN dw.DimDate AS dd
    ON dd.DateKey = f.DueDateKey

LEFT JOIN dw.DimDate AS sd
    ON sd.DateKey = f.ShipDateKey

LEFT JOIN dw.DimProduct AS p
    ON p.ProductID = s.ProductID
   AND p.IsCurrent = 1

LEFT JOIN dw.DimCustomer AS c
    ON c.CustomerID = s.CustomerID
   AND c.IsCurrent = 1

LEFT JOIN dw.DimTerritory AS t
    ON t.TerritoryID = s.TerritoryID
   AND t.IsCurrent = 1

LEFT JOIN dw.DimSalesPerson AS sp
    ON sp.BusinessEntityID = s.SalesPersonID
   AND sp.IsCurrent = 1

LEFT JOIN dw.DimShipMethod AS sm
    ON sm.ShipMethodID = s.ShipMethodID
   AND sm.IsCurrent = 1

CROSS APPLY
(
    SELECT
        CASE
            WHEN s.SalesPersonID IS NULL
             AND s.IsOnlineOrder = 1
                THEN CONVERT(BIGINT, -2)
            ELSE COALESCE
            (
                sp.SalesPersonKey,
                CONVERT(BIGINT, -1)
            )
        END AS ExpectedSalesPersonKey,

        CASE
            WHEN h.SalesPersonID IS NULL
             AND h.OnlineOrderFlag = 1
            THEN 1 ELSE 0
        END AS ExpectedNotApplicable
) AS expected

CROSS APPLY
(
    VALUES
    (
        1, N'ComparedRows',
        1, 0
    ),
    (
        2, N'MissingStagingLines',
        CASE WHEN s.SalesOrderDetailID IS NULL THEN 1 ELSE 0 END,
        1
    ),
    (
        3, N'MissingSourceHeaders',
        CASE WHEN h.SalesOrderID IS NULL THEN 1 ELSE 0 END,
        1
    ),
    (
        4, N'OrderDateMismatch',
        CASE
            WHEN od.DateKey IS NULL
              OR s.OrderDate IS NULL
              OR od.FullDate <> s.OrderDate
            THEN 1 ELSE 0
        END,
        1
    ),
    (
        5, N'DueDateMismatch',
        CASE
            WHEN dd.DateKey IS NULL
              OR s.DueDate IS NULL
              OR dd.FullDate <> s.DueDate
            THEN 1 ELSE 0
        END,
        1
    ),
    (
        6, N'ShipDateMismatch',
        CASE
            WHEN
                (
                    s.ShipDate IS NULL
                    AND f.ShipDateKey IS NOT NULL
                )
                OR
                (
                    s.ShipDate IS NOT NULL
                    AND
                    (
                        sd.DateKey IS NULL
                        OR sd.FullDate <> s.ShipDate
                    )
                )
            THEN 1 ELSE 0
        END,
        1
    ),
    (
        7, N'ProductKeyMismatch',
        CASE
            WHEN f.ProductKey <>
                COALESCE(p.ProductKey, CONVERT(BIGINT, -1))
            THEN 1 ELSE 0
        END,
        1
    ),
    (
        8, N'CustomerKeyMismatch',
        CASE
            WHEN f.CustomerKey <>
                COALESCE(c.CustomerKey, CONVERT(BIGINT, -1))
            THEN 1 ELSE 0
        END,
        1
    ),
    (
        9, N'TerritoryKeyMismatch',
        CASE
            WHEN f.TerritoryKey <>
                COALESCE(t.TerritoryKey, CONVERT(BIGINT, -1))
            THEN 1 ELSE 0
        END,
        1
    ),
    (
        10, N'SalesPersonKeyMismatch',
        CASE
            WHEN f.SalesPersonKey <> expected.ExpectedSalesPersonKey
            THEN 1 ELSE 0
        END,
        1
    ),
    (
        11, N'ShipMethodKeyMismatch',
        CASE
            WHEN f.ShipMethodKey <>
                COALESCE(sm.ShipMethodKey, CONVERT(BIGINT, -1))
            THEN 1 ELSE 0
        END,
        1
    ),
    (
        12, N'SalesOrderNumberMismatch',
        CASE
            WHEN EXISTS
            (
                SELECT f.SalesOrderNumber COLLATE DATABASE_DEFAULT
                EXCEPT
                SELECT h.SalesOrderNumber COLLATE DATABASE_DEFAULT
            )
            THEN 1 ELSE 0
        END,
        1
    ),
    (
        13, N'OrderStatusMismatch',
        CASE
            WHEN EXISTS
            (
                SELECT f.OrderStatusCode
                EXCEPT
                SELECT h.[Status]
            )
            THEN 1 ELSE 0
        END,
        1
    ),
    (
        14, N'OnlineOrderMismatch',
        CASE
            WHEN EXISTS
            (
                SELECT f.IsOnlineOrder
                EXCEPT
                SELECT h.OnlineOrderFlag
            )
            THEN 1 ELSE 0
        END,
        1
    ),
    (
        15, N'UnknownProductRows',
        CASE WHEN f.ProductKey = -1 THEN 1 ELSE 0 END,
        0
    ),
    (
        16, N'UnknownCustomerRows',
        CASE WHEN f.CustomerKey = -1 THEN 1 ELSE 0 END,
        0
    ),
    (
        17, N'UnknownTerritoryRows',
        CASE WHEN f.TerritoryKey = -1 THEN 1 ELSE 0 END,
        0
    ),
    (
        18, N'UnknownSalesPersonRows',
        CASE WHEN f.SalesPersonKey = -1 THEN 1 ELSE 0 END,
        0
    ),
    (
        19, N'UnknownShipMethodRows',
        CASE WHEN f.ShipMethodKey = -1 THEN 1 ELSE 0 END,
        0
    ),
    (
        20, N'NotApplicableSalesPersonRows',
        CASE WHEN f.SalesPersonKey = -2 THEN 1 ELSE 0 END,
        0
    ),
    (
        21, N'ExpectedNotApplicableRows',
        expected.ExpectedNotApplicable,
        0
    ),
    (
        22, N'NotApplicableRuleMismatch',
        CASE
            WHEN
                CASE WHEN f.SalesPersonKey = -2 THEN 1 ELSE 0 END
                <> expected.ExpectedNotApplicable
            THEN 1 ELSE 0
        END,
        1
    )
) AS v(SortOrder, Metric, MetricValue, IsFailureMetric)

GROUP BY
    v.SortOrder,
    v.Metric,
    v.IsFailureMetric;

SELECT
    Metric,
    ResultValue
FROM @Results
ORDER BY SortOrder;

IF @FactRows = 0
   OR EXISTS
   (
       SELECT 1
       FROM @Results
       WHERE Metric = N'ComparedRows'
         AND ResultValue <> @FactRows
   )
   OR EXISTS
   (
       SELECT 1
       FROM @Results
       WHERE IsFailureMetric = 1
         AND ResultValue <> 0
   )
BEGIN
    THROW 51023,
        'FactSales dimension validation failed: empty fact, join multiplication, missing source rows, or mapping differences.',
        1;
END;
GO
