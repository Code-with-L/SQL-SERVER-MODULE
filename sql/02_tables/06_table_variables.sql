-- ============================================================================
-- Script: 06_table_variables.sql
-- Manual : Part 2 - TABLE VARIABLES - the @ prefix
-- ============================================================================
--
-- WHAT A TABLE VARIABLE IS
--   A table that exists only inside the statement or batch that declares it.
--   Declared with DECLARE ... TABLE. It is not in tempdb - it is a value,
--   like any other variable, that happens to have rows.
--
-- THE THREE-WAY COMPARISON  (this is the whole topic)
--
--   |                | PERMANENT      | #TEMP   | @VARIABLE |
--   |----------------|----------------|---------|-----------|
--   | Prefix         | none / dbo.    | #       | @         |
--   | Lives in       | your database  | tempdb  | memory    |
--   | Survives commit| yes            | yes     | NO        |
--   | Survives discon| yes            | NO      | NO        |
--   | Survives rollback| yes          | yes     | NO        |
--   | Has statistics | yes (persisted)| no      | no        |
--   | Good for rows  | thousands+      | hundreds+| < 100    |
--   | Indexes        | yes            | yes     | no        |
--   | Triggers see it| yes            | yes     | NO        |
--
--   THE RULE OF THUMB FROM THE MANUAL'S CHAPTER
--     Permanent table -> the data is real and must survive.
--     #temp          -> many rows, or you need indexes, and it may be
--                      committed (a multi-step transaction).
--     @variable      -> a handful of rows, all-or-nothing, nothing outside
--                      this statement needs to know.
--
--   The famous gotcha: a table variable's contents are NOT restored by a
--   ROLLBACK. Drop a row, roll back, and the row stays gone. That surprises
--   everyone once.
-- ============================================================================

USE StudentRecordsDB;
GO

-- ---------------------------------------------------------------------------
-- 1. The simplest possible table variable
--
--    *** SCOPE WARNING - THIS IS THE WHOLE POINT OF THIS SCRIPT ***
--    A table variable lives only inside its BATCH. Everything from DECLARE to
--    the last use must be in ONE batch, with NO GO in between.
--    Put a GO after the DECLARE and the next batch fails with:
--       Msg 1087: Must declare the table variable "@Regions".
--    A #temp table would survive the GO. That difference is exactly why you
--    choose one over the other.
--
--    DECLARE must also be the FIRST statement in its batch. Anything before
--    it is a syntax error.
-- ---------------------------------------------------------------------------
DECLARE @Regions TABLE
(
    RegionID   tinyint     NOT NULL PRIMARY KEY,
    RegionName varchar(30) NOT NULL
);

INSERT INTO @Regions (RegionID, RegionName)
VALUES (1, 'North'), (2, 'South'), (3, 'East'), (4, 'West');

SELECT * FROM @Regions ORDER BY RegionID;
GO

-- ---------------------------------------------------------------------------
-- 2. A table variable with no rows - useful as a filter
--    This is the classic real-world pattern: a short list drives a query.
--    Again: declare AND use in one batch.
-- ---------------------------------------------------------------------------
DECLARE @Regions TABLE
(
    RegionID   tinyint     NOT NULL PRIMARY KEY,
    RegionName varchar(30) NOT NULL
);
DECLARE @ActiveRegions TABLE (RegionName varchar(30) NOT NULL);

INSERT INTO @Regions VALUES (1,'North'), (2,'South'), (3,'East'), (4,'West');
INSERT INTO @ActiveRegions VALUES ('North'), ('East');

SELECT
    r.RegionID,
    r.RegionName
FROM @Regions r
JOIN @ActiveRegions a ON a.RegionName = r.RegionName
ORDER BY r.RegionID;
GO

-- ---------------------------------------------------------------------------
-- 3. PROVING THE ROLLBACK BEHAVIOUR
--    A #temp table would roll back. A @variable does NOT.
--    This is the single most important practical difference.
--    Everything must stay in ONE batch so the variable is still in scope.
-- ---------------------------------------------------------------------------
DECLARE @Proof TABLE (id int NOT NULL);

BEGIN TRANSACTION;
    INSERT INTO @Proof VALUES (1), (2), (3);
    DELETE FROM @Proof WHERE id = 2;
    -- NOTE: [When] and [RowCount] both need brackets - WHEN and ROWCOUNT are
    -- reserved keywords in T-SQL (CASE...WHEN, @@ROWCOUNT). Bare, they give
    -- Msg 156, "Incorrect syntax near the keyword ...".
    SELECT 'BEFORE rollback' AS [When], COUNT(*) AS [RowCount] FROM @Proof;  -- 2
ROLLBACK TRANSACTION;

SELECT 'AFTER  rollback' AS [When], COUNT(*) AS [RowCount] FROM @Proof;     -- still 2
-- The DELETE was NOT undone. A #temp table in the same transaction would have
-- been restored to 3 rows. This surprises everyone exactly once.
GO

-- ---------------------------------------------------------------------------
-- 4. Things a table variable CANNOT do
--   - No indexes beyond the PRIMARY KEY / UNIQUE you declare inline
--   - No statistics, so the optimiser guesses the row count
--   - Not visible to triggers on other tables
--   - Cannot be the target of INSERT ... SELECT from a remote server
--   (Those limitations are why #temp is often the better choice for larger
--    row counts.)
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 5. RETURNING ROWS TO THE CALLER - table-valued functions
--
--    A table variable cannot escape its batch, so how do you return rows from
--    something that behaves like one? With a FUNCTION whose return type is
--    TABLE. That is the legitimate pattern.
--
--    Note the naming convention: prefix tvf_ = "table-valued function", so
--    callers can tell from the name that it returns rows rather than a scalar.
--
--    Requires dbo.AddressType, so run 01_create_permanent_tables.sql first.
-- ---------------------------------------------------------------------------
CREATE FUNCTION dbo.tvf_AddressTypesAbove (@MinID tinyint)
RETURNS TABLE
AS RETURN
(
    SELECT  at.AddressTypeID,
            at.AddressType,
            COUNT(ca.CustomerAddressID) AS AddressCount
    FROM        dbo.AddressType AS at
    LEFT JOIN   dbo.CustomerAddress AS ca
               ON  ca.AddressTypeID = at.AddressTypeID
    WHERE       at.AddressTypeID >= @MinID
    GROUP BY    at.AddressTypeID, at.AddressType
);
GO

-- Call it like a table. This is the whole point of RETURNS TABLE:
SELECT * FROM dbo.tvf_AddressTypesAbove(1) ORDER BY AddressTypeID;
GO

-- WHY NOT A MULTI-STATEMENT FUNCTION?
--   You can write CREATE FUNCTION ... RETURNS @Result TABLE AS BEGIN ... END
--   and fill it with inserts. But it is SLOWER, it cannot be used in a view
--   or with an index, and SQL Server gives a clear warning about it. Prefer
--   the inline (RETURNS TABLE AS RETURN) form above unless you must build the
--   result in stages.
-- ============================================================================

DROP FUNCTION dbo.tvf_AddressTypesAbove;
GO

-- ============================================================================
-- 6. Quick reference
-- ---------------------------------------------------------------------------
--   DECLARE @MyTable TABLE (...);     -- declare, must start a batch
--   INSERT INTO @MyTable VALUES ...;  -- populate
--   SELECT * FROM @MyTable;           -- read
--   -- gone at the end of the batch, automatically
--
--   Contrast:
--   CREATE TABLE #MyTable (...);      -- persists to end of SESSION
--   DROP TABLE #MyTable;              -- must clean up (or disconnect)
-- ============================================================================
