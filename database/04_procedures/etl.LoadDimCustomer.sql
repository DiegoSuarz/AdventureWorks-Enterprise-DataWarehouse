/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Author   : Diego Suárez
Object   : etl.LoadDimCustomer
Purpose  : Load dw.DimCustomer from stg.Customer using SCD Type 1 behavior.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

CREATE OR ALTER PROCEDURE etl.LoadDimCustomer
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    ---------------------------------------------------------------------------
    -- Execution variables
    ---------------------------------------------------------------------------

    DECLARE @executionId BIGINT = NULL;
    DECLARE @loadDateTime DATETIME2(7) = SYSUTCDATETIME();

    DECLARE @rowsRead BIGINT = 0;
    DECLARE @rowsInserted BIGINT = 0;
    DECLARE @rowsUpdated BIGINT = 0;

    DECLARE @errorMessage NVARCHAR(4000);

    DECLARE @openEndedDateTime DATETIME2(7) =
        CONVERT
        (
            DATETIME2(7),
            '9999-12-31 23:59:59.9999999'
        );

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
            N'etl.LoadDimCustomer',
            N'stg.Customer',
            N'dw.DimCustomer',
            SUSER_SNAME()
        );

        SET @executionId =
            CONVERT(BIGINT, SCOPE_IDENTITY());

        -----------------------------------------------------------------------
        -- Capture staging row count
        -----------------------------------------------------------------------

        SELECT
            @rowsRead = COUNT_BIG(*)
        FROM stg.Customer;

        -----------------------------------------------------------------------
        -- Start dimensional load
        -----------------------------------------------------------------------

        BEGIN TRANSACTION;

        -----------------------------------------------------------------------
        -- Insert new customers
        -----------------------------------------------------------------------

        INSERT INTO dw.DimCustomer
        (
            CustomerID,
            CustomerType,
            CustomerName,
            FirstName,
            MiddleName,
            LastName,
            StoreName,
            AccountNumber,
            EffectiveStartDateTime,
            EffectiveEndDateTime,
            IsCurrent,
            RowHash,
            SourceModifiedDate
        )
        SELECT
            s.CustomerID,
            s.CustomerType,
            s.CustomerName,
            s.FirstName,
            s.MiddleName,
            s.LastName,
            s.StoreName,
            s.AccountNumber,
            @loadDateTime,
            @openEndedDateTime,
            1,
            s.RowHash,
            s.SourceModifiedDate
        FROM stg.Customer AS s
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dw.DimCustomer AS d
            WHERE d.CustomerID = s.CustomerID
              AND d.IsCurrent = 1
        );

        SET @rowsInserted = @@ROWCOUNT;

        -----------------------------------------------------------------------
        -- Apply SCD Type 1 changes
        -----------------------------------------------------------------------

        UPDATE d
        SET
            d.CustomerType = s.CustomerType,
            d.CustomerName = s.CustomerName,
            d.FirstName = s.FirstName,
            d.MiddleName = s.MiddleName,
            d.LastName = s.LastName,
            d.StoreName = s.StoreName,
            d.AccountNumber = s.AccountNumber,
            d.RowHash = s.RowHash,
            d.SourceModifiedDate = s.SourceModifiedDate
        FROM dw.DimCustomer AS d
        INNER JOIN stg.Customer AS s
            ON d.CustomerID = s.CustomerID
        WHERE d.IsCurrent = 1
          AND d.RowHash <> s.RowHash;

        SET @rowsUpdated = @@ROWCOUNT;

        -----------------------------------------------------------------------
        -- Confirm dimensional load
        -----------------------------------------------------------------------

        COMMIT TRANSACTION;

        -----------------------------------------------------------------------
        -- Mark execution as successful
        -----------------------------------------------------------------------

        UPDATE audit.ETLExecutionLog
        SET
            EndTime = SYSUTCDATETIME(),
            [Status] = N'Succeeded',
            RowsRead = @rowsRead,
            RowsInserted = @rowsInserted,
            RowsUpdated = @rowsUpdated,
            RowsRejected = 0,
            ErrorMessage = NULL
        WHERE ExecutionID = @executionId;

    END TRY

    BEGIN CATCH

        -----------------------------------------------------------------------
        -- Roll back incomplete dimensional load
        -----------------------------------------------------------------------

        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -----------------------------------------------------------------------
        -- Build diagnostic error message
        -----------------------------------------------------------------------

        SET @errorMessage =
            CONCAT
            (
                N'ErrorNumber: ', ERROR_NUMBER(),
                N'; ErrorProcedure: ',
                COALESCE(ERROR_PROCEDURE(), N'Ad hoc batch'),
                N'; ErrorLine: ', ERROR_LINE(),
                N'; ErrorMessage: ', ERROR_MESSAGE()
            );

        -----------------------------------------------------------------------
        -- Mark execution as failed
        -----------------------------------------------------------------------

        IF @executionId IS NOT NULL
        BEGIN
            UPDATE audit.ETLExecutionLog
            SET
                EndTime = SYSUTCDATETIME(),
                [Status] = N'Failed',
                RowsRead = @rowsRead,
                RowsInserted = 0,
                RowsUpdated = 0,
                RowsRejected = 0,
                ErrorMessage = LEFT(@errorMessage, 4000)
            WHERE ExecutionID = @executionId;
        END;

        THROW;

    END CATCH;
END;
GO