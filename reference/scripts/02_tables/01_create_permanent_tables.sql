-- ============================================================================
-- Script: 01_create_permanent_tables.sql
-- Manual : Part 2 - Tables and Database Objects
-- Topic  : PERMANENT TABLES, CREATE TABLE, the course schema
-- ============================================================================
--
-- WHAT IS A PERMANENT TABLE?
--   A real table with a real file behind it. It exists until someone runs
--   DROP TABLE. This is the DEFAULT kind of table - no prefix means permanent.
--
--     CREATE TABLE dbo.Country  (...)   <- permanent (in schema dbo)
--     CREATE TABLE #Temp        (...)   <- temporary (prefix #)
--     DECLARE  @Var TABLE      (...)   <- table variable (prefix @)
--
-- WHY WE BUILD THESE SIX TABLES
--   This is the lecturer's specification. They form a small but complete
--   customer/address system, and they contain every concept in Manual 2:
--   IDENTITY, PRIMARY KEY, FOREIGN KEY, UNIQUE, NULL/NOT NULL, computed
--   columns, and all seven data-type categories.
--
-- SAFETY
--   ADDITIVE ONLY. Creates empty tables. Destroys nothing.
--   Safe to run on an empty StudentRecordsDB.
--   If a table already exists, SQL Server raises error 208 and changes nothing.
--
-- ORDER MATTERS
--   A table cannot reference a table that does not exist yet, and a FOREIGN
--   KEY cannot point at a column that is not a PRIMARY KEY. So we build in
--   this order:
--       1. Country           (no dependencies)
--       2. StateProvince     (no dependencies)
--       3. AddressType       (no dependencies)
--       4. Customer          (no dependencies)
--       5. CustomerAddress   (FK to 2, 3, 4)
--       6. CustomerToCustomerAddress (FK to 4 and 5)
-- ============================================================================

USE StudentRecordsDB;
GO

-- ---------------------------------------------------------------------------
-- 1. dbo.Country
--    Category 2 (exact numeric) + Category 1 (character).
-- ---------------------------------------------------------------------------
CREATE TABLE dbo.Country
(
    CountryID   int          IDENTITY(1,1)   PRIMARY KEY,
    Country     varchar(50)                  NOT NULL,
    CONSTRAINT UQ_Country_Country UNIQUE (Country)
);
GO

-- ---------------------------------------------------------------------------
-- 2. dbo.StateProvince
--    Identical shape to Country. In a real system it would also carry a
--    CountryID foreign key; the lecturer's exercise keeps it standalone.
-- ---------------------------------------------------------------------------
CREATE TABLE dbo.StateProvince
(
    StateProvinceID   int          IDENTITY(1,1)   PRIMARY KEY,
    StateProvince     varchar(50)                  NOT NULL,
    CONSTRAINT UQ_StateProvince_Name UNIQUE (StateProvince)
);
GO

-- ---------------------------------------------------------------------------
-- 3. dbo.AddressType
--
--    NOTE THE TYPE: tinyint, not int.
--      int     = -2,147,483,648 to 2,147,483,647      (4 bytes)
--      tinyint = 0 to 255                              (1 byte)
--
--    There are only ever a handful of address types (Home, Work, Billing...).
--    Using tinyint wastes nothing and saves 3 bytes per row. This is exactly
--    the manual's advice: choose the type that stores the expected values in
--    the LEAST space possible.
--
--    tinyint has NO IDENTITY default either, because the lecturer wants the
--    values seeded explicitly (see below) - but we use IDENTITY here so the
--    table is self-populating like the others.
-- ---------------------------------------------------------------------------
CREATE TABLE dbo.AddressType
(
    AddressTypeID   tinyint       IDENTITY(1,1)   PRIMARY KEY,
    AddressType     varchar(20)                   NOT NULL,
    CONSTRAINT UQ_AddressType_Name UNIQUE (AddressType)
);
GO

-- ---------------------------------------------------------------------------
-- 4. dbo.Customer     <-- the richest table in the schema
-- ---------------------------------------------------------------------------
CREATE TABLE dbo.Customer
(
    -- IDENTITY(1,1) = start at 1, add 1 each time.
    -- SQL Server refuses to let anyone type a value into an IDENTITY column,
    -- and never reuses a number - IDs are permanent labels, not counters.
    CustomerID          int          IDENTITY(1,1)   PRIMARY KEY,

    -- NOT NULL  = a value is REQUIRED. Omitting it raises error 515.
    -- UNIQUE    = no two customers may share a name.
    -- NONCLUSTERED = the index SQL Server builds to enforce UNIQUE is
    --                nonclustered (see 07_constraints_and_indexes.sql).
    CustomerName        varchar(50)  NOT NULL,

    -- smallmoney = Category 4 (Monetary) in the manual: decimal with up to
    -- four decimal places. NULL = the bank has not set a limit yet.
    CreditLine          smallmoney    NULL,
    OutstandingBalance  smallmoney    NULL,

    -- COMPUTED COLUMN.
    -- Not stored on disk at all. SQL Server recalculates it every time you
    -- read it. Change CreditLine and AvailableCredit is correct immediately -
    -- there is nothing to keep in sync, because nothing was saved.
    --
    -- GOTCHA: a computed column cannot be inserted into, and cannot use
    --          GETDATE() unless you declare it with PERSISTED.
    AvailableCredit     AS (CreditLine - OutstandingBalance),

    -- datetime in the 2005 manual. On SQL Server 2025 prefer datetime2:
    --   datetime    = rounded to 1/3000th second, range 1753-01-01 onward
    --   datetime2   = 100ns precision,    range 0001-01-01 onward
    CreationDate        datetime      NOT NULL
        CONSTRAINT DF_Customer_CreationDate DEFAULT (GETDATE())
);
GO

-- ---------------------------------------------------------------------------
-- 5. dbo.CustomerAddress
--    Now we add FOREIGN KEYs - the constraint that enforces REFERENTIAL
--    INTEGRITY: you cannot store a StateProvinceID that does not exist.
-- ---------------------------------------------------------------------------
CREATE TABLE dbo.CustomerAddress
(
    CustomerAddressID  int          IDENTITY(1,1)   PRIMARY KEY,
    AddressLine1       varchar(30)  NOT NULL,
    AddressLine2       varchar(30)  NULL,        -- optional; apartments etc.
    City               varchar(30)  NOT NULL,
    PostalCode         varchar(10)  NULL,

    -- REFERENCES dbo.X(Xcol) means: this column must already exist in that
    -- table AND be a PRIMARY KEY or UNIQUE column. SQL Server checks the
    -- definition when the table is created, so typos are caught immediately.
    StateProvinceID    int          NOT NULL
        CONSTRAINT FK_CustomerAddress_StateProvince
        REFERENCES dbo.StateProvince (StateProvinceID),

    CountryID          int          NOT NULL
        CONSTRAINT FK_CustomerAddress_Country
        REFERENCES dbo.Country (CountryID),

    AddressTypeID      tinyint      NOT NULL
        CONSTRAINT FK_CustomerAddress_AddressType
        REFERENCES dbo.AddressType (AddressTypeID)
);
GO

-- ---------------------------------------------------------------------------
-- 6. dbo.CustomerToCustomerAddress     <-- THE JUNCTION TABLE
--
--    THE PROBLEM IT SOLVES
--      One customer  -> many addresses   (one-to-many)
--      One address   -> many customers  (one-to-many)
--      A customer and an address together is MANY-TO-MANY, and T-SQL cannot
--      express many-to-many with a single FOREIGN KEY.
--
--    THE STANDARD SOLUTION
--      Break it into two one-to-many relationships, joined by a THIRD table
--      whose rows are the links.
--
--          Customer  1 ---<  CustomerToCustomerAddress  >---  CustomerAddress
--                       (CustomerID, CustomerAddressID)
--
--      Each row says "this customer has this address". Add rows to add links.
--
--    THE COMPOSITE PRIMARY KEY
--      PRIMARY KEY (CustomerID, CustomerAddressID)
--      Both columns together must be unique - which also means the SAME
--      address cannot be linked to the same customer twice. This is a
--      FOREIGN KEY plus a PRIMARY KEY in one declaration.
-- ---------------------------------------------------------------------------
CREATE TABLE dbo.CustomerToCustomerAddress
(
    CustomerID         int  NOT NULL
        CONSTRAINT FK_CTCA_Customer
        REFERENCES dbo.Customer (CustomerID),

    CustomerAddressID  int  NOT NULL
        CONSTRAINT FK_CTCA_CustomerAddress
        REFERENCES dbo.CustomerAddress (CustomerAddressID),

    CONSTRAINT PK_CustomerToCustomerAddress
        PRIMARY KEY (CustomerID, CustomerAddressID)
);
GO

-- ============================================================================
-- VERIFICATION - read only, always safe.
-- ============================================================================

-- 6a. Confirm all six tables exist
SELECT
    t.name                                        AS TableName,
    COUNT(c.column_id)                            AS ColumnCount,
    MAX(p.name)                                   AS PrimaryKeyName
FROM sys.tables t
JOIN sys.columns   c ON c.object_id = t.object_id
LEFT JOIN sys.indexes i ON i.object_id = t.object_id AND i.is_primary_key = 1
LEFT JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
LEFT JOIN sys.key_constraints p ON p.parent_object_id = t.object_id AND p.type = 'PK'
GROUP BY t.name
ORDER BY t.name;
GO

-- 6b. Every foreign key, and where it points
SELECT
    fk.name                                AS ForeignKeyName,
    OBJECT_NAME(fk.parent_object_id)       AS ChildTable,
    cp.name                                AS ChildColumn,
    OBJECT_NAME(fk.referenced_object_id)   AS ParentTable,
    cr.name                                AS ParentColumn
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns cp ON cp.object_id = fkc.parent_object_id
                   AND cp.column_id  = fkc.parent_column_id
JOIN sys.columns cr ON cr.object_id = fkc.referenced_object_id
                   AND cr.column_id  = fkc.referenced_column_id
ORDER BY ChildTable, ForeignKeyName;
GO
