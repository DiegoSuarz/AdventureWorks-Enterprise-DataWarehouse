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
IF COALESCE(HAS_PERMS_BY_NAME(DB_NAME(),N'DATABASE',N'CREATE TABLE'),0)<>1
 OR COALESCE(HAS_PERMS_BY_NAME(N'audit',N'SCHEMA',N'CONTROL'),0)<>1
 OR COALESCE(HAS_PERMS_BY_NAME(N'dw.FactSales',N'OBJECT',N'DELETE'),0)<>1
 OR COALESCE(HAS_PERMS_BY_NAME(N'stg.SalesOrderLineDelta',N'OBJECT',N'ALTER'),0)<>1
 OR COALESCE(HAS_PERMS_BY_NAME(N'stg.SalesOrderLineDelta',N'OBJECT',N'INSERT'),0)<>1
 OR COALESCE(HAS_PERMS_BY_NAME(N'etl.LoadFactSalesIncremental',N'OBJECT',N'EXECUTE'),0)<>1
    THROW 51704, 'Use an authorized administrator of AdventureWorks_EDW.', 1;
EXEC AdventureWorks2022.sys.sp_executesql N'
IF COALESCE(HAS_PERMS_BY_NAME(N''Sales.SalesOrderDetail'',N''OBJECT'',N''ALTER''),0)<>1
 OR COALESCE(HAS_PERMS_BY_NAME(N''Sales.SalesOrderDetail'',N''OBJECT'',N''INSERT''),0)<>1
 OR COALESCE(HAS_PERMS_BY_NAME(N''Sales.SalesOrderDetail'',N''OBJECT'',N''DELETE''),0)<>1
    THROW 51705, ''Source ALTER, INSERT and DELETE permissions are required.'', 1;';
EXEC AdventureWorks2022.sys.sp_executesql N'
IF (SELECT COUNT(*) FROM sys.triggers
    WHERE parent_id=OBJECT_ID(N''Sales.SalesOrderDetail'')) <> 1
 OR NOT EXISTS (SELECT 1 FROM sys.triggers
    WHERE parent_id=OBJECT_ID(N''Sales.SalesOrderDetail'')
      AND name=N''iduSalesOrderDetail'' AND is_disabled=0 AND is_instead_of_trigger=0)
    THROW 51703, ''Expected the sole standard Detail trigger, enabled.'', 1;';
IF OBJECT_ID(N'audit.PBI753_Control') IS NOT NULL
 OR OBJECT_ID(N'audit.PBI753_Fact') IS NOT NULL
 OR OBJECT_ID(N'audit.PBI753_Delta') IS NOT NULL
 OR OBJECT_ID(N'audit.PBI753_Watermarks') IS NOT NULL
 OR OBJECT_ID(N'audit.PBI753_Header') IS NOT NULL
 OR OBJECT_ID(N'audit.PBI753_Detail') IS NOT NULL
 OR OBJECT_ID(N'audit.PBI753_Fixture') IS NOT NULL
 OR OBJECT_ID(N'audit.PBI753_ExpectedFact') IS NOT NULL
    THROW 51707, 'PBI753 checkpoint already exists. Inspect or run RESTORE; never overwrite it.', 1;
DECLARE @LockResult int, @ReleaseResult int;
EXEC @LockResult = sys.sp_getapplock
    @Resource=N'etl.LoadFactSalesIncremental', @LockMode='Exclusive',
    @LockOwner='Session', @LockTimeout=0, @DbPrincipal='public';
IF @LockResult IS NULL OR @LockResult < 0
    THROW 51701, 'Another sales ETL owns the application lock.', 1;
DECLARE @NewID int, @SourceDate datetime;
DECLARE @Inserted TABLE (ID int NOT NULL);
BEGIN TRY
    BEGIN TRANSACTION;
SELECT * INTO audit.PBI753_Fact FROM dw.FactSales;
SELECT * INTO audit.PBI753_Delta FROM stg.SalesOrderLineDelta;
SELECT * INTO audit.PBI753_Header FROM AdventureWorks2022.Sales.SalesOrderHeader;
SELECT * INTO audit.PBI753_Detail FROM AdventureWorks2022.Sales.SalesOrderDetail;
SELECT * INTO audit.PBI753_Watermarks FROM audit.ETLWatermark WHERE ProcessName IN (N'etl.LoadFactSalesIncremental.Header', N'etl.LoadFactSalesIncremental.Detail');
IF (SELECT COUNT(*) FROM audit.PBI753_Watermarks)<>2
 OR EXISTS (SELECT 1 FROM audit.PBI753_Watermarks
    WHERE [Status]<>'Ready' OR LowModifiedDate IS NULL OR LowBusinessKey IS NULL
       OR HighModifiedDate IS NOT NULL OR HighBusinessKey IS NOT NULL
       OR CurrentExecutionID IS NOT NULL)
    THROW 51708, 'Both watermark streams must be initialized and Ready.', 1;
IF NOT EXISTS (SELECT 1 FROM audit.PBI753_Detail
    WHERE SalesOrderID=75123 AND SalesOrderDetailID=121317
      AND ProductID=712 AND SpecialOfferID=1
      AND OrderQty=1 AND UnitPrice=8.99 AND UnitPriceDiscount=0)
 OR NOT EXISTS (SELECT 1 FROM audit.PBI753_Fact
    WHERE SalesOrderID=75123 AND SalesOrderDetailID=121317
      AND OrderQuantity=1 AND UnitPrice=8.99 AND DiscountRate=0
      AND GrossAmount=8.99 AND DiscountAmount=0 AND NetSalesAmount=8.99)
    THROW 51709, 'The expected reference source/fact line is missing or changed.', 1;
IF EXISTS (
    SELECT 1 FROM AdventureWorks2022.Sales.SalesOrderHeader h
    JOIN audit.PBI753_Watermarks w
      ON w.ProcessName=N'etl.LoadFactSalesIncremental.Header'
    WHERE CONVERT(datetime2(7),h.ModifiedDate)>w.LowModifiedDate
       OR (CONVERT(datetime2(7),h.ModifiedDate)=w.LowModifiedDate
           AND h.SalesOrderID>w.LowBusinessKey))
 OR EXISTS (
    SELECT 1 FROM AdventureWorks2022.Sales.SalesOrderDetail d
    JOIN audit.PBI753_Watermarks w
      ON w.ProcessName=N'etl.LoadFactSalesIncremental.Detail'
    WHERE CONVERT(datetime2(7),d.ModifiedDate)>w.LowModifiedDate
       OR (CONVERT(datetime2(7),d.ModifiedDate)=w.LowModifiedDate
           AND d.SalesOrderDetailID>w.LowBusinessKey))
    THROW 51706, 'Unprocessed source candidates exist; do not mix them with this test.', 1;

SELECT @SourceDate=DATEADD(second,1,CONVERT(datetime,LowModifiedDate))
FROM audit.PBI753_Watermarks
WHERE ProcessName=N'etl.LoadFactSalesIncremental.Detail';
IF @SourceDate IS NULL OR CONVERT(datetime2(7),@SourceDate)<=
    (SELECT LowModifiedDate FROM audit.PBI753_Watermarks
     WHERE ProcessName=N'etl.LoadFactSalesIncremental.Detail')
    THROW 51710, 'Cannot construct a source timestamp after LOW.', 1;

CREATE TABLE audit.PBI753_Control (
    TestID int NOT NULL PRIMARY KEY CHECK (TestID=1),
    Phase varchar(20) NOT NULL,
    NewDetailID int NOT NULL,
    SourceDate datetime NOT NULL,
    PreparedAtUTC datetime2(7) NOT NULL,
    ParentBefore bigint NOT NULL,
    ExecutionID bigint NULL
);
EXEC AdventureWorks2022.sys.sp_executesql N'
    DISABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;';
INSERT INTO AdventureWorks2022.Sales.SalesOrderDetail
    (SalesOrderID,CarrierTrackingNumber,OrderQty,ProductID,SpecialOfferID,
     UnitPrice,UnitPriceDiscount,ModifiedDate)
OUTPUT inserted.SalesOrderDetailID INTO @Inserted(ID)
SELECT SalesOrderID,CarrierTrackingNumber,OrderQty,ProductID,SpecialOfferID,
       UnitPrice,UnitPriceDiscount,@SourceDate
FROM audit.PBI753_Detail
WHERE SalesOrderID=75123 AND SalesOrderDetailID=121317;
IF @@ROWCOUNT<>1 THROW 51711, 'Expected exactly one new source detail.', 1;
SELECT @NewID=ID FROM @Inserted;
EXEC AdventureWorks2022.sys.sp_executesql N'
    ENABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;';
INSERT INTO audit.PBI753_Control
SELECT 1,'Prepared',@NewID,@SourceDate,SYSUTCDATETIME(),
       COALESCE(MAX(ExecutionID),0),NULL
FROM audit.ETLExecutionLog
WHERE ProcessName=N'etl.LoadFactSalesIncremental';
SELECT * INTO audit.PBI753_Fixture
FROM AdventureWorks2022.Sales.SalesOrderDetail
WHERE SalesOrderID=75123 AND SalesOrderDetailID=@NewID;
SELECT * INTO audit.PBI753_ExpectedFact FROM audit.PBI753_Fact
WHERE SalesOrderID=75123 AND SalesOrderDetailID=121317;
UPDATE audit.PBI753_ExpectedFact SET SalesOrderDetailID=@NewID;
IF EXISTS (SELECT 1 FROM dw.FactSales WHERE SalesOrderDetailID=@NewID)
    THROW 51712, 'New source identity already exists in fact.', 1;
IF EXISTS (SELECT * FROM AdventureWorks2022.Sales.SalesOrderHeader EXCEPT SELECT * FROM audit.PBI753_Header)
 OR EXISTS (SELECT * FROM audit.PBI753_Header EXCEPT SELECT * FROM AdventureWorks2022.Sales.SalesOrderHeader)
    THROW 51702, 'Source headers changed; inspect before proceeding.', 1;
IF EXISTS (SELECT * FROM AdventureWorks2022.Sales.SalesOrderDetail WHERE NOT (SalesOrderID=75123 AND SalesOrderDetailID=@NewID) EXCEPT SELECT * FROM audit.PBI753_Detail)
 OR EXISTS (SELECT * FROM audit.PBI753_Detail EXCEPT SELECT * FROM AdventureWorks2022.Sales.SalesOrderDetail WHERE NOT (SalesOrderID=75123 AND SalesOrderDetailID=@NewID))
    THROW 51702, 'Pre-existing source details changed; inspect before proceeding.', 1;
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

SELECT N'PREPARED: source inserted; ETL has NOT run.' AS Result;
SELECT NewDetailID,SourceDate,Phase FROM audit.PBI753_Control;
SELECT h.OrderDate, h.CustomerID, h.TerritoryID, d.ProductID,
       d.SalesOrderID, d.SalesOrderDetailID, d.OrderQty, d.LineTotal
FROM audit.PBI753_Fixture d
JOIN AdventureWorks2022.Sales.SalesOrderHeader h ON h.SalesOrderID=d.SalesOrderID;
SELECT N'Before' AS Stage,b.* FROM (SELECT COUNT_BIG(*) AS SalesOrderLines,
       COUNT(DISTINCT SalesOrderID) AS SalesOrders,
       SUM(CONVERT(bigint,OrderQuantity)) AS UnitsSold,
       SUM(GrossAmount) AS GrossSales,
       SUM(DiscountAmount) AS DiscountAmount,
       SUM(NetSalesAmount) AS NetSales
FROM audit.PBI753_Fact) b;
SELECT N'Expected after LOAD' AS Stage,b.* FROM (SELECT COUNT_BIG(*) AS SalesOrderLines,
       COUNT(DISTINCT SalesOrderID) AS SalesOrders,
       SUM(CONVERT(bigint,OrderQuantity)) AS UnitsSold,
       SUM(GrossAmount) AS GrossSales,
       SUM(DiscountAmount) AS DiscountAmount,
       SUM(NetSalesAmount) AS NetSales
FROM (SELECT * FROM audit.PBI753_Fact UNION ALL SELECT * FROM audit.PBI753_ExpectedFact) AS f) b;
