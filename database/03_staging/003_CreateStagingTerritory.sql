/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : stg.Territory
Script   : 003_CreateStagingTerritory.sql
Author   : Diego Suárez
Purpose  : Creates the staging table used to store the consolidated current-state
    representation of AdventureWorks sales territories before loading
    dw.DimTerritory.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE STAGING TABLE
===============================================================================
*/

IF OBJECT_ID(N'stg.Territory', N'U') IS NULL
BEGIN

    CREATE TABLE stg.Territory
    (
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
        -- Source Metadata
        -----------------------------------------------------------------------
        SourceModifiedDate DATETIME2(0) NOT NULL,
        ExtractedAt DATETIME2(7) NOT NULL
            CONSTRAINT DF_StgTerritory_ExtractedAt
            DEFAULT SYSUTCDATETIME(),


        -----------------------------------------------------------------------
        -- Change Detection
        -----------------------------------------------------------------------
        RowHash VARBINARY(32) NOT NULL,

        -----------------------------------------------------------------------
        -- Constraints
        -----------------------------------------------------------------------
        CONSTRAINT PK_StgTerritory
            PRIMARY KEY CLUSTERED (TerritoryID)
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
    AND t.name = N'Territory';
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
    c.object_id = OBJECT_ID(N'stg.Territory')
ORDER BY
    c.column_id;
GO