/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : etl.LoadDimProduct.sql
Author   : Diego Suárez
Purpose  : Load dw.DimProduct using Slowly Changing Dimension Type 2.
Version  : 0.1.0
===============================================================================
*/

USE AdventureWorks_EDW;
GO

CREATE OR ALTER PROCEDURE etl.LoadDimProduct
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    ---------------------------------------------------------------------------
    -- Execution variables
    ---------------------------------------------------------------------------

    DECLARE @ExecutionID BIGINT = NULL;
    DECLARE @LoadDateTime DATETIME2(7) = SYSUTCDATETIME();

    DECLARE @RowsRead BIGINT = 0;
    DECLARE @RowsInserted BIGINT = 0;
    DECLARE @RowsUpdated BIGINT = 0;

    DECLARE @NewRowsInserted BIGINT = 0;
    DECLARE @Type1RowsUpdated BIGINT = 0;
    DECLARE @VersionsExpired BIGINT = 0;
    DECLARE @NewVersionsInserted BIGINT = 0;

    DECLARE @ErrorMessage NVARCHAR(4000);

    DECLARE @OpenEndedDateTime DATETIME2(7) =
        CONVERT
        (
            DATETIME2(7),
            '9999-12-31 23:59:59.9999999'
        );

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
            N'etl.LoadDimProduct',
            N'stg.Product',
            N'dw.DimProduct',
            SUSER_SNAME()
        );

        SET @ExecutionID =
            CONVERT(BIGINT, SCOPE_IDENTITY());

        -----------------------------------------------------------------------
        -- Capture the number of staging rows read
        -----------------------------------------------------------------------

        SELECT
            @RowsRead = COUNT_BIG(*)
        FROM stg.Product;

        -----------------------------------------------------------------------
        -- Begin the dimensional load transaction
        -----------------------------------------------------------------------

        BEGIN TRANSACTION;

        -----------------------------------------------------------------------
        -- Store products with SCD Type 2 changes
        -----------------------------------------------------------------------

        CREATE TABLE #ChangedProducts
        (
            ProductID INT NOT NULL,

            CONSTRAINT PK_ChangedProducts
                PRIMARY KEY CLUSTERED (ProductID)
        );

        INSERT INTO #ChangedProducts
        (
            ProductID
        )
        SELECT
            s.ProductID
        FROM stg.Product AS s
        INNER JOIN dw.DimProduct AS d
            ON s.ProductID = d.ProductID
           AND d.IsCurrent = 1
        WHERE s.RowHash <> d.RowHash;

        -----------------------------------------------------------------------
        -- Insert products that do not have a current dimension member
        -----------------------------------------------------------------------

        INSERT INTO dw.DimProduct
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
            EffectiveStartDateTime,
            EffectiveEndDateTime,
            IsCurrent,
            RowHash,
            SourceModifiedDate
        )
        SELECT
            s.ProductID,
            s.ProductName,
            s.ProductNumber,
            s.Color,
            s.Size,
            s.StandardCost,
            s.ListPrice,
            s.SubcategoryName,
            s.CategoryName,
            s.SellStartDate,
            s.SellEndDate,
            s.DiscontinuedDate,
            @LoadDateTime,
            @OpenEndedDateTime,
            1,
            s.RowHash,
            s.SourceModifiedDate
        FROM stg.Product AS s
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dw.DimProduct AS d
            WHERE d.ProductID = s.ProductID
              AND d.IsCurrent = 1
        );

        SET @NewRowsInserted = @@ROWCOUNT;

        -----------------------------------------------------------------------
        -- Apply SCD Type 1 changes to unchanged current versions
        -----------------------------------------------------------------------

        UPDATE d
        SET
            d.ProductName = s.ProductName,
            d.ProductNumber = s.ProductNumber,
            d.SourceModifiedDate = s.SourceModifiedDate
        FROM dw.DimProduct AS d
        INNER JOIN stg.Product AS s
            ON d.ProductID = s.ProductID
        WHERE d.IsCurrent = 1
          AND d.RowHash = s.RowHash
          AND
          (
              d.ProductName <> s.ProductName
              OR d.ProductNumber <> s.ProductNumber
              OR d.SourceModifiedDate <> s.SourceModifiedDate
          );

        SET @Type1RowsUpdated = @@ROWCOUNT;

        -----------------------------------------------------------------------
        -- Expire current versions with SCD Type 2 changes
        -----------------------------------------------------------------------

        UPDATE d
        SET
            d.EffectiveEndDateTime = @LoadDateTime,
            d.IsCurrent = 0
        FROM dw.DimProduct AS d
        INNER JOIN #ChangedProducts AS c
            ON d.ProductID = c.ProductID
        WHERE d.IsCurrent = 1;

        SET @VersionsExpired = @@ROWCOUNT;

        -----------------------------------------------------------------------
        -- Insert the new current versions
        -----------------------------------------------------------------------

        INSERT INTO dw.DimProduct
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
            EffectiveStartDateTime,
            EffectiveEndDateTime,
            IsCurrent,
            RowHash,
            SourceModifiedDate
        )
        SELECT
            s.ProductID,
            s.ProductName,
            s.ProductNumber,
            s.Color,
            s.Size,
            s.StandardCost,
            s.ListPrice,
            s.SubcategoryName,
            s.CategoryName,
            s.SellStartDate,
            s.SellEndDate,
            s.DiscontinuedDate,
            @LoadDateTime,
            @OpenEndedDateTime,
            1,
            s.RowHash,
            s.SourceModifiedDate
        FROM stg.Product AS s
        INNER JOIN #ChangedProducts AS c
            ON s.ProductID = c.ProductID;

        SET @NewVersionsInserted = @@ROWCOUNT;

        -----------------------------------------------------------------------
        -- Calculate audit totals
        -----------------------------------------------------------------------

        SET @RowsInserted =
            @NewRowsInserted
            + @NewVersionsInserted;

        SET @RowsUpdated =
            @Type1RowsUpdated
            + @VersionsExpired;

        -----------------------------------------------------------------------
        -- Confirm the dimensional load
        -----------------------------------------------------------------------

        COMMIT TRANSACTION;

        -----------------------------------------------------------------------
        -- Mark the ETL execution as successful
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

    END TRY

    BEGIN CATCH

        -----------------------------------------------------------------------
        -- Roll back an incomplete dimensional load
        -----------------------------------------------------------------------

        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -----------------------------------------------------------------------
        -- Build the diagnostic error message
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
                [Status] = N'Failed',
                RowsRead = @RowsRead,
                RowsInserted = 0,
                RowsUpdated = 0,
                RowsRejected = 0,
                ErrorMessage = LEFT(@ErrorMessage, 4000)
            WHERE ExecutionID = @ExecutionID;
        END;

        -----------------------------------------------------------------------
        -- Propagate the original error
        -----------------------------------------------------------------------

        THROW;

    END CATCH;
END;
GO




USE AdventureWorks_EDW;
GO

SELECT
    s.name AS SchemaName,
    p.name AS ProcedureName,
    p.create_date AS CreatedAt,
    p.modify_date AS ModifiedAt
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s
    ON p.schema_id = s.schema_id
WHERE s.name = N'etl'
  AND p.name = N'LoadDimProduct';
GO