/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 009_ValidateFactSalesRetryNewChanges.sql
Author   : Diego Suárez
Purpose  : Validate frozen-boundary retry and deferral of new source changes.
Notes    : Development fixture: order 75123, detail 121317.
           Temporarily changes source dates, a fact row, and watermark state.
           Disables source triggers only inside preparation/cleanup transactions.
           Requires source ALTER/UPDATE permissions and stable dimensions.
           Run in development without concurrent source writes or ETL.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF @@TRANCOUNT <> 0
BEGIN
    THROW 51300, 'Run this validation without an outer transaction.', 1;
END;

IF OBJECT_ID
(
    N'dw.CK_FactSales_IncrementalRetry_ForceFailure',
    N'C'
) IS NOT NULL
BEGIN
    THROW 51301, 'The retry validation constraint already exists.', 1;
END;

DECLARE @HeaderDate DATETIME2(7);
DECLARE @PreviousExecutionID BIGINT;
DECLARE @FailedExecutionID BIGINT;
DECLARE @RetryExecutionID BIGINT;
DECLARE @CaughtErrorNumber INT = NULL;
DECLARE @CaughtErrorMessage NVARCHAR(4000) = NULL;
DECLARE @TransactionCountAtCatch INT = NULL;
DECLARE @ValidationFailureMessage NVARCHAR(2048) = NULL;

SELECT *
INTO #OriginalWatermarks
FROM audit.ETLWatermark
WHERE ProcessName IN
(
    N'etl.LoadFactSalesIncremental.Header',
    N'etl.LoadFactSalesIncremental.Detail'
);

SELECT *
INTO #OriginalFact
FROM dw.FactSales;

SELECT *
INTO #OriginalDelta
FROM stg.SalesOrderLineDelta;

IF (SELECT COUNT(*) FROM #OriginalWatermarks) <> 2
   OR EXISTS
   (
       SELECT 1
       FROM #OriginalWatermarks
       WHERE [Status] <> 'Ready'
          OR LowModifiedDate IS NULL
          OR LowBusinessKey IS NULL
          OR HighModifiedDate IS NOT NULL
          OR HighBusinessKey IS NOT NULL
          OR CurrentExecutionID IS NOT NULL
   )
BEGIN
    THROW 51302, 'Both sales controls must be initialized and Ready.', 1;
END;

SELECT
    @HeaderDate = CONVERT(DATETIME2(7), ModifiedDate)
FROM AdventureWorks2022.Sales.SalesOrderHeader
WHERE SalesOrderID = 75123;

IF @HeaderDate IS NULL
   OR NOT EXISTS
   (
       SELECT 1 FROM #OriginalWatermarks
       WHERE ProcessName = N'etl.LoadFactSalesIncremental.Header'
         AND LowModifiedDate = @HeaderDate
         AND LowBusinessKey = 75123
   )
   OR NOT EXISTS
   (
       SELECT 1
       FROM AdventureWorks2022.Sales.SalesOrderHeader
       WHERE SalesOrderID = 75122
         AND CONVERT(DATETIME2(7), ModifiedDate) = @HeaderDate
   )
BEGIN
    THROW 51303, 'The expected Header watermark fixture is unavailable.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM AdventureWorks2022.Sales.SalesOrderHeader AS h
    CROSS JOIN #OriginalWatermarks AS w
    WHERE w.ProcessName = N'etl.LoadFactSalesIncremental.Header'
      AND
      (
          CONVERT(DATETIME2(7), h.ModifiedDate) > w.LowModifiedDate
          OR
          (
              CONVERT(DATETIME2(7), h.ModifiedDate) = w.LowModifiedDate
              AND h.SalesOrderID > w.LowBusinessKey
          )
      )
)
OR EXISTS
(
    SELECT 1
    FROM AdventureWorks2022.Sales.SalesOrderDetail AS d
    CROSS JOIN #OriginalWatermarks AS w
    WHERE w.ProcessName = N'etl.LoadFactSalesIncremental.Detail'
      AND
      (
          CONVERT(DATETIME2(7), d.ModifiedDate) > w.LowModifiedDate
          OR
          (
              CONVERT(DATETIME2(7), d.ModifiedDate) = w.LowModifiedDate
              AND d.SalesOrderDetailID > w.LowBusinessKey
          )
      )
)
BEGIN
    THROW 51304, 'Source changes are pending outside this validation fixture.', 1;
END;

IF
(
    SELECT COUNT_BIG(*)
    FROM AdventureWorks2022.Sales.SalesOrderDetail
    WHERE SalesOrderID = 75123
) <> 3
OR
(
    SELECT COUNT_BIG(*)
    FROM #OriginalFact
    WHERE SalesOrderID = 75123
) <> 3
OR EXISTS
(
    SELECT SalesOrderID, SalesOrderDetailID
    FROM AdventureWorks2022.Sales.SalesOrderDetail
    WHERE SalesOrderID = 75123

    EXCEPT

    SELECT SalesOrderID, SalesOrderDetailID
    FROM #OriginalFact
    WHERE SalesOrderID = 75123
)
OR NOT EXISTS
(
    SELECT 1 FROM #OriginalFact
    WHERE SalesOrderID = 75123
      AND SalesOrderDetailID = 121317
      AND ShipDateKey IS NOT NULL
)
BEGIN
    THROW 51305, 'Required source and fact lines are unavailable or inconsistent.', 1;
END;

-- Verify source permissions and enabled triggers
EXEC AdventureWorks2022.sys.sp_executesql N'
    IF COALESCE(HAS_PERMS_BY_NAME(
           N''Sales.SalesOrderHeader'', N''OBJECT'', N''ALTER''), 0) <> 1
       OR COALESCE(HAS_PERMS_BY_NAME(
           N''Sales.SalesOrderDetail'', N''OBJECT'', N''ALTER''), 0) <> 1
       OR COALESCE(HAS_PERMS_BY_NAME(
           N''Sales.SalesOrderHeader'', N''OBJECT'', N''UPDATE''), 0) <> 1
       OR COALESCE(HAS_PERMS_BY_NAME(
           N''Sales.SalesOrderDetail'', N''OBJECT'', N''UPDATE''), 0) <> 1
    BEGIN
        THROW 51402, ''Source ALTER and UPDATE permissions are required.'', 1;
    END;

    IF
    (
        SELECT COUNT(*)
        FROM sys.triggers
        WHERE
            (parent_id = OBJECT_ID(N''Sales.SalesOrderHeader'')
             AND name = N''uSalesOrderHeader'')
            OR
            (parent_id = OBJECT_ID(N''Sales.SalesOrderDetail'')
             AND name = N''iduSalesOrderDetail'')
    ) <> 2
    OR EXISTS
    (
        SELECT 1
        FROM sys.triggers
        WHERE parent_id IN
        (
            OBJECT_ID(N''Sales.SalesOrderHeader''),
            OBJECT_ID(N''Sales.SalesOrderDetail'')
        )
          AND
          (
              is_disabled = 1
              OR is_instead_of_trigger = 1
              OR name NOT IN
                 (N''uSalesOrderHeader'', N''iduSalesOrderDetail'')
          )
    )
    BEGIN
        THROW 51403, ''Unexpected source trigger configuration.'', 1;
    END;
';

-- Preserve source dates before preparing the validation
DECLARE @NextExecutionID BIGINT = NULL;
DECLARE @NewHeaderDate DATETIME;
DECLARE @NewDetailDate DATETIME;

SELECT SalesOrderID, ModifiedDate
INTO #OriginalSourceHeader
FROM AdventureWorks2022.Sales.SalesOrderHeader
WHERE SalesOrderID = 75122;

SELECT SalesOrderID, SalesOrderDetailID, ModifiedDate
INTO #OriginalSourceDetail
FROM AdventureWorks2022.Sales.SalesOrderDetail
WHERE SalesOrderID = 75121
  AND SalesOrderDetailID = 121310;

IF (SELECT COUNT(*) FROM #OriginalSourceHeader) <> 1
   OR (SELECT COUNT(*) FROM #OriginalSourceDetail) <> 1
BEGIN
    THROW 51400, 'Required source fixtures are unavailable.', 1;
END;

SELECT SalesOrderID, SalesOrderDetailID
INTO #ExpectedNewCandidates
FROM AdventureWorks2022.Sales.SalesOrderDetail
WHERE SalesOrderID = 75122
   OR (SalesOrderID = 75121 AND SalesOrderDetailID = 121310);

IF (SELECT COUNT(*) FROM #ExpectedNewCandidates) <> 3
   OR EXISTS
   (
       SELECT SalesOrderID, SalesOrderDetailID
       FROM #ExpectedNewCandidates
       EXCEPT
       SELECT SalesOrderID, SalesOrderDetailID
       FROM #OriginalFact
   )
BEGIN
    THROW 51401, 'Expected three existing fact grains for the new changes.', 1;
END;

SELECT
    @NewHeaderDate = CONVERT(DATETIME, DATEADD(DAY, 1, LowModifiedDate))
FROM #OriginalWatermarks
WHERE ProcessName = N'etl.LoadFactSalesIncremental.Header';

SELECT
    @NewDetailDate = CONVERT(DATETIME, DATEADD(DAY, 1, LowModifiedDate))
FROM #OriginalWatermarks
WHERE ProcessName = N'etl.LoadFactSalesIncremental.Detail';

SELECT
    @PreviousExecutionID = COALESCE(MAX(ExecutionID), 0)
FROM audit.ETLExecutionLog
WHERE ProcessName = N'etl.LoadFactSalesIncremental';

BEGIN TRY

    -- Prepare the controlled failure
    BEGIN TRANSACTION;

    UPDATE audit.ETLWatermark
    SET
        LowBusinessKey = 75122,
        UpdatedAt = SYSUTCDATETIME()
    WHERE ProcessName = N'etl.LoadFactSalesIncremental.Header'
      AND [Status] = 'Ready'
      AND CurrentExecutionID IS NULL
      AND LowModifiedDate = @HeaderDate
      AND LowBusinessKey = 75123;

    IF @@ROWCOUNT <> 1
        THROW 51306, 'Expected one Header control to prepare the test.', 1;

    UPDATE dw.FactSales
    SET ShipDateKey = NULL
    WHERE SalesOrderID = 75123
      AND SalesOrderDetailID = 121317
      AND ShipDateKey IS NOT NULL;

    IF @@ROWCOUNT <> 1
        THROW 51307, 'Expected one fact line to prepare the test.', 1;

    ALTER TABLE dw.FactSales WITH NOCHECK
    ADD CONSTRAINT CK_FactSales_IncrementalRetry_ForceFailure
        CHECK
        (
            SalesOrderID <> 75123
            OR SalesOrderDetailID <> 121317
            OR ShipDateKey IS NULL
        );

    SELECT *
    INTO #PreparedFact
    FROM dw.FactSales;

    COMMIT TRANSACTION;

    BEGIN TRY

        EXEC etl.LoadFactSalesIncremental;

    END TRY
    BEGIN CATCH

        SET @CaughtErrorNumber = ERROR_NUMBER();
        SET @CaughtErrorMessage = ERROR_MESSAGE();
        SET @TransactionCountAtCatch = @@TRANCOUNT;

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

    END CATCH;

    IF ISNULL(@CaughtErrorNumber, -1) <> 547
       OR CHARINDEX
          (
              N'CK_FactSales_IncrementalRetry_ForceFailure',
              COALESCE(@CaughtErrorMessage, N'')
          ) = 0
       OR ISNULL(@TransactionCountAtCatch, -1) <> 0
    BEGIN
        THROW 51308, 'Expected constraint failure and transaction cleanup were not confirmed.', 1;
    END;

    SELECT
        @FailedExecutionID = MAX(ExecutionID)
    FROM audit.ETLExecutionLog
    WHERE ProcessName = N'etl.LoadFactSalesIncremental'
      AND ExecutionID > @PreviousExecutionID;

    IF
    (
        SELECT COUNT_BIG(*)
        FROM audit.ETLExecutionLog
        WHERE ProcessName = N'etl.LoadFactSalesIncremental'
          AND ExecutionID > @PreviousExecutionID
    ) <> 1
    BEGIN
        THROW 51309, 'Expected exactly one parent execution for the failed attempt.', 1;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM audit.ETLExecutionLog
        WHERE ExecutionID = @FailedExecutionID
          AND ProcessName = N'etl.LoadFactSalesIncremental'
          AND [Status] = N'Failed'
          AND RowsRead = 3
          AND RowsInserted = 0
          AND RowsUpdated = 0
          AND RowsRejected = 0
          AND EndTime IS NOT NULL
          AND CHARINDEX(N'ErrorNumber: 547;', ErrorMessage) > 0
          AND CHARINDEX(N'FactCommitted: 0;', ErrorMessage) > 0
          AND CHARINDEX
          (
              N'CK_FactSales_IncrementalRetry_ForceFailure',
              ErrorMessage
          ) > 0
    )
    BEGIN
        THROW 51310, 'The expected parent failure audit was not recorded.', 1;
    END;

    IF EXISTS
    (
        SELECT * FROM #PreparedFact
        EXCEPT
        SELECT * FROM dw.FactSales
    )
    OR EXISTS
    (
        SELECT * FROM dw.FactSales
        EXCEPT
        SELECT * FROM #PreparedFact
    )
    BEGIN
        THROW 51311, 'The failed attempt changed the prepared fact contents.', 1;
    END;

    SELECT *
    INTO #FailedWatermarks
    FROM audit.ETLWatermark
    WHERE ProcessName IN
    (
        N'etl.LoadFactSalesIncremental.Header',
        N'etl.LoadFactSalesIncremental.Detail'
    );

    IF NOT EXISTS
    (
        SELECT 1
        FROM #FailedWatermarks AS w
        INNER JOIN #OriginalWatermarks AS o
            ON o.WatermarkID = w.WatermarkID
        WHERE w.ProcessName = N'etl.LoadFactSalesIncremental.Header'
          AND w.[Status] = 'Failed'
          AND w.LowModifiedDate = @HeaderDate
          AND w.LowBusinessKey = 75122
          AND w.HighModifiedDate = @HeaderDate
          AND w.HighBusinessKey = 75123
          AND w.CurrentExecutionID = @FailedExecutionID
          AND NOT EXISTS
          (
              SELECT w.LastSuccessfulExecutionID
              EXCEPT
              SELECT o.LastSuccessfulExecutionID
          )
    )
    BEGIN
        THROW 51312, 'Header did not preserve the expected failed batch boundaries.', 1;
    END;

    IF EXISTS
    (
        SELECT * FROM #OriginalWatermarks
        WHERE ProcessName = N'etl.LoadFactSalesIncremental.Detail'
        EXCEPT
        SELECT * FROM #FailedWatermarks
        WHERE ProcessName = N'etl.LoadFactSalesIncremental.Detail'
    )
    OR EXISTS
    (
        SELECT * FROM #FailedWatermarks
        WHERE ProcessName = N'etl.LoadFactSalesIncremental.Detail'
        EXCEPT
        SELECT * FROM #OriginalWatermarks
        WHERE ProcessName = N'etl.LoadFactSalesIncremental.Detail'
    )
    BEGIN
        THROW 51313, 'The failed Header batch changed the inactive Detail control.', 1;
    END;

    -- Introduce changes beyond the frozen batch
    BEGIN TRANSACTION;

    EXEC AdventureWorks2022.sys.sp_executesql
        N'
        DISABLE TRIGGER Sales.uSalesOrderHeader ON Sales.SalesOrderHeader;
        DISABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;

        UPDATE Sales.SalesOrderHeader
        SET ModifiedDate = @HeaderDate
        WHERE SalesOrderID = 75122;

        IF @@ROWCOUNT <> 1
            THROW 51404, ''Expected one Header source row.'', 1;

        UPDATE Sales.SalesOrderDetail
        SET ModifiedDate = @DetailDate
        WHERE SalesOrderID = 75121
          AND SalesOrderDetailID = 121310;

        IF @@ROWCOUNT <> 1
            THROW 51405, ''Expected one Detail source row.'', 1;

        ENABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;
        ENABLE TRIGGER Sales.uSalesOrderHeader ON Sales.SalesOrderHeader;
        ',
        N'@HeaderDate DATETIME, @DetailDate DATETIME',
        @HeaderDate = @NewHeaderDate,
        @DetailDate = @NewDetailDate;

    COMMIT TRANSACTION;

    -- Retry after removing the forced failure
    ALTER TABLE dw.FactSales
    DROP CONSTRAINT CK_FactSales_IncrementalRetry_ForceFailure;

    EXEC etl.LoadFactSalesIncremental;

    SELECT
        @RetryExecutionID = MAX(ExecutionID)
    FROM audit.ETLExecutionLog
    WHERE ProcessName = N'etl.LoadFactSalesIncremental'
      AND ExecutionID > @FailedExecutionID;

    IF
    (
        SELECT COUNT_BIG(*)
        FROM audit.ETLExecutionLog
        WHERE ProcessName = N'etl.LoadFactSalesIncremental'
          AND ExecutionID > @FailedExecutionID
    ) <> 1
    OR @@TRANCOUNT <> 0
    OR NOT EXISTS
    (
        SELECT 1
        FROM audit.ETLExecutionLog
        WHERE ExecutionID = @RetryExecutionID
          AND ProcessName = N'etl.LoadFactSalesIncremental'
          AND [Status] = N'Succeeded'
          AND RowsRead = 3
          AND RowsInserted = 0
          AND RowsUpdated = 1
          AND RowsRejected = 0
          AND EndTime IS NOT NULL
          AND ErrorMessage IS NULL
    )
    BEGIN
        THROW 51314, 'The retry did not produce the expected successful execution.', 1;
    END;

    -- Verify retry candidates and deferred source changes
    IF (SELECT COUNT_BIG(*) FROM stg.SalesOrderLineDelta) <> 3
       OR EXISTS
       (
           SELECT SalesOrderID, SalesOrderDetailID
           FROM #OriginalFact
           WHERE SalesOrderID = 75123
           EXCEPT
           SELECT SalesOrderID, SalesOrderDetailID
           FROM stg.SalesOrderLineDelta
       )
       OR EXISTS
       (
           SELECT SalesOrderID, SalesOrderDetailID
           FROM stg.SalesOrderLineDelta
           EXCEPT
           SELECT SalesOrderID, SalesOrderDetailID
           FROM #OriginalFact
           WHERE SalesOrderID = 75123
       )
    BEGIN
        THROW 51408, 'Retry did not extract exactly the original Header batch.', 1;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM AdventureWorks2022.Sales.SalesOrderHeader
        WHERE SalesOrderID = 75122
          AND ModifiedDate = @NewHeaderDate
    )
    OR NOT EXISTS
    (
        SELECT 1
        FROM AdventureWorks2022.Sales.SalesOrderDetail
        WHERE SalesOrderID = 75121
          AND SalesOrderDetailID = 121310
          AND ModifiedDate = @NewDetailDate
    )
    OR NOT EXISTS
    (
        SELECT 1
        FROM #FailedWatermarks
        WHERE ProcessName = N'etl.LoadFactSalesIncremental.Header'
          AND @NewHeaderDate > HighModifiedDate
    )
    OR NOT EXISTS
    (
        SELECT 1
        FROM #OriginalWatermarks
        WHERE ProcessName = N'etl.LoadFactSalesIncremental.Detail'
          AND @NewDetailDate > LowModifiedDate
    )
    BEGIN
        THROW 51409, 'New source changes were not preserved beyond the original boundaries.', 1;
    END;

    SELECT *
    INTO #RetriedWatermarks
    FROM audit.ETLWatermark
    WHERE ProcessName IN
    (
        N'etl.LoadFactSalesIncremental.Header',
        N'etl.LoadFactSalesIncremental.Detail'
    );

    IF NOT EXISTS
    (
        SELECT 1
        FROM #RetriedWatermarks AS r
        INNER JOIN #FailedWatermarks AS f
            ON f.WatermarkID = r.WatermarkID
        WHERE r.ProcessName = N'etl.LoadFactSalesIncremental.Header'
          AND r.[Status] = 'Ready'
          AND r.LowModifiedDate = f.HighModifiedDate
          AND r.LowBusinessKey = f.HighBusinessKey
          AND r.HighModifiedDate IS NULL
          AND r.HighBusinessKey IS NULL
          AND r.CurrentExecutionID IS NULL
          AND r.LastSuccessfulExecutionID = @RetryExecutionID
    )
    BEGIN
        THROW 51315, 'Header did not finalize at the retained HIGH boundary.', 1;
    END;

    IF EXISTS
    (
        SELECT * FROM #OriginalWatermarks
        WHERE ProcessName = N'etl.LoadFactSalesIncremental.Detail'
        EXCEPT
        SELECT * FROM #RetriedWatermarks
        WHERE ProcessName = N'etl.LoadFactSalesIncremental.Detail'
    )
    OR EXISTS
    (
        SELECT * FROM #RetriedWatermarks
        WHERE ProcessName = N'etl.LoadFactSalesIncremental.Detail'
        EXCEPT
        SELECT * FROM #OriginalWatermarks
        WHERE ProcessName = N'etl.LoadFactSalesIncremental.Detail'
    )
    BEGIN
        THROW 51316, 'The retry changed the inactive Detail control.', 1;
    END;

    IF EXISTS
    (
        SELECT * FROM #OriginalFact
        EXCEPT
        SELECT * FROM dw.FactSales
    )
    OR EXISTS
    (
        SELECT * FROM dw.FactSales
        EXCEPT
        SELECT * FROM #OriginalFact
    )
    BEGIN
        THROW 51317, 'The retry did not restore the original fact contents.', 1;
    END;

    -- Process the deferred source changes
    EXEC etl.LoadFactSalesIncremental;

    SELECT @NextExecutionID = MAX(ExecutionID)
    FROM audit.ETLExecutionLog
    WHERE ProcessName = N'etl.LoadFactSalesIncremental'
      AND ExecutionID > @RetryExecutionID;

    IF
    (
        SELECT COUNT_BIG(*)
        FROM audit.ETLExecutionLog
        WHERE ProcessName = N'etl.LoadFactSalesIncremental'
          AND ExecutionID > @RetryExecutionID
    ) <> 1
    OR @@TRANCOUNT <> 0
    OR NOT EXISTS
    (
        SELECT 1
        FROM audit.ETLExecutionLog
        WHERE ExecutionID = @NextExecutionID
          AND ProcessName = N'etl.LoadFactSalesIncremental'
          AND [Status] = N'Succeeded'
          AND RowsRead = 3
          AND RowsInserted = 0
          AND RowsUpdated = 0
          AND RowsRejected = 0
          AND EndTime IS NOT NULL
          AND ErrorMessage IS NULL
    )
    BEGIN
        THROW 51410, 'Deferred changes did not produce the expected successful execution.', 1;
    END;

    IF (SELECT COUNT_BIG(*) FROM stg.SalesOrderLineDelta) <> 3
       OR EXISTS
       (
           SELECT * FROM #ExpectedNewCandidates
           EXCEPT
           SELECT SalesOrderID, SalesOrderDetailID
           FROM stg.SalesOrderLineDelta
       )
       OR EXISTS
       (
           SELECT SalesOrderID, SalesOrderDetailID
           FROM stg.SalesOrderLineDelta
           EXCEPT
           SELECT * FROM #ExpectedNewCandidates
       )
    BEGIN
        THROW 51411, 'The next execution did not extract exactly the deferred candidates.', 1;
    END;

    IF
    (
        SELECT COUNT(*)
        FROM audit.ETLWatermark AS w
        INNER JOIN
        (
            VALUES
            (N'etl.LoadFactSalesIncremental.Header',
             CONVERT(DATETIME2(7), @NewHeaderDate), CONVERT(BIGINT, 75122)),
            (N'etl.LoadFactSalesIncremental.Detail',
             CONVERT(DATETIME2(7), @NewDetailDate), CONVERT(BIGINT, 121310))
        ) AS e(ProcessName, ExpectedDate, ExpectedKey)
            ON e.ProcessName = w.ProcessName
        WHERE w.[Status] = 'Ready'
          AND w.LowModifiedDate = e.ExpectedDate
          AND w.LowBusinessKey = e.ExpectedKey
          AND w.HighModifiedDate IS NULL
          AND w.HighBusinessKey IS NULL
          AND w.CurrentExecutionID IS NULL
          AND w.LastSuccessfulExecutionID = @NextExecutionID
    ) <> 2
    BEGIN
        THROW 51412, 'Both streams did not finalize at the new source boundaries.', 1;
    END;

    IF EXISTS
    (
        SELECT * FROM #OriginalFact
        EXCEPT
        SELECT * FROM dw.FactSales
    )
    OR EXISTS
    (
        SELECT * FROM dw.FactSales
        EXCEPT
        SELECT * FROM #OriginalFact
    )
    BEGIN
        THROW 51413, 'Processing date-only source changes altered the fact contents.', 1;
    END;

END TRY
BEGIN CATCH

    SET @ValidationFailureMessage =
        LEFT
        (
            CONCAT
            (
                N'Validation error ', ERROR_NUMBER(),
                N'; Line: ', ERROR_LINE(),
                N'; Message: ', ERROR_MESSAGE()
            ),
            2048
        );

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

END CATCH;

-- Restore the original validation state
BEGIN TRY

    BEGIN TRANSACTION;

    IF OBJECT_ID
    (
        N'dw.CK_FactSales_IncrementalRetry_ForceFailure',
        N'C'
    ) IS NOT NULL
    BEGIN
        ALTER TABLE dw.FactSales
        DROP CONSTRAINT CK_FactSales_IncrementalRetry_ForceFailure;
    END;

    -- Restore source dates within the cleanup transaction
    EXEC AdventureWorks2022.sys.sp_executesql N'
        DISABLE TRIGGER Sales.uSalesOrderHeader ON Sales.SalesOrderHeader;
        DISABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;

        UPDATE h
        SET ModifiedDate = o.ModifiedDate
        FROM Sales.SalesOrderHeader AS h
        INNER JOIN #OriginalSourceHeader AS o
            ON o.SalesOrderID = h.SalesOrderID;

        IF @@ROWCOUNT <> 1
            THROW 51406, ''Cleanup could not restore the Header source date.'', 1;

        UPDATE d
        SET ModifiedDate = o.ModifiedDate
        FROM Sales.SalesOrderDetail AS d
        INNER JOIN #OriginalSourceDetail AS o
            ON o.SalesOrderID = d.SalesOrderID
           AND o.SalesOrderDetailID = d.SalesOrderDetailID;

        IF @@ROWCOUNT <> 1
            THROW 51407, ''Cleanup could not restore the Detail source date.'', 1;

        ENABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;
        ENABLE TRIGGER Sales.uSalesOrderHeader ON Sales.SalesOrderHeader;
    ';

    UPDATE f
    SET ShipDateKey = o.ShipDateKey
    FROM dw.FactSales AS f
    INNER JOIN #OriginalFact AS o
        ON o.SalesOrderID = f.SalesOrderID
       AND o.SalesOrderDetailID = f.SalesOrderDetailID
    WHERE f.SalesOrderID = 75123
      AND f.SalesOrderDetailID = 121317;

    IF @@ROWCOUNT <> 1
        THROW 51318, 'Cleanup could not restore the test fact line.', 1;

    UPDATE w
    SET
        LowModifiedDate = o.LowModifiedDate,
        LowBusinessKey = o.LowBusinessKey,
        HighModifiedDate = o.HighModifiedDate,
        HighBusinessKey = o.HighBusinessKey,
        [Status] = o.[Status],
        LastSuccessfulExecutionID = o.LastSuccessfulExecutionID,
        CurrentExecutionID = o.CurrentExecutionID,
        UpdatedAt = o.UpdatedAt
    FROM audit.ETLWatermark AS w
    INNER JOIN #OriginalWatermarks AS o
        ON o.WatermarkID = w.WatermarkID
       AND o.ProcessName = w.ProcessName;

    IF @@ROWCOUNT <> 2
        THROW 51319, 'Cleanup could not restore both watermark controls.', 1;

    TRUNCATE TABLE stg.SalesOrderLineDelta;

    INSERT INTO stg.SalesOrderLineDelta
    SELECT * FROM #OriginalDelta;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;

-- Verify complete restoration
SELECT *
INTO #RestoredWatermarks
FROM audit.ETLWatermark
WHERE ProcessName IN
(
    N'etl.LoadFactSalesIncremental.Header',
    N'etl.LoadFactSalesIncremental.Detail'
);

IF EXISTS
(
    SELECT * FROM #OriginalFact
    EXCEPT
    SELECT * FROM dw.FactSales
)
OR EXISTS
(
    SELECT * FROM dw.FactSales
    EXCEPT
    SELECT * FROM #OriginalFact
)
BEGIN
    THROW 51320, 'Cleanup verification failed for fact.', 1;
END;

IF EXISTS
(
    SELECT * FROM #OriginalDelta
    EXCEPT
    SELECT * FROM stg.SalesOrderLineDelta
)
OR EXISTS
(
    SELECT * FROM stg.SalesOrderLineDelta
    EXCEPT
    SELECT * FROM #OriginalDelta
)
BEGIN
    THROW 51320, 'Cleanup verification failed for delta staging.', 1;
END;

IF EXISTS
(
    SELECT * FROM #OriginalWatermarks
    EXCEPT
    SELECT * FROM #RestoredWatermarks
)
OR EXISTS
(
    SELECT * FROM #RestoredWatermarks
    EXCEPT
    SELECT * FROM #OriginalWatermarks
)
BEGIN
    THROW 51320, 'Cleanup verification failed for watermarks.', 1;
END;

IF @@TRANCOUNT <> 0
   OR OBJECT_ID
      (
          N'dw.CK_FactSales_IncrementalRetry_ForceFailure',
          N'C'
      ) IS NOT NULL
BEGIN
    THROW 51321, 'A transaction or validation constraint remains after cleanup.', 1;
END;

-- Verify restored source dates and enabled triggers
IF EXISTS
(
    SELECT * FROM #OriginalSourceHeader
    EXCEPT
    SELECT SalesOrderID, ModifiedDate
    FROM AdventureWorks2022.Sales.SalesOrderHeader
    WHERE SalesOrderID = 75122
)
OR EXISTS
(
    SELECT SalesOrderID, ModifiedDate
    FROM AdventureWorks2022.Sales.SalesOrderHeader
    WHERE SalesOrderID = 75122
    EXCEPT
    SELECT * FROM #OriginalSourceHeader
)
OR EXISTS
(
    SELECT * FROM #OriginalSourceDetail
    EXCEPT
    SELECT SalesOrderID, SalesOrderDetailID, ModifiedDate
    FROM AdventureWorks2022.Sales.SalesOrderDetail
    WHERE SalesOrderID = 75121 AND SalesOrderDetailID = 121310
)
OR EXISTS
(
    SELECT SalesOrderID, SalesOrderDetailID, ModifiedDate
    FROM AdventureWorks2022.Sales.SalesOrderDetail
    WHERE SalesOrderID = 75121 AND SalesOrderDetailID = 121310
    EXCEPT
    SELECT * FROM #OriginalSourceDetail
)
BEGIN
    THROW 51414, 'Cleanup did not restore the original source dates.', 1;
END;

EXEC AdventureWorks2022.sys.sp_executesql N'
    IF
    (
        SELECT COUNT(*)
        FROM sys.triggers
        WHERE is_disabled = 0
          AND is_instead_of_trigger = 0
          AND
          (
              (parent_id = OBJECT_ID(N''Sales.SalesOrderHeader'')
               AND name = N''uSalesOrderHeader'')
              OR
              (parent_id = OBJECT_ID(N''Sales.SalesOrderDetail'')
               AND name = N''iduSalesOrderDetail'')
          )
    ) <> 2
    BEGIN
        THROW 51415, ''Source triggers were not restored to enabled state.'', 1;
    END;
';

IF @ValidationFailureMessage IS NOT NULL
BEGIN
    THROW 51322, @ValidationFailureMessage, 1;
END;

SELECT
    @FailedExecutionID AS FailedExecutionID,
    @RetryExecutionID AS RetryExecutionID,
    @NextExecutionID AS NextExecutionID,
    @CaughtErrorNumber AS CaughtErrorNumber,
    (SELECT COUNT_BIG(*) FROM dw.FactSales) AS RestoredFactRows,
    (SELECT COUNT_BIG(*) FROM stg.SalesOrderLineDelta) AS RestoredDeltaRows,
    @TransactionCountAtCatch AS TransactionCountAtCatch,
    @@TRANCOUNT AS OpenTransactions;

PRINT 'PASS: Frozen HIGH retry, deferred source changes, next batch, and cleanup.';
GO
