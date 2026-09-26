/*
===============================================================================
Project  : AdventureWorks Enterprise Data Warehouse
Database : master / AdventureWorks2022 / AdventureWorks_EDW
Object   : Development security configuration
Script   : 004_ConfigureDevelopmentSecurity.sql
Author   : Diego Suárez
Purpose  : Configure reproducible least-privilege access required to develop,
           deploy, execute, and validate the Enterprise Data Warehouse.
===============================================================================
*/

USE master;
GO

/*
===============================================================================
1. VALIDATE DEVELOPMENT LOGIN
===============================================================================

Required sqlcmd variable:

    DevelopmentLogin

The SQL Server login must already exist.

Authentication credentials are intentionally not created or stored in this
repository.
===============================================================================
*/

DECLARE @DevelopmentLogin SYSNAME = N'$(DevelopmentLogin)';

IF NULLIF(LTRIM(RTRIM(@DevelopmentLogin)), N'') IS NULL
BEGIN
    THROW 51000,
        'DevelopmentLogin must be provided as a sqlcmd variable.',
        1;
END;

IF SUSER_ID(@DevelopmentLogin) IS NULL
BEGIN
    DECLARE @ErrorMessage NVARCHAR(2048);

    SET @ErrorMessage =
        N'Required SQL Server login does not exist: '
        + QUOTENAME(@DevelopmentLogin);

    THROW 51001, @ErrorMessage, 1;
END;

SELECT
    @DevelopmentLogin AS DevelopmentLogin,
    SUSER_ID(@DevelopmentLogin) AS LoginPrincipalID,
    N'Login exists' AS ValidationResult;
GO


/*
===============================================================================
2. CONFIGURE SOURCE DATABASE ACCESS
===============================================================================
*/

USE AdventureWorks2022;
GO

DECLARE @DevelopmentLogin SYSNAME = N'$(DevelopmentLogin)';
DECLARE @DevelopmentSID VARBINARY(85) = SUSER_SID(@DevelopmentLogin);
DECLARE @Sql NVARCHAR(MAX);

IF @DevelopmentSID IS NULL
BEGIN
    THROW 51002,
        'DevelopmentLogin does not resolve to a valid SQL Server login.',
        1;
END;

IF DATABASE_PRINCIPAL_ID(@DevelopmentLogin) IS NULL
BEGIN
    SET @Sql =
        N'CREATE USER '
        + QUOTENAME(@DevelopmentLogin)
        + N' FOR LOGIN '
        + QUOTENAME(@DevelopmentLogin)
        + N';';

    EXEC sys.sp_executesql @Sql;
END;

IF EXISTS
(
    SELECT 1
    FROM sys.database_principals AS dp
    WHERE
        dp.name = @DevelopmentLogin
        AND dp.sid <> @DevelopmentSID
)
BEGIN
    THROW 51003,
        'Existing database user is not mapped to the expected SQL Server login.',
        1;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members AS drm
    INNER JOIN sys.database_principals AS role_principal
        ON drm.role_principal_id = role_principal.principal_id
    INNER JOIN sys.database_principals AS member_principal
        ON drm.member_principal_id = member_principal.principal_id
    WHERE
        role_principal.name = N'db_datareader'
        AND member_principal.name = @DevelopmentLogin
)
BEGIN
    SET @Sql =
        N'ALTER ROLE db_datareader ADD MEMBER '
        + QUOTENAME(@DevelopmentLogin)
        + N';';

    EXEC sys.sp_executesql @Sql;
END;

SELECT
    DB_NAME() AS DatabaseName,
    member_principal.name AS DatabaseUser,
    role_principal.name AS DatabaseRole
FROM sys.database_role_members AS drm
INNER JOIN sys.database_principals AS role_principal
    ON drm.role_principal_id = role_principal.principal_id
INNER JOIN sys.database_principals AS member_principal
    ON drm.member_principal_id = member_principal.principal_id
WHERE
    role_principal.name = N'db_datareader'
    AND member_principal.name = @DevelopmentLogin;
GO


/*
===============================================================================
3. CONFIGURE EDW DEVELOPMENT ROLE
===============================================================================
*/

USE AdventureWorks_EDW;
GO

DECLARE @DevelopmentLogin SYSNAME = N'$(DevelopmentLogin)';
DECLARE @DevelopmentSID VARBINARY(85) = SUSER_SID(@DevelopmentLogin);
DECLARE @Sql NVARCHAR(MAX);

IF @DevelopmentSID IS NULL
BEGIN
    THROW 51004,
        'DevelopmentLogin does not resolve to a valid SQL Server login.',
        1;
END;

IF DATABASE_PRINCIPAL_ID(@DevelopmentLogin) IS NULL
BEGIN
    SET @Sql =
        N'CREATE USER '
        + QUOTENAME(@DevelopmentLogin)
        + N' FOR LOGIN '
        + QUOTENAME(@DevelopmentLogin)
        + N';';

    EXEC sys.sp_executesql @Sql;
END;

IF EXISTS
(
    SELECT 1
    FROM sys.database_principals AS dp
    WHERE
        dp.name = @DevelopmentLogin
        AND dp.sid <> @DevelopmentSID
)
BEGIN
    THROW 51005,
        'Existing EDW database user is not mapped to the expected SQL Server login.',
        1;
END;

IF DATABASE_PRINCIPAL_ID(N'edw_developer') IS NULL
BEGIN
    CREATE ROLE edw_developer AUTHORIZATION dbo;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members AS drm
    INNER JOIN sys.database_principals AS role_principal
        ON drm.role_principal_id = role_principal.principal_id
    INNER JOIN sys.database_principals AS member_principal
        ON drm.member_principal_id = member_principal.principal_id
    WHERE
        role_principal.name = N'edw_developer'
        AND member_principal.name = @DevelopmentLogin
)
BEGIN
    SET @Sql =
        N'ALTER ROLE edw_developer ADD MEMBER '
        + QUOTENAME(@DevelopmentLogin)
        + N';';

    EXEC sys.sp_executesql @Sql;
END;

SELECT
    DB_NAME() AS DatabaseName,
    member_principal.name AS DatabaseUser,
    role_principal.name AS DatabaseRole
FROM sys.database_role_members AS drm
INNER JOIN sys.database_principals AS role_principal
    ON drm.role_principal_id = role_principal.principal_id
INNER JOIN sys.database_principals AS member_principal
    ON drm.member_principal_id = member_principal.principal_id
WHERE
    role_principal.name = N'edw_developer'
    AND member_principal.name = @DevelopmentLogin;
GO


/*
===============================================================================
4. GRANT EDW DEVELOPMENT PERMISSIONS
===============================================================================
*/

USE AdventureWorks_EDW;
GO

-- Database-level object creation permissions.
GRANT CREATE TABLE TO edw_developer;
GRANT CREATE PROCEDURE TO edw_developer;

-- Allow metadata inspection required for deployment and validation.
GRANT VIEW DEFINITION TO edw_developer;

-- Schema-level development permissions.
GRANT ALTER ON SCHEMA::stg TO edw_developer;
GRANT ALTER ON SCHEMA::dw TO edw_developer;
GRANT ALTER ON SCHEMA::etl TO edw_developer;
GRANT ALTER ON SCHEMA::audit TO edw_developer;

-- Required to create foreign keys that reference warehouse dimensions.
GRANT REFERENCES ON SCHEMA::dw TO edw_developer;

-- Execute ETL procedures.
GRANT EXECUTE ON SCHEMA::etl TO edw_developer;

-- Read warehouse objects during development and validation.
GRANT SELECT ON SCHEMA::stg TO edw_developer;
GRANT SELECT ON SCHEMA::dw TO edw_developer;
GRANT SELECT ON SCHEMA::etl TO edw_developer;
GRANT SELECT ON SCHEMA::audit TO edw_developer;

-- Support staging loads, dimensional loads, seeds, and controlled tests.
GRANT INSERT, UPDATE, DELETE ON SCHEMA::stg TO edw_developer;
GRANT INSERT, UPDATE, DELETE ON SCHEMA::dw TO edw_developer;
GRANT INSERT, UPDATE, DELETE ON SCHEMA::etl TO edw_developer;
GRANT INSERT, UPDATE, DELETE ON SCHEMA::audit TO edw_developer;
GO


/*
===============================================================================
5. VALIDATE EDW ROLE PERMISSIONS
===============================================================================
*/

USE AdventureWorks_EDW;
GO

SELECT
    principal.name AS PrincipalName,
    permission.state_desc AS PermissionState,
    permission.permission_name AS PermissionName,
    permission.class_desc AS SecurableClass,
    CASE
        WHEN permission.class = 0
            THEN DB_NAME()
        WHEN permission.class = 3
            THEN SCHEMA_NAME(permission.major_id)
        ELSE NULL
    END AS SecurableName
FROM sys.database_permissions AS permission
INNER JOIN sys.database_principals AS principal
    ON permission.grantee_principal_id = principal.principal_id
WHERE
    principal.name = N'edw_developer'
ORDER BY
    permission.class_desc,
    SecurableName,
    permission.permission_name;
GO


/*
===============================================================================
6. VALIDATE EFFECTIVE DEVELOPMENT PERMISSIONS
===============================================================================
*/

USE AdventureWorks_EDW;
GO

DECLARE @DevelopmentLogin SYSNAME = N'$(DevelopmentLogin)';
DECLARE @Sql NVARCHAR(MAX);

SET @Sql =
    N'EXECUTE AS USER = '
    + QUOTENAME(@DevelopmentLogin, '''')
    + N';

SELECT
    USER_NAME() AS EffectiveDatabaseUser,
    IS_ROLEMEMBER(N''edw_developer'') AS IsEdwDeveloper,
    HAS_PERMS_BY_NAME(DB_NAME(), N''DATABASE'', N''CREATE TABLE'')
        AS CanCreateTable,
    HAS_PERMS_BY_NAME(DB_NAME(), N''DATABASE'', N''CREATE PROCEDURE'')
        AS CanCreateProcedure,
    HAS_PERMS_BY_NAME(DB_NAME(), N''DATABASE'', N''VIEW DEFINITION'')
        AS CanViewDefinition,
    HAS_PERMS_BY_NAME(N''dw'', N''SCHEMA'', N''ALTER'')
        AS CanAlterDw,
    HAS_PERMS_BY_NAME(N''dw'', N''SCHEMA'', N''REFERENCES'')
        AS CanReferenceDw,
    HAS_PERMS_BY_NAME(N''dw'', N''SCHEMA'', N''SELECT'')
        AS CanSelectDw,
    HAS_PERMS_BY_NAME(N''etl'', N''SCHEMA'', N''EXECUTE'')
        AS CanExecuteEtl,
    HAS_PERMS_BY_NAME(N''audit'', N''SCHEMA'', N''INSERT'')
        AS CanInsertAudit;

REVERT;';

EXEC sys.sp_executesql @Sql;
GO
