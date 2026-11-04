-- ============================================================================
-- Script: 02_locking_and_blocking.sql
-- Manual : Part 4 - Locking, blocking, deadlocks
-- ============================================================================
--
-- WHY LOCKS EXIST
--   Two things happened at once:
--       Session A: UPDATE dbo.Customer SET CreditLine = 0 WHERE CustomerID = 1
--       Session B: SELECT CreditLine FROM dbo.Customer WHERE CustomerID = 1
--   If B reads midway through A, it reads a value that never really existed.
--   A lock is how SQL Server says: "wait, I'm not finished."
--
-- THE LOCK MODES YOU MUST KNOW
--   Shared      (S) reads. Many readers OK, no writers.
--   Update      (U) "I'm about to write." Slightly stronger than S.
--   Exclusive   (X) writing. Blocks everything else.
--   Intent      (I) on a table, saying "I intend to lock rows inside."
--   Schema      (Sch) changing the structure. Blocks everything.
--
-- THE COMPATIBILITY MATRIX  (why SELECT and UPDATE fight)
--   held \ wants    S      U      X
--   S                 ok     ok    WAIT
--   U                 ok    WAIT   WAIT
--   X                WAIT   WAIT   WAIT
--
--   Note that U/U waits. That surprises people, and it is the mechanism
--   behind most deadlocks in real systems.
--
-- LOCK COMPATIBILITY ISOLATION LEVELS - the four the manual covers
--   READ UNCOMMITTED (RU / dirty read)
--     Reads uncommitted data. Needs only S locks.
--     Pro: never blocks.  Con: you can read a value that later ROLLS BACK.
--     You can see rows that never existed.
--
--   READ COMMITTED (RC) - the SQL Server DEFAULT
--     Reads only committed data, but takes the S lock only for the duration
--     of each individual row read, then releases it.
--     Pro: accurate, and far less blocking than RU.
--     Con: a report can still see an inconsistent PICTURE across rows if
--          another session changes rows between your reads.
--
--   REPEATABLE READ (RR)
--     Holds S locks until the transaction ends.
--     Pro: the same row always returns the same value within a transaction.
--     Con: much more blocking, and SQL Server only truly enforces it for
--          rows that have been MODIFIED (it uses row versioning for the
--          rest). This is a well-known and much-criticised gap between the
--          documented behaviour and the actual behaviour.
--
--   SERIALIZABLE (SS)
--     Like REPEATABLE READ, plus range locks. A WHERE on CustomerID = 5 will
--     lock the RANGE of IDs around 5, stopping new rows from being inserted
--     there.
--     Pro: completely consistent picture, and prevents phantom rows.
--     Con: the highest chance of blocking and deadlock of any level.
--
--   SNAPSHOT (SN) - requires ALLOW_SNAPSHOT_ISOLATION ON
--     Every reader sees the database as it was at the START of the
--     transaction, with no locks on the reads at all.
--     Pro: readers NEVER block writers and never see inconsistent data.
--     Con: you pay for it with row versions kept in tempdb until every older
--          transaction finishes. Needs database-wide enablement, and cannot
--          be enabled while other SNAPSHOT transactions are open.
--
--   TWO EXTRA ROW-VERSIONING LEVELS (not in the 2005 manual's main table)
--   READ COMMITTED SNAPSHOT (RCSI) - set at the DATABASE level:
--     Same benefit as SNAPSHOT for read-committed readers, but no blocking
--     and no need to write SET TRANSACTION ISOLATION LEVEL. Usually the right
--     choice. Requires the database option, not the session setting.
-- ============================================================================

USE StudentRecordsDB;
GO

-- ---------------------------------------------------------------------------
-- 1. The default, confirmed
-- =========================================================================---
SELECT
    @@VERSION                                   AS ServerVersion,
    DB_NAME()                                   AS CurrentDatabase,
    transaction_isolation_level                 AS SessionIsolationLevel,
    is_read_committed_snapshot_on               AS ReadCommittedSnapshotOn,
    snapshot_isolation_state                    AS SnapshotIsolationState
FROM sys.databases
WHERE name = DB_NAME();
GO
-- transaction_isolation_level reads:
--   0 = READ UNCOMMITTED
--   1 = READ COMMITTED
--   2 = REPEATABLE READ
--   3 = SERIALIZABLE
--   4 = SNAPSHOT
--
-- is_read_committed_snapshot_on is 0 here - we have not enabled it.

-- ---------------------------------------------------------------------------
-- 2. See your own session's locks and requests
--    sys.dm_tran_locks is a DYNAMIC MANAGEMENT VIEW: a DMV. It exposes
--    information SQL Server keeps internally that is not exposed by the
--    regular catalogue views. It is READ ONLY and always current.
-- ---------------------------------------------------------------------------
SELECT
    tl.request_session_id  AS SessionID,
    tl.resource_type       AS ResourceType,     -- DATABASE, TABLE, KEY, PAGE
    tl.request_mode        AS RequestMode,      -- S, U, X, IX
    tl.status              AS LockStatus,       -- GRANTED / WAIT
    tl.wait_type           AS WaitingFor,       -- only set when WAIT
    tl.wait_time           AS WaitMilliseconds,
    OBJECT_NAME(tl.resource_associated_entity_id) AS ObjectName
FROM sys.dm_tran_locks tl
WHERE tl.request_session_id = @@SPID
ORDER BY tl.resource_type;
GO
-- KEY  = a row (a row lock) - the finest and most common granularity.
-- PAGE = several rows in one 8 KB page.
-- TABLE= the whole table, usually via ALTER TABLE or a schema change.

-- ---------------------------------------------------------------------------
-- 3. BLOCKING: who is waiting on whom
--    The DMV for this is sys.dm_exec_requests. Joining it to itself through
--    sys.dm_exec_sessions gives you the blocking chain.
--    Run this WHILE a session is blocked, from a third window.
-- ---------------------------------------------------------------------------
SELECT
    r.session_id                     AS BlockedSession,
    r.blocking_session_id            AS BlockerSession,
    r.status                         AS RequestStatus,
    r.wait_type                      AS WaitingOn,
    r.wait_time                      AS WaitMs,
    r.wait_resource                  AS WaitingOnResource,
    s.host_name                      AS BlockedHost,
    s.login_name                     AS BlockedLogin,
    s.program_name                   AS BlockedProgram,
    txt.text                         AS BlockedQuery
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) txt
WHERE r.blocking_session_id <> 0
   OR EXISTS (SELECT 1 FROM sys.dm_exec_requests b WHERE b.blocking_session_id = r.session_id);
GO
-- blocking_session_id <> 0  -> this request IS blocked; the value is the
--                               session ID of the blocker.
-- The EXISTS clause also catches the BLOCKER, so you see both sides.

-- ---------------------------------------------------------------------------
-- 4. SEEING A BLOCK IN PRACTICE - two windows required
--
--    WINDOW 1 (the blocker):
--      USE StudentRecordsDB;
--      BEGIN TRANSACTION;
--          UPDATE dbo.Country SET Country = 'KENYA' WHERE CountryID = 1;
--          -- leave the transaction OPEN. Do not type COMMIT.
--
--    WINDOW 2 (the blocked session):
--      USE StudentRecordsDB;
--      SELECT * FROM dbo.Country WHERE CountryID = 1;
--      -- this hangs, waiting for the X lock to be released
--
--    WINDOW 3 (any time):
--      run query 3 above. BlockedSession = window 2, BlockerSession = window 1,
--      and it shows the exact UPDATE statement holding the lock.
--
--    WINDOW 1 (to release):
--      COMMIT TRANSACTION;    -- or ROLLBACK TRANSACTION
--
--    WINDOW 2 reports: Msg 1205? No - that is a deadlock. Blocking reports:
--      Msg 300, or simply "the query is still executing". The state is
--      Visible in the Results/Messages tab.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 5. KILLING a blocker - DESTRUCTIVE TO THAT SESSION'S WORK
--
--   KILL <spid> terminates the session and ROLLS BACK its open transaction.
--   It does not crash SQL Server and it does not affect other sessions, but
--   whatever that session had uncommitted is lost.
--
--   This is the emergency tool, not the first move. The correct first move is
--   to ask why the session is holding the lock.
-- ============================================================================
SELECT
    s.session_id   AS BlockedBySession,
    s.login_name,
    s.host_name,
    s.program_name,
    r.status,
    r.command
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r ON r.session_id = s.session_id
WHERE s.is_user_process = 1
ORDER BY s.session_id;
GO
-- Then, having identified the culprit:
--   KILL 55;                    -- terminates session 55
--   KILL 55;                    -- run again to confirm (first KILL is a
--                               -- warning, the second actually kills)
-- KILL 0 kills your own session. KILL sp_reset_connection <spid> resets the
-- connection pool entry without a full disconnect.

-- ---------------------------------------------------------------------------
-- 6. Blocking counters - did we HAVE a problem today?
--    Cumulative since the last SQL Server start (or RESET after reading).
-- ============================================================================
SELECT
    cntr_name                          AS Counter,
    cntr_value                         AS CurrentValue,
    cntr_type                          AS Type,     -- 272696576 = cumulative
    cntr_type / 4294967296.0            AS Base
FROM sys.dm_os_performance_counters
WHERE object_name = 'SQLServer:Locks'
   AND counter_name IN ('Number of Deadlocks/sec',
                        'Lock Timeouts/sec',
                        'Number of Lock Waits/sec',
                        'Lock Waits/sec',
                        'Avg. Lock Wait Time (ms)')
ORDER BY counter_name;
GO
-- Read these, then RESET, then read again to get a meaningful delta.
-- Cumulative counters alone are meaningless - a server running for a year
-- has a large "deadlocks" number even if nothing is currently wrong.
