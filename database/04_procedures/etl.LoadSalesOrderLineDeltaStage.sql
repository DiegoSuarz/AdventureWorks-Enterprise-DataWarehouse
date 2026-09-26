/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : etl.LoadSalesOrderLineDeltaStage
Script   : etl.LoadSalesOrderLineDeltaStage.sql
Author   : Diego Suárez
Purpose  : Extract normalized sales-order lines selected by independent
           Header and Detail composite watermark intervals.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

CREATE OR ALTER PROCEDURE etl.LoadSalesOrderLineDeltaStage
    @HeaderIsActive BIT,
    @DetailIsActive BIT,

    @HeaderLowModifiedDate DATETIME2(7) = NULL,
    @HeaderLowBusinessKey BIGINT = NULL,
    @HeaderHighModifiedDate DATETIME2(7) = NULL,
    @HeaderHighBusinessKey BIGINT = NULL,

    @DetailLowModifiedDate DATETIME2(7) = NULL,
    @DetailLowBusinessKey BIGINT = NULL,
    @DetailHighModifiedDate DATETIME2(7) = NULL,
    @DetailHighBusinessKey BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @@TRANCOUNT <> 0
    BEGIN
        THROW 51110,
            'Sales delta extraction requires no existing transaction.',
            1;
    END;

    DECLARE @ExecutionID BIGINT = NULL;
    DECLARE @RowsRead BIGINT = 0;
    DECLARE @RowsInserted BIGINT = 0;
    DECLARE @ExtractedAt DATETIME2(7) = SYSUTCDATETIME();
    DECLARE @ErrorMessage NVARCHAR(4000);

    BEGIN TRY

        -----------------------------------------------------------------------
        -- Register extraction execution
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
            N'etl.LoadSalesOrderLineDeltaStage',
            N'AdventureWorks2022.Sales.SalesOrderHeader + SalesOrderDetail',
            N'stg.SalesOrderLineDelta',
            SUSER_SNAME()
        );

        SET @ExecutionID =
            CONVERT(BIGINT, SCOPE_IDENTITY());

        -----------------------------------------------------------------------
        -- Validate composite watermark parameters
        -----------------------------------------------------------------------
        IF @HeaderIsActive IS NULL OR @DetailIsActive IS NULL
        BEGIN
            THROW 51111,
                'HeaderIsActive and DetailIsActive must not be NULL.',
                1;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM
            (
                VALUES
                (
                    @HeaderIsActive,
                    @HeaderLowModifiedDate, @HeaderLowBusinessKey,
                    @HeaderHighModifiedDate, @HeaderHighBusinessKey
                ),
                (
                    @DetailIsActive,
                    @DetailLowModifiedDate, @DetailLowBusinessKey,
                    @DetailHighModifiedDate, @DetailHighBusinessKey
                )
            ) AS b
            (
                IsActive,
                LowModifiedDate, LowBusinessKey,
                HighModifiedDate, HighBusinessKey
            )
            WHERE
                (b.LowModifiedDate IS NULL AND b.LowBusinessKey IS NOT NULL)
                OR
                (b.LowModifiedDate IS NOT NULL AND b.LowBusinessKey IS NULL)
                OR
                (
                    b.IsActive = 1
                    AND
                    (
                        b.HighModifiedDate IS NULL
                        OR b.HighBusinessKey IS NULL
                        OR
                        (
                            b.LowModifiedDate IS NOT NULL
                            AND NOT
                            (
                                b.HighModifiedDate > b.LowModifiedDate
                                OR
                                (
                                    b.HighModifiedDate = b.LowModifiedDate
                                    AND b.HighBusinessKey > b.LowBusinessKey
                                )
                            )
                        )
                    )
                )
                OR
                (
                    b.IsActive = 0
                    AND
                    (
                        b.HighModifiedDate IS NOT NULL
                        OR b.HighBusinessKey IS NOT NULL
                    )
                )
        )
        BEGIN
            THROW 51112,
                'Invalid watermark interval: incomplete LOW pair, missing or non-increasing active HIGH, or HIGH supplied for an inactive stream.',
                1;
        END;

        -----------------------------------------------------------------------
        -- Select candidate sales lines
        -----------------------------------------------------------------------
        BEGIN TRANSACTION;

        ;WITH ChangedHeaders AS
        (
            SELECT
                soh.SalesOrderID
            FROM AdventureWorks2022.Sales.SalesOrderHeader AS soh
            WHERE @HeaderIsActive = 1
              AND
              (
                  @HeaderLowModifiedDate IS NULL
                  OR CONVERT(DATETIME2(7), soh.ModifiedDate)
                     > @HeaderLowModifiedDate
                  OR
                  (
                      CONVERT(DATETIME2(7), soh.ModifiedDate)
                          = @HeaderLowModifiedDate
                      AND soh.SalesOrderID > @HeaderLowBusinessKey
                  )
              )
              AND
              (
                  CONVERT(DATETIME2(7), soh.ModifiedDate)
                      < @HeaderHighModifiedDate
                  OR
                  (
                      CONVERT(DATETIME2(7), soh.ModifiedDate)
                          = @HeaderHighModifiedDate
                      AND soh.SalesOrderID <= @HeaderHighBusinessKey
                  )
              )
        ),
        ChangedDetails AS
        (
            SELECT
                sod.SalesOrderID,
                sod.SalesOrderDetailID
            FROM AdventureWorks2022.Sales.SalesOrderDetail AS sod
            WHERE @DetailIsActive = 1
              AND
              (
                  @DetailLowModifiedDate IS NULL
                  OR CONVERT(DATETIME2(7), sod.ModifiedDate)
                     > @DetailLowModifiedDate
                  OR
                  (
                      CONVERT(DATETIME2(7), sod.ModifiedDate)
                          = @DetailLowModifiedDate
                      AND sod.SalesOrderDetailID > @DetailLowBusinessKey
                  )
              )
              AND
              (
                  CONVERT(DATETIME2(7), sod.ModifiedDate)
                      < @DetailHighModifiedDate
                  OR
                  (
                      CONVERT(DATETIME2(7), sod.ModifiedDate)
                          = @DetailHighModifiedDate
                      AND sod.SalesOrderDetailID <= @DetailHighBusinessKey
                  )
              )
        ),
        CandidateLines AS
        (
            SELECT
                sod.SalesOrderID,
                sod.SalesOrderDetailID
            FROM AdventureWorks2022.Sales.SalesOrderDetail AS sod
            INNER JOIN ChangedHeaders AS h
                ON h.SalesOrderID = sod.SalesOrderID

            UNION

            SELECT
                SalesOrderID,
                SalesOrderDetailID
            FROM ChangedDetails
        )
        SELECT
            SalesOrderID,
            SalesOrderDetailID
        INTO #CandidateSalesLines
        FROM CandidateLines;

        SELECT
            @RowsRead = COUNT_BIG(*)
        FROM #CandidateSalesLines;

        TRUNCATE TABLE stg.SalesOrderLineDelta;

        -----------------------------------------------------------------------
        -- Load normalized candidate lines
        -----------------------------------------------------------------------
        INSERT INTO stg.SalesOrderLineDelta
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
            CONVERT(NVARCHAR(25), soh.SalesOrderNumber),
            CONVERT(DATE, soh.OrderDate),
            CONVERT(DATE, soh.DueDate),
            CONVERT(DATE, soh.ShipDate),
            soh.[Status],
            CONVERT(BIT, soh.OnlineOrderFlag),
            soh.CustomerID,
            soh.SalesPersonID,
            soh.TerritoryID,
            soh.ShipMethodID,
            sod.ProductID,
            sod.OrderQty,
            CONVERT(DECIMAL(19,4), sod.UnitPrice),
            CONVERT(DECIMAL(10,4), sod.UnitPriceDiscount),
            CONVERT(DATETIME2(7), soh.ModifiedDate),
            CONVERT(DATETIME2(7), sod.ModifiedDate),
            @ExtractedAt

        FROM #CandidateSalesLines AS c

        INNER JOIN AdventureWorks2022.Sales.SalesOrderDetail AS sod
            ON sod.SalesOrderID = c.SalesOrderID
           AND sod.SalesOrderDetailID = c.SalesOrderDetailID

        INNER JOIN AdventureWorks2022.Sales.SalesOrderHeader AS soh
            ON soh.SalesOrderID = sod.SalesOrderID;

        SET @RowsInserted = @@ROWCOUNT;

        IF @RowsInserted <> @RowsRead
        BEGIN
            THROW 51113,
                'Sales delta extraction failed: inserted rows do not match the selected candidate lines.',
                1;
        END;

        -----------------------------------------------------------------------
        -- Confirm staging contents and successful audit together
        -----------------------------------------------------------------------
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

        IF @@ROWCOUNT <> 1
        BEGIN
            THROW 51114,
                'Sales delta extraction failed: execution audit row was not found.',
                1;
        END;

        COMMIT TRANSACTION;

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
