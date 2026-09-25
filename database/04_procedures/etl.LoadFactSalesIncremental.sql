/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : etl.LoadFactSalesIncremental
Script   : etl.LoadFactSalesIncremental.sql
Author   : Diego Suárez
Purpose  : Coordinate bounded sales delta extraction, fact application,
           and recoverable Header and Detail watermark advancement.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

CREATE OR ALTER PROCEDURE etl.LoadFactSalesIncremental
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @@TRANCOUNT <> 0
    BEGIN
        THROW 51200,
            'Sales incremental orchestration requires no existing transaction.',
            1;
    END;

    ---------------------------------------------------------------------------
    -- Execution and ownership variables
    ---------------------------------------------------------------------------
    DECLARE @ExecutionID BIGINT = NULL;
    DECLARE @ProcessName NVARCHAR(128) = N'etl.LoadFactSalesIncremental';
    DECLARE @LockResource NVARCHAR(255) = N'etl.LoadFactSalesIncremental';

    DECLARE @LockResult INT;
    DECLARE @ReleaseResult INT;
    DECLARE @LockAcquired BIT = 0;

    DECLARE @IsRetry BIT = 0;
    DECLARE @ActiveStreamCount INT = 0;
    DECLARE @BatchPersisted BIT = 0;
    DECLARE @FactCommitted BIT = 0;
    DECLARE @Finalized BIT = 0;

    DECLARE @RowsRead BIGINT = 0;
    DECLARE @RowsInserted BIGINT = 0;
    DECLARE @RowsUpdated BIGINT = 0;

    DECLARE @ErrorMessage NVARCHAR(4000);

    ---------------------------------------------------------------------------
    -- Coordinated watermark state
    ---------------------------------------------------------------------------
    DECLARE @Streams TABLE
    (
        StreamName VARCHAR(6) NOT NULL PRIMARY KEY,
        WatermarkID BIGINT NOT NULL,
        ProcessName NVARCHAR(128) NOT NULL,
        SourceObject NVARCHAR(256) NOT NULL,
        [Status] VARCHAR(20) NOT NULL,

        LowModifiedDate DATETIME2(7) NULL,
        LowBusinessKey BIGINT NULL,
        HighModifiedDate DATETIME2(7) NULL,
        HighBusinessKey BIGINT NULL,

        CurrentExecutionID BIGINT NULL,
        IsActive BIT NOT NULL DEFAULT (0)
    );

    ---------------------------------------------------------------------------
    -- Extraction parameters
    ---------------------------------------------------------------------------
    DECLARE @HeaderIsActive BIT = 0;
    DECLARE @DetailIsActive BIT = 0;

    DECLARE @HeaderLowModifiedDate DATETIME2(7) = NULL;
    DECLARE @HeaderLowBusinessKey BIGINT = NULL;
    DECLARE @HeaderHighModifiedDate DATETIME2(7) = NULL;
    DECLARE @HeaderHighBusinessKey BIGINT = NULL;

    DECLARE @DetailLowModifiedDate DATETIME2(7) = NULL;
    DECLARE @DetailLowBusinessKey BIGINT = NULL;
    DECLARE @DetailHighModifiedDate DATETIME2(7) = NULL;
    DECLARE @DetailHighBusinessKey BIGINT = NULL;

    BEGIN TRY

        -----------------------------------------------------------------------
        -- Acquire exclusive ownership across transaction boundaries
        -----------------------------------------------------------------------
        EXEC @LockResult = sys.sp_getapplock
            @Resource = @LockResource,
            @LockMode = 'Exclusive',
            @LockOwner = 'Session',
            @LockTimeout = 0,
            @DbPrincipal = 'public';

        IF @LockResult IS NULL OR @LockResult < 0
        BEGIN
            THROW 51201,
                'Sales incremental execution could not acquire its application lock.',
                1;
        END;

        SET @LockAcquired = 1;

        -----------------------------------------------------------------------
        -- Register parent execution after acquiring ownership
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
            @ProcessName,
            N'AdventureWorks2022.Sales.SalesOrderHeader + SalesOrderDetail',
            N'dw.FactSales',
            SUSER_SNAME()
        );

        SET @ExecutionID =
            CONVERT(BIGINT, SCOPE_IDENTITY());

        -----------------------------------------------------------------------
        -- Read both watermark controls under transaction locks
        -----------------------------------------------------------------------
        BEGIN TRANSACTION;

        INSERT INTO @Streams
        (
            StreamName,
            WatermarkID,
            ProcessName,
            SourceObject,
            [Status],
            LowModifiedDate,
            LowBusinessKey,
            HighModifiedDate,
            HighBusinessKey,
            CurrentExecutionID
        )
        SELECT
            s.StreamName,
            w.WatermarkID,
            w.ProcessName,
            w.SourceObject,
            w.[Status],
            w.LowModifiedDate,
            w.LowBusinessKey,
            w.HighModifiedDate,
            w.HighBusinessKey,
            w.CurrentExecutionID
        FROM audit.ETLWatermark AS w WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN
        (
            VALUES
            ('Header', N'etl.LoadFactSalesIncremental.Header'),
            ('Detail', N'etl.LoadFactSalesIncremental.Detail')
        ) AS s(StreamName, ProcessName)
            ON s.ProcessName = w.ProcessName;

        IF (SELECT COUNT(*) FROM @Streams) <> 2
        BEGIN
            THROW 51202,
                'Sales incremental execution requires both Header and Detail watermark controls.',
                1;
        END;

        -----------------------------------------------------------------------
        -- Validate source registration and execution state
        -----------------------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM @Streams
            WHERE SourceObject <>
                CASE StreamName
                    WHEN 'Header'
                        THEN N'AdventureWorks2022.Sales.SalesOrderHeader'
                    WHEN 'Detail'
                        THEN N'AdventureWorks2022.Sales.SalesOrderDetail'
                END
        )
        BEGIN
            THROW 51203,
                'A sales watermark control references an unexpected source.',
                1;
        END;

        IF EXISTS
        (
            SELECT 1 FROM @Streams
            WHERE [Status] = 'InProgress'
        )
        BEGIN
            THROW 51204,
                'A sales batch is InProgress. Verify execution ownership before explicit recovery.',
                1;
        END;

        IF EXISTS
        (
            SELECT 1 FROM @Streams
            WHERE [Status] NOT IN ('Ready', 'Failed')
        )
        BEGIN
            THROW 51205,
                'A sales watermark control has an unsupported status.',
                1;
        END;

        -----------------------------------------------------------------------
        -- Retry failed streams using their persisted boundaries
        -----------------------------------------------------------------------
        IF EXISTS
        (
            SELECT 1 FROM @Streams
            WHERE [Status] = 'Failed'
        )
        BEGIN
            SET @IsRetry = 1;

            IF
            (
                SELECT COUNT(DISTINCT CurrentExecutionID)
                FROM @Streams
                WHERE [Status] = 'Failed'
            ) <> 1
            BEGIN
                THROW 51206,
                    'Failed sales streams must reference the same previous execution.',
                    1;
            END;

            UPDATE @Streams
            SET IsActive =
                CASE
                    WHEN [Status] = 'Failed' THEN 1
                    ELSE 0
                END;
        END;

        -----------------------------------------------------------------------
        -- Capture new source boundaries
        -----------------------------------------------------------------------
        IF @IsRetry = 0
        BEGIN
            SELECT TOP (1)
                @HeaderHighModifiedDate =
                    CONVERT(DATETIME2(7), ModifiedDate),
                @HeaderHighBusinessKey =
                    CONVERT(BIGINT, SalesOrderID)
            FROM AdventureWorks2022.Sales.SalesOrderHeader
            ORDER BY ModifiedDate DESC, SalesOrderID DESC;

            SELECT TOP (1)
                @DetailHighModifiedDate =
                    CONVERT(DATETIME2(7), ModifiedDate),
                @DetailHighBusinessKey =
                    CONVERT(BIGINT, SalesOrderDetailID)
            FROM AdventureWorks2022.Sales.SalesOrderDetail
            ORDER BY ModifiedDate DESC, SalesOrderDetailID DESC;

            UPDATE @Streams
            SET
                HighModifiedDate =
                    CASE StreamName
                        WHEN 'Header' THEN @HeaderHighModifiedDate
                        WHEN 'Detail' THEN @DetailHighModifiedDate
                    END,
                HighBusinessKey =
                    CASE StreamName
                        WHEN 'Header' THEN @HeaderHighBusinessKey
                        WHEN 'Detail' THEN @DetailHighBusinessKey
                    END;
        END;

        -----------------------------------------------------------------------
        -- Determine active source streams
        -----------------------------------------------------------------------
        IF @IsRetry = 0
        BEGIN
            UPDATE @Streams
            SET IsActive =
                CASE
                    WHEN HighModifiedDate IS NOT NULL
                     AND HighBusinessKey IS NOT NULL
                     AND
                     (
                         LowModifiedDate IS NULL
                         OR HighModifiedDate > LowModifiedDate
                         OR
                         (
                             HighModifiedDate = LowModifiedDate
                             AND HighBusinessKey > LowBusinessKey
                         )
                     )
                    THEN 1
                    ELSE 0
                END;
        END;

        UPDATE @Streams
        SET
            HighModifiedDate = NULL,
            HighBusinessKey = NULL
        WHERE IsActive = 0;

        SELECT
            @ActiveStreamCount = COUNT(*)
        FROM @Streams
        WHERE IsActive = 1;

        -----------------------------------------------------------------------
        -- Persist ownership of all active streams
        -----------------------------------------------------------------------
        IF @ActiveStreamCount > 0
        BEGIN
            UPDATE w
            SET
                HighModifiedDate = s.HighModifiedDate,
                HighBusinessKey = s.HighBusinessKey,
                [Status] = 'InProgress',
                CurrentExecutionID = @ExecutionID,
                UpdatedAt = SYSUTCDATETIME()
            FROM audit.ETLWatermark AS w
            INNER JOIN @Streams AS s
                ON s.WatermarkID = w.WatermarkID
               AND s.ProcessName = w.ProcessName
            WHERE s.IsActive = 1
              AND w.[Status] = s.[Status]
              AND
              (
                  w.CurrentExecutionID = s.CurrentExecutionID
                  OR
                  (
                      w.CurrentExecutionID IS NULL
                      AND s.CurrentExecutionID IS NULL
                  )
              );

            IF @@ROWCOUNT <> @ActiveStreamCount
            BEGIN
                THROW 51207,
                    'Sales batch acquisition did not update every active watermark.',
                    1;
            END;
        END;

        COMMIT TRANSACTION;

        IF @ActiveStreamCount > 0
            SET @BatchPersisted = 1;

        -----------------------------------------------------------------------
        -- Execute the selected sales batch
        -----------------------------------------------------------------------
        SELECT
            @HeaderIsActive = IsActive,
            @HeaderLowModifiedDate = LowModifiedDate,
            @HeaderLowBusinessKey = LowBusinessKey,
            @HeaderHighModifiedDate = HighModifiedDate,
            @HeaderHighBusinessKey = HighBusinessKey
        FROM @Streams
        WHERE StreamName = 'Header';

        SELECT
            @DetailIsActive = IsActive,
            @DetailLowModifiedDate = LowModifiedDate,
            @DetailLowBusinessKey = LowBusinessKey,
            @DetailHighModifiedDate = HighModifiedDate,
            @DetailHighBusinessKey = HighBusinessKey
        FROM @Streams
        WHERE StreamName = 'Detail';

        EXEC etl.LoadSalesOrderLineDeltaStage
            @HeaderIsActive = @HeaderIsActive,
            @DetailIsActive = @DetailIsActive,
            @HeaderLowModifiedDate = @HeaderLowModifiedDate,
            @HeaderLowBusinessKey = @HeaderLowBusinessKey,
            @HeaderHighModifiedDate = @HeaderHighModifiedDate,
            @HeaderHighBusinessKey = @HeaderHighBusinessKey,
            @DetailLowModifiedDate = @DetailLowModifiedDate,
            @DetailLowBusinessKey = @DetailLowBusinessKey,
            @DetailHighModifiedDate = @DetailHighModifiedDate,
            @DetailHighBusinessKey = @DetailHighBusinessKey;

        SELECT
            @RowsRead = COUNT_BIG(*)
        FROM stg.SalesOrderLineDelta;

        IF @ActiveStreamCount > 0
        BEGIN
            EXEC etl.LoadFactSalesDelta
                @RowsRead = @RowsRead OUTPUT,
                @RowsInserted = @RowsInserted OUTPUT,
                @RowsUpdated = @RowsUpdated OUTPUT;

            SET @FactCommitted = 1;
        END;

        -----------------------------------------------------------------------
        -- Finalize active watermarks and parent audit atomically
        -----------------------------------------------------------------------
        BEGIN TRANSACTION;

        UPDATE w
        SET
            LowModifiedDate = s.HighModifiedDate,
            LowBusinessKey = s.HighBusinessKey,
            HighModifiedDate = NULL,
            HighBusinessKey = NULL,
            [Status] = 'Ready',
            LastSuccessfulExecutionID = @ExecutionID,
            CurrentExecutionID = NULL,
            UpdatedAt = SYSUTCDATETIME()
        FROM audit.ETLWatermark AS w
        INNER JOIN @Streams AS s
            ON s.WatermarkID = w.WatermarkID
           AND s.ProcessName = w.ProcessName
        WHERE s.IsActive = 1
          AND w.[Status] = 'InProgress'
          AND w.CurrentExecutionID = @ExecutionID
          AND w.HighModifiedDate = s.HighModifiedDate
          AND w.HighBusinessKey = s.HighBusinessKey
          AND NOT EXISTS
          (
              SELECT w.LowModifiedDate, w.LowBusinessKey
              EXCEPT
              SELECT s.LowModifiedDate, s.LowBusinessKey
          );

        IF @@ROWCOUNT <> @ActiveStreamCount
        BEGIN
            THROW 51208,
                'Sales batch finalization found changed ownership or watermark boundaries.',
                1;
        END;

        UPDATE audit.ETLExecutionLog
        SET
            EndTime = SYSUTCDATETIME(),
            [Status] = N'Succeeded',
            RowsRead = @RowsRead,
            RowsInserted = @RowsInserted,
            RowsUpdated = @RowsUpdated,
            RowsRejected = 0,
            ErrorMessage = NULL
        WHERE ExecutionID = @ExecutionID
          AND ProcessName = @ProcessName;

        IF @@ROWCOUNT <> 1
        BEGIN
            THROW 51209,
                'Sales batch finalization could not update its parent audit entry.',
                1;
        END;

        COMMIT TRANSACTION;

        SET @Finalized = 1;

        -----------------------------------------------------------------------
        -- Release execution ownership after successful finalization
        -----------------------------------------------------------------------
        EXEC @ReleaseResult = sys.sp_releaseapplock
            @Resource = @LockResource,
            @LockOwner = 'Session',
            @DbPrincipal = 'public';

        IF @ReleaseResult IS NULL OR @ReleaseResult < 0
        BEGIN
            THROW 51210,
                'Sales batch finalized, but its application lock could not be released.',
                1;
        END;

        SET @LockAcquired = 0;

    END TRY

    BEGIN CATCH

        -----------------------------------------------------------------------
        -- Preserve the original failure context
        -----------------------------------------------------------------------
        SET @ErrorMessage =
            CONCAT
            (
                N'ErrorNumber: ', ERROR_NUMBER(),
                N'; ErrorProcedure: ',
                COALESCE(ERROR_PROCEDURE(), N'Ad hoc batch'),
                N'; ErrorLine: ', ERROR_LINE(),
                N'; FactCommitted: ', @FactCommitted,
                N'; BatchFinalized: ', @Finalized,
                N'; ErrorMessage: ', ERROR_MESSAGE()
            );

        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        IF @FactCommitted = 0
        BEGIN
            SET @RowsInserted = 0;
            SET @RowsUpdated = 0;
        END;

        -----------------------------------------------------------------------
        -- Record owned batch failure and parent audit together
        -----------------------------------------------------------------------
        BEGIN TRY

            IF @Finalized = 0 AND @ExecutionID IS NOT NULL
            BEGIN
                BEGIN TRANSACTION;

                IF @BatchPersisted = 1
                BEGIN
                    UPDATE w
                    SET
                        [Status] = 'Failed',
                        UpdatedAt = SYSUTCDATETIME()
                    FROM audit.ETLWatermark AS w
                    INNER JOIN @Streams AS s
                        ON s.WatermarkID = w.WatermarkID
                       AND s.ProcessName = w.ProcessName
                    WHERE s.IsActive = 1
                      AND w.[Status] = 'InProgress'
                      AND w.CurrentExecutionID = @ExecutionID;

                    IF @@ROWCOUNT <> @ActiveStreamCount
                    BEGIN
                        THROW 51211,
                            'Failure handling could not retain ownership of every active sales stream.',
                            1;
                    END;
                END;

                UPDATE audit.ETLExecutionLog
                SET
                    EndTime = SYSUTCDATETIME(),
                    [Status] = N'Failed',
                    RowsRead = @RowsRead,
                    RowsInserted = @RowsInserted,
                    RowsUpdated = @RowsUpdated,
                    RowsRejected = 0,
                    ErrorMessage = LEFT(@ErrorMessage, 4000)
                WHERE ExecutionID = @ExecutionID
                  AND ProcessName = @ProcessName;

                IF @@ROWCOUNT <> 1
                BEGIN
                    THROW 51212,
                        'Failure handling could not update the parent sales audit entry.',
                        1;
                END;

                COMMIT TRANSACTION;
            END;

        END TRY

        BEGIN CATCH

            DECLARE @FailureHandlingMessage NVARCHAR(2048);

            SET @FailureHandlingMessage =
                LEFT
                (
                    CONCAT
                    (
                        N'Failure handling error ', ERROR_NUMBER(),
                        N': ', ERROR_MESSAGE(),
                        N'; Original failure: ', @ErrorMessage
                    ),
                    2048
                );

            IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;

            IF @LockAcquired = 1
            BEGIN
                EXEC @ReleaseResult = sys.sp_releaseapplock
                    @Resource = @LockResource,
                    @LockOwner = 'Session',
                    @DbPrincipal = 'public';

                IF @ReleaseResult >= 0
                    SET @LockAcquired = 0;

                SET @FailureHandlingMessage =
                    LEFT
                    (
                        CONCAT
                        (
                            N'Application lock release code: ',
                            COALESCE(CONVERT(NVARCHAR(12), @ReleaseResult), N'NULL'),
                            N'; ', @FailureHandlingMessage
                        ),
                        2048
                    );
            END;

            THROW 51213, @FailureHandlingMessage, 1;

        END CATCH;

        -----------------------------------------------------------------------
        -- Release ownership after recording the failure
        -----------------------------------------------------------------------
        IF @LockAcquired = 1
        BEGIN
            EXEC @ReleaseResult = sys.sp_releaseapplock
                @Resource = @LockResource,
                @LockOwner = 'Session',
                @DbPrincipal = 'public';

            IF @ReleaseResult IS NULL OR @ReleaseResult < 0
            BEGIN
                SET @ErrorMessage =
                    LEFT
                    (
                        CONCAT
                        (
                            N'Application lock release failed after error handling.',
                            N' Original failure: ', @ErrorMessage
                        ),
                        2048
                    );

                THROW 51214, @ErrorMessage, 1;
            END;

            SET @LockAcquired = 0;
        END;

        THROW;

    END CATCH;
END;
GO
