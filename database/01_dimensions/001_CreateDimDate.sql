/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 001_CreateDimDate.sql
Author   : Diego Suárez
Purpose  : Create the calendar date dimension used by analytical fact tables.
Version  : 0.1.0
===============================================================================
*/

USE AdventureWorks_EDW;
GO

------------------------------------------------------------------------------
-- Create date dimension
------------------------------------------------------------------------------

IF OBJECT_ID(N'dw.DimDate', N'U') IS NULL
BEGIN
    CREATE TABLE dw.DimDate
    (
        DateKey INT NOT NULL,
        FullDate DATE NOT NULL,

        DayNumberOfWeek TINYINT NOT NULL,
        DayName VARCHAR(10) NOT NULL,
        DayShortName CHAR(3) NOT NULL,
        DayNumberOfMonth TINYINT NOT NULL,
        DayNumberOfYear SMALLINT NOT NULL,

        WeekNumberOfYear TINYINT NOT NULL,

        MonthNumber TINYINT NOT NULL,
        MonthName VARCHAR(10) NOT NULL,
        MonthShortName CHAR(3) NOT NULL,
        YearMonth CHAR(7) NOT NULL,
        YearMonthNumber INT NOT NULL,

        QuarterNumber TINYINT NOT NULL,
        QuarterName CHAR(2) NOT NULL,
        YearQuarter CHAR(7) NOT NULL,
        YearQuarterNumber INT NOT NULL,

        SemesterNumber TINYINT NOT NULL,
        SemesterName CHAR(2) NOT NULL,

        CalendarYear SMALLINT NOT NULL,

        IsWeekend BIT NOT NULL,
        IsWeekday BIT NOT NULL,

        CONSTRAINT PK_DimDate
            PRIMARY KEY CLUSTERED (DateKey),

        CONSTRAINT UQ_DimDate_FullDate
            UNIQUE (FullDate),

        CONSTRAINT CK_DimDate_DayNumberOfWeek
            CHECK (DayNumberOfWeek BETWEEN 1 AND 7),

        CONSTRAINT CK_DimDate_DayNumberOfMonth
            CHECK (DayNumberOfMonth BETWEEN 1 AND 31),

        CONSTRAINT CK_DimDate_DayNumberOfYear
            CHECK (DayNumberOfYear BETWEEN 1 AND 366),

        CONSTRAINT CK_DimDate_WeekNumberOfYear
            CHECK (WeekNumberOfYear BETWEEN 1 AND 53),

        CONSTRAINT CK_DimDate_MonthNumber
            CHECK (MonthNumber BETWEEN 1 AND 12),

        CONSTRAINT CK_DimDate_QuarterNumber
            CHECK (QuarterNumber BETWEEN 1 AND 4),

        CONSTRAINT CK_DimDate_SemesterNumber
            CHECK (SemesterNumber BETWEEN 1 AND 2),

        CONSTRAINT CK_DimDate_WeekendWeekday
            CHECK
            (
                (IsWeekend = 1 AND IsWeekday = 0)
                OR
                (IsWeekend = 0 AND IsWeekday = 1)
            )
    );
END;
GO

------------------------------------------------------------------------------
-- Validate date dimension
------------------------------------------------------------------------------

SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    t.create_date AS CreatedAt
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'dw'
  AND t.name = N'DimDate';
GO