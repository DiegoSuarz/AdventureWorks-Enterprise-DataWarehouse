/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : etl.LoadFactSalesDelta
Script   : etl.LoadFactSalesDelta.sql
Author   : Diego Suárez
Purpose  : Apply staged sales deltas through transactional updates and inserts,
           preserving fact rows outside the selected delta.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

CREATE OR ALTER PROCEDURE etl.LoadFactSalesDelta
    @RowsRead BIGINT = 0 OUTPUT,
    @RowsInserted BIGINT = 0 OUTPUT,
    @RowsUpdated BIGINT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @@TRANCOUNT <> 0
    BEGIN
        THROW 51130,
            'FactSales delta loading requires no existing transaction.',
            1;
    END;

    SET @RowsRead = 0;
    SET @RowsInserted = 0;
    SET @RowsUpdated = 0;

    DECLARE @ExecutionID BIGINT = NULL;
    DECLARE @ErrorMessage NVARCHAR(4000);

    BEGIN TRY

        -----------------------------------------------------------------------
        -- Register fact delta execution
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
            N'etl.LoadFactSalesDelta',
            N'stg.SalesOrderLineDelta',
            N'dw.FactSales',
            SUSER_SNAME()
        );

        SET @ExecutionID =
            CONVERT(BIGINT, SCOPE_IDENTITY());

        -----------------------------------------------------------------------
        -- Start transactional fact delta processing
        -----------------------------------------------------------------------
        BEGIN TRANSACTION;

        SELECT
            @RowsRead = COUNT_BIG(*)
        FROM stg.SalesOrderLineDelta;

        -----------------------------------------------------------------------
        -- Validate date resolution before applying fact changes
        -----------------------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM stg.SalesOrderLineDelta AS s

            LEFT JOIN dw.DimDate AS od
                ON od.FullDate = s.OrderDate

            LEFT JOIN dw.DimDate AS dd
                ON dd.FullDate = s.DueDate

            LEFT JOIN dw.DimDate AS sd
                ON sd.FullDate = s.ShipDate

            WHERE
                od.DateKey IS NULL
                OR dd.DateKey IS NULL
                OR
                (
                    s.ShipDate IS NOT NULL
                    AND sd.DateKey IS NULL
                )
        )
        BEGIN
            THROW 51131,
                'FactSales delta load aborted: a required date could not be resolved against dw.DimDate.',
                1;
        END;

        -----------------------------------------------------------------------
        -- Build reusable fact delta projection
        -----------------------------------------------------------------------
        ;WITH BaseMeasures AS
        (
            SELECT
                s.*,
                CONVERT
                (
                    DECIMAL(19,4),
                    s.OrderQuantity * s.UnitPrice
                ) AS GrossAmount,
                CONVERT
                (
                    DECIMAL(19,4),
                    s.OrderQuantity * s.UnitPrice
                        * (CONVERT(DECIMAL(10,4), 1) - s.DiscountRate)
                ) AS NetSalesAmount
            FROM stg.SalesOrderLineDelta AS s
        )
        SELECT
            od.DateKey AS OrderDateKey,
            dd.DateKey AS DueDateKey,
            sd.DateKey AS ShipDateKey,

            COALESCE(p.ProductKey, CONVERT(BIGINT, -1)) AS ProductKey,
            COALESCE(c.CustomerKey, CONVERT(BIGINT, -1)) AS CustomerKey,
            COALESCE(t.TerritoryKey, CONVERT(BIGINT, -1)) AS TerritoryKey,

            CASE
                WHEN s.SalesPersonID IS NULL AND s.IsOnlineOrder = 1
                    THEN CONVERT(BIGINT, -2)
                ELSE COALESCE(sp.SalesPersonKey, CONVERT(BIGINT, -1))
            END AS SalesPersonKey,

            COALESCE(sm.ShipMethodKey, CONVERT(BIGINT, -1)) AS ShipMethodKey,

            s.SalesOrderID,
            s.SalesOrderDetailID,
            s.SalesOrderNumber,
            s.OrderStatusCode,
            s.IsOnlineOrder,
            s.OrderQuantity,
            s.UnitPrice,
            s.DiscountRate,
            s.GrossAmount,

            CONVERT
            (
                DECIMAL(19,4),
                s.GrossAmount - s.NetSalesAmount
            ) AS DiscountAmount,

            s.NetSalesAmount

        INTO #FactSalesDelta
        FROM BaseMeasures AS s

        LEFT JOIN dw.DimDate AS od
            ON od.FullDate = s.OrderDate

        LEFT JOIN dw.DimDate AS dd
            ON dd.FullDate = s.DueDate

        LEFT JOIN dw.DimDate AS sd
            ON sd.FullDate = s.ShipDate

        LEFT JOIN dw.DimProduct AS p
            ON p.ProductID = s.ProductID
           AND p.IsCurrent = 1

        LEFT JOIN dw.DimCustomer AS c
            ON c.CustomerID = s.CustomerID
           AND c.IsCurrent = 1

        LEFT JOIN dw.DimTerritory AS t
            ON t.TerritoryID = s.TerritoryID
           AND t.IsCurrent = 1

        LEFT JOIN dw.DimSalesPerson AS sp
            ON sp.BusinessEntityID = s.SalesPersonID
           AND sp.IsCurrent = 1

        LEFT JOIN dw.DimShipMethod AS sm
            ON sm.ShipMethodID = s.ShipMethodID
           AND sm.IsCurrent = 1;

        IF (SELECT COUNT_BIG(*) FROM #FactSalesDelta) <> @RowsRead
        BEGIN
            THROW 51132,
                'FactSales delta load aborted: projection row count does not match delta staging.',
                1;
        END;

        -----------------------------------------------------------------------
        -- Update changed fact lines
        -----------------------------------------------------------------------
        UPDATE f
        SET
            OrderDateKey = d.OrderDateKey,
            DueDateKey = d.DueDateKey,
            ShipDateKey = d.ShipDateKey,
            ProductKey = d.ProductKey,
            CustomerKey = d.CustomerKey,
            TerritoryKey = d.TerritoryKey,
            SalesPersonKey = d.SalesPersonKey,
            ShipMethodKey = d.ShipMethodKey,
            SalesOrderNumber = d.SalesOrderNumber,
            OrderStatusCode = d.OrderStatusCode,
            IsOnlineOrder = d.IsOnlineOrder,
            OrderQuantity = d.OrderQuantity,
            UnitPrice = d.UnitPrice,
            DiscountRate = d.DiscountRate,
            GrossAmount = d.GrossAmount,
            DiscountAmount = d.DiscountAmount,
            NetSalesAmount = d.NetSalesAmount

        FROM dw.FactSales AS f
        INNER JOIN #FactSalesDelta AS d
            ON d.SalesOrderID = f.SalesOrderID
           AND d.SalesOrderDetailID = f.SalesOrderDetailID

        WHERE EXISTS
        (
            SELECT
                d.OrderDateKey,
                d.DueDateKey,
                d.ShipDateKey,
                d.ProductKey,
                d.CustomerKey,
                d.TerritoryKey,
                d.SalesPersonKey,
                d.ShipMethodKey,
                d.SalesOrderNumber,
                d.OrderStatusCode,
                d.IsOnlineOrder,
                d.OrderQuantity,
                d.UnitPrice,
                d.DiscountRate,
                d.GrossAmount,
                d.DiscountAmount,
                d.NetSalesAmount

            EXCEPT

            SELECT
                f.OrderDateKey,
                f.DueDateKey,
                f.ShipDateKey,
                f.ProductKey,
                f.CustomerKey,
                f.TerritoryKey,
                f.SalesPersonKey,
                f.ShipMethodKey,
                f.SalesOrderNumber,
                f.OrderStatusCode,
                f.IsOnlineOrder,
                f.OrderQuantity,
                f.UnitPrice,
                f.DiscountRate,
                f.GrossAmount,
                f.DiscountAmount,
                f.NetSalesAmount
        );

        SET @RowsUpdated = @@ROWCOUNT;

        -----------------------------------------------------------------------
        -- Insert new fact lines
        -----------------------------------------------------------------------
        INSERT INTO dw.FactSales
        (
            OrderDateKey,
            DueDateKey,
            ShipDateKey,
            ProductKey,
            CustomerKey,
            TerritoryKey,
            SalesPersonKey,
            ShipMethodKey,
            SalesOrderID,
            SalesOrderDetailID,
            SalesOrderNumber,
            OrderStatusCode,
            IsOnlineOrder,
            OrderQuantity,
            UnitPrice,
            DiscountRate,
            GrossAmount,
            DiscountAmount,
            NetSalesAmount
        )
        SELECT
            d.OrderDateKey,
            d.DueDateKey,
            d.ShipDateKey,
            d.ProductKey,
            d.CustomerKey,
            d.TerritoryKey,
            d.SalesPersonKey,
            d.ShipMethodKey,
            d.SalesOrderID,
            d.SalesOrderDetailID,
            d.SalesOrderNumber,
            d.OrderStatusCode,
            d.IsOnlineOrder,
            d.OrderQuantity,
            d.UnitPrice,
            d.DiscountRate,
            d.GrossAmount,
            d.DiscountAmount,
            d.NetSalesAmount
        FROM #FactSalesDelta AS d
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dw.FactSales AS f WITH (UPDLOCK, HOLDLOCK)
            WHERE f.SalesOrderID = d.SalesOrderID
              AND f.SalesOrderDetailID = d.SalesOrderDetailID
        );

        SET @RowsInserted = @@ROWCOUNT;

        -----------------------------------------------------------------------
        -- Confirm fact changes and successful audit together
        -----------------------------------------------------------------------
        UPDATE audit.ETLExecutionLog
        SET
            EndTime = SYSUTCDATETIME(),
            [Status] = N'Succeeded',
            RowsRead = @RowsRead,
            RowsInserted = @RowsInserted,
            RowsUpdated = @RowsUpdated,
            RowsRejected = 0,
            ErrorMessage = NULL
        WHERE ExecutionID = @ExecutionID;

        IF @@ROWCOUNT <> 1
        BEGIN
            THROW 51133,
                'FactSales delta load failed: execution audit row was not found.',
                1;
        END;

        COMMIT TRANSACTION;

    END TRY

    BEGIN CATCH

        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        SET @RowsInserted = 0;
        SET @RowsUpdated = 0;

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
                RowsInserted = @RowsInserted,
                RowsUpdated = @RowsUpdated,
                RowsRejected = 0,
                ErrorMessage = LEFT(@ErrorMessage, 4000)
            WHERE ExecutionID = @ExecutionID;
        END;

        THROW;

    END CATCH;
END;
GO
