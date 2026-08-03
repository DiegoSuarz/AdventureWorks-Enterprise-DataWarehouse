/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 001_CreateDatabase.sql
Author   : Diego Suárez
Purpose  : Create and configure the analytical database for local development.
Version  : 0.1.0
===============================================================================
*/

USE master;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.databases
    WHERE name = N'AdventureWorks_EDW'
)
BEGIN
    CREATE DATABASE AdventureWorks_EDW;
END;
GO

ALTER DATABASE AdventureWorks_EDW
SET RECOVERY SIMPLE;
GO

ALTER DATABASE AdventureWorks_EDW
SET AUTO_CLOSE OFF;
GO

ALTER DATABASE AdventureWorks_EDW
SET AUTO_SHRINK OFF;
GO

ALTER DATABASE AdventureWorks_EDW
SET PAGE_VERIFY CHECKSUM;
GO