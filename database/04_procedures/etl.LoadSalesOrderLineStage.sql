/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : etl.LoadSalesOrderLineStage
Script   : etl.LoadSalesOrderLineStage.sql
Author   : Diego Suárez
Purpose  : Load the normalized full sales-order-line snapshot from
           AdventureWorks2022 into stg.SalesOrderLine.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE OR ALTER PROCEDURE
===============================================================================
*/

CREATE OR ALTER PROCEDURE etl.LoadSalesOrderLineStage
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    ---------------------------------------------------------------------------
    -- Execution variables
    ---------------------------------------------------------------------------
    DECLARE @ExecutionID BIGINT = NULL;
    DECLARE @RowsRead BIGINT = 0;
    DECLARE @RowsInserted BIGINT = 0;
    DECLARE @ExtractedAt DATETIME2(7) = SYSUTCDATETIME();
    DECLARE @ErrorMessage NVARCHAR(4000);

    BEGIN TRY

        -----------------------------------------------------------------------
        -- Register ETL execution
        -----------------------------------------------------------------------
        INSERT INTO audit.ETLExecutionLog
        (
            ProcessName,
            SourceObject,
            TargetObject,
            ExecutedBy
        )
        VALUES
        (
            N'etl.LoadSalesOrderLineStage',
            N'AdventureWorks2022.Sales.SalesOrderHeader + SalesOrderDetail',
            N'stg.SalesOrderLine',
            SUSER_SNAME()
        );

        SET @ExecutionID =
            CONVERT(BIGINT, SCOPE_IDENTITY());

        -----------------------------------------------------------------------
        -- Capture source row count at staging grain
        -----------------------------------------------------------------------
        SELECT
            @RowsRead = COUNT_BIG(*)
        FROM AdventureWorks2022.Sales.SalesOrderDetail AS sod
        INNER JOIN AdventureWorks2022.Sales.SalesOrderHeader AS soh
            ON sod.SalesOrderID = soh.SalesOrderID;

        -----------------------------------------------------------------------
        -- Start staging load
        -----------------------------------------------------------------------
        BEGIN TRANSACTION;

        TRUNCATE TABLE stg.SalesOrderLine;

        /*
        =======================================================================
        2. LOAD SALES ORDER LINE SNAPSHOT
        =======================================================================
        */

        INSERT INTO stg.SalesOrderLine
        (
            SalesOrderID,
            SalesOrderDetailID,
            SalesOrderNumber,
            OrderDate,
            DueDate,
            ShipDate,
            OrderStatusCode,
            IsOnlineOrder,
            CustomerID,
            SalesPersonID,
            TerritoryID,
            ShipMethodID,
            ProductID,
            OrderQuantity,
            UnitPrice,
            DiscountRate,
            HeaderModifiedDate,
            DetailModifiedDate,
            ExtractedAt
        )
        SELECT
            sod.SalesOrderID,
            sod.SalesOrderDetailID,

            CONVERT
            (
                NVARCHAR(25),
                soh.SalesOrderNumber
            ) AS SalesOrderNumber,

            CONVERT(DATE, soh.OrderDate) AS OrderDate,
            CONVERT(DATE, soh.DueDate) AS DueDate,
            CONVERT(DATE, soh.ShipDate) AS ShipDate,

            soh.Status AS OrderStatusCode,

            CONVERT
            (
                BIT,
                soh.OnlineOrderFlag
            ) AS IsOnlineOrder,

            soh.CustomerID,
            soh.SalesPersonID,
            soh.TerritoryID,
            soh.ShipMethodID,
            sod.ProductID,

            sod.OrderQty AS OrderQuantity,

            CONVERT
            (
                DECIMAL(19,4),
                sod.UnitPrice
            ) AS UnitPrice,

            CONVERT
            (
                DECIMAL(10,4),
                sod.UnitPriceDiscount
            ) AS DiscountRate,

            CONVERT
            (
                DATETIME2(0),
                soh.ModifiedDate
            ) AS HeaderModifiedDate,

            CONVERT
            (
                DATETIME2(0),
                sod.ModifiedDate
            ) AS DetailModifiedDate,

            @ExtractedAt AS ExtractedAt

        FROM AdventureWorks2022.Sales.SalesOrderDetail AS sod
        INNER JOIN AdventureWorks2022.Sales.SalesOrderHeader AS soh
            ON sod.SalesOrderID = soh.SalesOrderID;

        SET @RowsInserted = @@ROWCOUNT;

        COMMIT TRANSACTION;

        /*
        =======================================================================
        3. MARK EXECUTION AS SUCCESSFUL
        =======================================================================
        */

        UPDATE audit.ETLExecutionLog
        SET
            EndTime = SYSUTCDATETIME(),
            [Status] = N'Succeeded',
            RowsRead = @RowsRead,
            RowsInserted = @RowsInserted,
            RowsUpdated = 0,
            RowsRejected = 0,
            ErrorMessage = NULL
        WHERE ExecutionID = @ExecutionID;

    END TRY

    BEGIN CATCH

        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        SET @ErrorMessage =
            CONCAT
            (
                N'ErrorNumber: ', ERROR_NUMBER(),
                N'; ErrorProcedure: ',
                COALESCE(ERROR_PROCEDURE(), N'Ad hoc batch'),
                N'; ErrorLine: ', ERROR_LINE(),
                N'; ErrorMessage: ', ERROR_MESSAGE()
            );

        IF @ExecutionID IS NOT NULL
        BEGIN
            UPDATE audit.ETLExecutionLog
            SET
                EndTime = SYSUTCDATETIME(),
                [Status] = N'Failed',
                RowsRead = @RowsRead,
                RowsInserted = 0,
                RowsUpdated = 0,
                RowsRejected = 0,
                ErrorMessage = LEFT(@ErrorMessage, 4000)
            WHERE ExecutionID = @ExecutionID;
        END;

        THROW;

    END CATCH;
END;
GO
