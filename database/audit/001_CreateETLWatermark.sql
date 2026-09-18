/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Object   : audit.ETLWatermark
Script   : 001_CreateETLWatermark.sql
Author   : Diego Suárez
Purpose  : Persist composite and high watermark state for incremental ETL
           processes.
===============================================================================
*/

USE AdventureWorks_EDW;
GO

/*
===============================================================================
1. CREATE WATERMARK CONTROL TABLE
===============================================================================
*/

IF OBJECT_ID(N'audit.ETLWatermark', N'U') IS NULL
BEGIN
    CREATE TABLE audit.ETLWatermark
    (
        WatermarkID BIGINT IDENTITY(1, 1) NOT NULL,

        ProcessName NVARCHAR(128) NOT NULL,
        SourceObject NVARCHAR(256) NOT NULL,

        LowModifiedDate DATETIME2(7) NULL,
        LowBusinessKey BIGINT NULL,

        HighModifiedDate DATETIME2(7) NULL,
        HighBusinessKey BIGINT NULL,

        [Status] VARCHAR(20) NOT NULL
            CONSTRAINT DF_ETLWatermark_Status
            DEFAULT 'Ready',

        LastSuccessfulExecutionID BIGINT NULL,
        CurrentExecutionID BIGINT NULL,

        CreatedAt DATETIME2(7) NOT NULL
            CONSTRAINT DF_ETLWatermark_CreatedAt
            DEFAULT SYSUTCDATETIME(),

        UpdatedAt DATETIME2(7) NOT NULL
            CONSTRAINT DF_ETLWatermark_UpdatedAt
            DEFAULT SYSUTCDATETIME(),

        /*
        -----------------------------------------------------------------------
        Keys and uniqueness
        -----------------------------------------------------------------------
        */

        CONSTRAINT PK_ETLWatermark
            PRIMARY KEY CLUSTERED (WatermarkID),

        CONSTRAINT UQ_ETLWatermark_ProcessName
            UNIQUE NONCLUSTERED (ProcessName),

        /*
        -----------------------------------------------------------------------
        Composite watermark integrity
        -----------------------------------------------------------------------
        */

        CONSTRAINT CK_ETLWatermark_LowPair
            CHECK
            (
                (
                    LowModifiedDate IS NULL
                    AND LowBusinessKey IS NULL
                )
                OR
                (
                    LowModifiedDate IS NOT NULL
                    AND LowBusinessKey IS NOT NULL
                )
            ),

        CONSTRAINT CK_ETLWatermark_HighPair
            CHECK
            (
                (
                    HighModifiedDate IS NULL
                    AND HighBusinessKey IS NULL
                )
                OR
                (
                    HighModifiedDate IS NOT NULL
                    AND HighBusinessKey IS NOT NULL
                )
            ),

        /*
        -----------------------------------------------------------------------
        Watermark state
        -----------------------------------------------------------------------
        */

        CONSTRAINT CK_ETLWatermark_Status
            CHECK
            (
                [Status] IN
                (
                    'Ready',
                    'InProgress',
                    'Failed'
                )
            ),

        CONSTRAINT CK_ETLWatermark_StateConsistency
            CHECK
            (
                (
                    [Status] = 'Ready'
                    AND HighModifiedDate IS NULL
                    AND HighBusinessKey IS NULL
                    AND CurrentExecutionID IS NULL
                )
                OR
                (
                    [Status] IN ('InProgress', 'Failed')
                    AND HighModifiedDate IS NOT NULL
                    AND HighBusinessKey IS NOT NULL
                    AND CurrentExecutionID IS NOT NULL
                )
            ),

        /*
        -----------------------------------------------------------------------
        Composite ordering
        -----------------------------------------------------------------------
        */

        CONSTRAINT CK_ETLWatermark_HighAfterLow
            CHECK
            (
                LowModifiedDate IS NULL
                OR HighModifiedDate IS NULL
                OR HighModifiedDate > LowModifiedDate
                OR
                (
                    HighModifiedDate = LowModifiedDate
                    AND HighBusinessKey > LowBusinessKey
                )
            ),

        /*
        -----------------------------------------------------------------------
        Audit execution references
        -----------------------------------------------------------------------
        */

        CONSTRAINT CK_ETLWatermark_LastSuccessfulExecutionID
            CHECK
            (
                LastSuccessfulExecutionID IS NULL
                OR LastSuccessfulExecutionID > 0
            ),

        CONSTRAINT CK_ETLWatermark_CurrentExecutionID
            CHECK
            (
                CurrentExecutionID IS NULL
                OR CurrentExecutionID > 0
            )
    );
END;
GO

/*
===============================================================================
2. VALIDATE WATERMARK CONTROL TABLE
===============================================================================
*/

SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    t.create_date AS CreatedAt
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'audit'
  AND t.name = N'ETLWatermark';
GO
