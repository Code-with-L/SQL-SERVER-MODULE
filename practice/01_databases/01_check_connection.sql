-- ==============================================================
-- 01_check_connection.sql
-- PART 1 / Manual 1 — which server and which database am I on?
--
-- Run this FIRST whenever you open SSMS. The DB_NAME() result
-- tells you exactly where your later statements will land.
-- If it ever says 'master', your changes will go to the system
-- database — switch with USE first.
-- ==============================================================

USE StudentRecordsDB;
GO

SELECT DB_NAME() AS CurrentDatabase;
GO

SELECT
    SERVERPROPERTY('Edition')        AS Edition,
    SERVERPROPERTY('InstanceName')   AS InstanceName,  -- NULL = the DEFAULT instance
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('IsIntegratedSecurityOnly') AS WindowsAuthOnly;  -- 1 = Windows only
GO
