/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : audit.ETLWatermark
Script   : 002_SeedETLWatermark.sql
Author   : Diego Suárez
Purpose  : Register the initial watermark control state for incremental ETL
           processes.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. REGISTER SHIP METHOD INCREMENTAL PROCESS
===============================================================================
*/

IF NOT EXISTS
(
    SELECT 1
    FROM audit.ETLWatermark
    WHERE ProcessName = N'etl.LoadShipMethodIncremental'
)
BEGIN
    INSERT INTO audit.ETLWatermark
    (
        ProcessName,
        SourceObject
    )
    VALUES
    (
        N'etl.LoadShipMethodIncremental',
        N'AdventureWorks2022.Purchasing.ShipMethod'
    );
END;
GO

/*
===============================================================================
2. VALIDATE WATERMARK INITIAL STATE
===============================================================================
*/

SELECT
    WatermarkID,
    ProcessName,
    SourceObject,
    LowModifiedDate,
    LowBusinessKey,
    HighModifiedDate,
    HighBusinessKey,
    [Status],
    LastSuccessfulExecutionID,
    CurrentExecutionID,
    CreatedAt,
    UpdatedAt
FROM audit.ETLWatermark
WHERE ProcessName = N'etl.LoadShipMethodIncremental';
GO
