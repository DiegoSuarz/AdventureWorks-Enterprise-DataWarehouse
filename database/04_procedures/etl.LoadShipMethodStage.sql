/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : etl.LoadShipMethodStage
Script   : etl.LoadShipMethodStage.sql
Author   : Diego Suárez
Purpose  : Loads the incremental ShipMethod batch defined by composite LOW and
           HIGH watermark boundaries into stg.ShipMethod.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE OR ALTER PROCEDURE
===============================================================================
*/

CREATE OR ALTER PROCEDURE etl.LoadShipMethodStage
    @LowModifiedDate DATETIME2(7) = NULL,
    @LowBusinessKey BIGINT = NULL,
    @HighModifiedDate DATETIME2(7),
    @HighBusinessKey BIGINT
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

    /*
    ===========================================================================
    2. VALIDATE WATERMARK BOUNDARIES
    ===========================================================================
    */

    IF
    (
        (
            @LowModifiedDate IS NULL
            AND @LowBusinessKey IS NOT NULL
        )
        OR
        (
            @LowModifiedDate IS NOT NULL
            AND @LowBusinessKey IS NULL
        )
    )
    BEGIN
        THROW 50001,
            'LOW watermark components must both be NULL or both be NOT NULL.',
            1;
    END;

    IF
    (
        @HighModifiedDate IS NULL
        OR @HighBusinessKey IS NULL
    )
    BEGIN
        THROW 50002,
            'HIGH watermark components must both be NOT NULL.',
            1;
    END;

    IF
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
    BEGIN
        THROW 50003,
            'HIGH watermark must be strictly greater than LOW watermark.',
            1;
    END;

    BEGIN TRY

        /*
        =======================================================================
        3. REGISTER ETL EXECUTION
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
            N'etl.LoadShipMethodStage',
            N'AdventureWorks2022.Purchasing.ShipMethod',
            N'stg.ShipMethod',
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
        4. CAPTURE INCREMENTAL SOURCE ROW COUNT
        =======================================================================
        */

        SELECT
            @RowsRead = COUNT_BIG(*)
        FROM AdventureWorks2022.Purchasing.ShipMethod AS sm
        WHERE
        (
            @LowModifiedDate IS NULL

            OR sm.ModifiedDate > @LowModifiedDate

            OR
            (
                sm.ModifiedDate = @LowModifiedDate
                AND sm.ShipMethodID > @LowBusinessKey
            )
        )
        AND
        (
            sm.ModifiedDate < @HighModifiedDate

            OR
            (
                sm.ModifiedDate = @HighModifiedDate
                AND sm.ShipMethodID <= @HighBusinessKey
            )
        );

        /*
        =======================================================================
        5. START INCREMENTAL STAGING LOAD
        =======================================================================
        */

        BEGIN TRANSACTION;

        TRUNCATE TABLE stg.ShipMethod;

        /*
        =======================================================================
        6. LOAD INCREMENTAL SHIPMETHOD BATCH
        =======================================================================
        */

        INSERT INTO stg.ShipMethod
        (
            ShipMethodID,
            ShipMethodName,
            ShipBase,
            ShipRate,
            SourceModifiedDate,
            ExtractedAt,
            RowHash
        )
        SELECT
            sm.ShipMethodID,

            -------------------------------------------------------------------
            -- Descriptive attributes
            -------------------------------------------------------------------
            NULLIF
            (
                LTRIM(RTRIM(sm.Name)),
                N''
            ) AS ShipMethodName,

            -------------------------------------------------------------------
            -- Tariff attributes
            -------------------------------------------------------------------
            CONVERT
            (
                DECIMAL(19,4),
                sm.ShipBase
            ) AS ShipBase,

            CONVERT
            (
                DECIMAL(19,4),
                sm.ShipRate
            ) AS ShipRate,

            -------------------------------------------------------------------
            -- Source metadata
            -------------------------------------------------------------------
            CONVERT
            (
                DATETIME2(0),
                sm.ModifiedDate
            ) AS SourceModifiedDate,

            SYSUTCDATETIME() AS ExtractedAt,

            -------------------------------------------------------------------
            -- SCD Type 2 change detection
            -------------------------------------------------------------------
            HASHBYTES
            (
                'SHA2_256',
                CONCAT
                (
                    N'ShipBase=',
                    CONVERT
                    (
                        NVARCHAR(50),
                        CONVERT
                        (
                            DECIMAL(19,4),
                            sm.ShipBase
                        )
                    ),

                    N'|ShipRate=',
                    CONVERT
                    (
                        NVARCHAR(50),
                        CONVERT
                        (
                            DECIMAL(19,4),
                            sm.ShipRate
                        )
                    )
                )
            ) AS RowHash

        FROM AdventureWorks2022.Purchasing.ShipMethod AS sm
        WHERE
        (
            @LowModifiedDate IS NULL

            OR sm.ModifiedDate > @LowModifiedDate

            OR
            (
                sm.ModifiedDate = @LowModifiedDate
                AND sm.ShipMethodID > @LowBusinessKey
            )
        )
        AND
        (
            sm.ModifiedDate < @HighModifiedDate

            OR
            (
                sm.ModifiedDate = @HighModifiedDate
                AND sm.ShipMethodID <= @HighBusinessKey
            )
        );

        SET @RowsInserted = @@ROWCOUNT;

        /*
        =======================================================================
        7. COMMIT INCREMENTAL STAGING LOAD
        =======================================================================
        */

        COMMIT TRANSACTION;

        /*
        =======================================================================
        8. MARK EXECUTION AS SUCCESSFUL
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
        9. ROLLBACK FAILED LOAD
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
        11. MARK EXECUTION AS FAILED
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
    AND p.name = N'LoadShipMethodStage';
GO
