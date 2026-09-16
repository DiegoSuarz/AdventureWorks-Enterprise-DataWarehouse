/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : etl.LoadShipMethodStage
Script   : etl.LoadShipMethodStage.sql
Author   : Diego Suárez
Purpose  : Loads the normalized current-state representation of AdventureWorks
           shipping methods into stg.ShipMethod.
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
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -----------------------------------------------------------------------
    -- Execution Variables
    -----------------------------------------------------------------------
    DECLARE @executionId BIGINT = NULL;
    DECLARE @rowsRead BIGINT = 0;
    DECLARE @rowsInserted BIGINT = 0;
    DECLARE @errorMessage NVARCHAR(4000);

    BEGIN TRY

        /*
        =======================================================================
        2. REGISTER ETL EXECUTION
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

        SET @executionId =
            CONVERT
            (
                BIGINT,
                SCOPE_IDENTITY()
            );


        /*
        =======================================================================
        3. CAPTURE SOURCE ROW COUNT
        =======================================================================
        */

        SELECT
            @rowsRead = COUNT_BIG(*)
        FROM AdventureWorks2022.Purchasing.ShipMethod;


        /*
        =======================================================================
        4. START STAGING LOAD
        =======================================================================
        */

        BEGIN TRANSACTION;

        TRUNCATE TABLE stg.ShipMethod;


        /*
        =======================================================================
        5. LOAD SHIPMETHOD SNAPSHOT
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
            -- Descriptive Attributes
            -------------------------------------------------------------------
            NULLIF
            (
                LTRIM(RTRIM(sm.Name)),
                N''
            ) AS ShipMethodName,

            -------------------------------------------------------------------
            -- Tariff Attributes
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
            -- Source Metadata
            -------------------------------------------------------------------
            CONVERT
            (
                DATETIME2(0),
                sm.ModifiedDate
            ) AS SourceModifiedDate,

            SYSUTCDATETIME() AS ExtractedAt,

            -------------------------------------------------------------------
            -- SCD Type 2 Change Detection
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

        FROM AdventureWorks2022.Purchasing.ShipMethod AS sm;

        SET @rowsInserted = @@ROWCOUNT;


        /*
        =======================================================================
        6. COMMIT STAGING LOAD
        =======================================================================
        */

        COMMIT TRANSACTION;


        /*
        =======================================================================
        7. MARK EXECUTION AS SUCCESSFUL
        =======================================================================
        */

        UPDATE audit.ETLExecutionLog
        SET
            EndTime = SYSUTCDATETIME(),
            [Status] = N'Succeeded',
            RowsRead = @rowsRead,
            RowsInserted = @rowsInserted,
            RowsUpdated = 0,
            RowsRejected = 0,
            ErrorMessage = NULL
        WHERE ExecutionID = @executionId;

    END TRY

    BEGIN CATCH

        /*
        =======================================================================
        8. ROLLBACK FAILED LOAD
        =======================================================================
        */

        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;


        /*
        =======================================================================
        9. BUILD ERROR MESSAGE
        =======================================================================
        */

        SET @errorMessage =
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
        10. MARK EXECUTION AS FAILED
        =======================================================================
        */

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
                ErrorMessage =
                    LEFT
                    (
                        @errorMessage,
                        4000
                    )
            WHERE ExecutionID = @executionId;
        END;

        THROW;

    END CATCH;
END;
GO


/*
===============================================================================
11. VALIDATE PROCEDURE CREATION
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
