/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : stg.SalesPerson
Script   : 004_CreateStagingSalesPerson.sql
Author   : Diego Suárez
Purpose  : Creates the staging table used to store the consolidated current-state
           representation of AdventureWorks sales personnel before loading
           dw.DimSalesPerson.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE STAGING TABLE
===============================================================================
*/

IF OBJECT_ID(N'stg.SalesPerson', N'U') IS NULL
BEGIN

    CREATE TABLE stg.SalesPerson
    (
        -----------------------------------------------------------------------
        -- Business Key
        -----------------------------------------------------------------------
        BusinessEntityID INT NOT NULL,

        -----------------------------------------------------------------------
        -- Personal Attributes
        -----------------------------------------------------------------------
        SalesPersonName NVARCHAR(200) NOT NULL,
        FirstName NVARCHAR(50) NOT NULL,
        MiddleName NVARCHAR(50) NULL,
        LastName NVARCHAR(50) NOT NULL,

        -----------------------------------------------------------------------
        -- Employment Attributes
        -----------------------------------------------------------------------
        JobTitle NVARCHAR(100) NOT NULL,
        HireDate DATE NOT NULL,
        CurrentFlag BIT NOT NULL,

        -----------------------------------------------------------------------
        -- Commercial Attributes
        -----------------------------------------------------------------------
        SalesQuota DECIMAL(19,4) NULL,
        Bonus DECIMAL(19,4) NOT NULL,
        CommissionPct DECIMAL(10,4) NOT NULL,

        -----------------------------------------------------------------------
        -- Source Lineage
        -----------------------------------------------------------------------
        TerritoryID INT NULL,

        -----------------------------------------------------------------------
        -- Source Metadata
        -----------------------------------------------------------------------
        SourceModifiedDate DATETIME2(0) NOT NULL,

        ExtractedAt DATETIME2(7) NOT NULL
            CONSTRAINT DF_StgSalesPerson_ExtractedAt
            DEFAULT SYSUTCDATETIME(),

        -----------------------------------------------------------------------
        -- Change Detection
        -----------------------------------------------------------------------
        RowHash VARBINARY(32) NOT NULL,

        -----------------------------------------------------------------------
        -- Constraints
        -----------------------------------------------------------------------
        CONSTRAINT PK_StgSalesPerson
            PRIMARY KEY CLUSTERED (BusinessEntityID),

        CONSTRAINT CK_StgSalesPerson_Bonus
            CHECK (Bonus >= 0),

        CONSTRAINT CK_StgSalesPerson_CommissionPct
            CHECK (CommissionPct >= 0),

        CONSTRAINT CK_StgSalesPerson_SalesQuota
            CHECK
            (
                SalesQuota IS NULL
                OR SalesQuota >= 0
            )
    );

END;
GO


/*
===============================================================================
2. VALIDATE TABLE CREATION
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SELECT
    s.name AS SchemaName,
    t.name AS TableName
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE
    s.name = N'stg'
    AND t.name = N'SalesPerson';
GO


/*
===============================================================================
3. VALIDATE TABLE STRUCTURE
===============================================================================
*/

USE AdventureWorks_EDW;
GO

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
    c.object_id = OBJECT_ID(N'stg.SalesPerson')
ORDER BY
    c.column_id;
GO