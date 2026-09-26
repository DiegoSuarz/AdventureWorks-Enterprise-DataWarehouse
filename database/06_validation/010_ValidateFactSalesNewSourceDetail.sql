/* Development validation: one genuinely new OLTP detail through the incremental ETL.
   Run once, without concurrent source writes or ETL and without an outer transaction.
   The test restores source, fact, delta staging, and both watermark controls.
   Audit entries and the consumed SQL Server identity value remain by design. */
USE AdventureWorks_EDW;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF @@TRANCOUNT <> 0 THROW 51500, 'An outer transaction is not allowed.', 1;

DECLARE @NewDetailID INT = NULL;
DECLARE @SourceDate DATETIME;
DECLARE @PreviousExecutionID BIGINT;
DECLARE @ExecutionID BIGINT;
DECLARE @Failure NVARCHAR(2048) = NULL;

SELECT * INTO #BeforeWatermarks
FROM audit.ETLWatermark
WHERE ProcessName IN (N'etl.LoadFactSalesIncremental.Header',
                      N'etl.LoadFactSalesIncremental.Detail');
SELECT * INTO #BeforeDelta FROM stg.SalesOrderLineDelta;
SELECT * INTO #BeforeFact FROM dw.FactSales;
CREATE TABLE #NewID (SalesOrderDetailID INT NOT NULL);

IF (SELECT COUNT(*) FROM #BeforeWatermarks) <> 2
    THROW 51501, 'The two watermark controls are required.', 1;
IF EXISTS (SELECT 1 FROM #BeforeWatermarks
           WHERE [Status] <> 'Ready' OR LowModifiedDate IS NULL
              OR LowBusinessKey IS NULL OR HighModifiedDate IS NOT NULL
              OR HighBusinessKey IS NOT NULL OR CurrentExecutionID IS NOT NULL)
    THROW 51502, 'Both watermarks must be initialized and Ready.', 1;
IF NOT EXISTS (SELECT 1 FROM AdventureWorks2022.Sales.SalesOrderDetail
               WHERE SalesOrderID = 75123 AND SalesOrderDetailID = 121317)
    THROW 51503, 'The reference source line is missing.', 1;
IF EXISTS (
    SELECT 1 FROM AdventureWorks2022.Sales.SalesOrderHeader h
    CROSS JOIN #BeforeWatermarks w
    WHERE w.ProcessName = N'etl.LoadFactSalesIncremental.Header'
      AND (CONVERT(DATETIME2(7),h.ModifiedDate) > w.LowModifiedDate
        OR (CONVERT(DATETIME2(7),h.ModifiedDate) = w.LowModifiedDate
            AND h.SalesOrderID > w.LowBusinessKey)))
 OR EXISTS (
    SELECT 1 FROM AdventureWorks2022.Sales.SalesOrderDetail d
    CROSS JOIN #BeforeWatermarks w
    WHERE w.ProcessName = N'etl.LoadFactSalesIncremental.Detail'
      AND (CONVERT(DATETIME2(7),d.ModifiedDate) > w.LowModifiedDate
        OR (CONVERT(DATETIME2(7),d.ModifiedDate) = w.LowModifiedDate
            AND d.SalesOrderDetailID > w.LowBusinessKey)))
    THROW 51504, 'There are pre-existing source candidates; run later.', 1;

SELECT @SourceDate = DATEADD(SECOND, 1, CONVERT(DATETIME,LowModifiedDate))
FROM #BeforeWatermarks
WHERE ProcessName = N'etl.LoadFactSalesIncremental.Detail';
IF @SourceDate IS NULL OR CONVERT(DATETIME2(7),@SourceDate) <=
   (SELECT LowModifiedDate FROM #BeforeWatermarks
    WHERE ProcessName = N'etl.LoadFactSalesIncremental.Detail')
    THROW 51505, 'Cannot construct a later source timestamp.', 1;

SELECT @PreviousExecutionID = COALESCE(MAX(ExecutionID),0)
FROM audit.ETLExecutionLog
WHERE ProcessName = N'etl.LoadFactSalesIncremental';

EXEC AdventureWorks2022.sys.sp_executesql N'
IF COALESCE(HAS_PERMS_BY_NAME(N''Sales.SalesOrderDetail'', N''OBJECT'', N''ALTER''),0) <> 1
 OR COALESCE(HAS_PERMS_BY_NAME(N''Sales.SalesOrderDetail'', N''OBJECT'', N''INSERT''),0) <> 1
 OR COALESCE(HAS_PERMS_BY_NAME(N''Sales.SalesOrderDetail'', N''OBJECT'', N''DELETE''),0) <> 1
 THROW 51506, ''Source ALTER, INSERT, and DELETE permissions are required.'', 1;
IF (SELECT COUNT(*) FROM sys.triggers WHERE parent_id = OBJECT_ID(N''Sales.SalesOrderDetail'')) <> 1
 OR NOT EXISTS (SELECT 1 FROM sys.triggers
                WHERE parent_id = OBJECT_ID(N''Sales.SalesOrderDetail'')
                  AND name = N''iduSalesOrderDetail'' AND is_disabled = 0)
 THROW 51507, ''The expected Detail trigger must be the only enabled trigger.'', 1;';

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC AdventureWorks2022.sys.sp_executesql N'
        DISABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;';
    INSERT INTO AdventureWorks2022.Sales.SalesOrderDetail
        (SalesOrderID, CarrierTrackingNumber, OrderQty, ProductID,
         SpecialOfferID, UnitPrice, UnitPriceDiscount, ModifiedDate)
    OUTPUT inserted.SalesOrderDetailID INTO #NewID
    SELECT SalesOrderID, CarrierTrackingNumber, OrderQty, ProductID,
           SpecialOfferID, UnitPrice, UnitPriceDiscount, @SourceDate
    FROM AdventureWorks2022.Sales.SalesOrderDetail
    WHERE SalesOrderID = 75123 AND SalesOrderDetailID = 121317;
    IF @@ROWCOUNT <> 1 THROW 51508, 'The new source detail was not inserted.', 1;
    SELECT @NewDetailID = SalesOrderDetailID FROM #NewID;
    EXEC AdventureWorks2022.sys.sp_executesql N'
        ENABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;';
    COMMIT TRANSACTION;

    IF @NewDetailID IS NULL
      OR EXISTS (SELECT 1 FROM dw.FactSales WHERE SalesOrderDetailID = @NewDetailID)
        THROW 51509, 'The new source key is unavailable or already exists in fact.', 1;

    EXEC etl.LoadFactSalesIncremental;
    SELECT @ExecutionID = MAX(ExecutionID)
    FROM audit.ETLExecutionLog
    WHERE ProcessName = N'etl.LoadFactSalesIncremental'
      AND ExecutionID > @PreviousExecutionID;
    IF (SELECT COUNT(*) FROM audit.ETLExecutionLog
        WHERE ProcessName = N'etl.LoadFactSalesIncremental'
          AND ExecutionID > @PreviousExecutionID) <> 1
      OR NOT EXISTS (
        SELECT 1 FROM audit.ETLExecutionLog
        WHERE ExecutionID = @ExecutionID AND [Status] = N'Succeeded'
          AND RowsRead = 1 AND RowsInserted = 1 AND RowsUpdated = 0
          AND RowsRejected = 0 AND ErrorMessage IS NULL)
        THROW 51510, 'The parent audit did not report one inserted line.', 1;
    IF (SELECT COUNT(*) FROM dw.FactSales WHERE SalesOrderID = 75123
        AND SalesOrderDetailID = @NewDetailID) <> 1
      OR (SELECT COUNT(*) FROM stg.SalesOrderLineDelta
          WHERE SalesOrderID = 75123 AND SalesOrderDetailID = @NewDetailID) <> 1
      OR (SELECT COUNT(*) FROM stg.SalesOrderLineDelta) <> 1
        THROW 51511, 'The source line did not reach both delta and fact.', 1;
    IF EXISTS (SELECT * FROM #BeforeFact EXCEPT SELECT * FROM dw.FactSales
                WHERE SalesOrderDetailID <> @NewDetailID)
      OR EXISTS (SELECT * FROM dw.FactSales WHERE SalesOrderDetailID <> @NewDetailID
                 EXCEPT SELECT * FROM #BeforeFact)
        THROW 51512, 'The ETL changed pre-existing fact rows.', 1;
    IF EXISTS (
        SELECT * FROM #BeforeWatermarks
        WHERE ProcessName = N'etl.LoadFactSalesIncremental.Header'
        EXCEPT SELECT * FROM audit.ETLWatermark
        WHERE ProcessName = N'etl.LoadFactSalesIncremental.Header')
      OR EXISTS (
        SELECT * FROM audit.ETLWatermark
        WHERE ProcessName = N'etl.LoadFactSalesIncremental.Header'
        EXCEPT SELECT * FROM #BeforeWatermarks
        WHERE ProcessName = N'etl.LoadFactSalesIncremental.Header')
        THROW 51513, 'The inactive Header watermark changed.', 1;
    IF NOT EXISTS (
        SELECT 1 FROM audit.ETLWatermark
        WHERE ProcessName = N'etl.LoadFactSalesIncremental.Detail'
          AND [Status] = N'Ready' AND LowModifiedDate = CONVERT(DATETIME2(7),@SourceDate)
          AND LowBusinessKey = @NewDetailID AND HighModifiedDate IS NULL
          AND HighBusinessKey IS NULL AND CurrentExecutionID IS NULL
          AND LastSuccessfulExecutionID = @ExecutionID)
        THROW 51514, 'The Detail watermark did not advance to the new line.', 1;
END TRY
BEGIN CATCH
    SET @Failure = LEFT(CONCAT(N'Error ',ERROR_NUMBER(),N' at line ',ERROR_LINE(),
                               N': ',ERROR_MESSAGE()),2048);
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
END CATCH;

-- Always attempt restoration after the ETL run or any handled error.
BEGIN TRY
    BEGIN TRANSACTION;
    IF @NewDetailID IS NOT NULL
    BEGIN
        DELETE FROM dw.FactSales
        WHERE SalesOrderID = 75123 AND SalesOrderDetailID = @NewDetailID;
        EXEC AdventureWorks2022.sys.sp_executesql N'
            DISABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;';
        DELETE FROM AdventureWorks2022.Sales.SalesOrderDetail
        WHERE SalesOrderID = 75123 AND SalesOrderDetailID = @NewDetailID;
        EXEC AdventureWorks2022.sys.sp_executesql N'
            ENABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;';
    END;
    UPDATE w SET LowModifiedDate = b.LowModifiedDate,
                 LowBusinessKey = b.LowBusinessKey,
                 HighModifiedDate = b.HighModifiedDate,
                 HighBusinessKey = b.HighBusinessKey,
                 [Status] = b.[Status],
                 LastSuccessfulExecutionID = b.LastSuccessfulExecutionID,
                 CurrentExecutionID = b.CurrentExecutionID,
                 UpdatedAt = b.UpdatedAt
    FROM audit.ETLWatermark w
    JOIN #BeforeWatermarks b ON b.WatermarkID = w.WatermarkID
                            AND b.ProcessName = w.ProcessName;
    IF @@ROWCOUNT <> 2 THROW 51515, 'Both watermark controls must be restored.', 1;
    TRUNCATE TABLE stg.SalesOrderLineDelta;
    INSERT INTO stg.SalesOrderLineDelta SELECT * FROM #BeforeDelta;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

IF EXISTS (SELECT * FROM #BeforeFact EXCEPT SELECT * FROM dw.FactSales)
 OR EXISTS (SELECT * FROM dw.FactSales EXCEPT SELECT * FROM #BeforeFact)
 OR EXISTS (SELECT * FROM #BeforeDelta EXCEPT SELECT * FROM stg.SalesOrderLineDelta)
 OR EXISTS (SELECT * FROM stg.SalesOrderLineDelta EXCEPT SELECT * FROM #BeforeDelta)
 OR EXISTS (SELECT * FROM #BeforeWatermarks EXCEPT SELECT * FROM audit.ETLWatermark
            WHERE ProcessName IN (N'etl.LoadFactSalesIncremental.Header',N'etl.LoadFactSalesIncremental.Detail'))
 OR EXISTS (SELECT * FROM audit.ETLWatermark
            WHERE ProcessName IN (N'etl.LoadFactSalesIncremental.Header',N'etl.LoadFactSalesIncremental.Detail')
            EXCEPT SELECT * FROM #BeforeWatermarks)
 OR EXISTS (SELECT 1 FROM AdventureWorks2022.Sales.SalesOrderDetail
            WHERE SalesOrderID = 75123 AND SalesOrderDetailID = @NewDetailID)
 OR EXISTS (SELECT 1 FROM AdventureWorks2022.sys.triggers
            WHERE name = N'iduSalesOrderDetail' AND is_disabled = 1)
 OR @@TRANCOUNT <> 0
    THROW 51516, 'Restoration verification failed; inspect the development databases.', 1;

IF @Failure IS NOT NULL THROW 51517, @Failure, 1;
SELECT @ExecutionID AS ExecutionID, @NewDetailID AS TestedDetailID,
       N'Succeeded and restored' AS Result;
