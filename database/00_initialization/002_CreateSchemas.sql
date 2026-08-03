/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 002_CreateSchemas.sql
Author   : Diego Suárez
Purpose  : Create the logical schemas used by the EDW architecture.
Version  : 0.1.0
===============================================================================
*/

USE AdventureWorks_EDW;
GO

------------------------------------------------------------------------------
-- Create staging schema
------------------------------------------------------------------------------

IF NOT EXISTS
(
    SELECT 1
    FROM sys.schemas
    WHERE name = N'stg'
)
BEGIN
    EXEC sys.sp_executesql N'CREATE SCHEMA stg AUTHORIZATION dbo;';
END;
GO

------------------------------------------------------------------------------
-- Create dimensional model schema
------------------------------------------------------------------------------

IF NOT EXISTS
(
    SELECT 1
    FROM sys.schemas
    WHERE name = N'dw'
)
BEGIN
    EXEC sys.sp_executesql N'CREATE SCHEMA dw AUTHORIZATION dbo;';
END;
GO

------------------------------------------------------------------------------
-- Create ETL schema
------------------------------------------------------------------------------

IF NOT EXISTS
(
    SELECT 1
    FROM sys.schemas
    WHERE name = N'etl'
)
BEGIN
    EXEC sys.sp_executesql N'CREATE SCHEMA etl AUTHORIZATION dbo;';
END;
GO

------------------------------------------------------------------------------
-- Create audit schema
------------------------------------------------------------------------------

IF NOT EXISTS
(
    SELECT 1
    FROM sys.schemas
    WHERE name = N'audit'
)
BEGIN
    EXEC sys.sp_executesql N'CREATE SCHEMA audit AUTHORIZATION dbo;';
END;
GO

------------------------------------------------------------------------------
-- Validate the schemas
------------------------------------------------------------------------------

SELECT
    name AS SchemaName,
    USER_NAME(principal_id) AS SchemaOwner
FROM sys.schemas
WHERE name IN
(
    N'stg',
    N'dw',
    N'etl',
    N'audit'
)
ORDER BY name;
GO