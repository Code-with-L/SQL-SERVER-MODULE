-- ============================================================================
-- Script: 03_deadlocks.sql
-- Manual : Part 4 - Deadlocks
-- ============================================================================
--
-- WHAT A DEADLOCK IS
--   Two sessions each hold a resource the other needs. Neither can continue.
--   Neither will ever release voluntarily.
--   Both sit there forever until SQL Server intervenes.
--
--   Session A                      Session B
--   ------------------------------  ------------------------------
--   BEGIN TRANSACTION              BEGIN TRANSACTION
--   UPDATE Country  (lock on row 1) UPDATE StateProvince (lock on row 1)
--   UPDATE StateProvince           UPDATE Country
--     (needs row 1's lock)           (needs row 1's lock)
--   WAITING --------------------------- WAITING
--
--   THAT is a deadlock. Not complicated - just unlucky ordering.
--
-- WHY SQL SERVER KILLS ONE OF THEM
--   It must, or the database stops serving queries entirely. It picks a
--   victim using a COST-based rule: lowest rollback cost wins. Killing the
--   cheapest transaction is the least disruptive action available.
--
-- THE ERROR
--   Msg 1205, Level 16, State 1:
--   Deadlock detected. The transaction has been chosen as the deadlock
--   victim. Execute the transaction again.
--
-- "Execute the transaction again" is literal and important: your application
-- MUST be written to retry. A deadlock is a normal, expected event under
-- concurrency, not a server fault.
--
-- DEADLOCK vs BLOCKING vs LOCK TIMEOUT - do not confuse them
--   BLOCKING    one session waits for another that is still working.
--               It resolves itself. Normal. Might be a performance problem.
--   TIMEOUT     blocking that went on too long and SQL Server gave up.
--               Controlled by SET LOCK_TIMEOUT. Default is -1 (wait forever).
--   DEADLOCK    a cycle. It can NEVER resolve itself, so one session is
--               forcibly killed. Always an error.
-- ============================================================================

USE StudentRecordsDB;
GO

-- ---------------------------------------------------------------------------
-- 1. Is the server's deadlock detection even enabled? (It always is.)
-- ---------------------------------------------------------------------------
SELECT
    is_deadlock_detector_on          AS DeadlockDetectorOn,
    deadlock_monitoring_level        AS DeadlockMonitoringLevel
FROM sys.dm_exec_sessions
WHERE session_id = @@SPID;
GO
-- deadlock_monitoring_level:
--   OFF      no detection (fastest, dangerous on a busy server)
--   LOW      every 5 seconds
--   HIGH     every 100 milliseconds  <-- the default on SQL Server 2025
--
-- HIGH costs a little CPU but means a deadlock is detected and resolved in
-- milliseconds instead of seconds. Leave it alone unless someone has a very
-- specific reason and has measured it.

-- ---------------------------------------------------------------------------
-- 2. Reading the SQL Server error log for deadlock graphs
--
--   SQL Server writes a full deadlock XML graph to the ERRORLOG for EVERY
--   deadlock, in the ERRORLOG (not the Messages pane). The Messages pane only
--   shows you Msg 1205.
--
--   sp_readerrorlog reads it from T-SQL - read only, no side effects:
-- ============================================================================
EXEC sp_readerrorlog 0, 1, 'deadlock';
GO
-- Returns every logged line containing "deadlock". On a busy server this can
-- be thousands of rows and slow to render. Narrow it by date if needed:
--   EXEC sp_readerrorlog 0, 1, 'deadlock', '2026-09-30';
--
--   In SSMS you can also read it directly:
--   Management > SQL Server Logs > right-click current log > View SQL Server Log

-- ---------------------------------------------------------------------------
-- 3. Count deadlocks since start-up
-- ---------------------------------------------------------------------------
SELECT
    cntr_name  AS CounterName,
    cntr_value AS CumulativeCount
FROM sys.dm_os_performance_counters
WHERE object_name = 'SQLServer:Locks'
  AND counter_name LIKE '%Deadlock%';
GO

-- ---------------------------------------------------------------------------
-- 4. REPRODUCING ONE - two windows, deliberately
--
--    This creates a deadlock on purpose. It is the clearest demonstration
--    possible and it fails safely: one of your transactions is rolled back
--    and the other completes normally. No data is lost because both sessions
--    are only doing trivial UPDATEs you can undo.
--
--    WINDOW 1:
--      USE StudentRecordsDB;
--      BEGIN TRANSACTION;
--          UPDATE dbo.Country    SET Country = Country    WHERE CountryID = 1;
--          WAITFOR DELAY '00:00:15';       -- hold the lock, stay alive
--          UPDATE dbo.StateProvince SET StateProvince = StateProvince
--              WHERE StateProvinceID = 1;   -- needs window 2's lock
--      COMMIT TRANSACTION;
--
--    WINDOW 2 (start ~5 seconds AFTER window 1):
--      USE StudentRecordsDB;
--      BEGIN TRANSACTION;
--          UPDATE dbo.StateProvince SET StateProvince = StateProvince
--              WHERE StateProvinceID = 1;
--          WAITFOR DELAY '00:00:15';
--          UPDATE dbo.Country    SET Country = Country    WHERE CountryID = 1;
--      COMMIT TRANSACTION;
--
--    EXPECTED: window 2's Messages tab shows Msg 1205 almost immediately,
--    because the cycle closes as soon as both sessions want the second lock.
--
--    NOTE the self-assignment (Country = Country). It acquires an exclusive
--    lock WITHOUT changing anything, which is exactly what we want for a
--    controlled demonstration. Do not use this pattern for real work.
--
--    SAFETY: nothing is committed and nothing changes value. The victim's
--    transaction is rolled back by SQL Server. Afterwards verify with:
--      SELECT * FROM dbo.Country;
--      SELECT * FROM dbo.StateProvince;
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 5. The RETRY pattern - what a real application must do
--
--   A deadlock is normal. Application code should retry, with a small random
--   delay so both sessions do not collide again at the same millisecond.
-- ============================================================================
--   DECLARE @attempt int = 1, @max int = 3;
--   WHILE @attempt <= @max
--   BEGIN
--       BEGIN TRY
--           BEGIN TRANSACTION;
--               -- your two updates here, in a CONSISTENT ORDER
--               UPDATE dbo.Country      SET ... ;
--               UPDATE dbo.StateProvince SET ... ;
--           COMMIT TRANSACTION;
--           BREAK;
--       END TRY
--       BEGIN CATCH
--           IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
--           IF ERROR_NUMBER() = 1205 AND @attempt < @max
--           BEGIN
--               WAITFOR DELAY '00:00:0' + CAST(@attempt * 200 AS varchar(4));
--               SET @attempt += 1;
--               CONTINUE;
--           END
--           THROW;                    -- not a deadlock, or out of retries
--       END CATCH
--   END
--
--   THE REAL FIX, THOUGH: eliminate the deadlock by standardising the order
--   in which tables are always touched. If every transaction updates Country
--   before StateProvince, the cycle can never form. Retries are the safety
--   net; consistent ordering is the cure.
--
--   DEADLOCK PROOFREADING LIST
--     [ ] Do all transactions touch tables in the SAME order?
--     [ ] Are transactions as SHORT as possible? (Long = more locks held)
--     [ ] Are there indexes on every FOREIGN KEY column?
--     [ ] Does any transaction read a wide range of rows it does not need?
--     [ ] Is an application running interactive queries inside transactions?
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 6. LOCK_TIMEOUT - how long to wait before giving up (without dying)
-- =========================================================================---
--   SET LOCK_TIMEOUT 5000;    -- wait 5 seconds, then Msg 1222
--   SET LOCK_TIMEOUT -1;       -- the default: wait forever
--
--   Msg 1222: Lock request time out period exceeded.
--   This is arguably BETTER than a deadlock for a web request: the app gets
--   a quick failure it can retry, instead of one session being sacrificed.
-- ============================================================================
