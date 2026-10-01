-- ============================================================================
-- Script: 04_isolation_levels.sql
-- Manual : Part 4 - Isolation levels
-- ============================================================================
--
-- THE PROBLEM EACH LEVEL SOLVES
--
--   Anomalies that can happen when transactions interleave:
--     DIRTY READ        you read a row another session later rolls back
--     NON-REPEATABLE   you read the same row twice and get two values
--     PHANTOM          your WHERE matches a different number of rows each run
--     LOST UPDATE      two sessions write the same row and one write vanishes
--
--   The trade-off is always: stronger consistency  vs  more blocking / less
--   concurrency. Isolation level is where you choose your point on that line.
--
--   A handy analogy - reading a bank balance:
--     RU  read the number on the screen, mid-update, before it is committed
--     RC  read it after each individual update commits, but a report of
--         several rows can still catch them at different moments
--     RR  read the same row and always get the same number back
--     SS  like RR, and also make sure nobody can insert a matching row while
--         you are looking
--     SN  travel back to the start of your transaction and read the world as
--         it was then, without locking anyone
-- ============================================================================

USE StudentRecordsDB;
GO

-- ---------------------------------------------------------------------------
-- THE FOUR LEVELS, SIDE BY SIDE
--
-- Level             Reads uncommitted?  Locks held until
-- ----------------- -------------------- ----------------------------
-- READ UNCOMMITTED       YES            end of statement
-- READ COMMITTED         no             end of each statement
-- REPEATABLE READ        no             end of transaction
-- SERIALIZABLE           no             end of transaction (+ ranges)
-- SNAPSHOT               no             none (uses row versions)
--
-- Default: READ COMMITTED. Snapshot must be enabled at the DATABASE level
-- before any session can use it.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Which levels does THIS database allow?
-- =========================================================================---
SELECT
    name                                          AS DatabaseName,
    is_read_committed_snapshot_on                AS RCSI_Enabled,
    snapshot_isolation_state                      AS AllowSnapshotIsolation,
    CASE snapshot_isolation_state
        WHEN 0 THEN 'OFF  - sessions cannot SET SNAPSHOT'
        WHEN 1 THEN 'ON   - sessions may SET SNAPSHOT'
    END                                          AS SnapshotState
FROM sys.databases
WHERE name = DB_NAME();
GO
-- snapshot_isolation_state reads 0 (OFF) on a fresh database. Until you run
-- the ALTER DATABASE below, a session trying SNAPSHOT gets:
--   Msg 3961: Snapshot isolation transaction failed accessing database
--   because the database does not have the snapshot isolation option enabled.

-- ---------------------------------------------------------------------------
-- 2. Setting the level for your session - all five forms
-- ============================================================================
--   SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
--   SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
--   SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
--   SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
--   SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
--
--   Applies to the connection until changed or disconnected. Not persisted.
--
--   Confirm it took effect:
SELECT
    transaction_isolation_level_desc AS CurrentIsolationLevel
FROM sys.dm_exec_sessions
WHERE session_id = @@SPID;
GO

-- ---------------------------------------------------------------------------
-- 3. THE THREE ANOMALIES, DEMONSTRATED
--
--    Each needs TWO windows. WINDOW 1 opens a transaction and waits;
--    WINDOW 2 performs the read. Read the comments for what to expect.
-- ============================================================================

-- (a) DIRTY READ - READ UNCOMMITTED
--
--   WINDOW 1:
--     USE StudentRecordsDB;
--     BEGIN TRANSACTION;
--         UPDATE dbo.Country SET Country = 'DIRTY' WHERE CountryID = 1;
--         WAITFOR DELAY '00:00:20';
--     ROLLBACK TRANSACTION;      -- never actually happened
--
--   WINDOW 2:
--     USE StudentRecordsDB;
--     SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
--     SELECT Country FROM dbo.Country WHERE CountryID = 1;
--     -- reads 'DIRTY' - a value that was rolled back and never existed.
--     SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
--
--   This is why READ UNCOMMITTED is called a DIRTY READ. The only legitimate
--   use is a rough estimate where a wrong number is acceptable (a dashboard
--   tile that retries). Never use it for money, stock, or grades.

-- (b) NON-REPEATABLE READ - READ COMMITTED vs REPEATABLE READ
--
--   WINDOW 1:
--     USE StudentRecordsDB;
--     BEGIN TRANSACTION;
--         UPDATE dbo.Country SET Country = 'CHANGED' WHERE CountryID = 2;
--         WAITFOR DELAY '00:00:20';
--     COMMIT TRANSACTION;
--
--   WINDOW 2 (inside one transaction):
--     USE StudentRecordsDB;
--     SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
--     BEGIN TRANSACTION;
--         SELECT Country FROM dbo.Country WHERE CountryID = 2;  -- 'KENYA'
--         WAITFOR DELAY '00:00:08';        -- let window 1 commit
--         SELECT Country FROM dbo.Country WHERE CountryID = 2;  -- 'CHANGED'
--         -- different value in the SAME transaction. Non-repeatable read.
--     COMMIT TRANSACTION;
--     SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
--     BEGIN TRANSACTION;
--         SELECT Country FROM dbo.Country WHERE CountryID = 2;  -- 'KENYA'
--         WAITFOR DELAY '00:00:08';
--         SELECT Country FROM dbo.Country WHERE CountryID = 2;  -- 'KENYA' still
--         -- same value. Repeatable read fixed it.
--     COMMIT TRANSACTION;
--     SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- (c) PHANTOM - SERIALIZABLE
--
--   "The same query returns a different NUMBER of rows."
--
--   WINDOW 1:
--     USE StudentRecordsDB;
--     BEGIN TRANSACTION;
--         INSERT INTO dbo.Country (Country) VALUES ('PHANTOMVILLE');
--         WAITFOR DELAY '00:00:20';
--     ROLLBACK TRANSACTION;
--
--   WINDOW 2:
--     USE StudentRecordsDB;
--     BEGIN TRANSACTION;
--         SELECT COUNT(*) FROM dbo.Country;     -- 3
--         WAITFOR DELAY '00:00:08';             -- window 1 inserts
--         SELECT COUNT(*) FROM dbo.Country;     -- 4 at REPEATABLE READ
--     COMMIT TRANSACTION;
--     SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
--     BEGIN TRANSACTION;
--         SELECT COUNT(*) FROM dbo.Country;     -- 3
--         WAITFOR DELAY '00:00:08';             -- window 1 now BLOCKS
--         SELECT COUNT(*) FROM dbo.Country;     -- 3
--         -- SERIALIZABLE range-locked the table so the INSERT cannot proceed.
--     COMMIT TRANSACTION;
--     SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- (d) LOST UPDATE - no isolation level fixes this; you need a hint
--   Two sessions read the same value, both calculate from it, both write.
--   The second write silently discards the first. READ COMMITTED does not
--   prevent this and SERIALIZABLE prevents it by locking too much.
--
--   The correct fix is an explicit hint on the UPDATE:
--     UPDATE dbo.Country WITH (UPDLOCK, ROWLOCK)
--        SET Country = 'New'
--      WHERE CountryID = 1;
--
--   UPDLOCK takes an Update lock at the START of the statement rather than
--   escalating from Shared at write time. That closes the window in which two
--   sessions can both be reading before either writes. This is the single
--   most practically useful thing in this entire chapter.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 4. ENABLING SNAPSHOT ISOLATION - DATABASE level, once, by an administrator
--
--   DESTRUCTIVE-ISH: this rewrites row-version information for the whole
--   database and cannot be undone while any connection is open. It is
--   DISABLED by default and is a deliberate architectural decision.
--
--   ALLOW_SNAPSHOT_ISOLATION ON   -> enables the SNAPSHOT level for sessions
--   READ_COMMITTED_SNAPSHOT ON    -> enables RCSI, the database-level default
--
--   The two are independent. RCSI is usually the better first move because
--   it needs no changes to application code.
-- ============================================================================
-- ALTER DATABASE StudentRecordsDB SET READ_COMMITTED_SNAPSHOT ON WITH NO_WAIT;
--
-- Verify:
--   SELECT is_read_committed_snapshot_on FROM sys.databases WHERE name = DB_NAME();
--
--   WITH NO_WAIT makes it fail immediately instead of waiting, if there are
--   open transactions. Omitting NO_WAIT can queue the change behind a long
--   running transaction and block indefinitely.
--
--   Once enabled, READ COMMITTED readers stop taking shared locks. They read
--   row versions from tempdb instead, so they never block writers and never
--   block each other.
--
--   THE COST: every modified row keeps its old version in tempdb until the
--   oldest open transaction finishes. A report that runs for an hour pins an
--   hour of row versions, which grows tempdb. Long-running transactions are
--   what make RCSI dangerous.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 5. DBCC OPENTRAN - the transaction you forgot about
--
--   Long-running open transactions are the most common cause of both
--   blocking and unexpected tempdb growth. There is always one.
-- =========================================================================---
SELECT
    s.session_id       AS SessionID,
    s.login_name,
    s.host_name,
    s.program_name,
    at.transaction_begin_time,
    DATEDIFF(SECOND, at.transaction_begin_time, SYSDATETIME()) AS SecondsOpen,
    t.text             AS TheStatement
FROM sys.dm_tran_active_transactions at
JOIN sys.dm_tran_session_transactions st ON st.transaction_id = at.transaction_id
JOIN sys.dm_exec_sessions  s ON s.session_id = st.session_id
JOIN sys.dm_exec_requests r ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
ORDER BY at.transaction_begin_time;
GO
-- Anything open for more than a few seconds deserves an explanation.
-- Query this before blaming isolation levels for a performance problem.
