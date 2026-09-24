/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 001_ValidateFactSalesGrain.sql
Author   : Diego Suárez
Purpose  : Validate FactSales row counts, grain uniqueness, and bidirectional
           line coverage against the existing staging snapshot.
Notes    : Run after staging and fact loading, without concurrent ETL activity.
           This script does not modify persistent data.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SET NOCOUNT ON;

DECLARE @StagingRows BIGINT;
DECLARE @FactRows BIGINT;
DECLARE @MissingFactLines BIGINT;
DECLARE @UnexpectedFactLines BIGINT;
DECLARE @DuplicateFactGrains BIGINT;

SELECT
    @StagingRows = COUNT_BIG(*)
FROM stg.SalesOrderLine;

SELECT
    @FactRows = COUNT_BIG(*)
FROM dw.FactSales;

;WITH MissingFactLines AS
(
    SELECT
        SalesOrderID,
        SalesOrderDetailID
    FROM stg.SalesOrderLine

    EXCEPT

    SELECT
        SalesOrderID,
        SalesOrderDetailID
    FROM dw.FactSales
),
UnexpectedFactLines AS
(
    SELECT
        SalesOrderID,
        SalesOrderDetailID
    FROM dw.FactSales

    EXCEPT

    SELECT
        SalesOrderID,
        SalesOrderDetailID
    FROM stg.SalesOrderLine
),
DuplicateFactGrains AS
(
    SELECT
        SalesOrderID,
        SalesOrderDetailID
    FROM dw.FactSales
    GROUP BY
        SalesOrderID,
        SalesOrderDetailID
    HAVING COUNT_BIG(*) > 1
)
SELECT
    @MissingFactLines =
        (SELECT COUNT_BIG(*) FROM MissingFactLines),

    @UnexpectedFactLines =
        (SELECT COUNT_BIG(*) FROM UnexpectedFactLines),

    @DuplicateFactGrains =
        (SELECT COUNT_BIG(*) FROM DuplicateFactGrains);

SELECT
    @StagingRows AS StagingRows,
    @FactRows AS FactRows,
    @MissingFactLines AS MissingFactLines,
    @UnexpectedFactLines AS UnexpectedFactLines,
    @DuplicateFactGrains AS DuplicateFactGrains;

IF @StagingRows = 0
   OR @StagingRows <> @FactRows
   OR @MissingFactLines <> 0
   OR @UnexpectedFactLines <> 0
   OR @DuplicateFactGrains <> 0
BEGIN
    THROW 51020,
        'FactSales grain validation failed: empty staging, row-count mismatch, missing or unexpected lines, or duplicate grains.',
        1;
END;
GO
