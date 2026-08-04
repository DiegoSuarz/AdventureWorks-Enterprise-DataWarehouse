/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 001_LoadDimDate.sql
Author   : Diego Suárez
Purpose  : Populate dw.DimDate with calendar dates and analytical attributes.
Version  : 0.1.0
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @StartDate DATE = '2010-01-01';
DECLARE @EndDate   DATE = '2035-12-31';

------------------------------------------------------------------------------
-- Validate the requested date range
------------------------------------------------------------------------------

IF @EndDate < @StartDate
BEGIN
    ;THROW 50001, 'EndDate cannot be earlier than StartDate.', 1;
END;

IF DATEDIFF(YEAR, @StartDate, @EndDate) > 100
BEGIN
    ;THROW 50002,
          'Date range cannot exceed 100 years.',
          1;
END;


BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH NumberSequence AS
    (
        SELECT TOP (DATEDIFF(DAY, @StartDate, @EndDate) + 1)
            ROW_NUMBER() OVER
            (
                ORDER BY (SELECT NULL)
            ) - 1 AS DayOffset
        FROM sys.all_objects AS a
        CROSS JOIN sys.all_objects AS b
    ),
    CalendarDates AS
    (
        SELECT
            DATEADD(DAY, DayOffset, @StartDate) AS FullDate
        FROM NumberSequence
    ),
    DateAttributes AS
    (
        SELECT
            FullDate,

            CONVERT
            (
                INT,
                CONVERT(CHAR(8), FullDate, 112)
            ) AS DateKey,

            (
                DATEDIFF(DAY, '19000101', FullDate) % 7
            ) + 1 AS DayNumberOfWeek,

            DAY(FullDate) AS DayNumberOfMonth,

            DATEPART(DAYOFYEAR, FullDate) AS DayNumberOfYear,

            DATEPART(ISO_WEEK, FullDate) AS WeekNumberOfYear,

            MONTH(FullDate) AS MonthNumber,

            YEAR(FullDate) AS CalendarYear,

            DATEPART(QUARTER, FullDate) AS QuarterNumber,

            CASE
                WHEN MONTH(FullDate) BETWEEN 1 AND 6 THEN 1
                ELSE 2
            END AS SemesterNumber
        FROM CalendarDates
    )
    INSERT INTO dw.DimDate
    (
        DateKey,
        FullDate,

        DayNumberOfWeek,
        DayName,
        DayShortName,
        DayNumberOfMonth,
        DayNumberOfYear,

        WeekNumberOfYear,

        MonthNumber,
        MonthName,
        MonthShortName,
        YearMonth,
        YearMonthNumber,

        QuarterNumber,
        QuarterName,
        YearQuarter,
        YearQuarterNumber,

        SemesterNumber,
        SemesterName,

        CalendarYear,

        IsWeekend,
        IsWeekday
    )
    SELECT
        da.DateKey,
        da.FullDate,

        da.DayNumberOfWeek,

        CASE da.DayNumberOfWeek
            WHEN 1 THEN 'Monday'
            WHEN 2 THEN 'Tuesday'
            WHEN 3 THEN 'Wednesday'
            WHEN 4 THEN 'Thursday'
            WHEN 5 THEN 'Friday'
            WHEN 6 THEN 'Saturday'
            WHEN 7 THEN 'Sunday'
        END AS DayName,

        CASE da.DayNumberOfWeek
            WHEN 1 THEN 'Mon'
            WHEN 2 THEN 'Tue'
            WHEN 3 THEN 'Wed'
            WHEN 4 THEN 'Thu'
            WHEN 5 THEN 'Fri'
            WHEN 6 THEN 'Sat'
            WHEN 7 THEN 'Sun'
        END AS DayShortName,

        da.DayNumberOfMonth,
        da.DayNumberOfYear,

        da.WeekNumberOfYear,

        da.MonthNumber,

        CASE da.MonthNumber
            WHEN 1  THEN 'January'
            WHEN 2  THEN 'February'
            WHEN 3  THEN 'March'
            WHEN 4  THEN 'April'
            WHEN 5  THEN 'May'
            WHEN 6  THEN 'June'
            WHEN 7  THEN 'July'
            WHEN 8  THEN 'August'
            WHEN 9  THEN 'September'
            WHEN 10 THEN 'October'
            WHEN 11 THEN 'November'
            WHEN 12 THEN 'December'
        END AS MonthName,

        CASE da.MonthNumber
            WHEN 1  THEN 'Jan'
            WHEN 2  THEN 'Feb'
            WHEN 3  THEN 'Mar'
            WHEN 4  THEN 'Apr'
            WHEN 5  THEN 'May'
            WHEN 6  THEN 'Jun'
            WHEN 7  THEN 'Jul'
            WHEN 8  THEN 'Aug'
            WHEN 9  THEN 'Sep'
            WHEN 10 THEN 'Oct'
            WHEN 11 THEN 'Nov'
            WHEN 12 THEN 'Dec'
        END AS MonthShortName,

        CONVERT(CHAR(7), da.FullDate, 120) AS YearMonth,

        da.CalendarYear * 100
            + da.MonthNumber AS YearMonthNumber,

        da.QuarterNumber,

        CONCAT(
            'Q',
            da.QuarterNumber
        ) AS QuarterName,

        CONCAT(
            da.CalendarYear,
            '-Q',
            da.QuarterNumber
        ) AS YearQuarter,

        da.CalendarYear * 10
            + da.QuarterNumber AS YearQuarterNumber,

        da.SemesterNumber,

        CONCAT(
            'S',
            da.SemesterNumber
        ) AS SemesterName,

        da.CalendarYear,

        CASE
            WHEN da.DayNumberOfWeek IN (6, 7) THEN 1
            ELSE 0
        END AS IsWeekend,

        CASE
            WHEN da.DayNumberOfWeek BETWEEN 1 AND 5 THEN 1
            ELSE 0
        END AS IsWeekday

    FROM DateAttributes AS da
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM dw.DimDate AS existing
        WHERE existing.FullDate = da.FullDate
    );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;
END CATCH;
GO