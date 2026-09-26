/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 006_ValidateFactSalesDeltaRollback.sql
Author   : Diego Suárez
Purpose  : Validate atomic rollback of a fact delta UPDATE followed by a
           deliberately rejected INSERT, and verify failure auditing.
Notes    : Development-only test using order 75123 and detail 121317.
           Requires its three original lines in delta staging and a validated
           fact baseline. Run without concurrent ETL or an outer transaction.
           Temporarily modifies fact rows and adds a CHECK constraint.
           Restores test rows during normal execution and handled errors.
           An interrupted session can require manual recovery.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SET NOCOUNT ON;

IF @@TRANCOUNT <> 0
BEGIN
    THROW 51143, 'Run this test without an existing transaction.', 1;
END;

IF OBJECT_ID
(
    N'dw.CK_FactSales_DeltaValidation_ForceFailure',
    N'C'
) IS NOT NULL
BEGIN
    THROW 51144, 'The test constraint already exists.', 1;
END;

IF (SELECT COUNT_BIG(*) FROM stg.SalesOrderLineDelta) <> 3
   OR EXISTS
   (
       SELECT 1
       FROM stg.SalesOrderLineDelta
       WHERE SalesOrderID <> 75123
   )
   OR NOT EXISTS
   (
       SELECT 1
       FROM stg.SalesOrderLineDelta
       WHERE SalesOrderID = 75123
         AND SalesOrderDetailID = 121317
   )
BEGIN
    THROW 51145, 'Expected the three-line delta for order 75123.', 1;
END;

DECLARE @UpdateDetailID INT;
DECLARE @PreviousExecutionID BIGINT;
DECLARE @CaughtErrorNumber INT = NULL;
DECLARE @CaughtErrorMessage NVARCHAR(4000) = NULL;
DECLARE @TransactionCountAtCatch INT = NULL;
DECLARE @BeforeOnlyRows BIGINT;
DECLARE @AfterOnlyRows BIGINT;

SELECT *
INTO #FactOriginal
FROM dw.FactSales;

SELECT
    @PreviousExecutionID = COALESCE(MAX(ExecutionID), 0)
FROM audit.ETLExecutionLog
WHERE ProcessName = N'etl.LoadFactSalesDelta';

SELECT TOP (1)
    @UpdateDetailID = f.SalesOrderDetailID
FROM dw.FactSales AS f
INNER JOIN stg.SalesOrderLineDelta AS s
    ON s.SalesOrderID = f.SalesOrderID
   AND s.SalesOrderDetailID = f.SalesOrderDetailID
WHERE f.SalesOrderID = 75123
  AND f.SalesOrderDetailID <> 121317
  AND f.ShipDateKey IS NOT NULL
ORDER BY f.SalesOrderDetailID;

IF @UpdateDetailID IS NULL
   OR NOT EXISTS
   (
       SELECT 1 FROM #FactOriginal
       WHERE SalesOrderID = 75123
         AND SalesOrderDetailID = 121317
   )
BEGIN
    THROW 51146, 'Required fact rows were not found.', 1;
END;

BEGIN TRY

    BEGIN TRANSACTION;

    UPDATE dw.FactSales
    SET ShipDateKey = NULL
    WHERE SalesOrderID = 75123
      AND SalesOrderDetailID = @UpdateDetailID;

    IF @@ROWCOUNT <> 1
        THROW 51147, 'Expected one row to prepare the UPDATE test.', 1;

    DELETE FROM dw.FactSales
    WHERE SalesOrderID = 75123
      AND SalesOrderDetailID = 121317;

    IF @@ROWCOUNT <> 1
        THROW 51148, 'Expected one row to prepare the INSERT test.', 1;

    ALTER TABLE dw.FactSales WITH NOCHECK
    ADD CONSTRAINT CK_FactSales_DeltaValidation_ForceFailure
        CHECK (SalesOrderDetailID <> 121317);

    SELECT *
    INTO #FactPrepared
    FROM dw.FactSales;

    COMMIT TRANSACTION;

    BEGIN TRY

        EXEC etl.LoadFactSalesDelta;

    END TRY
    BEGIN CATCH

        SET @CaughtErrorNumber = ERROR_NUMBER();
        SET @CaughtErrorMessage = ERROR_MESSAGE();
        SET @TransactionCountAtCatch = @@TRANCOUNT;

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

    END CATCH;

    SELECT @BeforeOnlyRows = COUNT_BIG(*)
    FROM
    (
        SELECT * FROM #FactPrepared
        EXCEPT
        SELECT * FROM dw.FactSales
    ) AS BeforeOnly;

    SELECT @AfterOnlyRows = COUNT_BIG(*)
    FROM
    (
        SELECT * FROM dw.FactSales
        EXCEPT
        SELECT * FROM #FactPrepared
    ) AS AfterOnly;

    SELECT
        @CaughtErrorNumber AS CaughtErrorNumber,
        @CaughtErrorMessage AS CaughtErrorMessage;

    SELECT
        @UpdateDetailID AS UpdateTestDetailID,
        (SELECT COUNT_BIG(*) FROM #FactPrepared) AS PreparedRows,
        (SELECT COUNT_BIG(*) FROM dw.FactSales) AS AfterFailureRows,
        @BeforeOnlyRows AS BeforeOnlyRows,
        @AfterOnlyRows AS AfterOnlyRows,
        @TransactionCountAtCatch AS TransactionCountAtCatch;

    -- Restore original fact rows
    BEGIN TRANSACTION;

    IF OBJECT_ID
    (
        N'dw.CK_FactSales_DeltaValidation_ForceFailure',
        N'C'
    ) IS NOT NULL
    BEGIN
        ALTER TABLE dw.FactSales
        DROP CONSTRAINT CK_FactSales_DeltaValidation_ForceFailure;
    END;

    UPDATE f
    SET ShipDateKey = b.ShipDateKey
    FROM dw.FactSales AS f
    INNER JOIN #FactOriginal AS b
        ON b.SalesOrderID = f.SalesOrderID
       AND b.SalesOrderDetailID = f.SalesOrderDetailID
    WHERE f.SalesOrderID = 75123
      AND f.SalesOrderDetailID = @UpdateDetailID;

    INSERT INTO dw.FactSales
    SELECT b.*
    FROM #FactOriginal AS b
    WHERE b.SalesOrderID = 75123
      AND b.SalesOrderDetailID = 121317
      AND NOT EXISTS
      (
          SELECT 1
          FROM dw.FactSales AS f
          WHERE f.SalesOrderID = b.SalesOrderID
            AND f.SalesOrderDetailID = b.SalesOrderDetailID
      );

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    -- Restore original fact rows
    BEGIN TRANSACTION;

    IF OBJECT_ID
    (
        N'dw.CK_FactSales_DeltaValidation_ForceFailure',
        N'C'
    ) IS NOT NULL
    BEGIN
        ALTER TABLE dw.FactSales
        DROP CONSTRAINT CK_FactSales_DeltaValidation_ForceFailure;
    END;

    UPDATE f
    SET ShipDateKey = b.ShipDateKey
    FROM dw.FactSales AS f
    INNER JOIN #FactOriginal AS b
        ON b.SalesOrderID = f.SalesOrderID
       AND b.SalesOrderDetailID = f.SalesOrderDetailID
    WHERE f.SalesOrderID = 75123
      AND f.SalesOrderDetailID = @UpdateDetailID;

    INSERT INTO dw.FactSales
    SELECT b.*
    FROM #FactOriginal AS b
    WHERE b.SalesOrderID = 75123
      AND b.SalesOrderDetailID = 121317
      AND NOT EXISTS
      (
          SELECT 1
          FROM dw.FactSales AS f
          WHERE f.SalesOrderID = b.SalesOrderID
            AND f.SalesOrderDetailID = b.SalesOrderDetailID
      );

    COMMIT TRANSACTION;

    THROW;

END CATCH;

-- Final assertions
DECLARE @RestoredBeforeOnly BIGINT;
DECLARE @RestoredAfterOnly BIGINT;

SELECT @RestoredBeforeOnly = COUNT_BIG(*)
FROM
(
    SELECT * FROM #FactOriginal
    EXCEPT
    SELECT * FROM dw.FactSales
) AS OriginalOnly;

SELECT @RestoredAfterOnly = COUNT_BIG(*)
FROM
(
    SELECT * FROM dw.FactSales
    EXCEPT
    SELECT * FROM #FactOriginal
) AS CurrentOnly;

SELECT
    ExecutionID, [Status], RowsRead, RowsInserted,
    RowsUpdated, RowsRejected, EndTime, ErrorMessage
INTO #TestAudit
FROM audit.ETLExecutionLog
WHERE ProcessName = N'etl.LoadFactSalesDelta'
  AND ExecutionID > @PreviousExecutionID;

SELECT
    (SELECT COUNT_BIG(*) FROM #FactOriginal) AS OriginalRows,
    (SELECT COUNT_BIG(*) FROM dw.FactSales) AS RestoredRows,
    @RestoredBeforeOnly AS OriginalOnlyRows,
    @RestoredAfterOnly AS RestoredOnlyRows,
    @@TRANCOUNT AS OpenTransactions;

SELECT * FROM #TestAudit ORDER BY ExecutionID;

IF ISNULL(@CaughtErrorNumber, -1) <> 547
   OR CHARINDEX(N'CK_FactSales_DeltaValidation_ForceFailure',
                COALESCE(@CaughtErrorMessage, N'')) = 0
   OR ISNULL(@TransactionCountAtCatch, -1) <> 0
   OR @BeforeOnlyRows <> 0 OR @AfterOnlyRows <> 0
BEGIN
    THROW 51149, 'Expected INSERT failure or complete rollback was not confirmed.', 1;
END;

IF @RestoredBeforeOnly <> 0 OR @RestoredAfterOnly <> 0
   OR @@TRANCOUNT <> 0
   OR OBJECT_ID(N'dw.CK_FactSales_DeltaValidation_ForceFailure', N'C') IS NOT NULL
BEGIN
    THROW 51150, 'Original fact restoration or test cleanup failed.', 1;
END;

IF (SELECT COUNT_BIG(*) FROM #TestAudit) <> 1
   OR NOT EXISTS
   (
       SELECT 1 FROM #TestAudit
       WHERE [Status] = N'Failed'
         AND RowsRead = 3 AND RowsInserted = 0
         AND RowsUpdated = 0 AND RowsRejected = 0
         AND EndTime IS NOT NULL
         AND CHARINDEX(N'ErrorNumber: 547;', ErrorMessage) > 0
         AND CHARINDEX(N'CK_FactSales_DeltaValidation_ForceFailure',
                       ErrorMessage) > 0
   )
BEGIN
    THROW 51151, 'Expected failure audit entry was not confirmed.', 1;
END;

DROP TABLE #TestAudit;
DROP TABLE #FactPrepared;
DROP TABLE #FactOriginal;

PRINT 'PASS: FactSales delta rollback, restoration, and failure audit.';
GO
