-- ============================================================================
-- Script: 03_instances_editions_auth.sql
-- Manual : Part 1 - Installing SQL Server, editions, instances, authentication
-- ============================================================================
--
-- EVERYTHING IN THIS SCRIPT IS READ ONLY. It only READS SQL Server's own
-- catalogue views to report how this server is configured. Change nothing.
--
-- Everything here maps to a question your lecturer can ask, and to the
-- "Understanding SQL Server Editions" chapter of Part 1.
-- ============================================================================

-- ============================================================================
-- 1. EDITIONS
--
--   The edition decides what features you may use and how much hardware you
--   may use. It is chosen once, at install time, and is the most expensive
--   decision in Part 1.
--
--   Enterprise     - everything: compression, TDE, partitioning, snapshot,
--                    row-level security, unlimited cores. Licensed per core.
--   Standard       - most features. No compression, no TDE.
--   Web            - free. Small footprint, no memory limit beyond ~4 GB.
--   Express        - free. Capped at 1 socket and ~10 GB buffer pool. Ideal
--                    for learning and for a small free database.
--   Developer      - Enterprise features, FREE, but LICENSED FOR DEVELOPMENT
--                    ONLY. Running a Developer edition in production is a
--                    licensing violation.
--
--   YOUR SERVER: Enterprise Developer Edition. Perfect for this course - every
--   feature is available. Remember it must not be used commercially.
-- ============================================================================
SELECT
    SERVERPROPERTY('ProductVersion')          AS ProductVersion,      -- 17.x
    SERVERPROPERTY('ProductLevel')            AS ProductLevel,       -- RTM
    SERVERPROPERTY('Edition')                 AS Edition,
    SERVERPROPERTY('EditionID')               AS EditionID,
    SERVERPROPERTY('EngineEdition')           AS EngineEdition,       -- 17
    SERVERPROPERTY('ProductVersion')          AS FullVersion,
    SERVERPROPERTY('InstanceName')            AS InstanceName,        -- MSSQLSERVER
    SERVERPROPERTY('MachineName')             AS MachineName,
    SERVERPROPERTY('ComputerName')            AS ComputerName,
    SERVERPROPERTY('ServerName')              AS ServerName,
    SERVERPROPERTY('IsClustered')             AS IsClustered,
    SERVERPROPERTY('IsIntegratedSecurityOnly')AS WindowsAuthOnly,
    SERVERPROPERTY('IsStandalone')            AS IsStandalone,
    SERVERPROPERTY('ProductInfo')             AS ProductInfo;
GO
-- Read the results against the edition table above.

-- ============================================================================
-- 2. INSTANCES - the concept Part 1 spends most of its pages on
--
--   An INSTANCE is a completely independent SQL Server: its own services,
--   its own databases, its own memory, its own configuration, its own port.
--
--   WHY RUN MORE THAN ONE
--     - Test an upgrade without touching production
--     - Run SQL 2005 side by side with SQL 2025 (this is exactly the
--       situation your course manuals describe!)
--     - Separate customers' data from each other
--     - A 32-bit instance alongside a 64-bit instance
--
--   DEFAULT INSTANCE
--     Always named MSSQLSERVER. Reached with NO name:
--         localhost
--         localhost,1433
--         SERVER\  (empty)
--     It gets the "nice" service names - MSSQLSERVER, SQLSERVERAGENT - with no
--     $ suffix. Only one default instance can exist per computer.
--
--   NAMED INSTANCES
--     You choose the name at install. Reached as:
--         SERVER\NAME
--         localhost\SQLEXPRESS
--     Services become MSSQL$NAME, SQLAgent$NAME. The $ means "parameterised
--     service" - that is how one SCM template serves any instance name.
--
--   WHY THIS MATTERS TO YOU RIGHT NOW
--     Your SSMS title bar says "localhost (SQL Server 17.0...)" with no
--     backslash and no instance name. That is how you know you are on the
--     DEFAULT instance. If it were a named instance it would read
--     "localhost\SQLEXPRESS (...)" or similar.
--
--     SSMS lists both kinds in the Connect dialog's Server name dropdown:
--       Browse              - network servers found automatically
--       <local>             - this computer
--       localhost           - default instance
--       localhost\SQLEXPRESS- named instance
-- ============================================================================
SELECT
    SERVERPROPERTY('InstanceName')                     AS InstanceName,
    SERVERPROPERTY('InstanceName')                     AS IsDefaultInstance,
    SERVERPROPERTY('ServerName')                       AS HowToConnect,
    @@SERVERNAME                                       AS AtServerName,
    @@SERVICENAME                                      AS WindowsServiceName;
GO
-- InstanceName = MSSQLSERVER, so this IS the default instance.
-- @@SERVERNAME returns whatever NAME the client typed to reach it, which is a
-- classic gotcha: it can read "localhost" even though the machine is
-- LEOKINGXLING. Use SERVERPROPERTY('ServerName') when you want the truth.

-- Which services are registered on this machine?
SELECT
    servicename    AS ServiceName,
    status_desc    AS Status,
    start_mode_desc AS StartMode,
    start_name     AS RunsAsAccount
FROM sys.dm_server_services;
GO
-- status_desc = 'Running' confirms SQL Server is up.
-- start_mode_desc tells you whether it starts automatically or manually.
-- start_name is the SERVICE ACCOUNT - the Windows identity the service runs
-- as. That account needs rights to the data folders and the Windows Event Log.
-- Never use LocalSystem for a production SQL Server; the virtual accounts
-- NT SERVICE\MSSQLSERVER (or a domain gMSA) are preferred.

-- ============================================================================
-- 3. AUTHENTICATION - how someone proves who they are
--
--   WINDOWS AUTHENTICATION (a.k.a. "integrated")
--     The client sends the Windows token. SQL Server trusts the domain.
--     No password is ever transmitted or stored by SQL Server.
--     Centralised, supports groups, Kerberos, lockout policy, MFA.
--     THIS IS WHAT YOUR SERVER USES.
--
--   SQL SERVER AUTHENTICATION ("mixed mode")
--     SQL Server stores and checks passwords itself in master..sys.sql_logins.
--     Passwords are hashed, but SQL Server is the system of record.
--     Needed for: non-Windows clients, legacy apps, cross-platform.
--
--   MIXED MODE = both enabled. Usually needed only during a migration from a
--   SQL-auth setup to Windows auth.
--
--   YOUR SERVER: Windows only. That is the more secure option and it is why
--   this project has NO passwords anywhere. Notice SERVERPROPERTY above:
--   IsIntegratedSecurityOnly should read 1.
--
--   WHY SQL SERVER AUTH IS WORSE
--     - The password exists in sys.sql_logins (hashed, but present)
--     - No lockout policy by default
--     - No central revocation - change it on every server individually
--     - No group membership, so permissions are managed one login at a time
--
--   Checking which logins exist and how they authenticate:
-- ============================================================================
SELECT
    name                                        AS LoginName,
    type_desc                                   AS Type,
    is_disabled                                 AS IsDisabled,
    is_policy_checked                           AS PasswordPolicyChecked,
    is_expiration_checked                       AS PasswordExpiryChecked,
    create_date                                 AS CreatedOn
FROM sys.server_principals
WHERE type IN ('S', 'U', 'G')
ORDER BY type_desc, name;
GO
-- type_desc values:
--   S = SQL LOGIN          (a SQL Server login - has a SQL password)
--   U = WINDOWS LOGIN      (maps to a Windows account - no SQL password)
--   G = WINDOWS GROUP      (a Windows group, mapped for convenience)
--
-- Your own login should appear as U. If you see S logins, mixed mode is on.
--
-- server_principals is a SERVER-level catalogue view, so it is queried from
-- ANY database but always describes the whole server. Contrast with
-- sys.database_principals which is database-specific (see 03_security/).

-- Your Windows login mapped into the database:
SELECT
    dp.name        AS DatabaseUser,
    dp.type_desc   AS UserType,
    dp.authentication_type_desc AS AuthType,
    dp.sid         AS SecurityIdentifier
FROM sys.database_principals dp
WHERE dp.sid IS NOT NULL AND dp.type = 'U';
GO
-- authentication_type_desc reads WINDOWS, confirming no SQL auth is in play.

-- ============================================================================
-- 4. MEMORY - the setting administrators argue about most
--
--   The manual's guidance: leave the DEFAULT configuration to SQL Server
--   unless you have measured a reason to change it.
--
--   modern versions have MIN_SERVER_MEMORY / MAX_SERVER_MEMORY, and
--   server_memory_options. Default is automatic, which SQL Server manages.
-- ============================================================================
SELECT
    sqlserver_start_time                        AS StartedAt,
    total_server_memory_gb / 1024               AS MaxServerMemoryGB,
    min_server_memory_gb / 1024                 AS MinServerMemoryGB,
    DATEDIFF(HOUR, sqlserver_start_time, SYSDATETIME()) AS HoursSinceRestart
FROM sys.dm_os_sys_memory;
GO
-- total_server_memory_gb is in KB, hence / 1024 to reach GB.
-- If this EQUALS your physical RAM, SQL Server is configured to take
-- everything. On a shared machine that starves Windows itself; the usual
-- advice is to leave 1-2 GB for the OS.

-- ============================================================================
-- 5. COMPATIBILITY LEVEL - the 2005 vs 2025 difference, restated
--
--   The manuals describe SQL Server 2005, which is compatibility level 90.
--   This server is level 170. Behaviour changes between levels include:
--
--     - Query optimiser decisions
--     - Whether a missing outer join row counts as a match
--     - ANSI behaviour for some expressions
--     - Whether the DATE/TIME/DATETIME2 types exist at all (introduced at 110,
--       i.e. SQL Server 2008 - which is why they did not exist in 2005)
--
--   Setting a database to level 90 on SQL Server 2025 is possible and is how
--   applications are validated before an upgrade.
-- ============================================================================
SELECT
    name                          AS DatabaseName,
    compatibility_level           AS CompatLevel,
    CASE compatibility_level
        WHEN 90  THEN 'SQL Server 2005  <-- your course manuals'
        WHEN 100 THEN 'SQL Server 2008'
        WHEN 110 THEN 'SQL Server 2012'
        WHEN 120 THEN 'SQL Server 2014'
        WHEN 130 THEN 'SQL Server 2016'
        WHEN 140 THEN 'SQL Server 2017'
        WHEN 150 THEN 'SQL Server 2019'
        WHEN 160 THEN 'SQL Server 2022'
        WHEN 170 THEN 'SQL Server 2025  <-- this server'
    END                           AS WhichVersion
FROM sys.databases
WHERE database_id > 4            -- exclude the four system databases
ORDER BY name;
GO

-- Changing it (DANGEROUS on a real system - forces a plan cache flush and can
-- change query behaviour overnight, so it is never done casually):
--   ALTER DATABASE StudentRecordsDB SET COMPATIBILITY_LEVEL = 90;

-- ============================================================================
-- 6. PUTTING PART 1 TOGETHER - the six questions
--
--   Q: What edition?          SERVERPROPERTY('Edition')
--   Q: Default or named?      SERVERPROPERTY('InstanceName') = MSSQLSERVER
--   Q: How many instances?    Get-Service, or SQL Server Configuration Manager
--   Q: What service account?   sys.dm_server_services.start_name
--   Q: Which auth mode?       SERVERPROPERTY('IsIntegratedSecurityOnly')
--   Q: What collation?        sys.databases.collation_name
--
--   You can now answer all six for any SQL Server, including this one,
--   without opening the GUI. That is the practical skill Part 1 is teaching.
-- ============================================================================
