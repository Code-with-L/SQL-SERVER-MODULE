# 📕 Manual 4 — Monitoring & Troubleshooting

> **Your notes:** *SQL Server Profiler, SQL Trace, Database Engine Tuning Advisor,
> workloads, query performance, locking, blocking, deadlocks, isolation levels.*

---

## The diagnostic ladder

**Follow it in order. Never jump to step 4.**

| Step | Question | Tool |
|---|---|---|
| 1 | Is the problem **specific**? | Talk to whoever reported it |
| 2 | Is it **even the database**? | `sys.dm_exec_requests`, `sys.dm_os_wait_stats` |
| 3 | What is it **waiting on**? | `sys.dm_os_wait_stats` |
| 4 | What is the **plan**? | Actual Execution Plan (Ctrl+M) |
| 5 | What is the **workload**? | Profiler / Extended Events |
| 6 | What should I **change**? | Tuning Advisor, indexes, the query |
| 7 | Did it **help**? | Measure again |

**Skipping to step 6** is how people add indexes nobody uses and make writes
slower forever.

---

## Step 2 — Is it even the database?

### The most important DMV in SQL Server: what are we waiting on?

```sql
SELECT
    wait_type,
    wait_type_desc,
    current_waiting_tasks_count,
    max_wait_time_ms,
    signal_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE current_waiting_tasks_count > 0
ORDER BY current_waiting_tasks_count DESC;
```

| Wait type | Meaning | Act on it? |
|---|---|---|
| `NOT_THREADSAFE` | short-term, CPU-bound | **No.** Normal, ignore |
| `CXPACKET` | parallelism | Usually no |
| **`PAGEIOLATCH`** | page not in memory, read from disk | **Add memory.** The most misdiagnosed wait |
| `LCK_M_U` / `LCK_M_X` | waiting on locks | See locking, below |
| `WRITELOG` | waiting for log flush | Only if log volume is on slow disk |
| `SOS_SCHEDULER_YIELD` | CPU oversubscribed | More cores, or less work |

> ⚠️ These counters are **cumulative since start-up**. Capture a value, wait,
> capture again, **subtract**. A server up for a year has a large "deadlocks"
> count even if nothing is currently wrong.

### Reading requests
```sql
SELECT
    r.session_id, r.status, r.command,
    r.cpu_time, r.total_elapsed_time,
    r.logical_reads, r.wait_type, r.wait_time,
    r.blocking_session_id,
    s.login_name, s.host_name, s.program_name
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
WHERE s.is_user_process = 1
ORDER BY r.total_elapsed_time DESC;
```

**The ratio that tells you the story:**
- `wait_time` **high**, `cpu_time` **low** → waiting on something else
- `wait_time` **low**, `cpu_time` **high** → CPU-bound; tune the query or index

### Memory
```sql
SELECT
    (SELECT SUM(object_resident_page_count) * 8.0 / 1024
     FROM sys.dm_os_buffer_descriptors) AS ResidentMB,
    (SELECT physical_memory_in_bytes / 1024.0 / 1024 / 1024
     FROM sys.dm_os_sys_memory)         AS PhysicalMemoryGB;
```
If `ResidentMB` is a large share of `PhysicalMemoryGB`, the cache is doing its
job and **more indexes may not help.**

---

## Step 4 — The execution plan

**In SSMS, do this before anything else:**
`Query` → `Query Options` → **Actual Execution Plan** (`Ctrl+M`), then run.

Look for the **widest bar**. That is where the time and rows go. A clustered
index scan returning 100,000 rows when you expected 5 is your answer.

### From T-SQL
```sql
SET STATISTICS XML ON;         -- the plan as XML
SET STATISTICS TIME ON;        -- CPU and elapsed per statement
SET STATISTICS IO ON;          -- reads and writes
```

**"Logical reads"** = 8 KB pages touched **from cache**. Compare before and
after an index: 400 → 4 means the index worked. **Physical reads** actually hit disk.

### The queries hurting you most
```sql
SELECT TOP 10
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1, (
        (CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1
    ) AS QueryText,
    qs.execution_count,
    qs.total_elapsed_time / 1000                              AS TotalElapsedMs,
    qs.total_elapsed_time / 1000 / qs.execution_count        AS AvgElapsedMs,
    qs.total_logical_reads / qs.execution_count              AS AvgLogicalReads,
    CAST(qp.query_plan AS xml) AS QueryPlan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE st.text IS NOT NULL
ORDER BY qs.total_elapsed_time DESC;
```

- `ORDER BY total_elapsed_time` → hurts most **in total**
- `ORDER BY avg_elapsed_time` → hurts most **per execution**

**These are frequently different queries.** Optimising the total is usually the
bigger win.

Plans are cached — they vanish when SQL Server restarts.

---

## Step 5 — Profiler / the workload

### What Profiler is
A GUI that traces SQL Server events as they happen: which query ran, how long,
which rows, what it waited on. **A CCTV camera on your database.**

### Three steps
1. SSMS → `Tools` → `SQL Server Profiler` → Connect
2. Trace Properties — name it, choose a **template**
3. Run, reproduce, **Pause**, Stop, Save

| Template | Use |
|---|---|
| Blank | learning |
| **SQLServerAudit** | logins, permission changes |
| Tuning | what Tuning Advisor needs |
| **Deadlock graph** | captures deadlock XML automatically |

> ⚠️ **The manual's own caution:** *"Profiler captures only SQL Server events, not
> operating system or networking conditions that might be affecting database
> performance."*
>
> So Profiler can show a 4-second query and prove nothing about whether SQL
> Server or the network was slow. **Always correlate with the waits.**

Also: Profiler adds overhead. Tracing every event on a busy server measurably
slows it. Filter to only the events and columns you need.

### The deadlock graph — the single best use
`Events` → select **"Deadlock (Graph)"** from the "Locks" group. Reproduce the
deadlock and Profiler shows the full XML of **both** processes, their exact
statements, and the resources involved.

---

## Locking

### Why locks exist
Two things at once:
- Session A: `UPDATE dbo.Customer SET CreditLine = 0 WHERE CustomerID = 1`
- Session B: `SELECT CreditLine FROM dbo.Customer WHERE CustomerID = 1`

If B reads midway through A, it reads a value that **never really existed.**
A lock is how SQL Server says *"wait, I am not finished."*

### The modes
| Mode | Meaning |
|---|---|
| **Shared (S)** | reading. Many readers, no writers. |
| **Update (U)** | "about to write." Slightly stronger than S. |
| **Exclusive (X)** | writing. Blocks everything. |
| **Intent (I)** | on a table — "I intend to lock rows inside." |
| **Schema (Sch)** | changing structure. Blocks everything. |

### The compatibility matrix — why SELECT and UPDATE fight
| held \ wants | S | U | X |
|---|---|---|---|
| **S** | ok | ok | **WAIT** |
| **U** | ok | **WAIT** | **WAIT** |
| **X** | **WAIT** | **WAIT** | **WAIT** |

**`U` vs `U` waits.** That surprises people and is behind most deadlocks.

### Seeing a block — two windows
```sql
-- WINDOW 1 (the blocker)
BEGIN TRANSACTION;
    UPDATE dbo.Country SET Country = 'KENYA' WHERE CountryID = 1;
    -- do NOT commit
```

```sql
-- WINDOW 2 (gets blocked)
SELECT * FROM dbo.Country WHERE CountryID = 1;
```

```sql
-- WINDOW 3 (any time) - who blocks whom
SELECT
    r.session_id, r.blocking_session_id, r.wait_type, r.wait_time,
    s.login_name, s.host_name, s.program_name, txt.text
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) txt
WHERE r.blocking_session_id <> 0
   OR EXISTS (SELECT 1 FROM sys.dm_exec_requests b
              WHERE b.blocking_session_id = r.session_id);
```

### Lock granularities
`KEY` = one row (most common) · `PAGE` = several rows in 8 KB ·
`TABLE` = whole table (usually a schema change)

### Killing a blocker
```sql
KILL 55;    -- first KILL is a WARNING
KILL 55;    -- second KILL actually terminates
```
Rolls back that session's open transaction. **Not the first move** — find out
*why* it is holding the lock.

---

## Blocking vs deadlock vs timeout — do not confuse them

| | Cause | Resolves itself? | Error |
|---|---|---|---|
| **Blocking** | a session waits for one still working | ✅ yes | none — it just hangs |
| **Timeout** | blocking that went too long | ❌ | `Msg 1222` |
| **Deadlock** | a **cycle** | ❌ **never** | `Msg 1205` |

```sql
SET LOCK_TIMEOUT 5000;   -- give up after 5s
SET LOCK_TIMEOUT -1;     -- default: wait forever
```
For a web request, a timeout is often **better** than a deadlock: a quick failure
you can retry, instead of one session being sacrificed.

---

## Deadlocks

### What one is
Two sessions each hold what the other needs. Neither continues, neither yields.
Both wait forever until SQL Server intervenes.

```
Session A                     Session B
BEGIN TRANSACTION             BEGIN TRANSACTION
UPDATE Country   (lock row1)  UPDATE StateProvince (lock row1)
UPDATE StateProvince          UPDATE Country
  (needs row1's lock)           (needs row1's lock)
WAITING ------------------------- WAITING
```

### Why SQL Server kills one
It must — otherwise the database stops serving queries. It picks the victim by
**cost**: the cheapest transaction to roll back.

```
Msg 1205: Deadlock detected. The transaction has been chosen as the deadlock
victim. Execute the transaction again.
```

**"Execute again" is literal.** Applications **must** retry. A deadlock is a
normal event under concurrency, not a fault.

### Reading the graph
The full XML goes to the **ERRORLOG**, not the Messages pane (which shows only
`Msg 1205`).

```sql
EXEC sp_readerrorlog 0, 1, 'deadlock';
EXEC sp_readerrorlog 0, 1, 'deadlock', '2026-09-30';   -- narrow by date
```
Or SSMS → Management → SQL Server Logs → View SQL Server Log.

### Reproducing one deliberately
```sql
-- WINDOW 1
BEGIN TRANSACTION;
    UPDATE dbo.Country SET Country = Country WHERE CountryID = 1;
    WAITFOR DELAY '00:00:15';
    UPDATE dbo.StateProvince SET StateProvince = StateProvince WHERE StateProvinceID = 1;
COMMIT TRANSACTION;

-- WINDOW 2, start ~5s later
BEGIN TRANSACTION;
    UPDATE dbo.StateProvince SET StateProvince = StateProvince WHERE StateProvinceID = 1;
    WAITFOR DELAY '00:00:15';
    UPDATE dbo.Country SET Country = Country WHERE CountryID = 1;
COMMIT TRANSACTION;
```
`Country = Country` takes an exclusive lock **without changing anything** —
exactly what a controlled demo needs.

**Safety:** nothing commits, nothing changes value. The victim is rolled back.

### The retry pattern
```sql
DECLARE @attempt int = 1, @max int = 3;
WHILE @attempt <= @max
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;
            -- your statements, in a CONSISTENT ORDER
        COMMIT TRANSACTION;
        BREAK;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() = 1205 AND @attempt < @max
        BEGIN
            WAITFOR DELAY '00:00:0' + CAST(@attempt * 200 AS varchar(4));
            SET @attempt += 1;
            CONTINUE;
        END
        THROW;
    END CATCH
END
```

### The real fix
**Consistent ordering.** If every transaction updates `Country` before
`StateProvince`, the cycle can never form. Retries are the safety net;
consistent ordering is the cure.

**Deadlock proofreading list**
- [ ] Do all transactions touch tables in the **same order**?
- [ ] Are transactions as **short** as possible?
- [ ] Is every FOREIGN KEY column indexed?
- [ ] Does any transaction read rows it does not need?
- [ ] Is an application running interactive queries inside transactions?

---

## Isolation levels

### The anomalies

| Anomaly | Means |
|---|---|
| **Dirty read** | you read a row another session later rolls back |
| **Non-repeatable read** | same row twice, two different values |
| **Phantom** | your `WHERE` matches a different **number** of rows |
| **Lost update** | two sessions write; one write silently vanishes |

### The five levels

| Level | Dirty reads | Locks held until |
|---|---|---|
| `READ UNCOMMITTED` | **YES** | end of statement |
| `READ COMMITTED` *(default)* | no | end of each statement |
| `REPEATABLE READ` | no | end of transaction |
| `SERIALIZABLE` | no | end of transaction **+ ranges** |
| `SNAPSHOT` | no | **none** (uses row versions) |

### Detail

**READ UNCOMMITTED** — reads uncommitted data. Only legitimate for a rough
estimate where a wrong number is fine. Never for money, stock, or grades.

**READ COMMITTED** — the default. Accurate, much less blocking than RU.
But a report can still see an inconsistent *picture* if another session changes
rows between your reads.

**REPEATABLE READ** — holds S locks to end of transaction.
⚠️ **SQL Server only truly enforces this for rows that have been *modified*** —
it uses row versioning for the rest. This is a well-known and much-criticised
gap between documented and actual behaviour.

**SERIALIZABLE** — like RR plus range locks. `WHERE CustomerID = 5` locks the
**range** around 5, stopping inserts there. Highest blocking/deadlock risk.

**SNAPSHOT** — every reader sees the database as it was at the **start** of the
transaction, with **no read locks at all**.
- ✅ Readers never block writers, never see inconsistent data
- ❌ Row versions accumulate in `tempdb` until the oldest transaction finishes
- Requires `ALLOW_SNAPSHOT_ISOLATION ON` (database level)

```sql
ALTER DATABASE StudentRecordsDB SET READ_COMMITTED_SNAPSHOT ON WITH NO_WAIT;
```
`WITH NO_WAIT` fails fast instead of queueing behind a long transaction.

### The two bonus row-versioning levels
`READ COMMITTED_SNAPSHOT` (RCSI) — same benefit, but it is the **database-level
default**, so no application code changes. **Usually the better first move.**

### 🔥 LOST UPDATE — no isolation level fixes this
Two sessions read a value, both calculate from it, both write. The second write
discards the first.

The correct fix is a **lock hint**:
```sql
UPDATE dbo.Country WITH (UPDLOCK, ROWLOCK)
   SET Country = 'New'
 WHERE CountryID = 1;
```
`UPDLOCK` takes an Update lock at the **start** of the statement instead of
escalating from Shared at write time, closing the window. **The single most
practically useful thing in this chapter.**

---

## Database Engine Tuning Advisor

### What it is
Reads a workload and **proposes indexes**. Genuinely useful. But it is an
**advisor** — a student, not a DBA.

### Using it safely
1. Capture a workload with Profiler — a **representative hour**, not the whole day
2. SSMS → `Tools` → `Database Engine Tuning Advisor`
3. Select the database and the `.trc` file
4. Analyse all columns, or pick tables
5. Read **Estimated Impact** and **Statement Cost** before applying anything

### ⚠️ The caution that matters
Every index makes reads faster and writes slower. Tuning Advisor **only sees the
workload you gave it.** Feed it an hour of `SELECT`s and it will happily
recommend indexes that wreck your overnight `INSERT`s.

**Propose, then MEASURE.** Apply to a test copy first. Never apply an index
nobody has explained to you.

It also cannot see: 2am-only queries, ad-hoc queries nobody admits to, and
anything not in the trace.

---

## Check whether an index is actually used

The step most people skip — and the reason databases accumulate unused indexes
that only slow writes down.

```sql
SELECT
    s.name AS IndexName, s.type_desc,
    us.user_seeks, us.user_scans, us.user_lookups, us.last_user_seek
FROM sys.indexes s
LEFT JOIN sys.dm_db_index_usage_stats us
       ON us.object_id = s.object_id AND us.index_id = s.index_id
      AND us.database_id = DB_ID()
WHERE s.object_id = OBJECT_ID('dbo.CustomerAddress')
ORDER BY us.user_seeks DESC;
```

- `user_seeks` = the optimiser chose a **seek** (jumped straight to rows)
- `user_scans` = a **scan** anyway
- `user_lookups` = seeks that then went back to the clustered index

An index with 0 seeks **and** 0 scans since restart is a removal candidate — but
confirm against `last_user_seek`'s date versus when SQL Server started, because
**the stats reset on restart.**

---

## The rule for this whole manual

> **Never make a change you have not measured.**
>
> Before: note `total_elapsed_time`, `total_logical_reads`, `total_worker_time`.
> Apply the change. Let the workload run. Measure again.
>
> If reads dropped and writes did not worsen → keep it.
> If reads dropped and writes got worse → you traded one problem for another.
> **Document it**, because the next engineer will not know why the index is there.

---

## Self-check

1. Which DMV answers "what is the server waiting on right now?"
2. `PAGEIOLATCH` — what does it actually mean, and what is the fix?
3. Which lock modes wait against each other? Why does that cause deadlocks?
4. Blocking, timeout, deadlock — how do you tell them apart?
5. Which isolation level has no lost-update problem? What fixes it instead?
6. Why must every transaction touch tables in the same order?
7. Why should you not feed Tuning Advisor a whole day of traces?

---

**Back to:** [README](../README.md) · [Exercises & answers](05_exercises_and_answers.md)
