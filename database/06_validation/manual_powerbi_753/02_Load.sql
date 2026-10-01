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
IF NOT EXISTS (SELECT 1 FROM audit.PBI753_Control WHERE Phase='Prepared')
    THROW 51716, 'LOAD is only allowed once from Prepared. Use RESTORE after a failed attempt.', 1;
IF EXISTS (SELECT 1 FROM audit.ETLExecutionLog
    WHERE ProcessName=N'etl.LoadFactSalesIncremental' AND ExecutionID>@Before)
    THROW 51717, 'Another orchestrator execution occurred after PREPARE. Inspect before continuing.', 1;
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
IF EXISTS (SELECT * FROM audit.ETLWatermark WHERE ProcessName IN (N'etl.LoadFactSalesIncremental.Header', N'etl.LoadFactSalesIncremental.Detail') EXCEPT SELECT * FROM audit.PBI753_Watermarks)
 OR EXISTS (SELECT * FROM audit.PBI753_Watermarks EXCEPT SELECT * FROM audit.ETLWatermark WHERE ProcessName IN (N'etl.LoadFactSalesIncremental.Header', N'etl.LoadFactSalesIncremental.Detail'))
    THROW 51702, 'Watermarks changed since PREPARE.', 1;
IF EXISTS (SELECT * FROM stg.SalesOrderLineDelta EXCEPT SELECT * FROM audit.PBI753_Delta)
 OR EXISTS (SELECT * FROM audit.PBI753_Delta EXCEPT SELECT * FROM stg.SalesOrderLineDelta)
    THROW 51702, 'Delta staging changed since PREPARE.', 1;
EXEC AdventureWorks2022.sys.sp_executesql N'
IF (SELECT COUNT(*) FROM sys.triggers
    WHERE parent_id=OBJECT_ID(N''Sales.SalesOrderDetail'')) <> 1
 OR NOT EXISTS (SELECT 1 FROM sys.triggers
    WHERE parent_id=OBJECT_ID(N''Sales.SalesOrderDetail'')
      AND name=N''iduSalesOrderDetail'' AND is_disabled=0 AND is_instead_of_trigger=0)
    THROW 51703, ''Expected the sole standard Detail trigger, enabled.'', 1;';

IF EXISTS (SELECT 1 FROM dw.FactSales WHERE SalesOrderID=75123 AND SalesOrderDetailID=@NewID)
    THROW 51718, 'Test line is already in fact; do not repeat LOAD.', 1;
UPDATE audit.PBI753_Control SET Phase='Loading' WHERE TestID=1;
EXEC etl.LoadFactSalesIncremental;
SELECT @ExecutionID=MAX(ExecutionID) FROM audit.ETLExecutionLog
WHERE ProcessName=N'etl.LoadFactSalesIncremental' AND ExecutionID>@Before;
UPDATE audit.PBI753_Control SET ExecutionID=@ExecutionID WHERE TestID=1;
IF (SELECT COUNT(*) FROM audit.ETLExecutionLog
    WHERE ProcessName=N'etl.LoadFactSalesIncremental' AND ExecutionID>@Before)<>1
 OR NOT EXISTS (SELECT 1 FROM audit.ETLExecutionLog
    WHERE ExecutionID=@ExecutionID AND [Status]='Succeeded'
      AND RowsRead=1 AND RowsInserted=1 AND RowsUpdated=0 AND RowsRejected=0
      AND ErrorMessage IS NULL)
    THROW 51719, 'Expected one successful parent execution with exactly one insert.', 1;
IF EXISTS (SELECT * FROM dw.FactSales WHERE NOT (SalesOrderID=75123 AND SalesOrderDetailID=@NewID) EXCEPT SELECT * FROM audit.PBI753_Fact)
 OR EXISTS (SELECT * FROM audit.PBI753_Fact EXCEPT SELECT * FROM dw.FactSales WHERE NOT (SalesOrderID=75123 AND SalesOrderDetailID=@NewID))
    THROW 51702, 'Pre-existing fact rows changed; automatic restoration is refused.', 1;
IF EXISTS (SELECT * FROM AdventureWorks2022.Sales.SalesOrderHeader EXCEPT SELECT * FROM audit.PBI753_Header)
 OR EXISTS (SELECT * FROM audit.PBI753_Header EXCEPT SELECT * FROM AdventureWorks2022.Sales.SalesOrderHeader)
    THROW 51702, 'Source headers changed; inspect before proceeding.', 1;
IF EXISTS (SELECT * FROM AdventureWorks2022.Sales.SalesOrderDetail WHERE NOT (SalesOrderID=75123 AND SalesOrderDetailID=@NewID) EXCEPT SELECT * FROM audit.PBI753_Detail)
 OR EXISTS (SELECT * FROM audit.PBI753_Detail EXCEPT SELECT * FROM AdventureWorks2022.Sales.SalesOrderDetail WHERE NOT (SalesOrderID=75123 AND SalesOrderDetailID=@NewID))
    THROW 51702, 'Pre-existing source details changed; inspect before proceeding.', 1;
IF EXISTS (SELECT * FROM AdventureWorks2022.Sales.SalesOrderDetail WHERE SalesOrderID=75123 AND SalesOrderDetailID=@NewID EXCEPT SELECT * FROM audit.PBI753_Fixture)
 OR EXISTS (SELECT * FROM audit.PBI753_Fixture EXCEPT SELECT * FROM AdventureWorks2022.Sales.SalesOrderDetail WHERE SalesOrderID=75123 AND SalesOrderDetailID=@NewID)
    THROW 51702, 'The test source line is missing or changed.', 1;
IF EXISTS (SELECT * FROM dw.FactSales WHERE SalesOrderID=75123 AND SalesOrderDetailID=@NewID EXCEPT SELECT * FROM audit.PBI753_ExpectedFact)
 OR EXISTS (SELECT * FROM audit.PBI753_ExpectedFact EXCEPT SELECT * FROM dw.FactSales WHERE SalesOrderID=75123 AND SalesOrderDetailID=@NewID)
    THROW 51702, 'Loaded fact projection differs from the expected test line.', 1;

IF (SELECT COUNT(*) FROM stg.SalesOrderLineDelta)<>1
 OR NOT EXISTS (SELECT 1 FROM stg.SalesOrderLineDelta
    WHERE SalesOrderID=75123 AND SalesOrderDetailID=@NewID)
    THROW 51720, 'Expected exactly the test grain in delta staging.', 1;
IF EXISTS (SELECT * FROM audit.ETLWatermark WHERE ProcessName=N'etl.LoadFactSalesIncremental.Header' EXCEPT SELECT * FROM audit.PBI753_Watermarks WHERE ProcessName=N'etl.LoadFactSalesIncremental.Header')
 OR EXISTS (SELECT * FROM audit.PBI753_Watermarks WHERE ProcessName=N'etl.LoadFactSalesIncremental.Header' EXCEPT SELECT * FROM audit.ETLWatermark WHERE ProcessName=N'etl.LoadFactSalesIncremental.Header')
    THROW 51702, 'Inactive Header watermark changed.', 1;

IF NOT EXISTS (SELECT 1 FROM audit.ETLWatermark
    WHERE ProcessName=N'etl.LoadFactSalesIncremental.Detail'
      AND [Status]='Ready' AND LowModifiedDate=CONVERT(datetime2(7),@SourceDate)
      AND LowBusinessKey=@NewID AND HighModifiedDate IS NULL AND HighBusinessKey IS NULL
      AND CurrentExecutionID IS NULL AND LastSuccessfulExecutionID=@ExecutionID)
    THROW 51721, 'Detail watermark did not finalize at the test line.', 1;
EXEC AdventureWorks2022.sys.sp_executesql N'
IF (SELECT COUNT(*) FROM sys.triggers
    WHERE parent_id=OBJECT_ID(N''Sales.SalesOrderDetail'')) <> 1
 OR NOT EXISTS (SELECT 1 FROM sys.triggers
    WHERE parent_id=OBJECT_ID(N''Sales.SalesOrderDetail'')
      AND name=N''iduSalesOrderDetail'' AND is_disabled=0 AND is_instead_of_trigger=0)
    THROW 51703, ''Expected the sole standard Detail trigger, enabled.'', 1;';
UPDATE audit.PBI753_Control SET Phase='Loaded' WHERE TestID=1;
EXEC @ReleaseResult = sys.sp_releaseapplock
    @Resource=N'etl.LoadFactSalesIncremental', @LockOwner='Session',
    @DbPrincipal='public';
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    UPDATE audit.PBI753_Control SET Phase='LoadFailed'
    WHERE TestID=1 AND Phase='Loading';
    EXEC @ReleaseResult = sys.sp_releaseapplock
    @Resource=N'etl.LoadFactSalesIncremental', @LockOwner='Session',
    @DbPrincipal='public';
    THROW;
END CATCH;
SELECT N'LOADED: compare Power BI BEFORE Refresh, then AFTER Refresh.' AS Result;
SELECT ExecutionID,[Status],RowsRead,RowsInserted,RowsUpdated,RowsRejected,ErrorMessage
FROM audit.ETLExecutionLog WHERE ExecutionID=@ExecutionID;
SELECT COUNT_BIG(*) AS SalesOrderLines,
       COUNT(DISTINCT SalesOrderID) AS SalesOrders,
       SUM(CONVERT(bigint,OrderQuantity)) AS UnitsSold,
       SUM(GrossAmount) AS GrossSales,
       SUM(DiscountAmount) AS DiscountAmount,
       SUM(NetSalesAmount) AS NetSales
FROM dw.FactSales;
SELECT * FROM dw.FactSales WHERE SalesOrderID=75123 AND SalesOrderDetailID=@NewID;
