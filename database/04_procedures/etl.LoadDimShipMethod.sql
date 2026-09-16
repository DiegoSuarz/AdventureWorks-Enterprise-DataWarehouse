/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : etl.LoadDimShipMethod
Script   : etl.LoadDimShipMethod.sql
Author   : Diego Suárez
Purpose  : Loads dw.DimShipMethod from stg.ShipMethod using combined Slowly
           Changing Dimension Type 1 and Type 2 processing.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE OR ALTER PROCEDURE
===============================================================================
*/

CREATE OR ALTER PROCEDURE etl.LoadDimShipMethod
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -----------------------------------------------------------------------
    -- Execution Variables
    -----------------------------------------------------------------------
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
            N'etl.LoadDimShipMethod',
            N'stg.ShipMethod',
            N'dw.DimShipMethod',
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
        3. CAPTURE STAGING ROW COUNT
        =======================================================================
        */

        SELECT
            @rowsRead = COUNT_BIG(*)
        FROM stg.ShipMethod;


        /*
        =======================================================================
        4. START DIMENSIONAL LOAD
        =======================================================================
        */

        BEGIN TRANSACTION;


        /*
        =======================================================================
        5. INSERT NEW SHIPPING METHODS
        =======================================================================
        */

        INSERT INTO dw.DimShipMethod
        (
            ShipMethodID,
            ShipMethodName,
            ShipBase,
            ShipRate,
            EffectiveStartDateTime,
            EffectiveEndDateTime,
            IsCurrent,
            RowHash,
            SourceModifiedDate
        )
        SELECT
            s.ShipMethodID,
            s.ShipMethodName,
            s.ShipBase,
            s.ShipRate,
            @loadDateTime,
            @openEndedDateTime,
            1,
            s.RowHash,
            s.SourceModifiedDate
        FROM stg.ShipMethod AS s
        WHERE NOT EXISTS
        (
            SELECT
                1
            FROM dw.DimShipMethod AS d
            WHERE
                d.ShipMethodID = s.ShipMethodID
                AND d.IsCurrent = 1
        );

        SET @rowsInserted =
            @rowsInserted + @@ROWCOUNT;


        /*
        =======================================================================
        6. APPLY SCD TYPE 1 CHANGES
        =======================================================================

        Type 1 attributes:
            - ShipMethodName

        Type 1 updates are applied only when the Type 2 RowHash remains
        unchanged.
        =======================================================================
        */

        UPDATE d
        SET
            d.ShipMethodName = s.ShipMethodName,
            d.SourceModifiedDate = s.SourceModifiedDate
        FROM dw.DimShipMethod AS d
        INNER JOIN stg.ShipMethod AS s
            ON d.ShipMethodID = s.ShipMethodID
        WHERE
            d.IsCurrent = 1
            AND d.RowHash = s.RowHash
            AND d.ShipMethodName <> s.ShipMethodName;

        SET @rowsUpdated =
            @rowsUpdated + @@ROWCOUNT;


        /*
        =======================================================================
        7. IDENTIFY SCD TYPE 2 CHANGES
        =======================================================================

        Type 2 attributes:
            - ShipBase
            - ShipRate
        =======================================================================
        */

        CREATE TABLE #Type2Changes
        (
            ShipMethodID INT NOT NULL
                PRIMARY KEY
        );

        INSERT INTO #Type2Changes
        (
            ShipMethodID
        )
        SELECT
            s.ShipMethodID
        FROM stg.ShipMethod AS s
        INNER JOIN dw.DimShipMethod AS d
            ON s.ShipMethodID = d.ShipMethodID
        WHERE
            d.IsCurrent = 1
            AND d.RowHash <> s.RowHash;


        /*
        =======================================================================
        8. EXPIRE CURRENT TYPE 2 VERSIONS
        =======================================================================
        */

        UPDATE d
        SET
            d.EffectiveEndDateTime = @loadDateTime,
            d.IsCurrent = 0
        FROM dw.DimShipMethod AS d
        INNER JOIN #Type2Changes AS c
            ON d.ShipMethodID = c.ShipMethodID
        WHERE
            d.IsCurrent = 1;

        SET @rowsUpdated =
            @rowsUpdated + @@ROWCOUNT;


        /*
        =======================================================================
        9. INSERT NEW TYPE 2 VERSIONS
        =======================================================================
        */

        INSERT INTO dw.DimShipMethod
        (
            ShipMethodID,
            ShipMethodName,
            ShipBase,
            ShipRate,
            EffectiveStartDateTime,
            EffectiveEndDateTime,
            IsCurrent,
            RowHash,
            SourceModifiedDate
        )
        SELECT
            s.ShipMethodID,
            s.ShipMethodName,
            s.ShipBase,
            s.ShipRate,
            @loadDateTime,
            @openEndedDateTime,
            1,
            s.RowHash,
            s.SourceModifiedDate
        FROM stg.ShipMethod AS s
        INNER JOIN #Type2Changes AS c
            ON s.ShipMethodID = c.ShipMethodID;

        SET @rowsInserted =
            @rowsInserted + @@ROWCOUNT;


        /*
        =======================================================================
        10. COMMIT DIMENSIONAL LOAD
        =======================================================================
        */

        COMMIT TRANSACTION;


        /*
        =======================================================================
        11. MARK EXECUTION AS SUCCESSFUL
        =======================================================================
        */

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

        /*
        =======================================================================
        12. ROLLBACK FAILED LOAD
        =======================================================================
        */

        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;


        /*
        =======================================================================
        13. BUILD ERROR MESSAGE
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
        14. MARK EXECUTION AS FAILED
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
    AND p.name = N'LoadDimShipMethod';
GO
