/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : stg.ShipMethod
Script   : 005_CreateStagingShipMethod.sql
Author   : Diego Suárez
Purpose  : Creates the staging table used to store the normalized current-state
           representation of AdventureWorks shipping methods before loading
           dw.DimShipMethod.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE STAGING TABLE
===============================================================================
*/

IF OBJECT_ID(N'stg.ShipMethod', N'U') IS NULL
BEGIN

    CREATE TABLE stg.ShipMethod
    (
        -----------------------------------------------------------------------
        -- Business Key
        -----------------------------------------------------------------------
        ShipMethodID INT NOT NULL,

        -----------------------------------------------------------------------
        -- Descriptive Attributes
        -----------------------------------------------------------------------
        ShipMethodName NVARCHAR(50) NOT NULL,

        -----------------------------------------------------------------------
        -- Tariff Attributes
        -----------------------------------------------------------------------
        ShipBase DECIMAL(19,4) NOT NULL,
        ShipRate DECIMAL(19,4) NOT NULL,

        -----------------------------------------------------------------------
        -- Source Metadata
        -----------------------------------------------------------------------
        SourceModifiedDate DATETIME2(0) NOT NULL,

        ExtractedAt DATETIME2(7) NOT NULL
            CONSTRAINT DF_StgShipMethod_ExtractedAt
            DEFAULT SYSUTCDATETIME(),

        -----------------------------------------------------------------------
        -- Change Detection
        -----------------------------------------------------------------------
        RowHash VARBINARY(32) NOT NULL,

        -----------------------------------------------------------------------
        -- Constraints
        -----------------------------------------------------------------------
        CONSTRAINT PK_StgShipMethod
            PRIMARY KEY CLUSTERED (ShipMethodID),

        CONSTRAINT CK_StgShipMethod_ShipBase
            CHECK (ShipBase >= 0),

        CONSTRAINT CK_StgShipMethod_ShipRate
            CHECK (ShipRate >= 0)
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
    AND t.name = N'ShipMethod';
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
    c.object_id = OBJECT_ID(N'stg.ShipMethod')
ORDER BY
    c.column_id;
GO
