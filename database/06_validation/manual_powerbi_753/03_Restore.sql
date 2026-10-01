/* M7 / 7.5.3 - MANUAL DEVELOPMENT TEST, not an automatic validation.
   Use the authorized administrative connection. Run each file in full.
   No other source/dimension writes or ETL between PREPARE and RESTORE.
   Persistent audit.PBI753_* tables survive connection loss.
   SQL audit records and consumed identity numbers are intentionally retained.
   Based on the repository's test 010; SQL Server execution is pending. */
USE AdventureWorks_EDW;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT <> 0 THROW 51700, 'Run without an outer transaction.', 1;
IF OBJECT_ID(N'audit.PBI753_Control',N'U') IS NULL
 OR OBJECT_ID(N'audit.PBI753_Fact',N'U') IS NULL
 OR OBJECT_ID(N'audit.PBI753_Delta',N'U') IS NULL
 OR OBJECT_ID(N'audit.PBI753_Watermarks',N'U') IS NULL
 OR OBJECT_ID(N'audit.PBI753_Header',N'U') IS NULL
 OR OBJECT_ID(N'audit.PBI753_Detail',N'U') IS NULL
 OR OBJECT_ID(N'audit.PBI753_Fixture',N'U') IS NULL
 OR OBJECT_ID(N'audit.PBI753_ExpectedFact',N'U') IS NULL
    THROW 51713, 'Incomplete or missing checkpoint. Run PREPARE once, or inspect recovery state.', 1;
IF (SELECT COUNT(*) FROM audit.PBI753_Control)<>1
 OR (SELECT COUNT(*) FROM audit.PBI753_Watermarks)<>2
 OR (SELECT COUNT(*) FROM audit.PBI753_Fixture)<>1
 OR (SELECT COUNT(*) FROM audit.PBI753_ExpectedFact)<>1
    THROW 51714, 'Checkpoint row counts are invalid.', 1;
DECLARE @NewID int, @SourceDate datetime, @Before bigint, @ExecutionID bigint;
SELECT @NewID=NewDetailID,@SourceDate=SourceDate,@Before=ParentBefore,
       @ExecutionID=ExecutionID FROM audit.PBI753_Control WHERE TestID=1;
IF @NewID IS NULL OR @NewID=121317
    THROW 51715, 'Invalid test identity.', 1;
DECLARE @LockResult int, @ReleaseResult int;
EXEC @LockResult = sys.sp_getapplock
    @Resource=N'etl.LoadFactSalesIncremental', @LockMode='Exclusive',
    @LockOwner='Session', @LockTimeout=0, @DbPrincipal='public';
IF @LockResult IS NULL OR @LockResult < 0
    THROW 51701, 'Another sales ETL owns the application lock.', 1;
BEGIN TRY
BEGIN TRANSACTION;
IF NOT EXISTS (SELECT 1 FROM audit.PBI753_Control
    WHERE Phase IN ('Prepared','Loading','Loaded','LoadFailed'))
    THROW 51722, 'Unexpected checkpoint phase.', 1;
IF EXISTS (SELECT * FROM AdventureWorks2022.Sales.SalesOrderHeader EXCEPT SELECT * FROM audit.PBI753_Header)
 OR EXISTS (SELECT * FROM audit.PBI753_Header EXCEPT SELECT * FROM AdventureWorks2022.Sales.SalesOrderHeader)
    THROW 51702, 'Source headers changed; inspect before proceeding.', 1;
IF EXISTS (SELECT * FROM AdventureWorks2022.Sales.SalesOrderDetail WHERE NOT (SalesOrderID=75123 AND SalesOrderDetailID=@NewID) EXCEPT SELECT * FROM audit.PBI753_Detail)
 OR EXISTS (SELECT * FROM audit.PBI753_Detail EXCEPT SELECT * FROM AdventureWorks2022.Sales.SalesOrderDetail WHERE NOT (SalesOrderID=75123 AND SalesOrderDetailID=@NewID))
    THROW 51702, 'Pre-existing source details changed; inspect before proceeding.', 1;
IF EXISTS (SELECT * FROM AdventureWorks2022.Sales.SalesOrderDetail WHERE SalesOrderID=75123 AND SalesOrderDetailID=@NewID EXCEPT SELECT * FROM audit.PBI753_Fixture)
 OR EXISTS (SELECT * FROM audit.PBI753_Fixture EXCEPT SELECT * FROM AdventureWorks2022.Sales.SalesOrderDetail WHERE SalesOrderID=75123 AND SalesOrderDetailID=@NewID)
    THROW 51702, 'The test source line is missing or changed.', 1;
IF EXISTS (SELECT * FROM dw.FactSales WHERE NOT (SalesOrderID=75123 AND SalesOrderDetailID=@NewID) EXCEPT SELECT * FROM audit.PBI753_Fact)
 OR EXISTS (SELECT * FROM audit.PBI753_Fact EXCEPT SELECT * FROM dw.FactSales WHERE NOT (SalesOrderID=75123 AND SalesOrderDetailID=@NewID))
    THROW 51702, 'Pre-existing fact rows changed; automatic restoration is refused.', 1;
EXEC AdventureWorks2022.sys.sp_executesql N'
IF (SELECT COUNT(*) FROM sys.triggers
    WHERE parent_id=OBJECT_ID(N''Sales.SalesOrderDetail'')) <> 1
 OR NOT EXISTS (SELECT 1 FROM sys.triggers
    WHERE parent_id=OBJECT_ID(N''Sales.SalesOrderDetail'')
      AND name=N''iduSalesOrderDetail'' AND is_disabled=0 AND is_instead_of_trigger=0)
    THROW 51703, ''Expected the sole standard Detail trigger, enabled.'', 1;';

-- If present, the only removable fact row must be exactly the expected fixture.
IF EXISTS (SELECT 1 FROM dw.FactSales WHERE SalesOrderID=75123 AND SalesOrderDetailID=@NewID)
BEGIN
IF EXISTS (SELECT * FROM dw.FactSales WHERE SalesOrderID=75123 AND SalesOrderDetailID=@NewID EXCEPT SELECT * FROM audit.PBI753_ExpectedFact)
 OR EXISTS (SELECT * FROM audit.PBI753_ExpectedFact EXCEPT SELECT * FROM dw.FactSales WHERE SalesOrderID=75123 AND SalesOrderDetailID=@NewID)
    THROW 51702, 'Test fact values changed; inspect instead of deleting automatically.', 1;
END;
IF (SELECT COUNT(*) FROM audit.ETLExecutionLog
    WHERE ProcessName=N'etl.LoadFactSalesIncremental' AND ExecutionID>@Before)>1
    THROW 51723, 'Multiple orchestrator attempts occurred; inspect before restoring watermarks.', 1;
SELECT @ExecutionID=MAX(ExecutionID) FROM audit.ETLExecutionLog
WHERE ProcessName=N'etl.LoadFactSalesIncremental' AND ExecutionID>@Before;
IF EXISTS (SELECT * FROM audit.ETLWatermark WHERE ProcessName=N'etl.LoadFactSalesIncremental.Header' EXCEPT SELECT * FROM audit.PBI753_Watermarks WHERE ProcessName=N'etl.LoadFactSalesIncremental.Header')
 OR EXISTS (SELECT * FROM audit.PBI753_Watermarks WHERE ProcessName=N'etl.LoadFactSalesIncremental.Header' EXCEPT SELECT * FROM audit.ETLWatermark WHERE ProcessName=N'etl.LoadFactSalesIncremental.Header')
    THROW 51702, 'Header watermark changed; automatic restoration refused.', 1;

-- Detail control must be original, finalized at our fixture, or owned by our failed/interrupted batch.
IF EXISTS (SELECT * FROM audit.ETLWatermark
           WHERE ProcessName=N'etl.LoadFactSalesIncremental.Detail'
           EXCEPT SELECT * FROM audit.PBI753_Watermarks
           WHERE ProcessName=N'etl.LoadFactSalesIncremental.Detail')
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM audit.ETLWatermark w
        JOIN audit.PBI753_Watermarks b ON b.WatermarkID=w.WatermarkID
          AND b.ProcessName=w.ProcessName AND b.SourceObject=w.SourceObject
        WHERE w.ProcessName=N'etl.LoadFactSalesIncremental.Detail'
          AND @ExecutionID IS NOT NULL
          AND (
            (w.[Status]='Ready' AND w.LowModifiedDate=CONVERT(datetime2(7),@SourceDate)
             AND w.LowBusinessKey=@NewID AND w.HighModifiedDate IS NULL
             AND w.HighBusinessKey IS NULL AND w.CurrentExecutionID IS NULL
             AND w.LastSuccessfulExecutionID=@ExecutionID)
            OR
            (w.[Status] IN ('Failed','InProgress') AND w.CurrentExecutionID=@ExecutionID
             AND w.HighModifiedDate=CONVERT(datetime2(7),@SourceDate)
             AND w.HighBusinessKey=@NewID AND w.LowModifiedDate=b.LowModifiedDate
             AND w.LowBusinessKey=b.LowBusinessKey
             AND NOT EXISTS (SELECT w.LastSuccessfulExecutionID EXCEPT SELECT b.LastSuccessfulExecutionID))
          ))
        THROW 51724, 'Detail watermark is not owned by this test. Inspect before restoration.', 1;
END;
IF EXISTS (SELECT * FROM stg.SalesOrderLineDelta EXCEPT SELECT * FROM audit.PBI753_Delta)
 OR EXISTS (SELECT * FROM audit.PBI753_Delta EXCEPT SELECT * FROM stg.SalesOrderLineDelta)
BEGIN
    IF EXISTS (SELECT 1 FROM stg.SalesOrderLineDelta
               WHERE SalesOrderID<>75123 OR SalesOrderDetailID<>@NewID)
     OR (SELECT COUNT_BIG(*) FROM stg.SalesOrderLineDelta)>1
        THROW 51725, 'Unexpected delta grains; automatic staging restoration refused.', 1;
END;
DELETE FROM dw.FactSales WHERE SalesOrderID=75123 AND SalesOrderDetailID=@NewID;
EXEC AdventureWorks2022.sys.sp_executesql N'
    DISABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;';
DELETE FROM AdventureWorks2022.Sales.SalesOrderDetail
WHERE SalesOrderID=75123 AND SalesOrderDetailID=@NewID;
IF @@ROWCOUNT<>1 THROW 51726, 'Cleanup expected exactly one source test row.', 1;
EXEC AdventureWorks2022.sys.sp_executesql N'
    ENABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;';
UPDATE w SET LowModifiedDate=b.LowModifiedDate,LowBusinessKey=b.LowBusinessKey,
    HighModifiedDate=b.HighModifiedDate,HighBusinessKey=b.HighBusinessKey,
    [Status]=b.[Status],LastSuccessfulExecutionID=b.LastSuccessfulExecutionID,
    CurrentExecutionID=b.CurrentExecutionID,UpdatedAt=b.UpdatedAt
FROM audit.ETLWatermark w
JOIN audit.PBI753_Watermarks b ON b.WatermarkID=w.WatermarkID AND b.ProcessName=w.ProcessName;
IF @@ROWCOUNT<>2 THROW 51727, 'Expected to restore exactly two watermark rows.', 1;
TRUNCATE TABLE stg.SalesOrderLineDelta;
INSERT INTO stg.SalesOrderLineDelta SELECT * FROM audit.PBI753_Delta;

-- Verify complete state BEFORE commit or dropping recovery tables.
IF EXISTS (SELECT * FROM AdventureWorks2022.Sales.SalesOrderHeader EXCEPT SELECT * FROM audit.PBI753_Header)
 OR EXISTS (SELECT * FROM audit.PBI753_Header EXCEPT SELECT * FROM AdventureWorks2022.Sales.SalesOrderHeader)
    THROW 51702, 'Source headers changed; inspect before proceeding.', 1;
IF EXISTS (SELECT * FROM AdventureWorks2022.Sales.SalesOrderDetail EXCEPT SELECT * FROM audit.PBI753_Detail)
 OR EXISTS (SELECT * FROM audit.PBI753_Detail EXCEPT SELECT * FROM AdventureWorks2022.Sales.SalesOrderDetail)
    THROW 51702, 'Source restoration verification failed.', 1;
IF EXISTS (SELECT * FROM dw.FactSales EXCEPT SELECT * FROM audit.PBI753_Fact)
 OR EXISTS (SELECT * FROM audit.PBI753_Fact EXCEPT SELECT * FROM dw.FactSales)
    THROW 51702, 'Fact restoration verification failed.', 1;
IF EXISTS (SELECT * FROM stg.SalesOrderLineDelta EXCEPT SELECT * FROM audit.PBI753_Delta)
 OR EXISTS (SELECT * FROM audit.PBI753_Delta EXCEPT SELECT * FROM stg.SalesOrderLineDelta)
    THROW 51702, 'Delta restoration verification failed.', 1;
IF EXISTS (SELECT * FROM audit.ETLWatermark WHERE ProcessName IN (N'etl.LoadFactSalesIncremental.Header', N'etl.LoadFactSalesIncremental.Detail') EXCEPT SELECT * FROM audit.PBI753_Watermarks)
 OR EXISTS (SELECT * FROM audit.PBI753_Watermarks EXCEPT SELECT * FROM audit.ETLWatermark WHERE ProcessName IN (N'etl.LoadFactSalesIncremental.Header', N'etl.LoadFactSalesIncremental.Detail'))
    THROW 51702, 'Watermark restoration verification failed.', 1;
EXEC AdventureWorks2022.sys.sp_executesql N'
IF (SELECT COUNT(*) FROM sys.triggers
    WHERE parent_id=OBJECT_ID(N''Sales.SalesOrderDetail'')) <> 1
 OR NOT EXISTS (SELECT 1 FROM sys.triggers
    WHERE parent_id=OBJECT_ID(N''Sales.SalesOrderDetail'')
      AND name=N''iduSalesOrderDetail'' AND is_disabled=0 AND is_instead_of_trigger=0)
    THROW 51703, ''Expected the sole standard Detail trigger, enabled.'', 1;';
DROP TABLE audit.PBI753_ExpectedFact;
DROP TABLE audit.PBI753_Fixture;
DROP TABLE audit.PBI753_Detail;
DROP TABLE audit.PBI753_Header;
DROP TABLE audit.PBI753_Watermarks;
DROP TABLE audit.PBI753_Delta;
DROP TABLE audit.PBI753_Fact;
DROP TABLE audit.PBI753_Control;
COMMIT TRANSACTION;
EXEC @ReleaseResult = sys.sp_releaseapplock
    @Resource=N'etl.LoadFactSalesIncremental', @LockOwner='Session',
    @DbPrincipal='public';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    EXEC @ReleaseResult = sys.sp_releaseapplock
    @Resource=N'etl.LoadFactSalesIncremental', @LockOwner='Session',
    @DbPrincipal='public';
    THROW;
END CATCH;

SELECT N'RESTORED: original data verified; now Refresh Power BI again.' AS Result,
       @NewID AS RemovedTestDetailID, @@TRANCOUNT AS OpenTransactions;
SELECT COUNT_BIG(*) AS SalesOrderLines,
       COUNT(DISTINCT SalesOrderID) AS SalesOrders,
       SUM(CONVERT(bigint,OrderQuantity)) AS UnitsSold,
       SUM(GrossAmount) AS GrossSales,
       SUM(DiscountAmount) AS DiscountAmount,
       SUM(NetSalesAmount) AS NetSales
FROM dw.FactSales;
