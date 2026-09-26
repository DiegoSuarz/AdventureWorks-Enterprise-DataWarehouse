/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 005_ValidateFactSalesRollback.sql
Author   : Diego Suárez
Purpose  : Validate rollback after a forced INSERT failure and failure auditing.
Notes    : Development validation. Temporarily adds a rejecting CHECK constraint
           and executes etl.LoadFactSales. Creates a Failed audit entry.
           Run after validations 001-003, without concurrent ETL activity,
           source changes, or an outer transaction.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SET NOCOUNT ON;

IF @@TRANCOUNT <> 0
BEGIN
    THROW 51028,
        'Run rollback validation without an existing transaction.',
        1;
END;

IF OBJECT_ID
(
    N'dw.CK_FactSales_Validation_ForceFailure',
    N'C'
) IS NOT NULL
BEGIN
    THROW 51029,
        'The validation constraint already exists. Review before continuing.',
        1;
END;

IF NOT EXISTS (SELECT 1 FROM dw.FactSales)
   OR NOT EXISTS (SELECT 1 FROM stg.SalesOrderLine)
BEGIN
    THROW 51030,
        'Rollback validation requires populated and previously validated staging and fact tables.',
        1;
END;

DECLARE @PreviousExecutionID BIGINT;
DECLARE @StagingRows BIGINT;
DECLARE @BeforeRows BIGINT;
DECLARE @AfterRows BIGINT;
DECLARE @BeforeOnlyRows BIGINT;
DECLARE @AfterOnlyRows BIGINT;
DECLARE @NewExecutionCount BIGINT;
DECLARE @CaughtErrorNumber INT = NULL;
DECLARE @CaughtErrorMessage NVARCHAR(4000) = NULL;
DECLARE @TransactionCountAtCatch INT = NULL;
DECLARE @TestConstraintRemoved BIT;

SELECT
    @PreviousExecutionID = COALESCE(MAX(ExecutionID), 0)
FROM audit.ETLExecutionLog
WHERE ProcessName = N'etl.LoadFactSales';

SELECT
    @StagingRows = COUNT_BIG(*)
FROM stg.SalesOrderLine;

SELECT
    f.*
INTO #FactSalesBeforeFailure
FROM dw.FactSales AS f;

SELECT
    @BeforeRows = COUNT_BIG(*)
FROM #FactSalesBeforeFailure;

BEGIN TRY

    ALTER TABLE dw.FactSales WITH NOCHECK
    ADD CONSTRAINT CK_FactSales_Validation_ForceFailure
        CHECK (OrderQuantity < 0);

    BEGIN TRY

        EXEC etl.LoadFactSales;

    END TRY
    BEGIN CATCH

        SET @CaughtErrorNumber = ERROR_NUMBER();
        SET @CaughtErrorMessage = ERROR_MESSAGE();
        SET @TransactionCountAtCatch = @@TRANCOUNT;

        -- Defensive cleanup; an open transaction also fails validation below.
        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

    END CATCH;

    ALTER TABLE dw.FactSales
    DROP CONSTRAINT CK_FactSales_Validation_ForceFailure;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    IF OBJECT_ID
    (
        N'dw.CK_FactSales_Validation_ForceFailure',
        N'C'
    ) IS NOT NULL
    BEGIN
        ALTER TABLE dw.FactSales
        DROP CONSTRAINT CK_FactSales_Validation_ForceFailure;
    END;

    DROP TABLE #FactSalesBeforeFailure;
    THROW;

END CATCH;

SELECT
    @AfterRows = COUNT_BIG(*)
FROM dw.FactSales;

;WITH BeforeOnly AS
(
    SELECT *
    FROM #FactSalesBeforeFailure

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
    FROM #FactSalesBeforeFailure
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

SET @TestConstraintRemoved =
    CASE
        WHEN OBJECT_ID
        (
            N'dw.CK_FactSales_Validation_ForceFailure',
            N'C'
        ) IS NULL
        THEN 1 ELSE 0
    END;

SELECT
    @CaughtErrorNumber AS CaughtErrorNumber,
    @CaughtErrorMessage AS CaughtErrorMessage;

SELECT
    @BeforeRows AS BeforeRows,
    @AfterRows AS AfterRows,
    @BeforeOnlyRows AS BeforeOnlyRows,
    @AfterOnlyRows AS AfterOnlyRows,
    @TestConstraintRemoved AS TestConstraintRemoved,
    @TransactionCountAtCatch AS TransactionCountAtCatch,
    @@TRANCOUNT AS OpenTransactions,
    @NewExecutionCount AS NewExecutionCount;

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

DROP TABLE #FactSalesBeforeFailure;

IF COALESCE(@CaughtErrorNumber, 0) <> 547
   OR CHARINDEX
   (
       N'CK_FactSales_Validation_ForceFailure',
       COALESCE(@CaughtErrorMessage, N'')
   ) = 0
BEGIN
    THROW 51031,
        'Rollback validation failed: the expected CHECK constraint error was not captured.',
        1;
END;

IF @BeforeRows <> @AfterRows
   OR @BeforeOnlyRows <> 0
   OR @AfterOnlyRows <> 0
   OR @TestConstraintRemoved <> 1
   OR COALESCE(@TransactionCountAtCatch, -1) <> 0
   OR @@TRANCOUNT <> 0
BEGIN
    THROW 51032,
        'Rollback validation failed: fact contents changed, the loader left a transaction open, or cleanup is incomplete.',
        1;
END;

IF @NewExecutionCount <> 1
   OR NOT EXISTS
   (
       SELECT 1
       FROM audit.ETLExecutionLog
       WHERE ProcessName = N'etl.LoadFactSales'
         AND ExecutionID > @PreviousExecutionID
         AND [Status] = N'Failed'
         AND RowsRead = @StagingRows
         AND RowsInserted = 0
         AND RowsUpdated = 0
         AND RowsRejected = 0
         AND EndTime IS NOT NULL
         AND CHARINDEX(N'ErrorNumber: 547;', ErrorMessage) > 0
         AND CHARINDEX
         (
             N'CK_FactSales_Validation_ForceFailure',
             ErrorMessage
         ) > 0
   )
BEGIN
    THROW 51033,
        'Rollback validation failed: the expected failure audit entry was not recorded.',
        1;
END;
GO
