SELECT DB_NAME();
SELECT
    SERVERPROPERTY('Edition')        AS Edition,
    SERVERPROPERTY('InstanceName')   AS InstanceName,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('IsIntegratedSecurityOnly') AS WindowsAuthOnly;
GO
USE StudentRecordsDB;
GO
CREATE TABLE dbo.Departments (
    DepartmentID int IDENTITY(1,1) PRIMARY KEY,
    DepartmentName varchar(50) NOT NULL
);
GO
SELECT * FROM dbo.Departments;
GO
INSERT INTO dbo.Departments (DepartmentName)
VALUES ('Engineering'), ('Sales');
GO
SELECT * FROM dbo.Departments;
GO