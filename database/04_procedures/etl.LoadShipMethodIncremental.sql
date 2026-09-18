/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : etl.LoadShipMethodIncremental
Script   : etl.LoadShipMethodIncremental.sql
Author   : Diego Suárez
Purpose  : Orchestrate incremental ShipMethod loading using a composite LOW
           watermark and a persisted HIGH watermark batch boundary.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE OR ALTER PROCEDURE
===============================================================================
*/

CREATE OR ALTER PROCEDURE etl.LoadShipMethodIncremental
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    ---------------------------------------------------------------------------
    -- Process metadata
    ---------------------------------------------------------------------------
    DECLARE @ProcessName NVARCHAR(128) =
        N'etl.LoadShipMethodIncremental';

    DECLARE @SourceObject NVARCHAR(256) =
        N'AdventureWorks2022.Purchasing.ShipMethod';

    DECLARE @TargetObject NVARCHAR(256) =
        N'dw.DimShipMethod';

    ---------------------------------------------------------------------------
    -- Execution state
    ---------------------------------------------------------------------------
    DECLARE @ExecutionID BIGINT = NULL;
    DECLARE @RowsRead BIGINT = 0;

    DECLARE @LowModifiedDate DATETIME2(7) = NULL;
    DECLARE @LowBusinessKey BIGINT = NULL;

    DECLARE @HighModifiedDate DATETIME2(7) = NULL;
    DECLARE @HighBusinessKey BIGINT = NULL;

    DECLARE @WatermarkStatus VARCHAR(20);
    DECLARE @ErrorMessage NVARCHAR(4000);

    BEGIN TRY

        /*
        =======================================================================
        2. REGISTER PARENT ETL EXECUTION
        =======================================================================
        */

        INSERT INTO audit.ETLExecutionLog
        (
            ProcessName,
            SourceObject,
            TargetObject,
            ExecutedBy
        )
        VALUES
        (
            @ProcessName,
            @SourceObject,
            @TargetObject,
            SUSER_SNAME()
        );

        SET @ExecutionID =
            CONVERT(BIGINT, SCOPE_IDENTITY());

        /*
        =======================================================================
        3. ACQUIRE AND FREEZE BATCH BOUNDARY
        =======================================================================
        */

        BEGIN TRANSACTION;

        SELECT
            @LowModifiedDate = LowModifiedDate,
            @LowBusinessKey = LowBusinessKey,
            @WatermarkStatus = [Status]
        FROM audit.ETLWatermark WITH (UPDLOCK, HOLDLOCK)
        WHERE ProcessName = @ProcessName;

        IF @WatermarkStatus IS NULL
        BEGIN
            THROW 50010,
                'Watermark configuration was not found for the incremental process.',
                1;
        END;

        IF @WatermarkStatus <> 'Ready'
        BEGIN
            THROW 50011,
                'Watermark process is not in Ready state.',
                1;
        END;

        -----------------------------------------------------------------------
        -- Capture the maximum composite position currently visible in source
        -----------------------------------------------------------------------

        SELECT TOP (1)
            @HighModifiedDate =
                CONVERT(DATETIME2(7), sm.ModifiedDate),
            @HighBusinessKey =
                CONVERT(BIGINT, sm.ShipMethodID)
        FROM AdventureWorks2022.Purchasing.ShipMethod AS sm
        ORDER BY
            sm.ModifiedDate DESC,
            sm.ShipMethodID DESC;

        /*
        =======================================================================
        4. HANDLE NO-CHANGE BATCH
        =======================================================================
        */

        IF
        (
            @HighModifiedDate IS NULL

            OR
            (
                @LowModifiedDate IS NOT NULL
                AND NOT
                (
                    @HighModifiedDate > @LowModifiedDate
                    OR
                    (
                        @HighModifiedDate = @LowModifiedDate
                        AND @HighBusinessKey > @LowBusinessKey
                    )
                )
            )
        )
        BEGIN

            ---------------------------------------------------------------------------
            -- Staging represents the current incremental batch.
            -- No source delta means staging must be empty before releasing the
            -- watermark lock.
            ---------------------------------------------------------------------------

            TRUNCATE TABLE stg.ShipMethod;

            COMMIT TRANSACTION;

            UPDATE audit.ETLExecutionLog
            SET
                EndTime = SYSUTCDATETIME(),
                [Status] = N'Succeeded',
                RowsRead = 0,
                RowsInserted = 0,
                RowsUpdated = 0,
                RowsRejected = 0,
                ErrorMessage = NULL
            WHERE ExecutionID = @ExecutionID;

            RETURN;
        END;
        -----------------------------------------------------------------------
        -- Freeze HIGH before processing any source rows
        -----------------------------------------------------------------------

        UPDATE audit.ETLWatermark
        SET
            HighModifiedDate = @HighModifiedDate,
            HighBusinessKey = @HighBusinessKey,
            [Status] = 'InProgress',
            CurrentExecutionID = @ExecutionID,
            UpdatedAt = SYSUTCDATETIME()
        WHERE ProcessName = @ProcessName;

        COMMIT TRANSACTION;

        /*
        =======================================================================
        5. LOAD INCREMENTAL STAGING BATCH
        =======================================================================
        */

        EXEC etl.LoadShipMethodStage
            @LowModifiedDate = @LowModifiedDate,
            @LowBusinessKey = @LowBusinessKey,
            @HighModifiedDate = @HighModifiedDate,
            @HighBusinessKey = @HighBusinessKey;

        SELECT
            @RowsRead = COUNT_BIG(*)
        FROM stg.ShipMethod;

        /*
        =======================================================================
        6. APPLY DIMENSIONAL PROCESSING
        =======================================================================
        */

        EXEC etl.LoadDimShipMethod;

        /*
        =======================================================================
        7. COMMIT WATERMARK PROGRESS
        =======================================================================
        */

        BEGIN TRANSACTION;

        UPDATE audit.ETLWatermark
        SET
            LowModifiedDate = HighModifiedDate,
            LowBusinessKey = HighBusinessKey,
            HighModifiedDate = NULL,
            HighBusinessKey = NULL,
            [Status] = 'Ready',
            LastSuccessfulExecutionID = @ExecutionID,
            CurrentExecutionID = NULL,
            UpdatedAt = SYSUTCDATETIME()
        WHERE ProcessName = @ProcessName
          AND CurrentExecutionID = @ExecutionID
          AND [Status] = 'InProgress';

        IF @@ROWCOUNT <> 1
        BEGIN
            THROW 50012,
                'Watermark finalization failed because the expected in-progress state was not found.',
                1;
        END;

        COMMIT TRANSACTION;

        /*
        =======================================================================
        8. MARK PARENT EXECUTION AS SUCCESSFUL
        =======================================================================
        */

        UPDATE audit.ETLExecutionLog
        SET
            EndTime = SYSUTCDATETIME(),
            [Status] = N'Succeeded',
            RowsRead = @RowsRead,
            RowsInserted = 0,
            RowsUpdated = 0,
            RowsRejected = 0,
            ErrorMessage = NULL
        WHERE ExecutionID = @ExecutionID;

    END TRY

    BEGIN CATCH

        /*
        =======================================================================
        9. ROLLBACK ACTIVE TRANSACTION
        =======================================================================
        */

        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        /*
        =======================================================================
        10. BUILD ERROR MESSAGE
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
        11. PRESERVE FAILED BATCH BOUNDARY
        =======================================================================
        */

        IF @ExecutionID IS NOT NULL
        BEGIN

            UPDATE audit.ETLWatermark
            SET
                [Status] = 'Failed',
                UpdatedAt = SYSUTCDATETIME()
            WHERE ProcessName = @ProcessName
              AND CurrentExecutionID = @ExecutionID
              AND HighModifiedDate IS NOT NULL
              AND HighBusinessKey IS NOT NULL;

            UPDATE audit.ETLExecutionLog
            SET
                EndTime = SYSUTCDATETIME(),
                [Status] = N'Failed',
                RowsRead = @RowsRead,
                RowsInserted = 0,
                RowsUpdated = 0,
                RowsRejected = 0,
                ErrorMessage =
                    LEFT(@ErrorMessage, 4000)
            WHERE ExecutionID = @ExecutionID;
        END;

        THROW;

    END CATCH;
END;
GO

/*
===============================================================================
12. VALIDATE PROCEDURE CREATION
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SELECT
    s.name AS SchemaName,
    p.name AS ProcedureName,
    p.create_date AS CreateDate,
    p.modify_date AS ModifyDate
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s
    ON p.schema_id = s.schema_id
WHERE
    s.name = N'etl'
    AND p.name = N'LoadShipMethodIncremental';
GO
