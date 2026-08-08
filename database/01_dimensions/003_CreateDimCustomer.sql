/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : dw.DimCustomer
Author   : Diego Suárez
Purpose  : Store the analytical representation of AdventureWorks customers.
           Current implementation uses SCD Type 1 behavior while remaining
           structurally prepared for future SCD Type 2 history.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

IF OBJECT_ID(N'dw.DimCustomer', N'U') IS NULL
BEGIN
    CREATE TABLE dw.DimCustomer
    (
        -----------------------------------------------------------------------
        -- Surrogate and business keys
        -----------------------------------------------------------------------

        CustomerKey BIGINT IDENTITY(1,1) NOT NULL,
        CustomerID INT NOT NULL,

        -----------------------------------------------------------------------
        -- Customer attributes
        -----------------------------------------------------------------------

        CustomerType NVARCHAR(20) NOT NULL,
        CustomerName NVARCHAR(200) NOT NULL,

        FirstName NVARCHAR(50) NULL,
        MiddleName NVARCHAR(50) NULL,
        LastName NVARCHAR(50) NULL,

        StoreName NVARCHAR(200) NULL,

        AccountNumber NVARCHAR(20) NOT NULL,

        -----------------------------------------------------------------------
        -- SCD metadata
        -----------------------------------------------------------------------

        EffectiveStartDateTime DATETIME2(7) NOT NULL,

        EffectiveEndDateTime DATETIME2(7) NOT NULL
            CONSTRAINT DF_DimCustomer_EffectiveEndDateTime
            DEFAULT
            (
                CONVERT
                (
                    DATETIME2(7),
                    '9999-12-31 23:59:59.9999999'
                )
            ),

        IsCurrent BIT NOT NULL
            CONSTRAINT DF_DimCustomer_IsCurrent
            DEFAULT (1),

        -----------------------------------------------------------------------
        -- Change detection and audit metadata
        -----------------------------------------------------------------------

        RowHash VARBINARY(32) NOT NULL,

        SourceModifiedDate DATETIME2(0) NOT NULL,

        CreatedAt DATETIME2(7) NOT NULL
            CONSTRAINT DF_DimCustomer_CreatedAt
            DEFAULT SYSUTCDATETIME(),

        -----------------------------------------------------------------------
        -- Constraints
        -----------------------------------------------------------------------

        CONSTRAINT PK_DimCustomer
            PRIMARY KEY CLUSTERED (CustomerKey),

        CONSTRAINT CK_DimCustomer_CustomerType
            CHECK
            (
                CustomerType IN
                (
                    N'Individual',
                    N'Store',
                    N'Unknown'
                )
            ),

        CONSTRAINT CK_DimCustomer_ValidityRange
            CHECK
            (
                EffectiveStartDateTime
                < EffectiveEndDateTime
            )
    );
END;
GO


-----------------------------------------------------------------------
-- Create unique index on current customers
-----------------------------------------------------------------------
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE
        object_id = OBJECT_ID(N'dw.DimCustomer')
        AND name = N'UX_DimCustomer_Current'
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_DimCustomer_Current
        ON dw.DimCustomer(CustomerID)
        WHERE IsCurrent = 1;
END;
GO