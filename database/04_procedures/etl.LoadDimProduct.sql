/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 001_LoadProductStage.sql
Author   : Diego Suárez
Purpose  : Perform a full refresh of product data into stg.Product.
Version  : 0.1.0
===============================================================================
*/

USE AdventureWorks_EDW;
GO

CREATE OR ALTER PROCEDURE etl.LoadProductStage
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ExecutionID BIGINT = NULL;
    DECLARE @RowsRead BIGINT = 0;
    DECLARE @RowsInserted BIGINT = 0;
    DECLARE @ErrorMessage NVARCHAR(4000);

    BEGIN TRY

        -----------------------------------------------------------------------
        -- Register the beginning of the ETL execution
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
            N'etl.LoadProductStage',
            N'AdventureWorks2022.Production.Product',
            N'stg.Product',
            SUSER_SNAME()
        );

        SET @ExecutionID =
            CONVERT(BIGINT, SCOPE_IDENTITY());

        -----------------------------------------------------------------------
        -- Begin the staging load transaction
        -----------------------------------------------------------------------

        BEGIN TRANSACTION;

        -----------------------------------------------------------------------
        -- Full refresh: remove the previous staging snapshot
        -----------------------------------------------------------------------

        TRUNCATE TABLE stg.Product;

        -----------------------------------------------------------------------
        -- Extract, transform and load the current product snapshot
        -----------------------------------------------------------------------

        INSERT INTO stg.Product
        (
            ProductID,
            ProductName,
            ProductNumber,
            Color,
            Size,
            StandardCost,
            ListPrice,
            SubcategoryName,
            CategoryName,
            SellStartDate,
            SellEndDate,
            DiscontinuedDate,
            SourceModifiedDate,
            RowHash
        )
        SELECT
            p.ProductID,
            p.Name AS ProductName,
            p.ProductNumber,
            p.Color,
            p.Size,
            p.StandardCost,
            p.ListPrice,

            COALESCE
            (
                ps.Name,
                N'Uncategorized'
            ) AS SubcategoryName,

            COALESCE
            (
                pc.Name,
                N'Uncategorized'
            ) AS CategoryName,

            p.SellStartDate,
            p.SellEndDate,
            p.DiscontinuedDate,
            p.ModifiedDate AS SourceModifiedDate,

            HASHBYTES
            (
                'SHA2_256',
                CONCAT
                (                    
                    N'|Color=', COALESCE(p.Color, N'<NULL>'),
                    N'|Size=', COALESCE(p.Size, N'<NULL>'),

                    N'|StandardCost=',
                    CONVERT
                    (
                        NVARCHAR(50),
                        CONVERT(DECIMAL(19, 4), p.StandardCost)
                    ),

                    N'|ListPrice=',
                    CONVERT
                    (
                        NVARCHAR(50),
                        CONVERT(DECIMAL(19, 4), p.ListPrice)
                    ),

                    N'|SubcategoryName=',
                    COALESCE(ps.Name, N'Uncategorized'),

                    N'|CategoryName=',
                    COALESCE(pc.Name, N'Uncategorized'),

                    N'|SellStartDate=',
                    CONVERT
                    (
                        NVARCHAR(30),
                        p.SellStartDate,
                        126
                    ),

                    N'|SellEndDate=',
                    COALESCE
                    (
                        CONVERT
                        (
                            NVARCHAR(30),
                            p.SellEndDate,
                            126
                        ),
                        N'<NULL>'
                    ),

                    N'|DiscontinuedDate=',
                    COALESCE
                    (
                        CONVERT
                        (
                            NVARCHAR(30),
                            p.DiscontinuedDate,
                            126
                        ),
                        N'<NULL>'
                    )
                )
            ) AS RowHash

        FROM AdventureWorks2022.Production.Product AS p

        LEFT JOIN AdventureWorks2022.Production.ProductSubcategory AS ps
            ON p.ProductSubcategoryID = ps.ProductSubcategoryID

        LEFT JOIN AdventureWorks2022.Production.ProductCategory AS pc
            ON ps.ProductCategoryID = pc.ProductCategoryID;

        -----------------------------------------------------------------------
        -- Capture the number of rows processed
        -----------------------------------------------------------------------

        SET @RowsInserted = @@ROWCOUNT;
        SET @RowsRead = @RowsInserted;

        COMMIT TRANSACTION;

        -----------------------------------------------------------------------
        -- Mark the ETL execution as successful
        -----------------------------------------------------------------------

        UPDATE audit.ETLExecutionLog
        SET
            EndTime = SYSUTCDATETIME(),
            [Status] = 'Succeeded',
            RowsRead = @RowsRead,
            RowsInserted = @RowsInserted,
            RowsUpdated = 0,
            RowsRejected = 0,
            ErrorMessage = NULL
        WHERE ExecutionID = @ExecutionID;

    END TRY

    BEGIN CATCH

        -----------------------------------------------------------------------
        -- Roll back an incomplete staging load
        -----------------------------------------------------------------------

        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -----------------------------------------------------------------------
        -- Build a diagnostic error message
        -----------------------------------------------------------------------

        SET @ErrorMessage =
            CONCAT
            (
                N'ErrorNumber: ', ERROR_NUMBER(),
                N'; ErrorProcedure: ',
                COALESCE(ERROR_PROCEDURE(), N'Ad hoc batch'),
                N'; ErrorLine: ', ERROR_LINE(),
                N'; ErrorMessage: ', ERROR_MESSAGE()
            );

        -----------------------------------------------------------------------
        -- Mark the ETL execution as failed
        -----------------------------------------------------------------------

        IF @ExecutionID IS NOT NULL
        BEGIN
            UPDATE audit.ETLExecutionLog
            SET
                EndTime = SYSUTCDATETIME(),
                [Status] = 'Failed',
                RowsRead = @RowsRead,
                RowsInserted = 0,
                RowsUpdated = 0,
                RowsRejected = 0,
                ErrorMessage = LEFT(@ErrorMessage, 4000)
            WHERE ExecutionID = @ExecutionID;
        END;

        -----------------------------------------------------------------------
        -- Propagate the original error to the caller or orchestrator
        -----------------------------------------------------------------------

        THROW;

    END CATCH;
END;
GO