/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : etl.LoadFactSales
Script   : etl.LoadFactSales.sql
Author   : Diego Suárez
Purpose  : Load a complete sales fact snapshot from stg.SalesOrderLine,
           resolving dimension keys and deriving reconciled sales measures.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE OR ALTER PROCEDURE
===============================================================================
*/

CREATE OR ALTER PROCEDURE etl.LoadFactSales
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
            N'etl.LoadFactSales',
            N'stg.SalesOrderLine',
            N'dw.FactSales',
            SUSER_SNAME()
        );

        SET @ExecutionID =
            CONVERT(BIGINT, SCOPE_IDENTITY());

        -----------------------------------------------------------------------
        -- Capture staging row count
        -----------------------------------------------------------------------
        SELECT
            @RowsRead = COUNT_BIG(*)
        FROM stg.SalesOrderLine;

        -----------------------------------------------------------------------
        -- Start transactional fact load
        -----------------------------------------------------------------------
        BEGIN TRANSACTION;

        -----------------------------------------------------------------------
        -- Validate required date resolution before replacing fact data
        -----------------------------------------------------------------------
        IF EXISTS
        (
            SELECT
                1
            FROM stg.SalesOrderLine AS s

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
            THROW 51001,
                'FactSales load aborted: a required date could not be resolved against dw.DimDate.',
                1;
        END;

        /*
        =======================================================================
        2. REPLACE FACT SNAPSHOT
        =======================================================================
        */

        TRUNCATE TABLE dw.FactSales;

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
                    s.OrderQuantity
                        * s.UnitPrice
                        * (
                            CONVERT(DECIMAL(10,4), 1)
                            - s.DiscountRate
                          )
                ) AS NetSalesAmount

            FROM stg.SalesOrderLine AS s
        )
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
            od.DateKey AS OrderDateKey,
            dd.DateKey AS DueDateKey,
            sd.DateKey AS ShipDateKey,

            COALESCE
            (
                p.ProductKey,
                CONVERT(BIGINT, -1)
            ) AS ProductKey,

            COALESCE
            (
                c.CustomerKey,
                CONVERT(BIGINT, -1)
            ) AS CustomerKey,

            COALESCE
            (
                t.TerritoryKey,
                CONVERT(BIGINT, -1)
            ) AS TerritoryKey,

            CASE
                WHEN s.SalesPersonID IS NULL
                 AND s.IsOnlineOrder = 1
                    THEN CONVERT(BIGINT, -2)

                ELSE COALESCE
                (
                    sp.SalesPersonKey,
                    CONVERT(BIGINT, -1)
                )
            END AS SalesPersonKey,

            COALESCE
            (
                sm.ShipMethodKey,
                CONVERT(BIGINT, -1)
            ) AS ShipMethodKey,

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

        /*
        =======================================================================
        4. ROLLBACK FAILED LOAD
        =======================================================================
        */

        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        /*
        =======================================================================
        5. BUILD ERROR MESSAGE
        =======================================================================
        */

        SET @ErrorMessage =
            CONCAT
            (
                N'ErrorNumber: ', ERROR_NUMBER(),
                N'; ErrorProcedure: ',
                COALESCE(ERROR_PROCEDURE(), N'Ad hoc batch'),
                N'; ErrorLine: ', ERROR_LINE(),
                N'; ErrorMessage: ', ERROR_MESSAGE()
            );

        /*
        =======================================================================
        6. MARK EXECUTION AS FAILED
        =======================================================================
        */

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
