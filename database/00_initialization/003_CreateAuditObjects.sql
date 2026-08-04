/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : AdventureWorks_EDW
Script   : 003_CreateAuditObjects.sql
Author   : Diego Suárez
Purpose  : Create the audit objects used to monitor ETL executions.
Version  : 0.1.0
===============================================================================
*/

USE AdventureWorks_EDW;
GO

------------------------------------------------------------------------------
-- Create ETL execution log table
------------------------------------------------------------------------------

IF OBJECT_ID(N'audit.ETLExecutionLog', N'U') IS NULL
BEGIN
    CREATE TABLE audit.ETLExecutionLog
    (
        ExecutionID BIGINT IDENTITY(1, 1) NOT NULL,
        ProcessName NVARCHAR(128) NOT NULL,
        SourceObject NVARCHAR(256) NULL,
        TargetObject NVARCHAR(256) NULL,

        StartTime DATETIME2(3) NOT NULL
            CONSTRAINT DF_ETLExecutionLog_StartTime
            DEFAULT SYSUTCDATETIME(),

        EndTime DATETIME2(3) NULL,

        [Status] VARCHAR(20) NOT NULL
            CONSTRAINT DF_ETLExecutionLog_Status
            DEFAULT 'Running',

        RowsRead BIGINT NOT NULL
            CONSTRAINT DF_ETLExecutionLog_RowsRead
            DEFAULT 0,

        RowsInserted BIGINT NOT NULL
            CONSTRAINT DF_ETLExecutionLog_RowsInserted
            DEFAULT 0,

        RowsUpdated BIGINT NOT NULL
            CONSTRAINT DF_ETLExecutionLog_RowsUpdated
            DEFAULT 0,

        RowsRejected BIGINT NOT NULL
            CONSTRAINT DF_ETLExecutionLog_RowsRejected
            DEFAULT 0,

        ErrorMessage NVARCHAR(4000) NULL,
        ExecutedBy NVARCHAR(128) NULL,

        CONSTRAINT PK_ETLExecutionLog
            PRIMARY KEY CLUSTERED (ExecutionID),

        CONSTRAINT CK_ETLExecutionLog_Status
            CHECK ([Status] IN ('Running', 'Succeeded', 'Failed')),

        CONSTRAINT CK_ETLExecutionLog_EndTime
            CHECK (EndTime IS NULL OR EndTime >= StartTime),

        CONSTRAINT CK_ETLExecutionLog_RowCounts
            CHECK
            (
                RowsRead >= 0
                AND RowsInserted >= 0
                AND RowsUpdated >= 0
                AND RowsRejected >= 0
            )
    );
END;
GO

------------------------------------------------------------------------------
-- Validate the audit table
------------------------------------------------------------------------------

SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    t.create_date AS CreatedAt
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'audit'
  AND t.name = N'ETLExecutionLog';
GO
