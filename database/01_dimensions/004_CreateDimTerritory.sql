/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : dw.DimTerritory
Script   : 004_CreateDimTerritory.sql
Author   : Diego Suárez
Purpose  : Creates the Territory dimension used to analyze sales by territory,
           country/region, and commercial territory group while preserving
           historically relevant classification changes.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE DIMENSION TABLE
===============================================================================
*/

IF OBJECT_ID(N'dw.DimTerritory', N'U') IS NULL
BEGIN

    CREATE TABLE dw.DimTerritory
    (
        -----------------------------------------------------------------------
        -- Surrogate Key
        -----------------------------------------------------------------------
        TerritoryKey BIGINT IDENTITY(1,1) NOT NULL,

        -----------------------------------------------------------------------
        -- Business Key
        -----------------------------------------------------------------------
        TerritoryID INT NOT NULL,

        -----------------------------------------------------------------------
        -- Descriptive Attributes
        -----------------------------------------------------------------------
        TerritoryName NVARCHAR(50) NOT NULL,
        CountryRegionCode NVARCHAR(3) NOT NULL,
        CountryRegionName NVARCHAR(50) NOT NULL,
        TerritoryGroup NVARCHAR(50) NOT NULL,

        -----------------------------------------------------------------------
        -- SCD Metadata
        -----------------------------------------------------------------------
        EffectiveStartDateTime DATETIME2(7) NOT NULL,

        EffectiveEndDateTime DATETIME2(7) NOT NULL
            CONSTRAINT DF_DimTerritory_EffectiveEndDateTime
            DEFAULT
            (
                CONVERT
                (
                    DATETIME2(7),
                    '9999-12-31 23:59:59.9999999'
                )
            ),

        IsCurrent BIT NOT NULL
            CONSTRAINT DF_DimTerritory_IsCurrent
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
            CONSTRAINT DF_DimTerritory_CreatedAt
            DEFAULT SYSUTCDATETIME(),

        -----------------------------------------------------------------------
        -- Constraints
        -----------------------------------------------------------------------
        CONSTRAINT PK_DimTerritory
            PRIMARY KEY CLUSTERED (TerritoryKey),

        CONSTRAINT CK_DimTerritory_ValidityRange
            CHECK
            (
                EffectiveStartDateTime
                < EffectiveEndDateTime
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
        object_id = OBJECT_ID(N'dw.DimTerritory')
        AND name = N'UX_DimTerritory_Current'
)
BEGIN

    CREATE UNIQUE NONCLUSTERED INDEX UX_DimTerritory_Current
        ON dw.DimTerritory(TerritoryID)
        WHERE IsCurrent = 1;

END;
GO


/*
===============================================================================
3. VALIDATE TABLE CREATION
===============================================================================
*/

SELECT
    s.name AS SchemaName,
    t.name AS TableName
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE
    s.name = N'dw'
    AND t.name = N'DimTerritory';
GO

/*
===============================================================================
4. VALIDATE TABLE STRUCTURE
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
    c.object_id = OBJECT_ID(N'dw.DimTerritory')
ORDER BY
    c.column_id;
GO


/*
===============================================================================
5. VALIDATE INDEXES
===============================================================================
*/

SELECT
    i.name AS IndexName,
    i.type_desc AS IndexType,
    i.is_unique AS IsUnique,
    i.has_filter AS HasFilter,
    i.filter_definition AS FilterDefinition
FROM sys.indexes AS i
WHERE
    i.object_id = OBJECT_ID(N'dw.DimTerritory')
ORDER BY
    i.index_id;
GO

