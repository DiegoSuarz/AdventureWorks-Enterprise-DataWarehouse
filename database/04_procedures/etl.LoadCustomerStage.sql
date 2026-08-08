/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Author   : Diego Suárez
Object   : etl.LoadCustomerStage
Purpose  : Load the consolidated current-state Customer snapshot into
           stg.Customer from AdventureWorks2022.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

CREATE OR ALTER PROCEDURE etl.LoadCustomerStage
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    ---------------------------------------------------------------------------
    -- Execution variables
    ---------------------------------------------------------------------------

    DECLARE @executionId BIGINT = NULL;
    DECLARE @rowsRead BIGINT = 0;
    DECLARE @rowsInserted BIGINT = 0;
    DECLARE @errorMessage NVARCHAR(4000);

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
            N'etl.LoadCustomerStage',
            N'AdventureWorks2022.Sales.Customer',
            N'stg.Customer',
            SUSER_SNAME()
        );

        SET @executionId =
            CONVERT(BIGINT, SCOPE_IDENTITY());

        -----------------------------------------------------------------------
        -- Capture source row count
        -----------------------------------------------------------------------

        SELECT
            @rowsRead = COUNT_BIG(*)
        FROM AdventureWorks2022.Sales.Customer;

        -----------------------------------------------------------------------
        -- Start staging load
        -----------------------------------------------------------------------

        BEGIN TRANSACTION;

        TRUNCATE TABLE stg.Customer;

        -----------------------------------------------------------------------
        -- Load consolidated Customer snapshot
        -----------------------------------------------------------------------

        INSERT INTO stg.Customer
        (
            CustomerID,
            PersonID,
            StoreID,
            PersonType,
            CustomerType,
            CustomerName,
            FirstName,
            MiddleName,
            LastName,
            StoreName,
            AccountNumber,
            SourceModifiedDate,
            ExtractedAt,
            RowHash
        )
        SELECT
            c.CustomerID,
            c.PersonID,
            c.StoreID,
            p.PersonType,

            -------------------------------------------------------------------
            -- Customer classification
            -------------------------------------------------------------------

            CASE
                WHEN c.StoreID IS NOT NULL
                    THEN N'Store'

                WHEN c.PersonID IS NOT NULL
                    THEN N'Individual'

                ELSE N'Unknown'
            END AS CustomerType,

            -------------------------------------------------------------------
            -- Customer analytical name
            -------------------------------------------------------------------

            CASE
                WHEN c.StoreID IS NOT NULL
                    THEN COALESCE
                    (
                        NULLIF(LTRIM(RTRIM(s.Name)), N''),
                        N'Unknown Customer'
                    )

                WHEN c.PersonID IS NOT NULL
                    THEN COALESCE
                    (
                        NULLIF
                        (
                            CONCAT_WS
                            (
                                N' ',
                                NULLIF(LTRIM(RTRIM(p.FirstName)), N''),
                                NULLIF(LTRIM(RTRIM(p.MiddleName)), N''),
                                NULLIF(LTRIM(RTRIM(p.LastName)), N'')
                            ),
                            N''
                        ),
                        N'Unknown Customer'
                    )

                ELSE N'Unknown Customer'
            END AS CustomerName,

            -------------------------------------------------------------------
            -- Person attributes only apply to Individual customers
            -------------------------------------------------------------------

            CASE
                WHEN c.StoreID IS NULL
                     AND c.PersonID IS NOT NULL
                    THEN p.FirstName
                ELSE NULL
            END AS FirstName,

            CASE
                WHEN c.StoreID IS NULL
                     AND c.PersonID IS NOT NULL
                    THEN p.MiddleName
                ELSE NULL
            END AS MiddleName,

            CASE
                WHEN c.StoreID IS NULL
                     AND c.PersonID IS NOT NULL
                    THEN p.LastName
                ELSE NULL
            END AS LastName,

            -------------------------------------------------------------------
            -- Store attributes only apply to Store customers
            -------------------------------------------------------------------

            CASE
                WHEN c.StoreID IS NOT NULL
                    THEN s.Name
                ELSE NULL
            END AS StoreName,

            c.AccountNumber,

            -------------------------------------------------------------------
            -- Latest relevant source modification
            -------------------------------------------------------------------

            CASE
                WHEN c.StoreID IS NOT NULL
                    THEN
                    (
                        SELECT MAX(v.ModifiedDate)
                        FROM
                        (
                            VALUES
                                (c.ModifiedDate),
                                (s.ModifiedDate)
                        ) AS v(ModifiedDate)
                    )

                WHEN c.PersonID IS NOT NULL
                    THEN
                    (
                        SELECT MAX(v.ModifiedDate)
                        FROM
                        (
                            VALUES
                                (c.ModifiedDate),
                                (p.ModifiedDate)
                        ) AS v(ModifiedDate)
                    )

                ELSE c.ModifiedDate
            END AS SourceModifiedDate,

            SYSUTCDATETIME() AS ExtractedAt,

            -------------------------------------------------------------------
            -- SCD Type 1 change detection
            -------------------------------------------------------------------

            HASHBYTES
            (
                'SHA2_256',
                CONCAT
                (
                    N'CustomerType=',
                    CASE
                        WHEN c.StoreID IS NOT NULL
                            THEN N'Store'
                        WHEN c.PersonID IS NOT NULL
                            THEN N'Individual'
                        ELSE N'Unknown'
                    END,

                    N'|CustomerName=',
                    CASE
                        WHEN c.StoreID IS NOT NULL
                            THEN COALESCE
                            (
                                NULLIF(LTRIM(RTRIM(s.Name)), N''),
                                N'Unknown Customer'
                            )

                        WHEN c.PersonID IS NOT NULL
                            THEN COALESCE
                            (
                                NULLIF
                                (
                                    CONCAT_WS
                                    (
                                        N' ',
                                        NULLIF(LTRIM(RTRIM(p.FirstName)), N''),
                                        NULLIF(LTRIM(RTRIM(p.MiddleName)), N''),
                                        NULLIF(LTRIM(RTRIM(p.LastName)), N'')
                                    ),
                                    N''
                                ),
                                N'Unknown Customer'
                            )

                        ELSE N'Unknown Customer'
                    END,

                    N'|FirstName=',
                    CASE
                        WHEN c.StoreID IS NULL
                             AND c.PersonID IS NOT NULL
                            THEN COALESCE(p.FirstName, N'<NULL>')
                        ELSE N'<NULL>'
                    END,

                    N'|MiddleName=',
                    CASE
                        WHEN c.StoreID IS NULL
                             AND c.PersonID IS NOT NULL
                            THEN COALESCE(p.MiddleName, N'<NULL>')
                        ELSE N'<NULL>'
                    END,

                    N'|LastName=',
                    CASE
                        WHEN c.StoreID IS NULL
                             AND c.PersonID IS NOT NULL
                            THEN COALESCE(p.LastName, N'<NULL>')
                        ELSE N'<NULL>'
                    END,

                    N'|StoreName=',
                    CASE
                        WHEN c.StoreID IS NOT NULL
                            THEN COALESCE(s.Name, N'<NULL>')
                        ELSE N'<NULL>'
                    END,

                    N'|AccountNumber=',
                    COALESCE(c.AccountNumber, N'<NULL>')
                )
            ) AS RowHash

        FROM AdventureWorks2022.Sales.Customer AS c

        LEFT JOIN AdventureWorks2022.Person.Person AS p
            ON c.PersonID = p.BusinessEntityID

        LEFT JOIN AdventureWorks2022.Sales.Store AS s
            ON c.StoreID = s.BusinessEntityID;

        SET @rowsInserted = @@ROWCOUNT;

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
            RowsUpdated = 0,
            RowsRejected = 0,
            ErrorMessage = NULL
        WHERE ExecutionID = @executionId;

    END TRY

    BEGIN CATCH

        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        SET @errorMessage =
            CONCAT
            (
                N'ErrorNumber: ', ERROR_NUMBER(),
                N'; ErrorProcedure: ',
                COALESCE(ERROR_PROCEDURE(), N'Ad hoc batch'),
                N'; ErrorLine: ', ERROR_LINE(),
                N'; ErrorMessage: ', ERROR_MESSAGE()
            );

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