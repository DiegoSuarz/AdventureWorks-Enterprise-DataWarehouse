/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : dw.FactSales
Script   : 001_CreateFactSales.sql
Author   : Diego Suárez
Purpose  : Create the sales fact table at sales order detail grain.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE FACT TABLE
===============================================================================
*/

IF OBJECT_ID(N'dw.FactSales', N'U') IS NULL
BEGIN

    CREATE TABLE dw.FactSales
    (
        -----------------------------------------------------------------------
        -- Role-playing date keys
        -----------------------------------------------------------------------
        OrderDateKey INT NOT NULL,
        DueDateKey INT NOT NULL,
        ShipDateKey INT NULL,

        -----------------------------------------------------------------------
        -- Dimensional surrogate keys
        -----------------------------------------------------------------------
        ProductKey BIGINT NOT NULL,
        CustomerKey BIGINT NOT NULL,
        TerritoryKey BIGINT NOT NULL,
        SalesPersonKey BIGINT NOT NULL,
        ShipMethodKey BIGINT NOT NULL,

        -----------------------------------------------------------------------
        -- Degenerate transaction identifiers
        -----------------------------------------------------------------------
        SalesOrderID INT NOT NULL,
        SalesOrderDetailID INT NOT NULL,
        SalesOrderNumber NVARCHAR(25) NOT NULL,

        -----------------------------------------------------------------------
        -- Transaction attributes
        -----------------------------------------------------------------------
        OrderStatusCode TINYINT NOT NULL,
        IsOnlineOrder BIT NOT NULL,

        -----------------------------------------------------------------------
        -- Measures and numeric transaction attributes
        -----------------------------------------------------------------------
        OrderQuantity SMALLINT NOT NULL,
        UnitPrice DECIMAL(19,4) NOT NULL,
        DiscountRate DECIMAL(10,4) NOT NULL,

        GrossAmount DECIMAL(19,4) NOT NULL,
        DiscountAmount DECIMAL(19,4) NOT NULL,
        NetSalesAmount DECIMAL(19,4) NOT NULL,

        -----------------------------------------------------------------------
        -- Primary key
        -----------------------------------------------------------------------
        CONSTRAINT PK_FactSales
            PRIMARY KEY CLUSTERED
            (
                SalesOrderID,
                SalesOrderDetailID
            ),

        -----------------------------------------------------------------------
        -- Domain constraints
        -----------------------------------------------------------------------
        CONSTRAINT CK_FactSales_OrderStatusCode
            CHECK
            (
                OrderStatusCode BETWEEN 1 AND 6
            ),

        CONSTRAINT CK_FactSales_OrderQuantity
            CHECK
            (
                OrderQuantity > 0
            ),

        CONSTRAINT CK_FactSales_UnitPrice
            CHECK
            (
                UnitPrice >= 0
            ),

        CONSTRAINT CK_FactSales_DiscountRate
            CHECK
            (
                DiscountRate BETWEEN 0 AND 1
            ),

        CONSTRAINT CK_FactSales_GrossAmount
            CHECK
            (
                GrossAmount >= 0
            ),

        CONSTRAINT CK_FactSales_DiscountAmount
            CHECK
            (
                DiscountAmount >= 0
                AND DiscountAmount <= GrossAmount
            ),

        CONSTRAINT CK_FactSales_NetSalesAmount
            CHECK
            (
                NetSalesAmount >= 0
                AND NetSalesAmount <= GrossAmount
            ),

        -----------------------------------------------------------------------
        -- Date and product foreign keys
        -----------------------------------------------------------------------
        CONSTRAINT FK_FactSales_OrderDate
            FOREIGN KEY (OrderDateKey)
            REFERENCES dw.DimDate(DateKey),

        CONSTRAINT FK_FactSales_DueDate
            FOREIGN KEY (DueDateKey)
            REFERENCES dw.DimDate(DateKey),

        CONSTRAINT FK_FactSales_ShipDate
            FOREIGN KEY (ShipDateKey)
            REFERENCES dw.DimDate(DateKey),

        CONSTRAINT FK_FactSales_Product
            FOREIGN KEY (ProductKey)
            REFERENCES dw.DimProduct(ProductKey),

        CONSTRAINT FK_FactSales_Customer
            FOREIGN KEY (CustomerKey)
            REFERENCES dw.DimCustomer(CustomerKey),

        CONSTRAINT FK_FactSales_Territory
            FOREIGN KEY (TerritoryKey)
            REFERENCES dw.DimTerritory(TerritoryKey),

        CONSTRAINT FK_FactSales_SalesPerson
            FOREIGN KEY (SalesPersonKey)
            REFERENCES dw.DimSalesPerson(SalesPersonKey),

        CONSTRAINT FK_FactSales_ShipMethod
            FOREIGN KEY (ShipMethodKey)
            REFERENCES dw.DimShipMethod(ShipMethodKey)
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
    s.name = N'dw'
    AND t.name = N'FactSales';
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
    c.object_id = OBJECT_ID(N'dw.FactSales')
ORDER BY
    c.column_id;
GO


/*
===============================================================================
4. VALIDATE KEY AND CHECK CONSTRAINTS
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SELECT
    kc.name AS ConstraintName,
    kc.type_desc AS ConstraintType
FROM sys.key_constraints AS kc
WHERE
    kc.parent_object_id = OBJECT_ID(N'dw.FactSales')

UNION ALL

SELECT
    cc.name AS ConstraintName,
    N'CHECK_CONSTRAINT' AS ConstraintType
FROM sys.check_constraints AS cc
WHERE
    cc.parent_object_id = OBJECT_ID(N'dw.FactSales')
ORDER BY
    ConstraintType,
    ConstraintName;
GO


/*
===============================================================================
5. VALIDATE FOREIGN KEYS
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SELECT
    fk.name AS ForeignKeyName,
    pc.name AS FactColumn,
    OBJECT_SCHEMA_NAME(fk.referenced_object_id) AS ReferencedSchema,
    OBJECT_NAME(fk.referenced_object_id) AS ReferencedTable,
    rc.name AS ReferencedColumn
FROM sys.foreign_keys AS fk
INNER JOIN sys.foreign_key_columns AS fkc
    ON fk.object_id = fkc.constraint_object_id
INNER JOIN sys.columns AS pc
    ON fkc.parent_object_id = pc.object_id
    AND fkc.parent_column_id = pc.column_id
INNER JOIN sys.columns AS rc
    ON fkc.referenced_object_id = rc.object_id
    AND fkc.referenced_column_id = rc.column_id
WHERE
    fk.parent_object_id = OBJECT_ID(N'dw.FactSales')
ORDER BY
    fk.name;
GO
