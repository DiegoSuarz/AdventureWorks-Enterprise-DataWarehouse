/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : dw.DimSalesPerson
Script   : 005_CreateDimSalesPerson.sql
Author   : Diego Suárez
Purpose  : Creates the SalesPerson dimension used to analyze sales personnel
           while preserving historically relevant employment and commercial
           attribute changes.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE DIMENSION TABLE
===============================================================================
*/

IF OBJECT_ID(N'dw.DimSalesPerson', N'U') IS NULL
BEGIN

    CREATE TABLE dw.DimSalesPerson
    (
        -----------------------------------------------------------------------
        -- Surrogate Key
        -----------------------------------------------------------------------
        SalesPersonKey BIGINT IDENTITY(1,1) NOT NULL,

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
        -- SCD Metadata
        -----------------------------------------------------------------------
        EffectiveStartDateTime DATETIME2(7) NOT NULL,

        EffectiveEndDateTime DATETIME2(7) NOT NULL
            CONSTRAINT DF_DimSalesPerson_EffectiveEndDateTime
            DEFAULT
            (
                CONVERT
                (
                    DATETIME2(7),
                    '9999-12-31 23:59:59.9999999'
                )
            ),

        IsCurrent BIT NOT NULL
            CONSTRAINT DF_DimSalesPerson_IsCurrent
            DEFAULT (1),

        -----------------------------------------------------------------------
        -- Change Detection
        -----------------------------------------------------------------------
        RowHash VARBINARY(32) NOT NULL,

        -----------------------------------------------------------------------
        -- Source Metadata
        -----------------------------------------------------------------------
        SourceModifiedDate DATETIME2(0) NOT NULL,

        CreatedAt DATETIME2(7) NOT NULL
            CONSTRAINT DF_DimSalesPerson_CreatedAt
            DEFAULT SYSUTCDATETIME(),

        -----------------------------------------------------------------------
        -- Constraints
        -----------------------------------------------------------------------
        CONSTRAINT PK_DimSalesPerson
            PRIMARY KEY CLUSTERED (SalesPersonKey),

        CONSTRAINT CK_DimSalesPerson_ValidityRange
            CHECK
            (
                EffectiveStartDateTime
                < EffectiveEndDateTime
            ),

        CONSTRAINT CK_DimSalesPerson_Bonus
            CHECK (Bonus >= 0),

        CONSTRAINT CK_DimSalesPerson_CommissionPct
            CHECK (CommissionPct >= 0),

        CONSTRAINT CK_DimSalesPerson_SalesQuota
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
2. CREATE CURRENT-VERSION UNIQUE INDEX
===============================================================================
*/

IF NOT EXISTS
(
    SELECT
        1
    FROM sys.indexes
    WHERE
        object_id = OBJECT_ID(N'dw.DimSalesPerson')
        AND name = N'UX_DimSalesPerson_Current'
)
BEGIN

    CREATE UNIQUE NONCLUSTERED INDEX UX_DimSalesPerson_Current
        ON dw.DimSalesPerson(BusinessEntityID)
        WHERE IsCurrent = 1;

END;
GO


/*
===============================================================================
3. VALIDATE TABLE CREATION
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
    s.name = N'dw'
    AND t.name = N'DimSalesPerson';
GO


/*
===============================================================================
4. VALIDATE TABLE STRUCTURE
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
    c.object_id = OBJECT_ID(N'dw.DimSalesPerson')
ORDER BY
    c.column_id;
GO


/*
===============================================================================
5. VALIDATE INDEXES
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SELECT
    i.name AS IndexName,
    i.type_desc AS IndexType,
    i.is_unique AS IsUnique,
    i.has_filter AS HasFilter,
    i.filter_definition AS FilterDefinition
FROM sys.indexes AS i
WHERE
    i.object_id = OBJECT_ID(N'dw.DimSalesPerson')
ORDER BY
    i.index_id;
GO