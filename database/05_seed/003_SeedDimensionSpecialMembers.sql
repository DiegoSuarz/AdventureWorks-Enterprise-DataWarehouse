/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 003_SeedDimensionSpecialMembers.sql
Author   : Diego Suárez
Purpose  : Seed deterministic special dimension members used during surrogate
           key resolution for unknown and not-applicable conditions.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

SET XACT_ABORT ON;

DECLARE @SpecialStartDateTime DATETIME2(7) =
    CONVERT(DATETIME2(7), '1900-01-01 00:00:00');

DECLARE @SpecialSourceModifiedDate DATETIME2(0) =
    CONVERT(DATETIME2(0), '1900-01-01 00:00:00');

DECLARE @OpenEndedDateTime DATETIME2(7) =
    CONVERT
    (
        DATETIME2(7),
        '9999-12-31 23:59:59.9999999'
    );

BEGIN TRANSACTION;

/*
===============================================================================
1. DIM PRODUCT - UNKNOWN
===============================================================================
*/

SET IDENTITY_INSERT dw.DimProduct ON;

INSERT INTO dw.DimProduct
(
    ProductKey,
    ProductID,
    ProductName,
    ProductNumber,
    Color,
    Size,
    StandardCost,
    ListPrice,
    SubcategoryName,
    CategoryName,
    SellStartDate,
    SellEndDate,
    DiscontinuedDate,
    EffectiveStartDateTime,
    EffectiveEndDateTime,
    IsCurrent,
    RowHash,
    SourceModifiedDate
)
SELECT
    -1,
    -1,
    N'Unknown Product',
    N'UNKNOWN',
    NULL,
    NULL,
    CONVERT(DECIMAL(19,4), 0),
    CONVERT(DECIMAL(19,4), 0),
    N'Unknown',
    N'Unknown',
    @SpecialStartDateTime,
    NULL,
    NULL,
    @SpecialStartDateTime,
    @OpenEndedDateTime,
    1,
    HASHBYTES('SHA2_256', N'SPECIAL|DimProduct|Unknown'),
    @SpecialSourceModifiedDate
WHERE NOT EXISTS
(
    SELECT 1
    FROM dw.DimProduct
    WHERE ProductKey = -1
);

SET IDENTITY_INSERT dw.DimProduct OFF;


/*
===============================================================================
2. DIM CUSTOMER - UNKNOWN
===============================================================================
*/

SET IDENTITY_INSERT dw.DimCustomer ON;

INSERT INTO dw.DimCustomer
(
    CustomerKey,
    CustomerID,
    CustomerType,
    CustomerName,
    FirstName,
    MiddleName,
    LastName,
    StoreName,
    AccountNumber,
    EffectiveStartDateTime,
    EffectiveEndDateTime,
    IsCurrent,
    RowHash,
    SourceModifiedDate
)
SELECT
    -1,
    -1,
    N'Unknown',
    N'Unknown Customer',
    NULL,
    NULL,
    NULL,
    NULL,
    N'UNKNOWN',
    @SpecialStartDateTime,
    @OpenEndedDateTime,
    1,
    HASHBYTES('SHA2_256', N'SPECIAL|DimCustomer|Unknown'),
    @SpecialSourceModifiedDate
WHERE NOT EXISTS
(
    SELECT 1
    FROM dw.DimCustomer
    WHERE CustomerKey = -1
);

SET IDENTITY_INSERT dw.DimCustomer OFF;


/*
===============================================================================
3. DIM TERRITORY - UNKNOWN
===============================================================================
*/

SET IDENTITY_INSERT dw.DimTerritory ON;

INSERT INTO dw.DimTerritory
(
    TerritoryKey,
    TerritoryID,
    TerritoryName,
    CountryRegionCode,
    CountryRegionName,
    TerritoryGroup,
    EffectiveStartDateTime,
    EffectiveEndDateTime,
    IsCurrent,
    RowHash,
    SourceModifiedDate
)
SELECT
    -1,
    -1,
    N'Unknown Territory',
    N'UNK',
    N'Unknown',
    N'Unknown',
    @SpecialStartDateTime,
    @OpenEndedDateTime,
    1,
    HASHBYTES('SHA2_256', N'SPECIAL|DimTerritory|Unknown'),
    @SpecialSourceModifiedDate
WHERE NOT EXISTS
(
    SELECT 1
    FROM dw.DimTerritory
    WHERE TerritoryKey = -1
);

SET IDENTITY_INSERT dw.DimTerritory OFF;


/*
===============================================================================
4. DIM SALES PERSON - UNKNOWN
===============================================================================
*/

SET IDENTITY_INSERT dw.DimSalesPerson ON;

INSERT INTO dw.DimSalesPerson
(
    SalesPersonKey,
    BusinessEntityID,
    SalesPersonName,
    FirstName,
    MiddleName,
    LastName,
    JobTitle,
    HireDate,
    CurrentFlag,
    SalesQuota,
    Bonus,
    CommissionPct,
    EffectiveStartDateTime,
    EffectiveEndDateTime,
    IsCurrent,
    RowHash,
    SourceModifiedDate
)
SELECT
    -1,
    -1,
    N'Unknown Sales Person',
    N'Unknown',
    NULL,
    N'Unknown',
    N'Unknown',
    CONVERT(DATE, '19000101'),
    0,
    NULL,
    CONVERT(DECIMAL(19,4), 0),
    CONVERT(DECIMAL(10,4), 0),
    @SpecialStartDateTime,
    @OpenEndedDateTime,
    1,
    HASHBYTES('SHA2_256', N'SPECIAL|DimSalesPerson|Unknown'),
    @SpecialSourceModifiedDate
WHERE NOT EXISTS
(
    SELECT 1
    FROM dw.DimSalesPerson
    WHERE SalesPersonKey = -1
);


/*
===============================================================================
5. DIM SALES PERSON - NOT APPLICABLE
===============================================================================
*/

INSERT INTO dw.DimSalesPerson
(
    SalesPersonKey,
    BusinessEntityID,
    SalesPersonName,
    FirstName,
    MiddleName,
    LastName,
    JobTitle,
    HireDate,
    CurrentFlag,
    SalesQuota,
    Bonus,
    CommissionPct,
    EffectiveStartDateTime,
    EffectiveEndDateTime,
    IsCurrent,
    RowHash,
    SourceModifiedDate
)
SELECT
    -2,
    -2,
    N'Not Applicable',
    N'Not',
    NULL,
    N'Applicable',
    N'Not Applicable',
    CONVERT(DATE, '19000101'),
    0,
    NULL,
    CONVERT(DECIMAL(19,4), 0),
    CONVERT(DECIMAL(10,4), 0),
    @SpecialStartDateTime,
    @OpenEndedDateTime,
    1,
    HASHBYTES('SHA2_256', N'SPECIAL|DimSalesPerson|NotApplicable'),
    @SpecialSourceModifiedDate
WHERE NOT EXISTS
(
    SELECT 1
    FROM dw.DimSalesPerson
    WHERE SalesPersonKey = -2
);

SET IDENTITY_INSERT dw.DimSalesPerson OFF;


/*
===============================================================================
6. DIM SHIP METHOD - UNKNOWN
===============================================================================
*/

SET IDENTITY_INSERT dw.DimShipMethod ON;

INSERT INTO dw.DimShipMethod
(
    ShipMethodKey,
    ShipMethodID,
    ShipMethodName,
    ShipBase,
    ShipRate,
    EffectiveStartDateTime,
    EffectiveEndDateTime,
    IsCurrent,
    RowHash,
    SourceModifiedDate
)
SELECT
    -1,
    -1,
    N'Unknown Shipping Method',
    CONVERT(DECIMAL(19,4), 0),
    CONVERT(DECIMAL(19,4), 0),
    @SpecialStartDateTime,
    @OpenEndedDateTime,
    1,
    HASHBYTES('SHA2_256', N'SPECIAL|DimShipMethod|Unknown'),
    @SpecialSourceModifiedDate
WHERE NOT EXISTS
(
    SELECT 1
    FROM dw.DimShipMethod
    WHERE ShipMethodKey = -1
);

SET IDENTITY_INSERT dw.DimShipMethod OFF;

COMMIT TRANSACTION;
GO


/*
===============================================================================
7. VALIDATE SPECIAL MEMBERS
===============================================================================
*/

SELECT
    N'DimProduct' AS DimensionName,
    ProductKey AS SurrogateKey,
    ProductID AS BusinessKey,
    ProductName AS MemberName
FROM dw.DimProduct
WHERE ProductKey < 0

UNION ALL

SELECT
    N'DimCustomer',
    CustomerKey,
    CustomerID,
    CustomerName
FROM dw.DimCustomer
WHERE CustomerKey < 0

UNION ALL

SELECT
    N'DimTerritory',
    TerritoryKey,
    TerritoryID,
    TerritoryName
FROM dw.DimTerritory
WHERE TerritoryKey < 0

UNION ALL

SELECT
    N'DimSalesPerson',
    SalesPersonKey,
    BusinessEntityID,
    SalesPersonName
FROM dw.DimSalesPerson
WHERE SalesPersonKey < 0

UNION ALL

SELECT
    N'DimShipMethod',
    ShipMethodKey,
    ShipMethodID,
    ShipMethodName
FROM dw.DimShipMethod
WHERE ShipMethodKey < 0

ORDER BY
    DimensionName,
    SurrogateKey;
GO
