-- ============================================================================
-- Script: 05_temporary_tables.sql
-- Manual : Part 2 - "Permanent Tables, Temporary Tables, Table Variables"
-- Topic  : TEMPORARY TABLES - the # prefix
-- ============================================================================
--
-- WHAT A TEMPORARY TABLE IS
--   A table that exists only for your session. It is stored in tempdb, not in
--   your database, and SQL Server discards it the moment you disconnect.
--
--   The # is not decoration - it is how the server recognises it.
--
--     #Temp     local temporary table   - visible only to YOUR session
--     ##Temp    global temporary table  - visible to ALL sessions
--
-- WHEN TO USE ONE
--     - Staging: copy a slice of a big table, transform it, join it back.
--     - Isolating a multi-step calculation from the real tables.
--     - Holding a result set while you query it repeatedly.
--
-- WHEN NOT TO
--     - Not for permanent data. That is what real tables are for.
--     - Not automatically faster. Temporary tables are not magically quick;
--       their reputation comes from avoiding repeated recompiles, not magic.
--
-- GLOBALTEMPORARY TABLES are a genuine footgun: nothing stops another session
-- from reading or even dropping your ##Temp. Prefer a local #temp, or better
-- a table variable (next script) when you do not need a real table.
-- ============================================================================

USE StudentRecordsDB;
GO

-- ---------------------------------------------------------------------------
-- 1. CREATE, populate, use, and watch it vanish on disconnect
-- ---------------------------------------------------------------------------
CREATE TABLE #RecentOrders
(
    OrderID     int IDENTITY(1,1) PRIMARY KEY,
    CustomerID  int NOT NULL,
    OrderTotal  decimal(10,2) NOT NULL,
    OrderDate   date NOT NULL
);
GO

INSERT INTO #RecentOrders (CustomerID, OrderTotal, OrderDate)
VALUES (1, 250.00, '2026-09-01'),
       (1,  75.50, '2026-09-05'),
       (2, 999.99, '2026-09-07'),
       (2,  12.00, '2026-09-11'),
       (3, 480.75, '2026-09-12');
GO

-- A realistic use: stage rows, then aggregate them.
SELECT
    CustomerID,
    COUNT(*)              AS OrderCount,
    SUM(OrderTotal)       AS TotalSpent
FROM #RecentOrders
GROUP BY CustomerID
HAVING SUM(OrderTotal) > 100
ORDER BY TotalSpent DESC;
GO

-- ---------------------------------------------------------------------------
-- 2. WHERE does it actually live? tempdb.
--    Object IDs for #temp tables are NEGATIVE - that is how SQL Server
--    reserves them without a real name in the catalogue.
-- ---------------------------------------------------------------------------
SELECT
    OBJECT_NAME(object_id) AS TempTableName,   -- returns NULL for #tables
    object_id              AS ObjectId,         -- negative
    create_date            AS CreatedInTempdb
FROM tempdb.sys.objects
WHERE OBJECTPROPERTY(object_id, 'IsUserTable') = 1;
GO

-- ---------------------------------------------------------------------------
-- 3. Local vs global
--   #Mine   - only you can see it
--   ##Mine  - every session can see it (and can drop it)
-- ---------------------------------------------------------------------------
CREATE TABLE #LocalOnly  (id int);
CREATE TABLE ##GlobalOne (id int);
GO

SELECT
    CASE WHEN name LIKE '##%' THEN 'GLOBAL  ##'
         ELSE 'LOCAL   #'
    END   AS Scope,
    name   AS TempTableName
FROM tempdb.sys.objects
WHERE name LIKE '#%';
GO

-- Cleanup the global one explicitly rather than leaving it for someone else:
DROP TABLE ##GlobalOne;
GO

-- ============================================================================
-- 4. THE BEHAVIOUR THAT CATCHES PEOPLE OUT
--
--    A local #temp table is scoped to the BATCH, not the session, in one
--    specific way: if a name is re-created within the same batch, SQL Server
--    allows it. Across batches in the same session, the name persists.
--
--    Run this whole block and watch the error:
-- ============================================================================
--   CREATE TABLE #RecentOrders (Different int);   -- Msg 2714
--   -- "There is already an object named '#RecentOrders' in the database."
--
--    Fixes, in order of preference:
--      DROP TABLE #RecentOrders;
--      OR  CREATE TABLE #RecentOrders (Different int);  -- same batch, fine
--      OR  name every temp table uniquely: #RecentOrders_20260930

-- ============================================================================
-- 5. Explicit cleanup
--    Good practice even though SQL Server does it for you, because it makes
--    your intent visible and frees tempdb immediately.
-- ============================================================================
DROP TABLE #RecentOrders;
DROP TABLE #LocalOnly;
GO

-- ============================================================================
-- 6. The trap: it disappears and takes your work with it
--    If you close SSMS, #RecentOrders is gone forever. Temp tables are not
--    a place to keep results between sessions.
-- ============================================================================
