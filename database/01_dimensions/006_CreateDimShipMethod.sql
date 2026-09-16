/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : dw.DimShipMethod
Script   : 006_CreateDimShipMethod.sql
Author   : Diego Suárez
Purpose  : Creates the ShipMethod dimension used to analyze shipping methods
           while preserving historically relevant tariff changes.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE DIMENSION TABLE
===============================================================================
*/

IF OBJECT_ID(N'dw.DimShipMethod', N'U') IS NULL
BEGIN

    CREATE TABLE dw.DimShipMethod
    (
        -----------------------------------------------------------------------
        -- Surrogate Key
        -----------------------------------------------------------------------
        ShipMethodKey BIGINT IDENTITY(1,1) NOT NULL,

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
        -- SCD Metadata
        -----------------------------------------------------------------------
        EffectiveStartDateTime DATETIME2(7) NOT NULL,

        EffectiveEndDateTime DATETIME2(7) NOT NULL
            CONSTRAINT DF_DimShipMethod_EffectiveEndDateTime
            DEFAULT
            (
                CONVERT
                (
                    DATETIME2(7),
                    '9999-12-31 23:59:59.9999999'
                )
            ),

        IsCurrent BIT NOT NULL
            CONSTRAINT DF_DimShipMethod_IsCurrent
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
            CONSTRAINT DF_DimShipMethod_CreatedAt
            DEFAULT SYSUTCDATETIME(),

        -----------------------------------------------------------------------
        -- Constraints
        -----------------------------------------------------------------------
        CONSTRAINT PK_DimShipMethod
            PRIMARY KEY CLUSTERED (ShipMethodKey),

        CONSTRAINT CK_DimShipMethod_ValidityRange
            CHECK
            (
                EffectiveStartDateTime
                < EffectiveEndDateTime
            ),

        CONSTRAINT CK_DimShipMethod_ShipBase
            CHECK (ShipBase >= 0),

        CONSTRAINT CK_DimShipMethod_ShipRate
            CHECK (ShipRate >= 0)
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
        object_id = OBJECT_ID(N'dw.DimShipMethod')
        AND name = N'UX_DimShipMethod_Current'
)
BEGIN

    CREATE UNIQUE NONCLUSTERED INDEX UX_DimShipMethod_Current
        ON dw.DimShipMethod(ShipMethodID)
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
    AND t.name = N'DimShipMethod';
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
    c.object_id = OBJECT_ID(N'dw.DimShipMethod')
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
    i.object_id = OBJECT_ID(N'dw.DimShipMethod')
ORDER BY
    i.index_id;
GO
