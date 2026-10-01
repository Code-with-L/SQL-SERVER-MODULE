-- ============================================================================
-- Script: 02_data_types_reference.sql
-- Manual : Part 2 - "Understanding Data Types", Table 3-1
-- Topic  : the SEVEN CATEGORIES, with live examples
-- ============================================================================
--
-- WHY DATA TYPES ARE THE MOST IMPORTANT DECISION
--   From the manual: "The data type that you choose for a column is the most
--   critical decision that you make within your database."
--
--   Too RESTRICTIVE -> the application cannot store data it must store.
--                     (You chose INT for a phone number, then need 15 digits.)
--   Too BROAD      -> wasted space on disk and in memory -> slower queries
--                     and bigger backups. (You chose VARCHAR(500) for initials.)
--
-- THE RULE FROM THE MANUAL
--   "Choose the data type that allows all the data values that you expect to
--    be stored, while doing so in the least amount of space possible."
--
-- THIS SCRIPT IS A REFERENCE. It creates a scratch table, shows every type,
-- then DROPS it. Read it, run it, then move on.
-- ============================================================================

USE StudentRecordsDB;
GO

-- ---------------------------------------------------------------------------
-- The seven categories from Table 3-1 of the manual
-- ---------------------------------------------------------------------------
--  1. General Purpose     anything, any length          VARCHAR, NVARCHAR, INT
--  2. Exact Numeric       precise numbers               INT, DECIMAL(p,s), BIGINT
--  3. Approximate Numeric imprecise - can be rounded    FLOAT, REAL
--  4. Monetary            currency, up to 4 decimals    MONEY, SMALLMONEY
--  5. Date and Time       rejects February 30th         DATE, DATETIME2, TIME
--  6. Binary              strict 0 / 1 representation   BIT, BINARY, VARBINARY
--  7. Special Purpose     needs special handling         XML, UNIQUEIDENTIFIER
--
-- CATEGORY 2 vs 3 - the distinction students always miss
--   DECIMAL(10,2) stores 99999999.99 EXACTLY. Always use it for money.
--   FLOAT           is binary floating point. 0.1 cannot be represented
--                   exactly, so 0.1 + 0.2 may not equal 0.3. Faster, but lossy.
--   MONEY is really just a DECIMAL with a currency assumption - it is
--   discouraged in practice in favour of DECIMAL(19,4).
-- ============================================================================

CREATE TABLE dbo.DataTypePlayground
(
    -- CATEGORY 1: GENERAL PURPOSE
    C_VARCHAR      varchar(50),
    C_NVARCHAR     nvarchar(50),

    -- CATEGORY 2: EXACT NUMERIC
    C_TINYINT      tinyint,             -- 0 to 255                    (1 byte)
    C_SMALLINT     smallint,            -- 0 to 32,767                 (2 bytes)
    C_INT          int,                 -- +/-2.1 billion              (4 bytes)
    C_BIGINT       bigint,              -- +/-9.2 quintillion         (8 bytes)
    C_DECIMAL      decimal(10,2),       -- 10 digits total, 2 after point

    -- CATEGORY 3: APPROXIMATE NUMERIC
    C_FLOAT        float,               -- lossy!
    C_REAL         real,                -- lossy, smaller

    -- CATEGORY 4: MONETARY
    C_MONEY        money,
    C_SMALLMONEY   smallmoney,

    -- CATEGORY 5: DATE AND TIME
    C_DATE         date,                -- date only.  Not in SQL 2005!
    C_DATETIME     datetime,            -- the 2005-era default
    C_DATETIME2    datetime2(3),        -- preferred on modern SQL Server

    -- CATEGORY 6: BINARY
    C_BIT          bit,                 -- 0 / 1 / NULL. Not TRUE/FALSE.
    C_VARBINARY    varbinary(50),

    -- CATEGORY 7: SPECIAL PURPOSE
    C_XML          xml,
    C_UNIQUEIDENT  uniqueidentifier
);
GO

-- ---------------------------------------------------------------------------
-- EXAMINE WHAT GOT STORED AND HOW BIG EACH TYPE IS.
--
-- sys.columns.max_length is in BYTES and reflects the DECLARED width, so a
-- varchar(50) reports 50 while an nvarchar(50) reports 100. That doubling is
-- why NVARCHAR exists: UTF-16, two bytes per character, so it can store every
-- language on earth. Choose it only when you genuinely need non-Latin text.
-- ---------------------------------------------------------------------------
SELECT
    c.name                                        AS ColumnName,
    ty.name                                       AS DataType,
    c.max_length                                  AS DeclaredBytes,
    c.is_nullable                                 AS IsNullable,
    CASE WHEN ty.name IN ('varchar','char','varbinary','binary')
              THEN c.max_length - 2               -- subtract the 2-byte length prefix
         WHEN ty.name IN ('nvarchar','nchar')
              THEN (c.max_length - 2) * 2         -- UTF-16 = 2 bytes per character
         ELSE c.max_length
    END                                           AS StoredBytes
FROM sys.columns c
JOIN sys.types    ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.DataTypePlayground')
ORDER BY StoredBytes DESC;
GO

-- ---------------------------------------------------------------------------
-- DEMO: decimal precision, and why it is NOT the same as float
-- ---------------------------------------------------------------------------
SELECT
    CAST(0.1 AS decimal(10,2)) + CAST(0.2 AS decimal(10,2))  AS Decimal_Math,
    CAST(0.1 AS float)          + CAST(0.2 AS float)           AS Float_Math,
    CASE WHEN CAST(0.1 AS float) + CAST(0.2 AS float) = 0.3
         THEN 'equal' ELSE 'NOT equal' END                     AS Float_Verdict;
GO
-- Decimal_Math = 0.30   (exact)
-- Float_Math   = 0.3     (displayed) but the verdict reveals it is not
--                         bit-for-bit 0.3. This is why money is NEVER float.

-- ---------------------------------------------------------------------------
-- DEMO: DATE rejects impossible calendar dates.
-- The manual calls this out: "enables special chronological enforcement,
-- such as rejecting a value of February 30".
-- ---------------------------------------------------------------------------
-- Uncomment to see the error (Msg 241: conversion failed):
--   SELECT CAST('2005-02-30' AS date);

SELECT
    TRY_CAST('2005-02-30' AS date)  AS Feb30_Result,   -- NULL, no error
    ISDATE('2005-02-30')            AS ISDATE_Result;   -- 0
GO

-- ---------------------------------------------------------------------------
-- CLEANUP: drop the scratch table.
-- DROP TABLE removes the definition AND every row. Nothing else is touched.
-- ---------------------------------------------------------------------------
DROP TABLE dbo.DataTypePlayground;
GO
