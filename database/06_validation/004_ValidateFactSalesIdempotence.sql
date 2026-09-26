/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 004_ValidateFactSalesIdempotence.sql
Author   : Diego Suárez
Purpose  : Validate full-load idempotence and successful execution auditing.
Notes    : Executes etl.LoadFactSales and creates a new audit entry.
           Run against an already validated fact, with unchanged staging and
           dimensions, without concurrent ETL activity or an outer transaction.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SET NOCOUNT ON;

IF @@TRANCOUNT <> 0
BEGIN
    THROW 51024,
        'Run idempotence validation without an existing transaction.',
        1;
END;

IF NOT EXISTS (SELECT 1 FROM dw.FactSales)
BEGIN
    THROW 51025,
        'Idempotence validation requires a populated and previously validated fact.',
        1;
END;

DECLARE @PreviousExecutionID BIGINT;
DECLARE @StagingRows BIGINT;
DECLARE @BeforeRows BIGINT;
DECLARE @AfterRows BIGINT;
DECLARE @BeforeOnlyRows BIGINT;
DECLARE @AfterOnlyRows BIGINT;
DECLARE @NewExecutionCount BIGINT;

SELECT
    @PreviousExecutionID = COALESCE(MAX(ExecutionID), 0)
FROM audit.ETLExecutionLog
WHERE ProcessName = N'etl.LoadFactSales';

SELECT
    @StagingRows = COUNT_BIG(*)
FROM stg.SalesOrderLine;

SELECT
    f.*
INTO #FactSalesBefore
FROM dw.FactSales AS f;

SELECT
    @BeforeRows = COUNT_BIG(*)
FROM #FactSalesBefore;

BEGIN TRY

    EXEC etl.LoadFactSales;

END TRY
BEGIN CATCH

    DROP TABLE #FactSalesBefore;
    THROW;

END CATCH;

SELECT
    @AfterRows = COUNT_BIG(*)
FROM dw.FactSales;

;WITH BeforeOnly AS
(
    SELECT *
    FROM #FactSalesBefore

    EXCEPT

    SELECT *
    FROM dw.FactSales
),
AfterOnly AS
(
    SELECT *
    FROM dw.FactSales

    EXCEPT

    SELECT *
    FROM #FactSalesBefore
)
SELECT
    @BeforeOnlyRows =
        (SELECT COUNT_BIG(*) FROM BeforeOnly),

    @AfterOnlyRows =
        (SELECT COUNT_BIG(*) FROM AfterOnly);

SELECT
    @NewExecutionCount = COUNT_BIG(*)
FROM audit.ETLExecutionLog
WHERE ProcessName = N'etl.LoadFactSales'
  AND ExecutionID > @PreviousExecutionID;

SELECT
    @BeforeRows AS BeforeRows,
    @AfterRows AS AfterRows,
    @BeforeOnlyRows AS BeforeOnlyRows,
    @AfterOnlyRows AS AfterOnlyRows,
    @NewExecutionCount AS NewExecutionCount,
    @@TRANCOUNT AS OpenTransactions;

SELECT
    ExecutionID,
    [Status],
    RowsRead,
    RowsInserted,
    RowsUpdated,
    RowsRejected,
    ErrorMessage
FROM audit.ETLExecutionLog
WHERE ProcessName = N'etl.LoadFactSales'
  AND ExecutionID > @PreviousExecutionID
ORDER BY ExecutionID;

DROP TABLE #FactSalesBefore;

IF @BeforeRows <> @AfterRows
   OR @AfterRows <> @StagingRows
   OR @BeforeOnlyRows <> 0
   OR @AfterOnlyRows <> 0
BEGIN
    THROW 51026,
        'FactSales idempotence validation failed: row counts or fact contents differ.',
        1;
END;

IF @NewExecutionCount <> 1
   OR @@TRANCOUNT <> 0
   OR NOT EXISTS
   (
       SELECT 1
       FROM audit.ETLExecutionLog
       WHERE ProcessName = N'etl.LoadFactSales'
         AND ExecutionID > @PreviousExecutionID
         AND [Status] = N'Succeeded'
         AND RowsRead = @StagingRows
         AND RowsInserted = @AfterRows
         AND RowsUpdated = 0
         AND RowsRejected = 0
         AND ErrorMessage IS NULL
         AND EndTime IS NOT NULL
   )
BEGIN
    THROW 51027,
        'FactSales idempotence validation failed: unexpected audit result or an open transaction.',
        1;
END;
GO
