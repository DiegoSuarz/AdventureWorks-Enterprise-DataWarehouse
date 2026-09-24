/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 002_ValidateFactSalesMeasures.sql
Author   : Diego Suárez
Purpose  : Reconcile fact measures with the original source by line and totals.
Notes    : Run after staging and fact loading, without concurrent ETL activity
           or source changes. This script does not modify persistent data.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SET NOCOUNT ON;

SELECT
    sod.SalesOrderID,
    sod.SalesOrderDetailID,
    sod.OrderQty AS SourceQuantity,

    CONVERT(DECIMAL(19,4), sod.UnitPrice) AS SourceUnitPrice,
    CONVERT(DECIMAL(10,4), sod.UnitPriceDiscount) AS SourceDiscountRate,

    CONVERT
    (
        DECIMAL(19,4),
        sod.OrderQty * CONVERT(DECIMAL(19,4), sod.UnitPrice)
    ) AS SourceGrossAmount,

    CONVERT(DECIMAL(19,4), sod.LineTotal) AS SourceNetSalesAmount

INTO #SourceMeasures
FROM AdventureWorks2022.Sales.SalesOrderDetail AS sod;

DECLARE @LineResults TABLE
(
    SortOrder INT PRIMARY KEY,
    Metric NVARCHAR(64),
    ResultValue BIGINT
);

INSERT INTO @LineResults
(
    SortOrder,
    Metric,
    ResultValue
)
SELECT
    v.SortOrder,
    v.Metric,
    SUM(CONVERT(BIGINT, v.MetricValue))

FROM dw.FactSales AS f

LEFT JOIN #SourceMeasures AS s
    ON s.SalesOrderID = f.SalesOrderID
   AND s.SalesOrderDetailID = f.SalesOrderDetailID

CROSS APPLY
(
    VALUES
    (
        1, N'ComparedRows',
        1
    ),
    (
        2, N'MissingSourceLines',
        CASE WHEN s.SalesOrderDetailID IS NULL THEN 1 ELSE 0 END
    ),
    (
        3, N'QuantityMismatch',
        CASE WHEN f.OrderQuantity <> s.SourceQuantity THEN 1 ELSE 0 END
    ),
    (
        4, N'UnitPriceMismatch',
        CASE WHEN f.UnitPrice <> s.SourceUnitPrice THEN 1 ELSE 0 END
    ),
    (
        5, N'DiscountRateMismatch',
        CASE WHEN f.DiscountRate <> s.SourceDiscountRate THEN 1 ELSE 0 END
    ),
    (
        6, N'GrossAmountMismatch',
        CASE WHEN f.GrossAmount <> s.SourceGrossAmount THEN 1 ELSE 0 END
    ),
    (
        7, N'NetSalesAmountMismatch',
        CASE WHEN f.NetSalesAmount <> s.SourceNetSalesAmount THEN 1 ELSE 0 END
    ),
    (
        8, N'DiscountAmountMismatch',
        CASE
            WHEN f.DiscountAmount <>
                CONVERT
                (
                    DECIMAL(19,4),
                    s.SourceGrossAmount - s.SourceNetSalesAmount
                )
            THEN 1 ELSE 0
        END
    ),
    (
        9, N'ArithmeticIdentityMismatch',
        CASE
            WHEN f.GrossAmount - f.DiscountAmount <> f.NetSalesAmount
            THEN 1 ELSE 0
        END
    )
) AS v(SortOrder, Metric, MetricValue)

GROUP BY
    v.SortOrder,
    v.Metric;

SELECT
    Metric,
    ResultValue
FROM @LineResults
ORDER BY SortOrder;

DECLARE @AggregateResults TABLE
(
    SortOrder INT PRIMARY KEY,
    Dataset NVARCHAR(20),
    TotalRows BIGINT,
    TotalQuantity BIGINT,
    TotalGrossAmount DECIMAL(38,4),
    TotalDiscountAmount DECIMAL(38,4),
    TotalNetSalesAmount DECIMAL(38,4)
);

INSERT INTO @AggregateResults
SELECT
    1,
    N'Source',
    COUNT_BIG(*),
    SUM(CONVERT(BIGINT, SourceQuantity)),
    SUM(SourceGrossAmount),
    SUM
    (
        CONVERT
        (
            DECIMAL(19,4),
            SourceGrossAmount - SourceNetSalesAmount
        )
    ),
    SUM(SourceNetSalesAmount)
FROM #SourceMeasures

UNION ALL

SELECT
    2,
    N'FactSales',
    COUNT_BIG(*),
    SUM(CONVERT(BIGINT, OrderQuantity)),
    SUM(GrossAmount),
    SUM(DiscountAmount),
    SUM(NetSalesAmount)
FROM dw.FactSales;

SELECT
    Dataset,
    TotalRows,
    TotalQuantity,
    TotalGrossAmount,
    TotalDiscountAmount,
    TotalNetSalesAmount
FROM @AggregateResults
ORDER BY SortOrder;

IF NOT EXISTS
(
    SELECT 1
    FROM @LineResults
    WHERE Metric = N'ComparedRows'
      AND ResultValue > 0
)
OR EXISTS
(
    SELECT 1
    FROM @LineResults
    WHERE Metric <> N'ComparedRows'
      AND ResultValue <> 0
)
BEGIN
    THROW 51021,
        'FactSales measure validation failed: empty fact, missing source lines, or row-level differences.',
        1;
END;

IF EXISTS
(
    SELECT
        TotalRows,
        TotalQuantity,
        TotalGrossAmount,
        TotalDiscountAmount,
        TotalNetSalesAmount
    FROM @AggregateResults
    WHERE Dataset = N'Source'

    EXCEPT

    SELECT
        TotalRows,
        TotalQuantity,
        TotalGrossAmount,
        TotalDiscountAmount,
        TotalNetSalesAmount
    FROM @AggregateResults
    WHERE Dataset = N'FactSales'
)
BEGIN
    THROW 51022,
        'FactSales measure validation failed: source and fact aggregates differ.',
        1;
END;

DROP TABLE #SourceMeasures;
GO
