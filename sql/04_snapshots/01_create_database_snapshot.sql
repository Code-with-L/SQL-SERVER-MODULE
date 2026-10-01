-- ============================================================================
-- Script: 01_create_database_snapshot.sql
-- Manual : Part 3 - Managing Database Snapshots
-- ============================================================================
--
-- WHAT A DATABASE SNAPSHOT IS
--   A point-in-time, READ-ONLY copy of a database, taken almost instantly,
--   regardless of database size.
--
--   It is NOT a backup. You cannot RESTORE from it. You cannot use it to
--   recover a dropped table. Its purpose is different and narrower.
--
-- THE ANALOGY
--   Database      = a book you are writing
--   Backup        = a photocopy of the whole book
--   Snapshot      = a bookmark. You can look up what page 40 said at the
--                   moment you inserted the bookmark.
--
--   That is the key limitation: a snapshot shows you the database as it was
--   when the snapshot was taken. Later changes are invisible to it.
--
--   Use it for: "what did this table look like before that bad job ran?"
--   Use a BACKUP for: "the database has been deleted and I need it back."
-- ============================================================================

USE master;
GO

-- ============================================================================
-- CREATE THE SNAPSHOT
-- ============================================================================
--   Syntax:  CREATE DATABASE <snapshot_name> ON
--            ( NAME = <logical_file>, FILENAME = '<path>' ) [ , ... ]
--            AS SNAPSHOT OF <source_database>;
--
--   Every data file of the SOURCE must be listed. The log file is never
--   listed - snapshots have no transaction log at all.
--
--   IMPORTANT: FILENAME may differ from the source. The .ssn extension marks
--   a snapshot file. The paths must already exist on disk.
-- ============================================================================

CREATE DATABASE StudentRecordsDB_snap1
ON
    ( NAME = StudentRecordsDB,
      FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\DATA\StudentRecordsDB.ssn' )
AS SNAPSHOT OF StudentRecordsDB;
GO

-- ============================================================================
-- VERIFY IT EXISTS
-- ============================================================================
SELECT
    name,
    source_database_id,
    is_read_only,
    source_database_name
FROM sys.databases
WHERE name LIKE 'StudentRecordsDB%';
GO
-- source_database_id is NULL for a snapshot and set for a real database.
-- is_read_only = 1 confirms the snapshot cannot be written to.

-- ============================================================================
-- COMPARE: real database vs snapshot
-- ============================================================================
SELECT
    s.name                                    AS FileName,
    s.type_desc                               AS FileType,
    s.physical_name                           AS OnDisk,
    s.size / 128                              AS SizeMB
FROM StudentRecordsDB.sys.database_files s;

SELECT
    s.name                                    AS FileName,
    s.type_desc                               AS FileType,
    s.physical_name                           AS OnDisk,
    s.size / 128                              AS SizeMB
FROM StudentRecordsDB_snap1.sys.database_files s;
GO

-- ============================================================================
-- READ THE SNAPSHOT - this is the whole point
--   Query it exactly like a normal database. It is read-only.
-- ============================================================================
USE StudentRecordsDB_snap1;
GO

SELECT 'this is the SNAPSHOT' AS Which, COUNT(*) AS RowCount FROM dbo.Customer;
GO

-- Proof it is read-only:
--   INSERT INTO dbo.Customer (CustomerName, CreationDate) VALUES ('X', GETDATE());
--   -> Msg 3903: The Database is in read-only mode.
--   UPDATE dbo.Customer SET CustomerName = 'Y';
--   -> Msg 3903 as well.

USE StudentRecordsDB;
GO

-- ============================================================================
-- THE COPY-ON-WRITE BEHAVIOUR (the important concept in this chapter)
--
--   Creating a snapshot does NOT copy your data. A 400 GB database snapshots
--   in a second because it copies NOTHING.
--
--   Instead:
--     1. The snapshot records which pages the source currently holds.
--     2. The source keeps working normally.
--     3. If a page in the SOURCE changes, SQL Server copies the ORIGINAL page
--        out of the source and into the snapshot file.
--     4. Pages that never change are shared and never duplicated.
--
--   The consequences:
--     - A snapshot starts at nearly zero size and GROWS as the source changes.
--     - The snapshot's data is frozen. It reflects the instant of creation.
--     - A source that barely changes produces a tiny snapshot.
--     - A source that changes constantly produces a snapshot approaching the
--       size of the database.
--
--   Watch it happen:
-- ============================================================================

SELECT
    s.name                                            AS SnapshotFile,
    s.size / 128                                      AS SnapshotSizeMB,
    (SELECT SUM(size) / 128
       FROM StudentRecordsDB.sys.database_files)      AS SourceSizeMB
FROM StudentRecordsDB_snap1.sys.database_files s
WHERE s.type = 0;
GO

-- Now make the source dirty and watch the snapshot grow:
--   USE StudentRecordsDB;
--   INSERT INTO dbo.Customer (CustomerName, CreationDate)
--   VALUES ('Bulk change 1', GETDATE());
--   -- repeat a few hundred times to force many new pages
--
--   Then re-run the query above. SnapshotSizeMB will have risen.

-- ============================================================================
-- RESTRICTIONS - from the manual, worth knowing
--   A snapshot cannot:
--     - be written to (no INSERT/UPDATE/DELETE/DDL)
--     - have a transaction log
--     - take part in replication as a subscriber
--     - be attached, detached, or restored
--     - span multiple filegroups' FILENAME clauses for the same logical file
--   Snapshots also expire: they are removed by the auto-close setting
--   (default 0 = never) - see ALTER DATABASE ... SET AUTO_CLOSE OFF.
--
--   FILEGROUPS: a snapshot requires every FILEGROUP in the source to have at
--   least one file listed in the CREATE SNAPSHOT statement. A database with
--   several filegroups therefore needs a longer FILENAME list.
-- ============================================================================
