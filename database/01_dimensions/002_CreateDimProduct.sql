/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 002_CreateDimProduct.sql
Author   : Diego Suárez
Purpose  : Create the product dimension with SCD Type 2 history support.
Version  : 0.1.0
===============================================================================
*/

USE AdventureWorks_EDW;
GO

------------------------------------------------------------------------------
-- Create product dimension
------------------------------------------------------------------------------

IF OBJECT_ID(N'dw.DimProduct', N'U') IS NULL
BEGIN
    CREATE TABLE dw.DimProduct
    (
        -----------------------------------------------------------------------
        -- Keys
        -----------------------------------------------------------------------

        ProductKey BIGINT IDENTITY(1, 1) NOT NULL,
        ProductID INT NOT NULL,

        -----------------------------------------------------------------------
        -- Product descriptive attributes
        -----------------------------------------------------------------------

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

        -----------------------------------------------------------------------
        -- SCD Type 2 technical attributes
        -----------------------------------------------------------------------

        EffectiveStartDateTime DATETIME2(7) NOT NULL,
        EffectiveEndDateTime DATETIME2(7) NOT NULL,
        IsCurrent BIT NOT NULL,

        -----------------------------------------------------------------------
        -- ETL metadata
        -----------------------------------------------------------------------

        RowHash BINARY(32) NOT NULL,
        SourceModifiedDate DATETIME2(0) NOT NULL,

        CreatedAt DATETIME2(7) NOT NULL
            CONSTRAINT DF_DimProduct_CreatedAt
            DEFAULT SYSUTCDATETIME(),

        -----------------------------------------------------------------------
        -- Constraints
        -----------------------------------------------------------------------

        CONSTRAINT PK_DimProduct
            PRIMARY KEY CLUSTERED (ProductKey),

        CONSTRAINT CK_DimProduct_StandardCost
            CHECK (StandardCost >= 0),

        CONSTRAINT CK_DimProduct_ListPrice
            CHECK (ListPrice >= 0),

        CONSTRAINT CK_DimProduct_EffectiveDates
            CHECK
            (
                EffectiveEndDateTime > EffectiveStartDateTime
            ),

        CONSTRAINT CK_DimProduct_IsCurrent
            CHECK
            (
                IsCurrent IN (0, 1)
            ),

        CONSTRAINT CK_DimProduct_CurrentEndDate
            CHECK
            (
                (
                    IsCurrent = 1
                    AND EffectiveEndDateTime =
                        CONVERT
                        (
                            DATETIME2(7),
                            '9999-12-31 23:59:59.9999999'
                        )
                )
                OR
                (
                    IsCurrent = 0
                    AND EffectiveEndDateTime <
                        CONVERT
                        (
                            DATETIME2(7),
                            '9999-12-31 23:59:59.9999999'
                        )
                )
            )
    );
END;
GO

------------------------------------------------------------------------------
-- Guarantee only one current version per ProductID
------------------------------------------------------------------------------

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dw.DimProduct', N'U')
      AND name = N'UX_DimProduct_ProductID_Current'
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_DimProduct_ProductID_Current
        ON dw.DimProduct (ProductID)
        WHERE IsCurrent = 1;
END;
GO

------------------------------------------------------------------------------
-- Create an index for historical version lookups
------------------------------------------------------------------------------

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dw.DimProduct', N'U')
      AND name = N'IX_DimProduct_ProductID_EffectiveDates'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_DimProduct_ProductID_EffectiveDates
        ON dw.DimProduct
        (
            ProductID,
            EffectiveStartDateTime,
            EffectiveEndDateTime
        )
        INCLUDE
        (
            ProductKey,
            IsCurrent
        );
END;
GO

------------------------------------------------------------------------------
-- Validate the dimension
------------------------------------------------------------------------------

SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    t.create_date AS CreatedAt
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'dw'
  AND t.name = N'DimProduct';
GO

SELECT
    i.name AS IndexName,
    i.type_desc AS IndexType,
    i.is_unique AS IsUnique,
    i.has_filter AS HasFilter,
    i.filter_definition AS FilterDefinition
FROM sys.indexes AS i
WHERE i.object_id = OBJECT_ID(N'dw.DimProduct', N'U')
  AND i.name IS NOT NULL
ORDER BY i.index_id;
GO