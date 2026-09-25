/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : stg.SalesOrderLineDelta
Script   : 007_CreateStagingSalesOrderLineDelta.sql
Author   : Diego Suárez
Purpose  : Create delta staging for bounded sales-order-line extraction
           before surrogate-key resolution and incremental fact loading.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE STAGING TABLE
===============================================================================
*/

IF OBJECT_ID(N'stg.SalesOrderLineDelta', N'U') IS NULL
BEGIN

    CREATE TABLE stg.SalesOrderLineDelta
    (
        -----------------------------------------------------------------------
        -- Source Grain
        -----------------------------------------------------------------------
        SalesOrderID INT NOT NULL,
        SalesOrderDetailID INT NOT NULL,

        -----------------------------------------------------------------------
        -- Degenerate Transaction Identifier
        -----------------------------------------------------------------------
        SalesOrderNumber NVARCHAR(25) NOT NULL,

        -----------------------------------------------------------------------
        -- Transaction Dates
        -----------------------------------------------------------------------
        OrderDate DATE NOT NULL,
        DueDate DATE NOT NULL,
        ShipDate DATE NULL,

        -----------------------------------------------------------------------
        -- Transaction Attributes
        -----------------------------------------------------------------------
        OrderStatusCode TINYINT NOT NULL,
        IsOnlineOrder BIT NOT NULL,

        -----------------------------------------------------------------------
        -- Dimension Business Keys
        -----------------------------------------------------------------------
        CustomerID INT NOT NULL,
        SalesPersonID INT NULL,
        TerritoryID INT NULL,
        ShipMethodID INT NOT NULL,
        ProductID INT NOT NULL,

        -----------------------------------------------------------------------
        -- Transaction Values
        -----------------------------------------------------------------------
        OrderQuantity SMALLINT NOT NULL,
        UnitPrice DECIMAL(19,4) NOT NULL,
        DiscountRate DECIMAL(10,4) NOT NULL,

        -----------------------------------------------------------------------
        -- Source Change Metadata
        -----------------------------------------------------------------------
        HeaderModifiedDate DATETIME2(7) NOT NULL,
        DetailModifiedDate DATETIME2(7) NOT NULL,

        -----------------------------------------------------------------------
        -- Extraction Metadata
        -----------------------------------------------------------------------
        ExtractedAt DATETIME2(7) NOT NULL
            CONSTRAINT DF_StgSalesOrderLineDelta_ExtractedAt
            DEFAULT SYSUTCDATETIME(),

        -----------------------------------------------------------------------
        -- Constraints
        -----------------------------------------------------------------------
        CONSTRAINT PK_StgSalesOrderLineDelta
            PRIMARY KEY CLUSTERED
            (
                SalesOrderID,
                SalesOrderDetailID
            ),

        CONSTRAINT CK_StgSalesOrderLineDelta_OrderStatusCode
            CHECK (OrderStatusCode BETWEEN 1 AND 6),

        CONSTRAINT CK_StgSalesOrderLineDelta_OrderQuantity
            CHECK (OrderQuantity > 0),

        CONSTRAINT CK_StgSalesOrderLineDelta_UnitPrice
            CHECK (UnitPrice >= 0),

        CONSTRAINT CK_StgSalesOrderLineDelta_DiscountRate
            CHECK (DiscountRate BETWEEN 0 AND 1)
    );

END;
GO


/*
===============================================================================
2. VALIDATE TABLE CREATION
===============================================================================
*/

SELECT
    s.name AS SchemaName,
    t.name AS TableName
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE
    s.name = N'stg'
    AND t.name = N'SalesOrderLineDelta';
GO


/*
===============================================================================
3. VALIDATE TABLE STRUCTURE
===============================================================================
*/

SELECT
    c.column_id AS ColumnID,
    c.name AS ColumnName,
    TYPE_NAME(c.user_type_id) AS DataType,
    c.max_length AS MaxLength,
    c.precision AS [Precision],
    c.scale AS Scale,
    c.is_nullable AS IsNullable
FROM sys.columns AS c
WHERE
    c.object_id = OBJECT_ID(N'stg.SalesOrderLineDelta')
ORDER BY
    c.column_id;
GO
