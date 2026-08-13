/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : etl.LoadSalesPersonStage
Script   : etl.LoadSalesPersonStage.sql
Author   : Diego Suárez
Purpose  : Loads the consolidated current-state representation of AdventureWorks
           sales personnel into stg.SalesPerson.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE OR ALTER PROCEDURE
===============================================================================
*/

CREATE OR ALTER PROCEDURE etl.LoadSalesPersonStage
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
            N'etl.LoadSalesPersonStage',
            N'AdventureWorks2022.Sales.SalesPerson',
            N'stg.SalesPerson',
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
        FROM AdventureWorks2022.Sales.SalesPerson;


        /*
        =======================================================================
        4. START STAGING LOAD
        =======================================================================
        */

        BEGIN TRANSACTION;

        TRUNCATE TABLE stg.SalesPerson;


        /*
        =======================================================================
        5. LOAD CONSOLIDATED SALESPERSON SNAPSHOT
        =======================================================================
        */

        INSERT INTO stg.SalesPerson
        (
            BusinessEntityID,
            SalesPersonName,
            FirstName,
            MiddleName,
            LastName,
            JobTitle,
            HireDate,
            CurrentFlag,
            SalesQuota,
            Bonus,
            CommissionPct,
            TerritoryID,
            SourceModifiedDate,
            ExtractedAt,
            RowHash
        )
        SELECT
            sp.BusinessEntityID,

            -------------------------------------------------------------------
            -- Personal Attributes
            -------------------------------------------------------------------
            CONCAT_WS
            (
                N' ',
                NULLIF(LTRIM(RTRIM(p.FirstName)), N''),
                NULLIF(LTRIM(RTRIM(p.MiddleName)), N''),
                NULLIF(LTRIM(RTRIM(p.LastName)), N'')
            ) AS SalesPersonName,

            NULLIF
            (
                LTRIM(RTRIM(p.FirstName)),
                N''
            ) AS FirstName,

            NULLIF
            (
                LTRIM(RTRIM(p.MiddleName)),
                N''
            ) AS MiddleName,

            NULLIF
            (
                LTRIM(RTRIM(p.LastName)),
                N''
            ) AS LastName,

            -------------------------------------------------------------------
            -- Employment Attributes
            -------------------------------------------------------------------
            NULLIF
            (
                LTRIM(RTRIM(e.JobTitle)),
                N''
            ) AS JobTitle,

            e.HireDate,
            e.CurrentFlag,

            -------------------------------------------------------------------
            -- Commercial Attributes
            -------------------------------------------------------------------
            CONVERT
            (
                DECIMAL(19,4),
                sp.SalesQuota
            ) AS SalesQuota,

            CONVERT
            (
                DECIMAL(19,4),
                sp.Bonus
            ) AS Bonus,

            CONVERT
            (
                DECIMAL(10,4),
                sp.CommissionPct
            ) AS CommissionPct,

            -------------------------------------------------------------------
            -- Source Lineage
            -------------------------------------------------------------------
            sp.TerritoryID,

            -------------------------------------------------------------------
            -- Source Metadata
            -------------------------------------------------------------------
            (
                SELECT
                    MAX(v.ModifiedDate)
                FROM
                (
                    VALUES
                        (CONVERT(DATETIME2(0), sp.ModifiedDate)),
                        (CONVERT(DATETIME2(0), p.ModifiedDate)),
                        (CONVERT(DATETIME2(0), e.ModifiedDate))
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
                    N'JobTitle=',
                    COALESCE
                    (
                        NULLIF
                        (
                            LTRIM(RTRIM(e.JobTitle)),
                            N''
                        ),
                        N'<NULL>'
                    ),

                    N'|CurrentFlag=',
                    CONVERT
                    (
                        NVARCHAR(1),
                        e.CurrentFlag
                    ),

                    N'|SalesQuota=',
                    COALESCE
                    (
                        CONVERT
                        (
                            NVARCHAR(50),
                            CONVERT
                            (
                                DECIMAL(19,4),
                                sp.SalesQuota
                            )
                        ),
                        N'<NULL>'
                    ),

                    N'|Bonus=',
                    CONVERT
                    (
                        NVARCHAR(50),
                        CONVERT
                        (
                            DECIMAL(19,4),
                            sp.Bonus
                        )
                    ),

                    N'|CommissionPct=',
                    CONVERT
                    (
                        NVARCHAR(50),
                        CONVERT
                        (
                            DECIMAL(10,4),
                            sp.CommissionPct
                        )
                    )
                )
            ) AS RowHash

        FROM AdventureWorks2022.Sales.SalesPerson AS sp

        INNER JOIN AdventureWorks2022.Person.Person AS p
            ON sp.BusinessEntityID = p.BusinessEntityID

        INNER JOIN AdventureWorks2022.HumanResources.Employee AS e
            ON sp.BusinessEntityID = e.BusinessEntityID;

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
    AND p.name = N'LoadSalesPersonStage';
GO