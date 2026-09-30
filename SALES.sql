CREATE DATABASE Sales
ON PRIMARY
(
    NAME = SalesPrimary,
    FILENAME = 'D:\Sales\_Data\SalesPrimary.mdf',
    SIZE = 50MB,
    MAXSIZE = 200MB,
    FILEGROWTH = 20MB
),
FILEGROUP SalesFG
(
    NAME = SalesData1,
    FILENAME = 'E:\Sales\_Data\SalesData1.ndf',
    SIZE = 200MB,
    MAXSIZE = 800MB,
    FILEGROWTH = 100MB
),
(
    NAME = SalesData2,
    FILENAME = 'E:\Sales\_Data\SalesData2.ndf',
    SIZE = 400MB,
    MAXSIZE = 1200MB,
    FILEGROWTH = 300MB
),
FILEGROUP SalesHistoryFG
(
    NAME = SalesHistory1,
    FILENAME = 'E:\Sales\_Data\SalesHistory1.ndf',
    SIZE = 100MB,
    MAXSIZE = 500MB,
    FILEGROWTH = 50MB
)
LOG ON
(
    NAME = Archlog1,
    FILENAME = 'F:\Sales\_Data\SalesLog.ldf',
    SIZE = 300MB,
    MAXSIZE = 800MB,
    FILEGROWTH = 100MB
);
GO

ALTER DATABASE Sales
MODIFY FILEGROUP SalesFG DEFAULT;
GO