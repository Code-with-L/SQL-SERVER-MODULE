-- ==============================================================
-- 02_create_departments.sql
-- PART 2 / Manual 2 — first CREATE TABLE, with nothing fancy.
--
-- OBJECT_ID(..., 'U') returns the object's id ONLY if it is a user
-- table, otherwise NULL. So the script below does nothing if the
-- table already exists — safe to press F5 repeatedly.
-- If you ever see "Msg 2714", that is why: the guard caught it.
-- ==============================================================

USE StudentRecordsDB;
GO

IF OBJECT_ID('dbo.Departments', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Departments (
        DepartmentID   int IDENTITY(1,1) PRIMARY KEY,
        DepartmentName varchar(50) NOT NULL
    );
    PRINT 'Created dbo.Departments';
END
ELSE
    PRINT 'dbo.Departments already exists — nothing to do.';
GO
