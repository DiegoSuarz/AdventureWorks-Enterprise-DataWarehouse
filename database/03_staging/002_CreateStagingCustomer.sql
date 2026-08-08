/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : stg.Customer
Script   : 002_CreateStagingCustomer.sql
Author   : Diego Suárez
Purpose  : Store the consolidated current-state representation of customers
           extracted from AdventureWorks2022.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

------------------------------------------------------------------------------
-- Create customer staging table
------------------------------------------------------------------------------

IF OBJECT_ID(N'stg.Customer', N'U') IS NULL
BEGIN
    CREATE TABLE stg.Customer
    (
        -----------------------------------------------------------------------
        -- Source identifiers
        -----------------------------------------------------------------------

        CustomerID INT NOT NULL,
        PersonID INT NULL,
        StoreID INT NULL,
        PersonType NCHAR(2) NULL,

        -----------------------------------------------------------------------
        -- Dimensional attributes
        -----------------------------------------------------------------------

        CustomerType NVARCHAR(20) NOT NULL,
        CustomerName NVARCHAR(200) NOT NULL,

        FirstName NVARCHAR(50) NULL,
        MiddleName NVARCHAR(50) NULL,
        LastName NVARCHAR(50) NULL,

        StoreName NVARCHAR(200) NULL,

        AccountNumber NVARCHAR(20) NOT NULL,

        -----------------------------------------------------------------------
        -- ETL metadata
        -----------------------------------------------------------------------

        SourceModifiedDate DATETIME2(0) NOT NULL,

        ExtractedAt DATETIME2(7) NOT NULL
            CONSTRAINT DF_StgCustomer_ExtractedAt
            DEFAULT SYSUTCDATETIME(),

        RowHash VARBINARY(32) NOT NULL,

        -----------------------------------------------------------------------
        -- Constraints
        -----------------------------------------------------------------------

        CONSTRAINT PK_StgCustomer
            PRIMARY KEY CLUSTERED (CustomerID),

        CONSTRAINT CK_StgCustomer_CustomerType
            CHECK
            (
                CustomerType IN
                (
                    N'Individual',
                    N'Store',
                    N'Unknown'
                )
            )
    );
END;
GO

------------------------------------------------------------------------------
-- Validate the staging table
------------------------------------------------------------------------------

SELECT
    s.name AS SchemaName,
    t.name AS TableName
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'stg'
  AND t.name = N'Customer';
GO