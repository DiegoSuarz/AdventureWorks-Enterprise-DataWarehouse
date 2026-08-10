/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : etl.LoadDimTerritory
Script   : etl.LoadDimTerritory.sql
Author   : Diego Suárez
Purpose  : Loads dw.DimTerritory from stg.Territory using combined Slowly
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

CREATE OR ALTER PROCEDURE etl.LoadDimTerritory
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
            N'etl.LoadDimTerritory',
            N'stg.Territory',
            N'dw.DimTerritory',
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
        FROM stg.Territory;


        /*
        =======================================================================
        4. START DIMENSIONAL LOAD
        =======================================================================
        */

        BEGIN TRANSACTION;


        /*
        =======================================================================
        5. INSERT NEW TERRITORIES
        =======================================================================
        */

        INSERT INTO dw.DimTerritory
        (
            TerritoryID,
            TerritoryName,
            CountryRegionCode,
            CountryRegionName,
            TerritoryGroup,
            EffectiveStartDateTime,
            EffectiveEndDateTime,
            IsCurrent,
            RowHash,
            SourceModifiedDate
        )
        SELECT
            s.TerritoryID,
            s.TerritoryName,
            s.CountryRegionCode,
            s.CountryRegionName,
            s.TerritoryGroup,
            @loadDateTime,
            @openEndedDateTime,
            1,
            s.RowHash,
            s.SourceModifiedDate
        FROM stg.Territory AS s
        WHERE NOT EXISTS
        (
            SELECT
                1
            FROM dw.DimTerritory AS d
            WHERE
                d.TerritoryID = s.TerritoryID
                AND d.IsCurrent = 1
        );

        SET @rowsInserted =
            @rowsInserted + @@ROWCOUNT;


        /*
        =======================================================================
        6. APPLY SCD TYPE 1 CHANGES
        =======================================================================

        Type 1 attributes:
            - TerritoryName
            - CountryRegionName

        A Type 1 update is performed only when the Type 2 RowHash has not
        changed. This prevents modifying a historical version immediately
        before it is expired by Type 2 processing.
        =======================================================================
        */

        UPDATE d
        SET
            d.TerritoryName = s.TerritoryName,
            d.CountryRegionName = s.CountryRegionName,
            d.SourceModifiedDate = s.SourceModifiedDate
        FROM dw.DimTerritory AS d
        INNER JOIN stg.Territory AS s
            ON d.TerritoryID = s.TerritoryID
        WHERE
            d.IsCurrent = 1
            AND d.RowHash = s.RowHash
            AND
            (
                d.TerritoryName <> s.TerritoryName
                OR d.CountryRegionName <> s.CountryRegionName
            );

        SET @rowsUpdated =
            @rowsUpdated + @@ROWCOUNT;


        /*
        =======================================================================
        7. IDENTIFY SCD TYPE 2 CHANGES
        =======================================================================

        Type 2 attributes:
            - CountryRegionCode
            - TerritoryGroup

        RowHash contains only these Type 2 attributes.
        =======================================================================
        */

        CREATE TABLE #Type2Changes
        (
            TerritoryID INT NOT NULL
                PRIMARY KEY
        );

        INSERT INTO #Type2Changes
        (
            TerritoryID
        )
        SELECT
            s.TerritoryID
        FROM stg.Territory AS s
        INNER JOIN dw.DimTerritory AS d
            ON s.TerritoryID = d.TerritoryID
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
        FROM dw.DimTerritory AS d
        INNER JOIN #Type2Changes AS c
            ON d.TerritoryID = c.TerritoryID
        WHERE
            d.IsCurrent = 1;

        SET @rowsUpdated =
            @rowsUpdated + @@ROWCOUNT;


        /*
        =======================================================================
        9. INSERT NEW TYPE 2 VERSIONS
        =======================================================================
        */

        INSERT INTO dw.DimTerritory
        (
            TerritoryID,
            TerritoryName,
            CountryRegionCode,
            CountryRegionName,
            TerritoryGroup,
            EffectiveStartDateTime,
            EffectiveEndDateTime,
            IsCurrent,
            RowHash,
            SourceModifiedDate
        )
        SELECT
            s.TerritoryID,
            s.TerritoryName,
            s.CountryRegionCode,
            s.CountryRegionName,
            s.TerritoryGroup,
            @loadDateTime,
            @openEndedDateTime,
            1,
            s.RowHash,
            s.SourceModifiedDate
        FROM stg.Territory AS s
        INNER JOIN #Type2Changes AS c
            ON s.TerritoryID = c.TerritoryID;

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
    AND p.name = N'LoadDimTerritory';
GO