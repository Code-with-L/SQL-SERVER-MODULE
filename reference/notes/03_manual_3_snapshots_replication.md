# 📙 Manual 3 — Database Snapshots & Replication

> **Your notes:** *Database snapshots, read-only point-in-time copies, copy-on-write,
> creating/reverting snapshots, replication, snapshot/transactional/merge replication,
> replication agents.*

---

## The distinction to hold onto for the whole manual

| | Snapshot | Backup |
|---|---|---|
| Speed | **seconds**, regardless of size | scales with size |
| Size on disk | grows only as the source changes | full size immediately |
| **Restorable?** | **NO — you cannot `RESTORE` from it** | **YES — that is its purpose** |
| Writable? | no, read-only | n/a |
| Transaction log? | none | yes |
| Point-in-time? | one instant only | many, with log backups |
| Answers | *"what did this look like then?"* | *"we lost the database"* |

They are **complementary, not alternatives.** A sound recovery strategy uses both.

---

## What a database snapshot is

A **point-in-time, read-only copy**, created almost instantly no matter how large
the database is.

**The analogy:**
- Database = a book you are writing
- Backup = a photocopy of the whole book
- **Snapshot = a bookmark.** You can see what page 40 said at the moment you
  inserted the bookmark.

That bookmark framing explains the limitation: **the snapshot only shows the
database as it was at that instant.** Later changes are invisible to it.

---

## Copy-on-write — the concept that makes it fast

Creating a snapshot **does not copy your data.** A 400 GB database snapshots in
about a second because it copies *nothing*.

How it works:

1. The snapshot records which pages the source currently holds
2. The source carries on working normally
3. When a page **in the source changes**, SQL Server copies the **original** page
   out of the source into the snapshot file
4. Pages that never change are **shared** and never duplicated

### The consequences
- A snapshot starts at nearly **zero** size and **grows as the source changes**
- A source that barely changes → tiny snapshot
- A source that changes constantly → a snapshot approaching database size
- You can watch it grow: query `sys.database_files` inside the snapshot after
  making changes in the source

---

## Creating one

```sql
CREATE DATABASE StudentRecordsDB_snap1
ON ( NAME = StudentRecordsDB,
     FILENAME = '...DATA\StudentRecordsDB.ssn' )
AS SNAPSHOT OF StudentRecordsDB;
```

**Rules**
- **Every** data file of the source must be listed
- The **log file is never listed** — snapshots have no log
- `FILENAME` may differ from the source
- The `.ssn` extension marks a snapshot file
- Every **filegroup** needs at least one file listed

---

## Restrictions

A snapshot **cannot**:
- be written to (`INSERT`/`UPDATE`/`DELETE`/DDL → `Msg 3903`, read-only mode)
- have a transaction log
- be attached, detached, or restored
- act as a replication subscriber
- span multiple filegroups without listing all of them

Snapshots can auto-close and be dropped by an `AUTO_CLOSE` setting (default `0`
= never).

---

## "Reverting" — what that really means

**You cannot revert a snapshot onto a database.** There is no such operation.

What you actually do is **read from the snapshot and write into the live
database**:

```sql
UPDATE live
   SET live.CreditLine = snap.CreditLine
  FROM dbo.Customer live
  JOIN StudentRecordsDB_snap1.dbo.Customer snap
    ON snap.CustomerID = live.CustomerID;
```

That is the whole workflow. Row by row, with a `WHERE` clause you can see and
approve.

### Recovering a dropped table
1. `SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.Customer'))` — **in the snapshot
   context**, to get the definition as it was
2. Re-`CREATE` the table in the live database
3. Copy the rows across
4. `SET IDENTITY_INSERT ... ON` — because you are supplying values for an
   `IDENTITY` column

---

## Replication — what it is

**Copying database objects and data between databases, and keeping them in sync
automatically.** Usually one server (Publisher) → another (Subscriber).

It is **not** backup and **not** a snapshot. It is a live, ongoing feed.

### The four components

| Component | Role |
|---|---|
| **Publisher** | the source. Decides *what* is replicated. |
| **Subscriber** | the destination. Receives the data. |
| **Distribution** | the transport. A distribution database, or a share. |
| **Agent** | the background processes that move the data. |

### The agents — your manual devotes real attention to these

| Agent | What it does |
|---|---|
| **Snapshot Agent** | Runs **once** at initialisation. Copies the full data set. Only ever runs once per article. |
| **Log Reader Agent** | Tails the **transaction log** of the publisher and forwards changes to distribution. **The only agent that reads the log.** |
| **Distribution Agent** | Delivers queued changes from distribution to the subscriber. |
| **Merge Agent** | Resolves conflicts when both sides changed a row. Merge only. |

### The chain — and how to debug it
```
Publisher transaction log
   → Log Reader Agent
      → distribution database
         → Distribution Agent
            → Subscriber
```
**If replication stalls, find which agent in that chain stopped.** That single
technique is most of what this chapter is for.

---

## The three types

### Snapshot replication
- **What:** a point-in-time copy of the whole database, applied once
- **How:** the Snapshot Agent runs, copies everything, done
- **Sync:** one-shot, then nothing until re-run
- **Used for:** seeding a reporting database, small data sets, infrequent syncs
- **Risk:** none — it only ever writes

### Transactional replication
- **What:** an initial snapshot, then a **continuous stream of changes** in
  commit order
- **How:** Log Reader Agent reads the log → Distribution Agent forwards
- **Sync:** near real-time, **strict commit order**
- **Used for:** scale out reads, offload reporting, warm standby
- ⚠️ **Subscribers are READ ONLY.** Only the publisher accepts writes.
  **That single fact is the whole distinction.**

### Merge replication
- **What:** changes flow **both ways**
- **How:** every node has its own copy; the Merge Agent compares and merges
- **Sync:** near real-time, bidirectional
- **Used for:** mobile and branch-office users working offline
- ⚠️ **CONFLICTS.** Two people edited the same row while offline. The merge
  agent must pick a winner — the manual treats conflict resolution as a real
  design problem, not a detail

### Choosing

| Situation | Type |
|---|---|
| One-way, subscribers read-only | **Transactional** |
| Two-way editing | **Merge** (accept the complexity) |
| One-off copy | **Snapshot** |

---

## The metadata problem

The Log Reader Agent needs to know which rows are **already** published. It
cannot guess, so the publisher stores metadata **in the published table itself**
(`sp_MSrepl*`, `MSpeer_*` columns).

**Practical consequences:**
- Adding a column or changing a PK on a published table can break replication
- A table usually cannot be published twice with different column subsets
- Verify with:
```sql
SELECT c.name, ty.name, c.is_identity
FROM sys.columns c JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.Customer');
```

---

## Inspecting your own server

All read-only. Safe to run any time.

```sql
-- What replication exists at all?
SELECT r.name, r.publisher_db FROM msdb.dbo.MSreplication_services r;

-- Which tables are published (articles)?
SELECT spa.publisher_db, spa.publisher, spa.name AS Article, st.name AS SourceTable
FROM dbo.MSreplication_services spa
LEFT JOIN msdbo.msreplication_articles st ON st.publisher_id = spa.publisher_id
WHERE spa.article = 1;

-- Which subscriptions exist?
SELECT ss.subscription_db FROM dbo.MSreplication_services ss WHERE ss.subscription_type = 1;

-- Are the agent jobs running?
SELECT name, enabled FROM msdb.dbo.sysjobs
WHERE name LIKE '%Replication%';
```

Expect **zero rows** — replication is not configured here, and it does not need
to be. The views still answer *"what would I have?"*

---

## Why there is no live replication topology here

A two-server setup needs: a second instance, a distribution database, SQL Agent
jobs, Windows shares, and cross-machine account permissions. That is a full
afternoon of infrastructure on a single laptop.

The course objective is to **recognise the three types, name the agents, and know
what to check when replication stalls.** The scripts here cover that.

If your lecturer wants a live demo, the checklist is:
1. Second instance (or two databases on one instance)
2. Distributor → `sp_adddistributor`
3. Publisher → `sp_addpublisher` / `sp_addpublication`
4. Subscriber → `sp_addpushsubscription`
5. Agent jobs running; the Log Reader not erroring

---

## Self-check

1. Why does creating a snapshot take one second on a 400 GB database?
2. What is copied-on-write, and when?
3. Can you `RESTORE` from a snapshot? Why not?
4. Name the four replication agents and say which one reads the transaction log.
5. What single fact distinguishes transactional from merge replication?
6. Replication stalls. What is the first thing you check?

---

**Next:** [Manual 4 — Monitoring & Troubleshooting](04_manual_4_monitoring.md)
