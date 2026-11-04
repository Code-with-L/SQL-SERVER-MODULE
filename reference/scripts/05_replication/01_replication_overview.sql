-- ============================================================================
-- Script: 01_replication_overview.sql
-- Manual : Part 3 - Replication
-- ============================================================================
--
-- WHAT REPLICATION IS
--   Copying database objects and data between databases, and then KEEPING
--   them in sync automatically. Usually from one server (the Publisher) to
--   another (the Subscriber), for reporting, for performance, or for
--   offloading a workload.
--
--   It is not backup. It is not a snapshot. It is a live, ongoing feed.
--
-- THE FOUR COMPONENTS
--   Publisher    - the source. Decides WHAT gets replicated.
--   Subscriber   - the destination. Receives the replicated data.
--   Distribution - the transport. Carries the changes (a separate
--                  "distribution" database, or a file share, or nothing at
--                  all for a two-server snapshot pull).
--   Agent        - the background processes that actually move the data.
--
-- THE AGENTS - the manual devotes real attention to these
--   Snapshot Agent      - runs once at initialisation. Copies the full data
--                         set. Only ever runs ONE time per article.
--   Log Reader Agent    - tails the transaction log of the publisher and
--                         forwards changes to the distribution database.
--                         THIS IS THE ONLY AGENT THAT READS THE LOG.
--   Distribution Agent  - delivers the queued changes from distribution to
--                         the subscriber.
--   Merge Agent         - resolves conflicts when both sides changed the
--                         same row (merge replication only).
--
--   The chain for a standard push subscription:
--       Publisher transaction log
--            -> Log Reader Agent
--               -> distribution database
--                  -> Distribution Agent
--                     -> Subscriber
--
--   If replication stalls, find out which agent in that chain stopped.
-- ============================================================================

USE master;
GO

-- ============================================================================
-- THE THREE TYPES YOU MUST BE ABLE TO DIFFERENTIATE
-- ============================================================================
--
--   SNAPSHOT REPLICATION
--     What:  a point-in-time copy of the whole database, applied once.
--     How:   Snapshot Agent runs, copies everything, done.
--     Sync:  one-shot. Then nothing until you re-run it.
--     Used: seeding a reporting database; small data sets; infrequent syncs.
--     Risk:  none - it only ever writes.
--
--   TRANSACTIONAL REPLICATION
--     What:  an initial snapshot, then a CONTINUOUS stream of changes in
--            the order they were committed.
--     How:   Log Reader Agent reads the log; Distribution Agent forwards.
--     Sync:  near real-time (seconds), in strict commit order.
--     Used:  scale out reads; offload reporting; keep a warm standby.
--     Note:  subscribers are READ ONLY in this model. Only the publisher
--            accepts writes. That single fact is the whole distinction.
--
--   MERGE REPLICATION
--     What:  changes flow BOTH WAYS.
--     How:   every node has its own copy; the Merge Agent compares and
--            merges, detecting conflicts.
--     Sync:  near real-time, bidirectional.
--     Used:  mobile and branch-office users who work offline.
--     Risk:  CONFLICTS. Two people edited the same row while offline. The
--            merge agent must pick a winner, and the manual is explicit
--            that conflict resolution is a genuine design problem, not a
--            detail.
--
--   DECIDING
--     One-way and read-only for subscribers?  -> TRANSACTIONAL
--     Two-way editing?                      -> MERGE (accept the complexity)
--     One-off copy?                          -> SNAPSHOT
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Inspect what replication exists on THIS instance.
--   These are read-only catalogue views. Safe to run any time.
-- ---------------------------------------------------------------------------
SELECT
    r.name        AS PublisherName,
    r.publisher_db AS PublisherDatabase
FROM msdb.dbo.MSreplication_services r
WHERE r.publisher_db IS NOT NULL;
GO
-- Expect zero rows: replication has not been configured, and it does not
-- need to be for the course. The views still answer "what would I have?"

-- Published tables (articles) configured anywhere on this server:
SELECT
    sp.publisher_db  AS PublisherDatabase,
    spa.publisher    AS Publisher,
    spa.name         AS Article,
    st.name          AS SourceTable
FROM dbo.MSreplication_services spa
LEFT JOIN msdb.dbo.MSreplication_databases sp ON sp.publisher_db = spa.publisher_db
LEFT JOIN msdbo.msreplication_articles    st ON st.publisher_id = spa.publisher_id
WHERE spa.article = 1;
GO

-- Existing subscriptions:
SELECT
    ss.subscription_db AS SubscriberDatabase
FROM dbo.MSreplication_services ss
WHERE ss.subscription_type = 1;
GO

-- Are the replication agent jobs running? (MS Agent, not SQL Agent)
SELECT
    name        AS AgentJob,
    enabled     AS IsEnabled
FROM msdb.dbo.sysjobs
WHERE name LIKE '%Replication%' OR name LIKE 'SQLSERVERAGENT%';
GO

-- ---------------------------------------------------------------------------
-- WHAT SQL SERVER USES TO TRACK REPLICATED ROWS
--
--   The Log Reader Agent needs to know which rows are already published.
--   It cannot guess, so the publisher stores metadata in the published table.
--
--   sp_MSrepl incremental, sp_MSreplcmd, sp_MSreplmarkserveroob,
--   MSp_replident rowguid, MSpeer_*
--
--   Practical consequence: adding a column or a PK to a published table can
--   break replication, and a table cannot usually be published twice with
--   different column subsets.
--
--   Inspect what the publisher added to dbo.Customer:
-- ============================================================================
SELECT
    c.name            AS ColumnName,
    ty.name           AS DataType,
    c.is_identity     AS IsIdentity,
    c.is_nullable     AS IsNullable
FROM sys.columns c
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.Customer')
ORDER BY c.column_id;
GO
-- No MS-replication columns here, which is expected: Customer is not published.

-- ============================================================================
-- WHY WE ARE NOT BUILDING A LIVE REPLICATION TOPOLOGY
--
--   A two-server replication setup needs a second SQL Server instance, a
--   distribution database, SQL Agent jobs, Windows shares, and account
--   permissions between machines. That is a full afternoon of infrastructure
--   work on a single-machine laptop.
--
--   The course objective is to RECOGNISE the three types, name the agents,
--   and know what to check when replication stalls. The scripts here cover
--   that. If your lecturer wants a live demo, the full checklist is:
--     1. Second instance (or the same instance, two databases)
--     2. Distributor  -> sp_adddistributor
--     3. Publisher    -> sp_addpublisher / sp_addpublication
--     4. Subscriber   -> sp_addpushsubscription
--     5. Agent jobs running, and the Log Reader not erroring
-- ============================================================================
