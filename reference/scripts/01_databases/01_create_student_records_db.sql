-- ============================================================
-- Script: 01_create_student_records_db.sql
-- Manual reference: Part 1 (Installation & Configuration)
-- Purpose: Create the course database
-- Author: <put your name here>
-- Created: <put the date here>
-- ============================================================
--
-- WHAT THIS DOES:
--   Creates a new, empty database called StudentRecordsDB.
--   It clones the structure of the system database `model`.
--
-- SAFETY:
--   NOT destructive. CREATE DATABASE cannot overwrite anything.
--   If a database of this name already exists, SQL Server raises
--   error 1801 and changes nothing.
--
-- NOTE:
--   This script is NOT safe to run twice. Running it a second time
--   fails with "Msg 1801: Could not create database ... because
--   the name already exists." That is expected, not a bug.
--
-- TO REBUILD FROM SCRATCH you would need DROP DATABASE, which is
--   destructive and deletes all data. Do not run that casually.
-- ============================================================

USE master;   -- CREATE DATABASE must be run from outside the target DB
GO

CREATE DATABASE StudentRecordsDB;
GO

-- VERIFICATION (read-only, safe to run any time):
--   Shows the physical files SQL Server created on disk.
USE StudentRecordsDB;
GO

SELECT
    name            AS LogicalName,       -- alias SQL Server uses internally
    type_desc       AS FileType,          -- ROWS = data, LOG = transaction log
    physical_name   AS PathOnDisk,        -- real Windows path
    size / 128      AS SizeMB
FROM sys.database_files;
GO

-- Shows collation (how text is sorted/compared) and recovery model.
SELECT
    name,
    collation_name,
    recovery_model_desc
FROM sys.databases
WHERE name = 'StudentRecordsDB';
GO
