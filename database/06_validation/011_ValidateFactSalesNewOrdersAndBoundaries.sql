/*
M6 / 6.10 - New orders, fractional composite boundaries, and dual-stream recovery.
Development only. Run the ENTIRE file in a fresh administrative query session.
No concurrent source writes, dimension changes, or ETL. No outer transaction.
Source business triggers are disabled only inside preparation/cleanup transactions.
Audit entries and consumed Header/Detail identity values remain intentionally.
If interrupted, inspect source fixtures, triggers, watermark constraint and ETL state.
This script has been statically reviewed; execution against your SQL Server is pending.
*/
USE AdventureWorks_EDW;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT <> 0 THROW 51600, 'Run without an outer transaction.', 1;
IF OBJECT_ID(N'audit.CK_ETLWatermark_011_Finalization',N'C') IS NOT NULL
    THROW 51601, 'The validation constraint already exists. Inspect before proceeding.', 1;

DECLARE @Failure NVARCHAR(2048), @CaughtError INT, @CaughtMessage NVARCHAR(4000);
DECLARE @PreviousID BIGINT, @FailedID BIGINT, @RetryID BIGINT;
DECLARE @Base DATETIME, @SourceDate DATETIME, @Seq INT = 1;
DECLARE @OrderID INT, @DetailID INT, @LowDate DATETIME2(7), @HighDate DATETIME2(7);
DECLARE @LowKey INT, @HighKey INT;
DECLARE @OwnConstraint BIT = 0;

SELECT * INTO #OriginalWatermarks FROM audit.ETLWatermark
WHERE ProcessName IN (N'etl.LoadFactSalesIncremental.Header',N'etl.LoadFactSalesIncremental.Detail');
SELECT * INTO #OriginalFact FROM dw.FactSales;
SELECT * INTO #OriginalDelta FROM stg.SalesOrderLineDelta;
SELECT * INTO #OriginalHeader FROM AdventureWorks2022.Sales.SalesOrderHeader;
SELECT * INTO #OriginalDetail FROM AdventureWorks2022.Sales.SalesOrderDetail;
CREATE TABLE #Fixtures (
    Seq INT PRIMARY KEY, SalesOrderID INT NOT NULL,
    SalesOrderDetailID INT NOT NULL, ModifiedDate DATETIME2(7) NOT NULL);
CREATE TABLE #HeaderOutput (ID INT NOT NULL);
CREATE TABLE #DetailOutput (ID INT NOT NULL);
SELECT TOP (0) * INTO #ExpectedFact FROM #OriginalFact;

IF (SELECT COUNT(*) FROM #OriginalWatermarks) <> 2
 OR EXISTS (SELECT 1 FROM #OriginalWatermarks
            WHERE [Status] <> 'Ready' OR LowModifiedDate IS NULL OR LowBusinessKey IS NULL
               OR HighModifiedDate IS NOT NULL OR HighBusinessKey IS NOT NULL OR CurrentExecutionID IS NOT NULL)
    THROW 51602, 'Both controls must be initialized, Ready, and free of pending batches.', 1;
IF (SELECT COUNT(*) FROM #OriginalHeader WHERE SalesOrderID=75123) <> 1
 OR (SELECT COUNT(*) FROM #OriginalDetail WHERE SalesOrderID=75123 AND SalesOrderDetailID=121317) <> 1
 OR (SELECT COUNT(*) FROM #OriginalFact WHERE SalesOrderID=75123 AND SalesOrderDetailID=121317) <> 1
    THROW 51603, 'Source and fact reference fixtures are missing.', 1;
IF EXISTS (
    SELECT 1 FROM #OriginalHeader h CROSS JOIN #OriginalWatermarks w
    WHERE w.ProcessName=N'etl.LoadFactSalesIncremental.Header'
      AND (CONVERT(DATETIME2(7),h.ModifiedDate)>w.LowModifiedDate
        OR (CONVERT(DATETIME2(7),h.ModifiedDate)=w.LowModifiedDate AND h.SalesOrderID>w.LowBusinessKey)))
 OR EXISTS (
    SELECT 1 FROM #OriginalDetail d CROSS JOIN #OriginalWatermarks w
    WHERE w.ProcessName=N'etl.LoadFactSalesIncremental.Detail'
      AND (CONVERT(DATETIME2(7),d.ModifiedDate)>w.LowModifiedDate
        OR (CONVERT(DATETIME2(7),d.ModifiedDate)=w.LowModifiedDate AND d.SalesOrderDetailID>w.LowBusinessKey)))
    THROW 51604, 'Unprocessed source changes exist. Do not mix them with the test.', 1;
SELECT @Base=DATEADD(DAY,1,CONVERT(DATETIME,CONVERT(DATE,MAX(LowModifiedDate)))) FROM #OriginalWatermarks;

EXEC AdventureWorks2022.sys.sp_executesql N'
IF COALESCE(HAS_PERMS_BY_NAME(N''Sales.SalesOrderHeader'',N''OBJECT'',N''ALTER''),0)<>1
 OR COALESCE(HAS_PERMS_BY_NAME(N''Sales.SalesOrderHeader'',N''OBJECT'',N''INSERT''),0)<>1
 OR COALESCE(HAS_PERMS_BY_NAME(N''Sales.SalesOrderHeader'',N''OBJECT'',N''DELETE''),0)<>1
 OR COALESCE(HAS_PERMS_BY_NAME(N''Sales.SalesOrderDetail'',N''OBJECT'',N''ALTER''),0)<>1
 OR COALESCE(HAS_PERMS_BY_NAME(N''Sales.SalesOrderDetail'',N''OBJECT'',N''INSERT''),0)<>1
 OR COALESCE(HAS_PERMS_BY_NAME(N''Sales.SalesOrderDetail'',N''OBJECT'',N''DELETE''),0)<>1
    THROW 51605, ''Source ALTER, INSERT and DELETE permissions are required.'',1;
IF (SELECT COUNT(*) FROM sys.triggers
    WHERE parent_id IN (OBJECT_ID(N''Sales.SalesOrderHeader''),OBJECT_ID(N''Sales.SalesOrderDetail'')))<>2
 OR NOT EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id=OBJECT_ID(N''Sales.SalesOrderHeader'')
                AND name=N''uSalesOrderHeader'' AND is_disabled=0 AND is_instead_of_trigger=0)
 OR NOT EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id=OBJECT_ID(N''Sales.SalesOrderDetail'')
                AND name=N''iduSalesOrderDetail'' AND is_disabled=0 AND is_instead_of_trigger=0)
    THROW 51606, ''Expected exactly the two standard enabled source triggers.'',1;';

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC AdventureWorks2022.sys.sp_executesql N'
        DISABLE TRIGGER Sales.uSalesOrderHeader ON Sales.SalesOrderHeader;
        DISABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;';
    WHILE @Seq<=3
    BEGIN
        SET @SourceDate=DATEADD(MILLISECOND,CASE @Seq WHEN 1 THEN 3 WHEN 2 THEN 7 ELSE 10 END,@Base);
        DELETE FROM #HeaderOutput;
        DELETE FROM #DetailOutput;
        INSERT INTO AdventureWorks2022.Sales.SalesOrderHeader
            (RevisionNumber,OrderDate,DueDate,ShipDate,[Status],OnlineOrderFlag,
             PurchaseOrderNumber,AccountNumber,CustomerID,SalesPersonID,TerritoryID,
             BillToAddressID,ShipToAddressID,ShipMethodID,CreditCardID,CreditCardApprovalCode,
             CurrencyRateID,SubTotal,TaxAmt,Freight,Comment,ModifiedDate)
        OUTPUT inserted.SalesOrderID INTO #HeaderOutput
        SELECT h.RevisionNumber,h.OrderDate,h.DueDate,h.ShipDate,h.[Status],h.OnlineOrderFlag,
               h.PurchaseOrderNumber,h.AccountNumber,h.CustomerID,h.SalesPersonID,h.TerritoryID,
               h.BillToAddressID,h.ShipToAddressID,h.ShipMethodID,h.CreditCardID,h.CreditCardApprovalCode,
               h.CurrencyRateID,CONVERT(MONEY,d.LineTotal),h.TaxAmt,h.Freight,
               N'M6 test 011 - temporary new order',@SourceDate
        FROM #OriginalHeader h JOIN #OriginalDetail d ON d.SalesOrderID=h.SalesOrderID
        WHERE h.SalesOrderID=75123 AND d.SalesOrderDetailID=121317;
        IF @@ROWCOUNT<>1 THROW 51607, 'Expected one new Header.',1;
        SELECT @OrderID=ID FROM #HeaderOutput;
        INSERT INTO AdventureWorks2022.Sales.SalesOrderDetail
            (SalesOrderID,CarrierTrackingNumber,OrderQty,ProductID,SpecialOfferID,UnitPrice,UnitPriceDiscount,ModifiedDate)
        OUTPUT inserted.SalesOrderDetailID INTO #DetailOutput
        SELECT @OrderID,CarrierTrackingNumber,OrderQty,ProductID,SpecialOfferID,UnitPrice,UnitPriceDiscount,@SourceDate
        FROM #OriginalDetail WHERE SalesOrderID=75123 AND SalesOrderDetailID=121317;
        IF @@ROWCOUNT<>1 THROW 51608, 'Expected one new Detail.',1;
        SELECT @DetailID=ID FROM #DetailOutput;
        INSERT INTO #Fixtures VALUES (@Seq,@OrderID,@DetailID,CONVERT(DATETIME2(7),@SourceDate));
        SET @Seq+=1;
    END;
    EXEC AdventureWorks2022.sys.sp_executesql N'
        ENABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;
        ENABLE TRIGGER Sales.uSalesOrderHeader ON Sales.SalesOrderHeader;';
    COMMIT TRANSACTION;
    IF (SELECT COUNT(DISTINCT ModifiedDate) FROM #Fixtures)<>3
     OR EXISTS (SELECT 1 FROM #Fixtures WHERE DATEPART(NANOSECOND,ModifiedDate)=0
                OR DATEDIFF(SECOND,@Base,ModifiedDate)<>0)
        THROW 51609, 'Expected three distinct fractional timestamps in the same second.',1;

    -- Expected values use the previously reconciled reference fact, with new source identifiers.
    INSERT INTO #ExpectedFact
        (OrderDateKey,DueDateKey,ShipDateKey,ProductKey,CustomerKey,TerritoryKey,SalesPersonKey,ShipMethodKey,
         SalesOrderID,SalesOrderDetailID,SalesOrderNumber,OrderStatusCode,IsOnlineOrder,
         OrderQuantity,UnitPrice,DiscountRate,GrossAmount,DiscountAmount,NetSalesAmount)
    SELECT f.OrderDateKey,f.DueDateKey,f.ShipDateKey,f.ProductKey,f.CustomerKey,f.TerritoryKey,f.SalesPersonKey,f.ShipMethodKey,
           x.SalesOrderID,x.SalesOrderDetailID,h.SalesOrderNumber,f.OrderStatusCode,f.IsOnlineOrder,
           f.OrderQuantity,f.UnitPrice,f.DiscountRate,f.GrossAmount,f.DiscountAmount,f.NetSalesAmount
    FROM #OriginalFact f CROSS JOIN #Fixtures x
    JOIN AdventureWorks2022.Sales.SalesOrderHeader h ON h.SalesOrderID=x.SalesOrderID
    WHERE f.SalesOrderID=75123 AND f.SalesOrderDetailID=121317;
    IF (SELECT COUNT(*) FROM #ExpectedFact)<>3 THROW 51610, 'Expected three reference projections.',1;

    -- Bounded extraction: exact LOW excluded; exact HIGH included; later fraction excluded.
    SELECT @LowDate=ModifiedDate,@LowKey=SalesOrderID FROM #Fixtures WHERE Seq=1;
    SELECT @HighDate=ModifiedDate,@HighKey=SalesOrderID FROM #Fixtures WHERE Seq=2;
    EXEC etl.LoadSalesOrderLineDeltaStage
        @HeaderIsActive=1,@DetailIsActive=0,
        @HeaderLowModifiedDate=@LowDate,@HeaderLowBusinessKey=@LowKey,
        @HeaderHighModifiedDate=@HighDate,@HeaderHighBusinessKey=@HighKey,
        @DetailLowModifiedDate=NULL,@DetailLowBusinessKey=NULL,
        @DetailHighModifiedDate=NULL,@DetailHighBusinessKey=NULL;
    IF (SELECT COUNT(*) FROM stg.SalesOrderLineDelta)<>1
     OR NOT EXISTS (SELECT 1 FROM stg.SalesOrderLineDelta d JOIN #Fixtures x
        ON d.SalesOrderID=x.SalesOrderID AND d.SalesOrderDetailID=x.SalesOrderDetailID
        WHERE x.Seq=2 AND d.HeaderModifiedDate=x.ModifiedDate AND d.DetailModifiedDate=x.ModifiedDate)
        THROW 51611, 'Header fractional interval did not select only the exact HIGH fixture.',1;

    SELECT @LowKey=SalesOrderDetailID FROM #Fixtures WHERE Seq=1;
    SELECT @HighKey=SalesOrderDetailID FROM #Fixtures WHERE Seq=2;
    EXEC etl.LoadSalesOrderLineDeltaStage
        @HeaderIsActive=0,@DetailIsActive=1,
        @HeaderLowModifiedDate=NULL,@HeaderLowBusinessKey=NULL,
        @HeaderHighModifiedDate=NULL,@HeaderHighBusinessKey=NULL,
        @DetailLowModifiedDate=@LowDate,@DetailLowBusinessKey=@LowKey,
        @DetailHighModifiedDate=@HighDate,@DetailHighBusinessKey=@HighKey;
    IF (SELECT COUNT(*) FROM stg.SalesOrderLineDelta)<>1
     OR NOT EXISTS (SELECT 1 FROM stg.SalesOrderLineDelta d JOIN #Fixtures x
        ON d.SalesOrderID=x.SalesOrderID AND d.SalesOrderDetailID=x.SalesOrderDetailID
        WHERE x.Seq=2 AND d.HeaderModifiedDate=x.ModifiedDate AND d.DetailModifiedDate=x.ModifiedDate)
        THROW 51612, 'Detail fractional interval did not select only the exact HIGH fixture.',1;

    -- Fail finalization after all three inserts have committed to fact.
    ALTER TABLE audit.ETLWatermark WITH NOCHECK
    ADD CONSTRAINT CK_ETLWatermark_011_Finalization
        CHECK (ProcessName<>N'etl.LoadFactSalesIncremental.Header' OR [Status]<>'Ready');
    SET @OwnConstraint=1;
    SELECT @PreviousID=COALESCE(MAX(ExecutionID),0) FROM audit.ETLExecutionLog
    WHERE ProcessName=N'etl.LoadFactSalesIncremental';
    BEGIN TRY
        EXEC etl.LoadFactSalesIncremental;
    END TRY
    BEGIN CATCH
        SELECT @CaughtError=ERROR_NUMBER(),@CaughtMessage=ERROR_MESSAGE();
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    END CATCH;
    IF ISNULL(@CaughtError,-1)<>547
     OR CHARINDEX(N'CK_ETLWatermark_011_Finalization',COALESCE(@CaughtMessage,N''))=0
        THROW 51613, 'Expected the specific watermark-finalization constraint failure.',1;
    SELECT @FailedID=MAX(ExecutionID) FROM audit.ETLExecutionLog
    WHERE ProcessName=N'etl.LoadFactSalesIncremental' AND ExecutionID>@PreviousID;
    IF (SELECT COUNT(*) FROM audit.ETLExecutionLog
        WHERE ProcessName=N'etl.LoadFactSalesIncremental' AND ExecutionID>@PreviousID)<>1
     OR NOT EXISTS (SELECT 1 FROM audit.ETLExecutionLog
        WHERE ExecutionID=@FailedID AND [Status]=N'Failed' AND RowsRead=3
          AND RowsInserted=3 AND RowsUpdated=0 AND RowsRejected=0 AND EndTime IS NOT NULL
          AND CHARINDEX(N'FactCommitted: 1;',ErrorMessage)>0
          AND CHARINDEX(N'BatchFinalized: 0;',ErrorMessage)>0)
        THROW 51614, 'Expected three committed inserts and failed finalization in parent audit.',1;
    IF (SELECT COUNT(*) FROM audit.ETLWatermark w JOIN #OriginalWatermarks o ON o.WatermarkID=w.WatermarkID
        CROSS JOIN #Fixtures x
        WHERE x.Seq=3 AND w.[Status]='Failed' AND w.CurrentExecutionID=@FailedID
          AND w.LowModifiedDate=o.LowModifiedDate AND w.LowBusinessKey=o.LowBusinessKey
          AND w.HighModifiedDate=x.ModifiedDate
          AND w.HighBusinessKey=CASE w.ProcessName WHEN N'etl.LoadFactSalesIncremental.Header'
                                 THEN x.SalesOrderID ELSE x.SalesOrderDetailID END
          AND NOT EXISTS (SELECT w.LastSuccessfulExecutionID EXCEPT SELECT o.LastSuccessfulExecutionID))<>2
        THROW 51615, 'Both streams must retain original LOWs and pending HIGHs after failure.',1;
    IF (SELECT COUNT_BIG(*) FROM dw.FactSales)<>(SELECT COUNT_BIG(*)+3 FROM #OriginalFact)
     OR EXISTS (SELECT * FROM #ExpectedFact EXCEPT SELECT f.* FROM dw.FactSales f
                JOIN #Fixtures x ON x.SalesOrderID=f.SalesOrderID AND x.SalesOrderDetailID=f.SalesOrderDetailID)
     OR EXISTS (SELECT f.* FROM dw.FactSales f
                JOIN #Fixtures x ON x.SalesOrderID=f.SalesOrderID AND x.SalesOrderDetailID=f.SalesOrderDetailID
                EXCEPT SELECT * FROM #ExpectedFact)
     OR EXISTS (SELECT * FROM #OriginalFact EXCEPT SELECT * FROM dw.FactSales)
     OR EXISTS (SELECT f.* FROM dw.FactSales f WHERE NOT EXISTS
                (SELECT 1 FROM #Fixtures x WHERE x.SalesOrderID=f.SalesOrderID AND x.SalesOrderDetailID=f.SalesOrderDetailID)
                EXCEPT SELECT * FROM #OriginalFact)
        THROW 51616, 'Fact values or grain coverage differ from the expected original plus three new lines.',1;
    IF (SELECT COUNT(*) FROM stg.SalesOrderLineDelta)<>3
     OR EXISTS (SELECT SalesOrderID,SalesOrderDetailID FROM #Fixtures
                EXCEPT SELECT SalesOrderID,SalesOrderDetailID FROM stg.SalesOrderLineDelta)
        THROW 51617, 'Expected three unique new grains in delta staging.',1;
    ALTER TABLE audit.ETLWatermark DROP CONSTRAINT CK_ETLWatermark_011_Finalization;
    SET @OwnConstraint=0;
    EXEC etl.LoadFactSalesIncremental;
    SELECT @RetryID=MAX(ExecutionID) FROM audit.ETLExecutionLog
    WHERE ProcessName=N'etl.LoadFactSalesIncremental' AND ExecutionID>@FailedID;
    IF (SELECT COUNT(*) FROM audit.ETLExecutionLog
        WHERE ProcessName=N'etl.LoadFactSalesIncremental' AND ExecutionID>@FailedID)<>1
     OR NOT EXISTS (SELECT 1 FROM audit.ETLExecutionLog WHERE ExecutionID=@RetryID AND [Status]=N'Succeeded'
        AND RowsRead=3 AND RowsInserted=0 AND RowsUpdated=0 AND RowsRejected=0
        AND EndTime IS NOT NULL AND ErrorMessage IS NULL)
        THROW 51618, 'Retry must succeed without duplicate inserts or updates.',1;
    IF (SELECT COUNT(*) FROM audit.ETLWatermark w JOIN #OriginalWatermarks o ON o.WatermarkID=w.WatermarkID
        CROSS JOIN #Fixtures x WHERE x.Seq=3 AND w.[Status]='Ready'
          AND w.LowModifiedDate=x.ModifiedDate
          AND w.LowBusinessKey=CASE w.ProcessName WHEN N'etl.LoadFactSalesIncremental.Header'
                              THEN x.SalesOrderID ELSE x.SalesOrderDetailID END
          AND w.HighModifiedDate IS NULL AND w.HighBusinessKey IS NULL
          AND w.CurrentExecutionID IS NULL AND w.LastSuccessfulExecutionID=@RetryID)<>2
        THROW 51619, 'Both streams must finalize at their retained boundaries under the same successful execution.',1;
    IF (SELECT COUNT_BIG(*) FROM dw.FactSales)<>(SELECT COUNT_BIG(*)+3 FROM #OriginalFact)
     OR EXISTS (SELECT * FROM #ExpectedFact EXCEPT SELECT f.* FROM dw.FactSales f
                JOIN #Fixtures x ON x.SalesOrderID=f.SalesOrderID AND x.SalesOrderDetailID=f.SalesOrderDetailID)
     OR EXISTS (SELECT f.* FROM dw.FactSales f
                JOIN #Fixtures x ON x.SalesOrderID=f.SalesOrderID AND x.SalesOrderDetailID=f.SalesOrderDetailID
                EXCEPT SELECT * FROM #ExpectedFact)
     OR EXISTS (SELECT * FROM #OriginalFact EXCEPT SELECT * FROM dw.FactSales)
     OR EXISTS (SELECT f.* FROM dw.FactSales f WHERE NOT EXISTS
                (SELECT 1 FROM #Fixtures x WHERE x.SalesOrderID=f.SalesOrderID AND x.SalesOrderDetailID=f.SalesOrderDetailID)
                EXCEPT SELECT * FROM #OriginalFact)
        THROW 51616, 'Fact values or grain coverage differ from the expected original plus three new lines.',1;
    IF (SELECT COUNT(*) FROM stg.SalesOrderLineDelta)<>3
     OR EXISTS (SELECT SalesOrderID,SalesOrderDetailID FROM #Fixtures
                EXCEPT SELECT SalesOrderID,SalesOrderDetailID FROM stg.SalesOrderLineDelta)
        THROW 51617, 'Expected three unique new grains in delta staging.',1;
    IF @@TRANCOUNT<>0 THROW 51620, 'An unexpected transaction remains open.',1;
END TRY
BEGIN CATCH
    SET @Failure=LEFT(CONCAT(N'Error ',ERROR_NUMBER(),N', line ',ERROR_LINE(),N': ',ERROR_MESSAGE()),2048);
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
END CATCH;

-- Common cleanup, including after a handled test failure.
BEGIN TRY
    BEGIN TRANSACTION;
    IF @OwnConstraint=1 AND OBJECT_ID(N'audit.CK_ETLWatermark_011_Finalization',N'C') IS NOT NULL
        ALTER TABLE audit.ETLWatermark DROP CONSTRAINT CK_ETLWatermark_011_Finalization;
    EXEC AdventureWorks2022.sys.sp_executesql N'
        DISABLE TRIGGER Sales.uSalesOrderHeader ON Sales.SalesOrderHeader;
        DISABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;';
    DELETE f FROM dw.FactSales f JOIN #Fixtures x
    ON x.SalesOrderID=f.SalesOrderID AND x.SalesOrderDetailID=f.SalesOrderDetailID;
    DELETE d FROM AdventureWorks2022.Sales.SalesOrderDetail d JOIN #Fixtures x
    ON x.SalesOrderID=d.SalesOrderID AND x.SalesOrderDetailID=d.SalesOrderDetailID;
    DELETE h FROM AdventureWorks2022.Sales.SalesOrderHeader h JOIN #Fixtures x ON x.SalesOrderID=h.SalesOrderID;
    EXEC AdventureWorks2022.sys.sp_executesql N'
        ENABLE TRIGGER Sales.iduSalesOrderDetail ON Sales.SalesOrderDetail;
        ENABLE TRIGGER Sales.uSalesOrderHeader ON Sales.SalesOrderHeader;';
    UPDATE w SET LowModifiedDate=o.LowModifiedDate,LowBusinessKey=o.LowBusinessKey,
                 HighModifiedDate=o.HighModifiedDate,HighBusinessKey=o.HighBusinessKey,
                 [Status]=o.[Status],LastSuccessfulExecutionID=o.LastSuccessfulExecutionID,
                 CurrentExecutionID=o.CurrentExecutionID,UpdatedAt=o.UpdatedAt
    FROM audit.ETLWatermark w JOIN #OriginalWatermarks o ON o.WatermarkID=w.WatermarkID AND o.ProcessName=w.ProcessName;
    IF @@ROWCOUNT<>2 THROW 51621, 'Cleanup must restore exactly two watermark rows.',1;
    TRUNCATE TABLE stg.SalesOrderLineDelta;
    INSERT INTO stg.SalesOrderLineDelta SELECT * FROM #OriginalDelta;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    SELECT @Failure AS OriginalValidationFailure;
    THROW;
END CATCH;
IF (SELECT COUNT_BIG(*) FROM #OriginalHeader)<>(SELECT COUNT_BIG(*) FROM AdventureWorks2022.Sales.SalesOrderHeader)
 OR EXISTS (SELECT * FROM #OriginalHeader EXCEPT SELECT * FROM AdventureWorks2022.Sales.SalesOrderHeader)
 OR EXISTS (SELECT * FROM AdventureWorks2022.Sales.SalesOrderHeader EXCEPT SELECT * FROM #OriginalHeader)
    THROW 51622, 'Cleanup verification failed: AdventureWorks2022.Sales.SalesOrderHeader.',1;
IF (SELECT COUNT_BIG(*) FROM #OriginalDetail)<>(SELECT COUNT_BIG(*) FROM AdventureWorks2022.Sales.SalesOrderDetail)
 OR EXISTS (SELECT * FROM #OriginalDetail EXCEPT SELECT * FROM AdventureWorks2022.Sales.SalesOrderDetail)
 OR EXISTS (SELECT * FROM AdventureWorks2022.Sales.SalesOrderDetail EXCEPT SELECT * FROM #OriginalDetail)
    THROW 51622, 'Cleanup verification failed: AdventureWorks2022.Sales.SalesOrderDetail.',1;
IF (SELECT COUNT_BIG(*) FROM #OriginalFact)<>(SELECT COUNT_BIG(*) FROM dw.FactSales)
 OR EXISTS (SELECT * FROM #OriginalFact EXCEPT SELECT * FROM dw.FactSales)
 OR EXISTS (SELECT * FROM dw.FactSales EXCEPT SELECT * FROM #OriginalFact)
    THROW 51622, 'Cleanup verification failed: dw.FactSales.',1;
IF (SELECT COUNT_BIG(*) FROM #OriginalDelta)<>(SELECT COUNT_BIG(*) FROM stg.SalesOrderLineDelta)
 OR EXISTS (SELECT * FROM #OriginalDelta EXCEPT SELECT * FROM stg.SalesOrderLineDelta)
 OR EXISTS (SELECT * FROM stg.SalesOrderLineDelta EXCEPT SELECT * FROM #OriginalDelta)
    THROW 51622, 'Cleanup verification failed: stg.SalesOrderLineDelta.',1;
IF EXISTS (SELECT * FROM #OriginalWatermarks EXCEPT SELECT * FROM audit.ETLWatermark
            WHERE ProcessName IN (N'etl.LoadFactSalesIncremental.Header',N'etl.LoadFactSalesIncremental.Detail'))
 OR EXISTS (SELECT * FROM audit.ETLWatermark
            WHERE ProcessName IN (N'etl.LoadFactSalesIncremental.Header',N'etl.LoadFactSalesIncremental.Detail')
            EXCEPT SELECT * FROM #OriginalWatermarks)
 OR @@TRANCOUNT<>0 OR OBJECT_ID(N'audit.CK_ETLWatermark_011_Finalization',N'C') IS NOT NULL
    THROW 51623, 'Watermark, constraint or transaction cleanup failed.',1;
EXEC AdventureWorks2022.sys.sp_executesql N'
IF NOT EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id=OBJECT_ID(N''Sales.SalesOrderHeader'')
               AND name=N''uSalesOrderHeader'' AND is_disabled=0)
 OR NOT EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id=OBJECT_ID(N''Sales.SalesOrderDetail'')
               AND name=N''iduSalesOrderDetail'' AND is_disabled=0)
    THROW 51624, ''Both source triggers must remain enabled.'',1;';
IF @Failure IS NOT NULL THROW 51625,@Failure,1;
SELECT ExecutionID,[Status],RowsRead,RowsInserted,RowsUpdated
FROM audit.ETLExecutionLog WHERE ExecutionID IN (@FailedID,@RetryID) ORDER BY ExecutionID;
SELECT Seq,SalesOrderID,SalesOrderDetailID,ModifiedDate FROM #Fixtures ORDER BY Seq;
SELECT N'PASS: New orders, fractional boundaries, dual-stream recovery; state restored.' AS Result,
       @@TRANCOUNT AS OpenTransactions;
