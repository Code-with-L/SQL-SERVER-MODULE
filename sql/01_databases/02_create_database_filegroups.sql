-- ============================================================================
-- Script: 02_create_database_filegroups.sql
-- Manual : Part 1 - Installation and configuration
-- Topic  : FILEGROUPS, FILE placement, SIZE, FILEGROWTH
-- ============================================================================
--
-- THIS SCRIPT REBUILDS THE COURSE EXERCISE FROM YOUR ORIGINAL NOTES.
--
-- Recall: your first script, SALES.sql, specified data files on D:\, E:\
-- and F:\. This machine has only a C: drive, so that script could never run
-- here. The logic was fine; the paths were not.
--
-- Everything below is that same script, corrected to real paths, and heavily
-- commented so the concepts are visible.
--
--   DESTRUCTIVE - IT CREATES A DATABASE NAMED SalesLab. Creating is safe.
--   Running it twice fails with Msg 1801 (name already exists), which is
--   expected and changes nothing.
-- ============================================================================

USE master;
GO

-- ---------------------------------------------------------------------------
-- THE FOUR OPTIONS IN THE FILE SPECIFICATION, AND WHY EACH EXISTS
--
--   NAME       - the LOGICAL name. An alias SQL Server uses internally.
--                Renaming a logical name does not move the file. It is what
--                you reference in later ALTER DATABASE statements.
--
--   FILENAME   - the PHYSICAL path on disk. This must exist as a writable
--                folder. This is the part that broke in the original script.
--
--   SIZE       - the INITIAL size, allocated immediately. This is NOT a
--                cap. A database with more data grows past it.
--
--   MAXSIZE    - the hard ceiling before growth stops and SQL Server starts
--                throwing error 1105 "database is full". Setting MAXSIZE = 1GB
--                on a growing database means a production outage. Leave it
--                generous, or UNLIMITED.
--
--   FILEGROWTH - how much to add each time the file fills. A large increment
--                wastes space (a 300 MB growth on a busy file leaves 300 MB
--                mostly empty). A small increment causes frequent, small
--                file extensions, which fragment the file and can stall.
--                64 MB to 256 MB is the usual practical compromise.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- THE FILEGROUPS, EXPLAINED
--
--   PRIMARY           - always exists, always contains the system tables.
--                      Cannot be renamed or removed.
--
--   A USER FILEGROUP  - your own. You choose which objects live where.
--
--   WHY BOTHER?
--     1. PERFORMANCE. Hot tables (frequently read/written) on fast, low-
--        latency storage. Cold tables (logs, archives, reporting extracts) on
--        cheap, slower storage. They do not compete for the same IO.
--
--        This is the reason to know about filegroups even in a laptop project.
--
--     2. BACKUP SIZE. You can back up one filegroup at a time. Storing 90%
--        of your data in a static filegroup means your incremental backups
--        only cover the 10% that changes.
--
--     3. GROWTH MANAGEMENT. A 2 TB history table can have a huge MAXSIZE
--        without endangering the transaction log, because it is a separate
--        file.
--
--   THE COST
--     A table spans every file in its filegroup. So if a filegroup has three
--     files, reading one row may touch all three. Filegroups distribute I/O
--     across files - they do NOT parallelise a single table within one file.
-- =========================================================================---

CREATE DATABASE SalesLab
ON PRIMARY
(
    -- The PRIMARY filegroup. Note PRIMARY is a reserved word and does not
    -- need brackets in this position.
    NAME       = SalesLabPrimary,
    FILENAME   = 'C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\DATA\SalesLabPrimary.mdf',
    SIZE       = 50MB,
    MAXSIZE    = 200MB,
    FILEGROWTH = 20MB
),
FILEGROUP SalesFG
(
    -- Two files in one filegroup. On real systems these would be on SEPARATE
    -- physical disks, so that reads and writes can proceed in parallel.
    -- On one C: drive they sit side by side, so this layout gives you the
    -- structure and the syntax, but none of the parallel I/O benefit.
    NAME       = SalesData1,
    FILENAME   = 'C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\DATA\SalesData1.ndf',
    SIZE       = 200MB,
    MAXSIZE    = 800MB,
    FILEGROWTH = 100MB
),
(
    NAME       = SalesData2,
    FILENAME   = 'C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\DATA\SalesData2.ndf',
    SIZE       = 400MB,
    MAXSIZE    = 1200MB,
    FILEGROWTH = 300MB
),
FILEGROUP SalesHistoryFG
(
    -- A separate filegroup for history data. On a real server this would sit
    -- on cheap archival storage and be backed up rarely.
    --
    -- NOTE THE .ndf EXTENSION, not .mdf: a secondary data file is always
    -- .ndf. Only ONE file per database may be .mdf, and exactly one file
    -- per database is the log (.ldf).
    NAME       = SalesHistory1,
    FILENAME   = 'C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\DATA\SalesHistory1.ndf',
    SIZE       = 100MB,
    MAXSIZE    = 500MB,
    FILEGROWTH = 50MB
)
LOG ON
(
    -- THE LOG FILE. Notice it is OUTSIDE every filegroup - the log does not
    -- belong to any of them. Exactly one log file per database.
    --
    -- WHY IT IS SOFT IMPORTANT
    --   The log enables recovery AND guarantees that a committed transaction
    --   survives a power cut (WRITE-AHEAD LOGGING: the log is flushed to
    --   disk BEFORE the data page is). That is why the log file itself should
    --   be on fast, reliable storage, and why it is sized generously rather
    --   than tightly.
    NAME       = SalesLabLog,
    FILENAME   = 'C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\DATA\SalesLabLog.ldf',
    SIZE       = 300MB,
    MAXSIZE    = 800MB,
    FILEGROWTH = 100MB
);
GO

-- ---------------------------------------------------------------------------
-- 2. MAKE SalesFG THE DEFAULT
--
--   Without this, every new object lands in the PRIMARY filegroup - so
--   everything you create would quietly live on the same file as the system
--   tables, and SalesFG would sit empty.
--
--   The DEFAULT filegroup is used by every CREATE TABLE that does not
--   specify ON [filegroup].
-- ============================================================================
ALTER DATABASE SalesLab MODIFY FILEGROUP SalesFG DEFAULT;
GO

-- ============================================================================
-- 3. VERIFY THE LAYOUT - read only
-- ============================================================================
SELECT
    fg.name                        AS FileGroupName,
    f.name                         AS LogicalName,
    f.type_desc                    AS FileType,
    f.physical_name                AS OnDisk,
    f.size / 128                   AS SizeMB,
    f.max_size / 128               AS MaxSizeMB,
    f.growth / 128                 AS GrowthMB,
    fg.is_default                  AS IsDefaultFG
FROM SalesLab.sys.filegroups fg
JOIN SalesLab.sys.database_files f ON f.data_space_id = fg.data_space_id
ORDER BY fg.is_default DESC, f.type_desc, f.file_id;
GO
-- Every row with IsDefaultFG = 1 belongs to the filegroup new objects use.

-- ---------------------------------------------------------------------------
-- 4. PLACING A SPECIFIC TABLE ON A SPECIFIC FILEGROUP
--    The ON clause in CREATE TABLE, which the manual mentions explicitly.
-- ============================================================================
USE SalesLab;
GO
CREATE TABLE dbo.SalesHeader
(
    SaleID     int IDENTITY(1,1) PRIMARY KEY,
    SaleDate   datetime NOT NULL DEFAULT (GETDATE()),
    TotalAmount decimal(12,2) NOT NULL
)
ON [SalesFG];              -- this table lives in SalesFG, not PRIMARY
GO

CREATE TABLE dbo.SalesHistory
(
    SaleID       int NOT NULL,
    ArchivedDate datetime NOT NULL
)
ON [SalesHistoryFG];       -- the cold, rarely-touched table, kept separate
GO

-- Confirm the placement:
SELECT
    t.name         AS TableName,
    fg.name        AS FileGroup
FROM sys.tables t
JOIN sys.indexes i ON i.object_id = t.object_id
JOIN sys.filegroups fg ON fg.data_space_id = i.data_space_id
WHERE t.name LIKE 'Sales%'
GROUP BY t.name, fg.name
ORDER BY t.name;
GO

-- ============================================================================
-- 5. GROWING AND SHRINKING FILES AFTER THE FACT
--
--   Growing is proactive and safe. Shrinking is reactive and often a mistake.
-- ============================================================================
--   Growing now, without waiting for FILEGROWTH to trigger:
--     ALTER DATABASE SalesLab MODIFY FILE (NAME = SalesData1, SIZE = 300MB);
--
--   Growing the log (never shrink it - the log must stay large enough for
--   the biggest transaction it will ever see):
--     ALTER DATABASE SalesLab MODIFY FILE (NAME = SalesLabLog, SIZE = 500MB);
--
--   SHRINKING releases space at the END of the file only, and then
--   reconstructs the whole index in most cases. It is usually slower than
--   letting the file stay large. Prefer:
--     - a smaller FILEGROWTH increment
--     - moving a table to its own filegroup and backing that up separately
--     - if you must: DBCC SHRINKFILE (SalesData1, 250MB)
--       and only on a table you know is near the end of the file.
--
--   The one good reason to shrink: you deliberately over-provisioned during
--   a load and want the space back for something else.
-- ============================================================================

-- ============================================================================
-- 6. SETTING A DATABASE'S RECOVERY MODEL - Part 1 material
--
--   FULL        every transaction is logged in full. Supports point-in-time
--               restore. Safest. Default. Use for anything you care about.
--   SIMPLE      only the active transaction is logged. Log truncates
--               automatically, so it never grows. Faster, but you CANNOT
--               restore to a point in time - only to the last full backup.
--   BULK_LOGGED logs fully except for bulk operations. Compromise.
--
--   Log file growth is the practical symptom: under SIMPLE the log stays
--   small; under FULL it grows until a backup truncates it.
-- ============================================================================
SELECT
    name,
    recovery_model_desc,
    log_reuse_wait_desc      AS WhyTheLogIsWaiting
FROM sys.databases
WHERE name IN ('SalesLab', 'StudentRecordsDB');
GO
-- log_reuse_wait_desc reads:
--   NOTHING         no active transaction is blocking truncation
--   LOG_BACKUP     a backup must be taken first
--   ACTIVE_TRANSACTION  someone has an open transaction RIGHT NOW
--   CHECKPOINT      waiting for the next checkpoint
--
-- "The transaction log is full" is almost always log_reuse_wait_desc =
-- ACTIVE_TRANSACTION - and the fix is to find and end that transaction, NOT
-- to add disk. See 02_locking_and_blocking.sql, DBCC OPENTRAN.

ALTER DATABASE SalesLab SET RECOVERY_MODEL SIMPLE;
GO
ALTER DATABASE SalesLab SET RECOVERY_MODEL FULL;
GO

-- ============================================================================
-- 7. CHANGING COLLATION - Part 1 material
--
--   The collation is inherited from the model database at creation time.
--   You can override it per database, per column, or per comparison.
-- ============================================================================
ALTER DATABASE SalesLab COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

-- Per column:
--   ALTER TABLE dbo.Customer
--       ALTER COLUMN CustomerName varchar(50)
--       COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL;
--
-- Per comparison, without changing any definition:
--   SELECT * FROM dbo.Country
--    WHERE Country COLLATE Latin1_General_100_CI_AI = 'kenya';
--
-- Changing a database or column collation REWRITES the index on that column,
-- so it is a heavy operation on a large table.
--
-- WHY IT MATTERS ENOUGH TO MEMORISE
--   Collation decides whether two strings are "equal". Changing it changes
--   which rows match, which changes index behaviour and JOIN results.
--   A JOIN between columns with DIFFERENT collations works, but disables
--   index seeks on the columns - one of the most common causes of a
--   mysteriously slow query.
-- ============================================================================

-- ============================================================================
-- 8. CLEANUP (only if you no longer need this lab database)
--   DROP DATABASE SalesLab;
--   DESTRUCTIVE. Erases every file listed above and all data. Not reversible.
--   Requires no session to be using it.
-- ============================================================================
