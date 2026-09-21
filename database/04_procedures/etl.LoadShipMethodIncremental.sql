/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : etl.LoadShipMethodIncremental
Script   : etl.LoadShipMethodIncremental.sql
Author   : Diego Suárez
Purpose  : Orchestrate incremental ShipMethod loading using a composite LOW
           watermark, a persisted HIGH watermark batch boundary, and retryable
           failed batches.
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

    DECLARE @WatermarkStatus VARCHAR(20) = NULL;

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
            CONVERT
            (
                BIGINT,
                SCOPE_IDENTITY()
            );

        /*
        =======================================================================
        3. ACQUIRE WATERMARK STATE
        =======================================================================
        */

        BEGIN TRANSACTION;

        SELECT
            @LowModifiedDate = LowModifiedDate,
            @LowBusinessKey = LowBusinessKey,
            @HighModifiedDate = HighModifiedDate,
            @HighBusinessKey = HighBusinessKey,
            @WatermarkStatus = [Status]
        FROM audit.ETLWatermark WITH (UPDLOCK, HOLDLOCK)
        WHERE ProcessName = @ProcessName;

        -----------------------------------------------------------------------
        -- Watermark configuration must exist.
        -----------------------------------------------------------------------

        IF @WatermarkStatus IS NULL
        BEGIN
            THROW 50010,
                'Watermark configuration was not found for the incremental process.',
                1;
        END;

        -----------------------------------------------------------------------
        -- Another execution already owns an active batch.
        -----------------------------------------------------------------------

        IF @WatermarkStatus = 'InProgress'
        BEGIN
            THROW 50011,
                'Watermark process is already in progress.',
                1;
        END;

        -----------------------------------------------------------------------
        -- Only Ready and Failed are valid entry states.
        -----------------------------------------------------------------------

        IF @WatermarkStatus NOT IN ('Ready', 'Failed')
        BEGIN
            THROW 50013,
                'Watermark process is in an unsupported state.',
                1;
        END;

        /*
        =======================================================================
        4. DETERMINE BATCH HIGH WATERMARK
        =======================================================================

        Ready:
            Capture a new HIGH boundary from the source.

        Failed:
            Reuse the HIGH boundary persisted by the failed batch.
        =======================================================================
        */

        IF @WatermarkStatus = 'Ready'
        BEGIN

            -------------------------------------------------------------------
            -- Clear local HIGH variables before capturing a new source maximum.
            -------------------------------------------------------------------

            SET @HighModifiedDate = NULL;
            SET @HighBusinessKey = NULL;

            SELECT TOP (1)
                @HighModifiedDate =
                    CONVERT
                    (
                        DATETIME2(7),
                        sm.ModifiedDate
                    ),

                @HighBusinessKey =
                    CONVERT
                    (
                        BIGINT,
                        sm.ShipMethodID
                    )

            FROM AdventureWorks2022.Purchasing.ShipMethod AS sm

            ORDER BY
                sm.ModifiedDate DESC,
                sm.ShipMethodID DESC;

        END;
        ELSE
        BEGIN

            -------------------------------------------------------------------
            -- Failed batch retry.
            -- HIGH must already exist and must NOT be recaptured from source.
            -------------------------------------------------------------------

            IF
            (
                @HighModifiedDate IS NULL
                OR @HighBusinessKey IS NULL
            )
            BEGIN
                THROW 50014,
                    'Failed watermark state does not contain a persisted HIGH boundary.',
                    1;
            END;

        END;

        /*
        =======================================================================
        5. HANDLE NO-CHANGE BATCH
        =======================================================================

        No-change detection applies only to a new Ready batch.

        A Failed batch must always retry its previously frozen HIGH boundary.
        =======================================================================
        */

        IF
        (
            @WatermarkStatus = 'Ready'
            AND
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
        )
        BEGIN

            -------------------------------------------------------------------
            -- Staging represents the current incremental batch.
            -- No source delta means staging must be empty before releasing
            -- the watermark lock.
            -------------------------------------------------------------------

            TRUNCATE TABLE stg.ShipMethod;

            COMMIT TRANSACTION;

            -------------------------------------------------------------------
            -- Register successful no-op execution.
            -------------------------------------------------------------------

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

        /*
        =======================================================================
        6. FREEZE BATCH / START OR RETRY
        =======================================================================

        Ready:
            Persist the newly captured HIGH.

        Failed:
            Persist the same HIGH again while replacing CurrentExecutionID
            with the retry execution.
        =======================================================================
        */

        UPDATE audit.ETLWatermark
        SET
            HighModifiedDate = @HighModifiedDate,
            HighBusinessKey = @HighBusinessKey,
            [Status] = 'InProgress',
            CurrentExecutionID = @ExecutionID,
            UpdatedAt = SYSUTCDATETIME()
        WHERE ProcessName = @ProcessName;

        IF @@ROWCOUNT <> 1
        BEGIN
            THROW 50015,
                'Watermark batch acquisition failed.',
                1;
        END;

        COMMIT TRANSACTION;

        /*
        =======================================================================
        7. LOAD INCREMENTAL STAGING BATCH
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
        8. APPLY DIMENSIONAL PROCESSING
        =======================================================================
        */

        EXEC etl.LoadDimShipMethod;

        /*
        =======================================================================
        9. COMMIT WATERMARK PROGRESS
        =======================================================================

        LOW advances only after the complete batch succeeds.

        HIGH is cleared because no batch remains pending.
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

        WHERE
            ProcessName = @ProcessName
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
        10. MARK PARENT EXECUTION AS SUCCESSFUL
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
        11. ROLLBACK ACTIVE TRANSACTION
        =======================================================================
        */

        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        /*
        =======================================================================
        12. BUILD ERROR MESSAGE
        =======================================================================
        */

        SET @ErrorMessage =
            CONCAT
            (
                N'ErrorNumber: ',
                ERROR_NUMBER(),

                N'; ErrorProcedure: ',
                COALESCE
                (
                    ERROR_PROCEDURE(),
                    N'Ad hoc batch'
                ),

                N'; ErrorLine: ',
                ERROR_LINE(),

                N'; ErrorMessage: ',
                ERROR_MESSAGE()
            );

        /*
        =======================================================================
        13. PRESERVE FAILED BATCH BOUNDARY
        =======================================================================

        If HIGH was already frozen for this execution, LOW remains unchanged
        and HIGH is retained so the next execution retries the exact same batch.
        =======================================================================
        */

        IF @ExecutionID IS NOT NULL
        BEGIN

            UPDATE audit.ETLWatermark
            SET
                [Status] = 'Failed',
                UpdatedAt = SYSUTCDATETIME()
            WHERE
                ProcessName = @ProcessName
                AND CurrentExecutionID = @ExecutionID
                AND HighModifiedDate IS NOT NULL
                AND HighBusinessKey IS NOT NULL;

            /*
            ===================================================================
            14. MARK PARENT EXECUTION AS FAILED
            ===================================================================
            */

            UPDATE audit.ETLExecutionLog
            SET
                EndTime = SYSUTCDATETIME(),
                [Status] = N'Failed',
                RowsRead = @RowsRead,
                RowsInserted = 0,
                RowsUpdated = 0,
                RowsRejected = 0,
                ErrorMessage =
                    LEFT
                    (
                        @ErrorMessage,
                        4000
                    )
            WHERE ExecutionID = @ExecutionID;

        END;

        THROW;

    END CATCH;
END;
GO

/*
===============================================================================
15. VALIDATE PROCEDURE CREATION
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
