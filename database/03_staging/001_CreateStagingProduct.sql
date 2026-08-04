/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 003_CreateStagingProduct.sql
Author   : Diego Suárez
Purpose  : Create the staging table used to prepare product source data.
Version  : 0.1.0
===============================================================================
*/

USE AdventureWorks_EDW;
GO

------------------------------------------------------------------------------
-- Create product staging table
------------------------------------------------------------------------------

IF OBJECT_ID(N'stg.Product', N'U') IS NULL
BEGIN
    CREATE TABLE stg.Product
    (
        ProductID INT NOT NULL,
        ProductName NVARCHAR(100) NOT NULL,
        ProductNumber NVARCHAR(25) NOT NULL,
        Color NVARCHAR(30) NULL,
        Size NVARCHAR(10) NULL,

        StandardCost DECIMAL(19, 4) NOT NULL,
        ListPrice DECIMAL(19, 4) NOT NULL,

        SubcategoryName NVARCHAR(100) NOT NULL,
        CategoryName NVARCHAR(100) NOT NULL,

        SellStartDate DATETIME2(0) NOT NULL,
        SellEndDate DATETIME2(0) NULL,
        DiscontinuedDate DATETIME2(0) NULL,

        SourceModifiedDate DATETIME2(0) NOT NULL,
        RowHash BINARY(32) NOT NULL,

        ExtractedAt DATETIME2(7) NOT NULL
            CONSTRAINT DF_StagingProduct_ExtractedAt
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_StagingProduct
            PRIMARY KEY CLUSTERED (ProductID),

        CONSTRAINT CK_StagingProduct_StandardCost
            CHECK (StandardCost >= 0),

        CONSTRAINT CK_StagingProduct_ListPrice
            CHECK (ListPrice >= 0)
    );
END;
GO

------------------------------------------------------------------------------
-- Validate the staging table
------------------------------------------------------------------------------

SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    t.create_date AS CreatedAt
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'stg'
  AND t.name = N'Product';
GO