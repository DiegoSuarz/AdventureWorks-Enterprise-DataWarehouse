/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : etl.LoadTerritoryStage
Script   : etl.LoadTerritoryStage.sql
Author   : Diego Suárez
Purpose  : Loads the consolidated current-state representation of AdventureWorks
           sales territories into stg.Territory.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE OR ALTER PROCEDURE
===============================================================================
*/

CREATE OR ALTER PROCEDURE etl.LoadTerritoryStage
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
            N'etl.LoadTerritoryStage',
            N'AdventureWorks2022.Sales.SalesTerritory',
            N'stg.Territory',
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
        FROM AdventureWorks2022.Sales.SalesTerritory;


        /*
        =======================================================================
        4. START STAGING LOAD
        =======================================================================
        */

        BEGIN TRANSACTION;

        TRUNCATE TABLE stg.Territory;


        /*
        =======================================================================
        5. LOAD CONSOLIDATED TERRITORY SNAPSHOT
        =======================================================================
        */

        INSERT INTO stg.Territory
        (
            TerritoryID,
            TerritoryName,
            CountryRegionCode,
            CountryRegionName,
            TerritoryGroup,
            SourceModifiedDate,
            ExtractedAt,
            RowHash
        )
        SELECT
            st.TerritoryID,

            -------------------------------------------------------------------
            -- Descriptive Attributes
            -------------------------------------------------------------------
            NULLIF
            (
                LTRIM(RTRIM(st.Name)),
                N''
            ) AS TerritoryName,

            NULLIF
            (
                LTRIM(RTRIM(st.CountryRegionCode)),
                N''
            ) AS CountryRegionCode,

            NULLIF
            (
                LTRIM(RTRIM(cr.Name)),
                N''
            ) AS CountryRegionName,

            NULLIF
            (
                LTRIM(RTRIM(st.[Group])),
                N''
            ) AS TerritoryGroup,

            -------------------------------------------------------------------
            -- Source Metadata
            -------------------------------------------------------------------
            (
                SELECT
                    MAX(v.ModifiedDate)
                FROM
                (
                    VALUES
                        (st.ModifiedDate),
                        (cr.ModifiedDate)
                ) AS v(ModifiedDate)
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
                    N'CountryRegionCode=',
                    COALESCE
                    (
                        NULLIF
                        (
                            LTRIM(RTRIM(st.CountryRegionCode)),
                            N''
                        ),
                        N'<NULL>'
                    ),

                    N'|TerritoryGroup=',
                    COALESCE
                    (
                        NULLIF
                        (
                            LTRIM(RTRIM(st.[Group])),
                            N''
                        ),
                        N'<NULL>'
                    )
                )
            ) AS RowHash

        FROM AdventureWorks2022.Sales.SalesTerritory AS st

        INNER JOIN AdventureWorks2022.Person.CountryRegion AS cr
            ON st.CountryRegionCode = cr.CountryRegionCode;

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
    AND p.name = N'LoadTerritoryStage';
GO