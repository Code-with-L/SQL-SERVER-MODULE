-- ============================================================================
-- Script: 05_profiler_and_tuning.sql
-- Manual : Part 4 - SQL Server Profiler, SQL Trace, Tuning Advisor, workloads
-- ============================================================================
--
-- THE DIAGNOSTIC LADDER - follow it in order, never jump to step 4.
--
--   1. THE PROBLEM IS SPECIFIC?      "Everything is slow" is not a symptom.
--                                    Find the one slow report.
--   2. IS IT THE DATABASE AT ALL?    Check waits and CPU. It is often the
--                                    application or the network.
--   3. WHAT IS IT WAITING ON?        Look at sys.dm_exec_requests and
--                                    sys.dm_os_wait_stats.
--   4. WHAT IS THE PLAN?             Capture it with SET STATISTICS XML or
--                                    an actual plan in SSMS.
--   5. WHAT IS THE WORKLOAD?         Profiler / XE to see the real frequency.
--   6. WHAT SHOULD I CHANGE?         Tuning Advisor, indexes, plan, query.
--   7. DID IT HELP?                  Measure again. Never assume.
--
--   Skipping to step 6 is how people add indexes that are never used and make
--   writes slower forever.
-- ============================================================================

USE StudentRecordsDB;
GO

-- ============================================================================
-- STEP 2 - IS IT EVEN THE DATABASE?
-- ============================================================================

-- 2a. What is the CPU actually doing RIGHT NOW?
SELECT
    r.session_id,
    r.status,
    r.command,
    r.cpu_time             AS CpuTicks,
    r.total_elapsed_time   AS ElapsedTicks,
    r.logical_reads,
    r.reads,
    r.writes,
    r.wait_type,
    r.wait_time,
    r.wait_resource,
    r.blocking_session_id,
    r.percent_complete,
    s.login_name,
    s.host_name,
    s.program_name
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
WHERE s.is_user_process = 1
ORDER BY r.total_elapsed_time DESC;
GO
-- Read the ratio: wait_time high + cpu_time low  = waiting on something
--                wait_time low  + cpu_time high = CPU-bound, tune the query
--                                                      or add an index
--
-- percent_complete is only populated for BACKUP/RESTORE/DBCC.

-- 2b. THE MOST IMPORTANT DMV IN SQL SERVER: what are we WAITING on?
SELECT
    wait_type                          AS WaitType,
    wait_type_desc                     AS WhatItMeans,
    current_waiting_tasks_count        AS SessionsWaiting,
    max_wait_time_ms                   AS WorstWaitMs,
    signal_wait_time_ms                AS TimeWaitingOnCpu
FROM sys.dm_os_wait_stats
WHERE current_waiting_tasks_count > 0
ORDER BY current_waiting_tasks_count DESC;
GO
-- NOT THREADSAFE        - short-term, CPU-bound. Normal, ignore it.
-- CXPACKET              - parallelism. Often fine.
-- PAGEIOLATCH           - a page was not in memory and had to be read from
--                         disk. THE signal that you are I/O bound and need
--                         MORE MEMORY, not an index. This is the single most
--                         misdiagnosed wait.
-- LCK_M_U / LCK_M_X     - waiting on locks. See 02_locking_and_blocking.sql.
-- WRITELOG               - waiting for the transaction log to flush to disk.
--                         Only a problem if the log volume is on a slow disk.
-- SOS_SCHEDULER_YIELD   - the CPU is oversubscribed. Add cores or reduce work.
--
-- These counters are CUMULATIVE since start-up. To compare over a period,
-- capture a value, wait, capture again, and subtract. sys.dm_os_wait_stats
-- has a row for every wait type that has EVER occurred, so filter on
-- current_waiting_tasks_count > 0 or the list is 2000 rows of history.

-- 2c. Buffer cache: is memory working?
SELECT
    (SELECT CAST(SUM(object_resident_page_count) * 8.0 / 1024 AS decimal(10,2))
     FROM sys.dm_os_buffer_descriptors)  AS ResidentMB,
    (SELECT CAST(physical_memory_in_bytes * 1.0 / 1024 / 1024 / 1024 AS decimal(10,2))
     FROM sys.dm_os_sys_memory)          AS PhysicalMemoryGB;
GO
-- If ResidentMB is a large fraction of PhysicalMemoryGB, the cache is doing
-- its job and adding indexes may not help.
-- (ResidentMB includes database pages, procedure cache, and internal caches,
--  so it is an upper bound on what the buffer pool holds.)

-- ============================================================================
-- STEP 4 - GETTING THE EXECUTION PLAN
-- ============================================================================
--   IN SSMS (easiest, do this before anything else):
--     Query > Query Options > Actual Execution Plan  (Ctrl+M)
--   Then run the query. Look at which step is the WIDEST bar - that is where
--   the time and rows go. A clustered index scan returning 100,000 rows when
--   you expected 5 is the answer.
--
--   FROM T-SQL, without SSMS:
-- ============================================================================
SET STATISTICS XML ON;
GO
SELECT * FROM dbo.CustomerAddress WHERE City = 'Nairobi';
GO
SET STATISTICS XML OFF;
GO
-- Returns the plan as XML. Messy to read, but it is the same information.

-- STATISTICS TIME and IO are also available, and often enough on their own:
SET STATISTICS TIME ON;
SET STATISTICS IO  ON;
GO
SELECT * FROM dbo.CustomerAddress WHERE City = 'Nairobi';
GO
SET STATISTICS TIME OFF;
SET STATISTICS IO  OFF;
GO
-- "Logical reads" is the number of 8 KB pages touched FROM CACHE. Compare it
-- before and after an index: if it drops from 400 to 4, the index worked.
-- Physical reads are the ones that actually hit disk.

-- ============================================================================
-- STEP 4b - The plans SQL Server CACHES, worst first
--    sys.dm_exec_query_stats aggregates identical queries. This finds the
--    queries doing the most work, which is where optimisation pays.
-- ============================================================================
SELECT TOP 10
    SUBSTRING(st.text,
              (qs.statement_start_offset / 2) + 1,
              ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
                                            ELSE qs.statement_end_offset END
                - qs.statement_start_offset) / 2) + 1) AS QueryText,
    qs.execution_count                        AS Executions,
    qs.total_elapsed_time / 1000              AS TotalElapsedMs,
    qs.total_elapsed_time / 1000 / qs.execution_count AS AvgElapsedMs,
    qs.total_logical_reads                    AS TotalLogicalReads,
    qs.total_logical_reads / qs.execution_count       AS AvgLogicalReads,
    qs.total_worker_time                      AS TotalCpuMs,
    CAST(qp.query_plan AS xml)                AS QueryPlan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE st.text IS NOT NULL
ORDER BY qs.total_elapsed_time DESC;
GO
-- ORDER BY total_elapsed_time finds the queries that HURT MOST IN TOTAL.
-- ORDER BY avg_elapsed_time finds the ones that hurt per execution.
-- Those are frequently different queries, and optimising the total is usually
-- the bigger win.
--
-- The query_plan column is truncated in the grid; click it to see the XML, or
-- cast it into a new tab. Note: plans are only here while the plan is cached.
-- Restarting SQL Server empties this.

-- ============================================================================
-- STEP 5 - THE WORKLOAD: what is actually running?
--
--   SQL Server Profiler (the manual's tool) and Extended Events (its modern
--   replacement) both capture live activity. From T-SQL:
-- ============================================================================

-- 5a. Cached procedure definitions, with how often each is called
SELECT TOP 15
    OBJECT_NAME(p.object_id, p.dbid) AS ProcedureName,
    p.execution_count               AS Executions,
    DATEDIFF(SECOND, p.last_execution_time, SYSDATETIME())
                                       AS SecondsSinceLastRun
FROM sys.dm_exec_procedure_stats p
WHERE p.database_id = DB_ID()
ORDER BY p.execution_count DESC;
GO

-- 5b. Requests currently running, with the query text
SELECT
    r.session_id,
    r.status,
    r.command,
    r.total_elapsed_time / 1000 AS ElapsedMs,
    r.cpu_time / 1000           AS CpuMs,
    r.logical_reads,
    r.wait_type,
    txt.text                     AS QueryText
FROM sys.dm_exec_requests r
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) txt
WHERE r.database_id = DB_ID()
ORDER BY r.total_elapsed_time DESC;
GO
-- This is a poor man's Profiler for "right now". It cannot show finished
-- queries. For history you need Profiler or Extended Events.

-- ============================================================================
-- SQL SERVER PROFILER - the manual's GUI tool
--
--   WHAT IT IS
--     A GUI that traces SQL Server events as they happen: which query ran,
--     how long it took, which rows it touched, what it waited on. Think of
--     a CCTV camera on your database.
--
--   THE THREE STEPS
--     1. SSMS > Tools > SQL Server Profiler > Connect
--     2. Trace Properties: name it, choose TEMPLATE
--          Blank                 - start from nothing (fine for learning)
--          SQLServerAudit       - logins and permission changes
--          Tuning                - what Tuning Advisor needs
--          Deadlock graph       - captures deadlock XML automatically
--     3. Run, reproduce the problem, Pause, Stop, Save.
--
--   CRITICAL WARNING FROM THE MANUAL
--     "Profiler captures only SQL Server events, not operating system or
--      networking conditions that might be affecting database performance."
--
--     So Profiler can show you a query that took 4 seconds while proving
--     nothing about whether it was SQL Server or the network that was slow.
--     Always correlate with the WAITS (02_locking_and_blocking.sql, step 2b).
--
--     Also: Profiler itself adds overhead. Tracing every event on a busy
--     production server can slow it down measurably. Filter to only the
--     events and columns you need, and never trace on a production box
--     without a plan.
--
--   DEADLOCK GRAPH - the most valuable single use
--     Events > select "Deadlock (Graph)" from "Locks".
--     Run your application, wait for the deadlock, and Profiler shows the
--     full XML graph of BOTH processes, their exact statements, and the
--     resources. That graph is the single best diagnostic tool in this course.
-- ============================================================================

-- ============================================================================
-- DATABASE ENGINE TUNING ADVISOR
--
--   WHAT IT IS
--     It reads a workload and proposes indexes. That is genuinely useful.
--     But it is an ADVISOR - it is a student, not a DBA.
--
--   HOW TO USE IT SAFELY
--     1. Capture a workload with Profiler first (a representative hour, NOT
--        the whole day - the manual's point about not tracing everything).
--     2. SSMS > Tools > Database Engine Tuning Advisor > Connect
--     3. Choose the database, select the .trc file
--     4. Tick "Analyze all columns" or pick specific tables
--     5. It proposes indexes
--     6. BEFORE APPLYING: read "Estimated Impact" and "Statement Cost".
--        Report High Impact means a large improvement.
--
--   THE MANUAL'S CAUTION, and it is the important part
--     Every index makes reads faster and writes slower, and must be updated
--     on every INSERT, UPDATE and DELETE. Tuning Advisor only sees the
--     workload you gave it. If you feed it an hour of SELECTs, it will
--     happily recommend indexes that wreck your overnight INSERTs.
--
--     So: propose, then MEASURE. Apply to a test copy first. Never apply an
--     index nobody has explained to you.
--
--   Also remember it cannot see: queries that run only at 2am, ad-hoc
--   queries nobody will admit to writing, and anything not in the trace.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 6. CHECKING WHETHER AN INDEX IS ACTUALLY BEING USED
--    The step most people skip, and the reason databases accumulate dozens
--    of unused indexes that only slow writes down.
-- ---------------------------------------------------------------------------
SELECT
    s.name                                       AS IndexName,
    s.type_desc                                  AS Type,
    us.user_seeks                                AS Seeks,
    us.user_scans                                AS Scans,
    us.user_lookups                              AS Lookups,
    us.last_user_seek                            AS LastSeek
FROM sys.indexes s
LEFT JOIN sys.dm_db_index_usage_stats us
       ON us.object_id = s.object_id
      AND us.index_id  = s.index_id
      AND us.database_id = DB_ID()
WHERE s.object_id = OBJECT_ID('dbo.CustomerAddress')
ORDER BY us.user_seeks DESC;
GO
-- user_seeks   = the optimiser chose a SEEK (it jumped straight to rows)
-- user_scans   = it chose a SCAN (it read the whole index anyway)
-- user_lookups = seeks that then had to go back to the clustered index for
--                the remaining columns
--
-- An index with 0 seeks AND 0 scans since the last restart is a candidate
-- for removal. But confirm it is genuinely unused before dropping it - the
-- stats reset on restart, so check last_user_seek's DATE against when SQL
-- Server last started.
--
-- Also check for UNUSED COLUMN KEYS:
SELECT
    s.name                AS IndexName,
    c.name                AS ColumnName,
    c.index_column_id,
    c.is_included_column  AS IsIncludedColumn
FROM sys.indexes s
JOIN sys.index_columns c ON c.object_id = s.object_id AND c.index_id = s.index_id
WHERE s.object_id = OBJECT_ID('dbo.CustomerAddress')
ORDER BY s.name, c.index_column_id;
GO
-- is_included_column = 0 -> a KEY column, determines the sort order
-- is_included_column = 1 -> an INCLUDED column, stored in the leaf level but
--                            NOT used to sort or filter. This is how you add
--                            a column to a covering index WITHOUT widening
--                            the search key.

-- ---------------------------------------------------------------------------
-- 7. THE ULTIMATE MEASUREMENT - what a plan change actually costs
-- ---------------------------------------------------------------------------
--   Before adding an index, note: total_elapsed_time, total_logical_reads,
--   and total_worker_time from step 4b. Apply the change. Let the workload
--   run. Measure again.
--
--   If reads dropped and writes did not get worse: keep it.
--   If reads dropped and writes got noticeably worse: you have traded one
--   problem for another. Document that trade-off, because the next engineer
--   will not know why the index is there.
-- ============================================================================
