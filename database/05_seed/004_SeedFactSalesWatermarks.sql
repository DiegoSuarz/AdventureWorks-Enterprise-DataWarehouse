/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 004_SeedFactSalesWatermarks.sql
Author   : Diego Suárez
Purpose  : Register Header and Detail watermark streams for incremental sales.
           Preserve existing progress when executed again.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Streams TABLE
(
    ProcessName NVARCHAR(128) PRIMARY KEY,
    SourceObject NVARCHAR(256) NOT NULL
);

INSERT INTO @Streams
(
    ProcessName,
    SourceObject
)
VALUES
(
    N'etl.LoadFactSalesIncremental.Header',
    N'AdventureWorks2022.Sales.SalesOrderHeader'
),
(
    N'etl.LoadFactSalesIncremental.Detail',
    N'AdventureWorks2022.Sales.SalesOrderDetail'
);

IF EXISTS
(
    SELECT 1
    FROM audit.ETLWatermark AS w
    INNER JOIN @Streams AS s
        ON s.ProcessName = w.ProcessName
    WHERE w.SourceObject <> s.SourceObject
)
BEGIN
    THROW 51100,
        'FactSales watermark registration failed: an existing stream references a different source.',
        1;
END;

INSERT INTO audit.ETLWatermark
(
    ProcessName,
    SourceObject
)
SELECT
    s.ProcessName,
    s.SourceObject
FROM @Streams AS s
WHERE NOT EXISTS
(
    SELECT 1
    FROM audit.ETLWatermark AS w WITH (UPDLOCK, HOLDLOCK)
    WHERE w.ProcessName = s.ProcessName
);

SELECT
    w.ProcessName,
    w.SourceObject,
    w.[Status],
    w.LowModifiedDate,
    w.LowBusinessKey,
    w.HighModifiedDate,
    w.HighBusinessKey,
    w.LastSuccessfulExecutionID,
    w.CurrentExecutionID
FROM audit.ETLWatermark AS w
INNER JOIN @Streams AS s
    ON s.ProcessName = w.ProcessName
ORDER BY w.ProcessName;
GO
