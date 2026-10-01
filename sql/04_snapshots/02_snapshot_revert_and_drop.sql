-- ============================================================================
-- Script: 02_snapshot_revert_and_drop.sql
-- Manual : Part 3 - Creating and reverting snapshots
-- WARNING: EVERY SCRIPT IN THIS FILE IS DESTRUCTIVE
-- ============================================================================
--
--   DROP DATABASE and DROP SNAPSHOT both erase files from disk.
--   Nothing in Git can bring back data. Only a .bak can.
--   Read every line before running anything here.
-- ============================================================================

USE master;
GO

-- ============================================================================
-- RECOVERY SCENARIO 1: a bad UPDATE destroyed data.
--   The snapshot holds the ORIGINAL rows. This is what snapshots are FOR.
-- ============================================================================
--
-- Step 1 - simulate the accident (in the live database):
--   USE StudentRecordsDB;
--   UPDATE dbo.Customer
--      SET CreditLine = 0;            -- someone runs a bad UPDATE
--
-- Step 2 - confirm the damage:
--   USE StudentRecordsDB;
--   SELECT CustomerID, CustomerName, CreditLine FROM dbo.Customer;
--
-- Step 3 - see the ORIGINAL values in the snapshot:
--   USE StudentRecordsDB_snap1;
--   SELECT CustomerID, CustomerName, CreditLine FROM dbo.Customer;
--   -- CreditLine still holds 50000, 20000, 80000, 15000
--
-- Step 4 - repair by copying the good values back:
--   USE StudentRecordsDB;
--   UPDATE live
--      SET live.CreditLine = snap.CreditLine
--     FROM dbo.Customer live
--     JOIN StudentRecordsDB_snap1.dbo.Customer snap
--       ON snap.CustomerID = live.CustomerID;
--
-- THAT is the real workflow. You do NOT "revert" a snapshot onto a database.
-- You read from the snapshot and write into the live database, one row at a
-- time, with a WHERE clause you can see and approve.
-- ============================================================================

-- ============================================================================
-- RECOVERY SCENARIO 2: someone DROPped a table.
--   Restore the table's definition AND its rows from the snapshot.
-- ============================================================================
--
-- Step 1 - confirm it is really gone:
--   USE StudentRecordsDB;
--   SELECT OBJECT_ID('dbo.Customer') AS CustomerTableObjectId;   -- NULL
--
-- Step 2 - pull the DEFINITION out of the snapshot (read-only, always safe):
--
SELECT
    OBJECT_DEFINITION(OBJECT_ID('dbo.Customer')) AS Definition;
GO
-- Run this in the SNAPSHOT context to get the definition as it was:
--   USE StudentRecordsDB_snap1;
--   SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.Customer'));

-- Step 3 - rebuild the table in the live database:
--   CREATE TABLE dbo.Customer ( ...same definition as the snapshot... );
--
-- Step 4 - copy the rows across:
--   INSERT INTO dbo.Customer (CustomerID, CustomerName, CreditLine, ...)
--   SELECT CustomerID, CustomerName, CreditLine, ...
--   FROM StudentRecordsDB_snap1.dbo.Customer;
--
-- Note: you CANNOT SELECT * across databases if column order differs, and
-- IDENTITY_INSERT is needed because CustomerID is an IDENTITY column:
--   SET IDENTITY_INSERT dbo.Customer ON;
--   INSERT INTO dbo.Customer (CustomerID, CustomerName, CreationDate)
--   SELECT CustomerID, CustomerName, CreationDate
--   FROM StudentRecordsDB_snap1.dbo.Customer;
--   SET IDENTITY_INSERT dbo.Customer OFF;

-- ============================================================================
-- ###############  DESTRUCTIVE  ###########################################
-- ###############  DROP SNAPSHOT  ###########################################
--
--   WHAT IT DOES
--     Deletes the snapshot database and its .ssn file from disk.
--     The SOURCE database is not touched at all.
--     All data the snapshot held is gone. If the snapshot is your only record
--     of pre-accident data, dropping it destroys your safety net.
--
--   WHEN TO DO IT
--     Snapshots accumulate and consume disk. Delete old ones once the
--     investigation is finished and a proper BACKUP exists.
--
--   ALWAYS DROP FIRST, MEASURE SECOND. Dropping is far cheaper than running
--   out of disk on a production server.
-- ============================================================================
-- DROP DATABASE StudentRecordsDB_snap1;

-- ---------------------------------------------------------------------------
-- How many snapshots exist, and how much disk are they using?
-- ---------------------------------------------------------------------------
SELECT
    sdb.name                        AS SnapshotName,
    sdb.create_date                 AS CreatedAt,
    SUM(f.size) / 128               AS SizeMB
FROM sys.databases sdb
JOIN sys.master_files f ON f.database_id = sdb.database_id
WHERE sdb.source_database_id IS NOT NULL     -- snapshots only
GROUP BY sdb.name, sdb.create_date
ORDER BY sdb.create_date;
GO
-- Note: sys.master_files reports the LOG file size of a database, which is
-- meaningless for a snapshot because snapshots have no log. For accurate
-- snapshot size, query sys.database_files inside each snapshot instead.

-- ============================================================================
-- LISTING SNAPSHOTS OF A PARTICULAR DATABASE
-- ============================================================================
SELECT
    name          AS SnapshotName,
    create_date   AS CreatedAt
FROM sys.databases
WHERE source_database_id = DB_ID('StudentRecordsDB')
ORDER BY create_date;
GO

-- ============================================================================
-- SNAPSHOT vs BACKUP - the comparison the manual expects you to be able to
-- make from memory
-- ============================================================================
--                    DATABASE SNAPSHOT        FULL BACKUP
--   Speed           seconds                  scales with size (minutes)
--   Size on disk    grows on change          full size immediately
--   Restorable?     NO - cannot RESTORE      YES - this is its purpose
--   Writable?       NO - read only           n/a
--   Log file?       none                     yes
--   Point-in-time?   one instant only          with log backups, many
--   Typical use     "what changed?"          "we lost the database"
--
--   They are complementary, not alternatives. Almost every real recovery
--   strategy uses BOTH.
-- ============================================================================
