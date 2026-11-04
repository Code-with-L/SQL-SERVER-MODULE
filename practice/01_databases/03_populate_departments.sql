-- ==============================================================
-- 03_populate_departments.sql
-- PART 2 / Manual 2 — put the first two rows in, then read them back.
--
-- NOTE FOR LEARNING: re-running this file inserts the two rows again.
-- The table has no unique constraint on DepartmentName, so duplicate
-- names are allowed. Feel free to observe that, or to add
--     UNIQUE (DepartmentName)
-- yourself as an exercise and see what changes.
-- ==============================================================

USE StudentRecordsDB;
GO

INSERT INTO dbo.Departments (DepartmentName)
VALUES ('Engineering'), ('Sales');
GO

SELECT * FROM dbo.Departments;
GO
