# ✏️ Exercises & Answers

Work through these **without looking at the answers**. The answers are at the
bottom of each section so you cannot see them by accident.

Every exercise uses `StudentRecordsDB`. Nothing here is destructive to anything
you have not created.

---

## 🟢 Level 1 — Warm-up

### Q1. `DB_NAME()` returns `master` instead of `StudentRecordsDB`.
**What is wrong, and how do you fix it without clicking around the GUI?**

<details><summary>Answer</summary>

Your session is pointed at `master` — the default for a new query window. It
is not an error; `master` is a valid database. `USE` only lasts for the session
it runs in.

```sql
USE StudentRecordsDB;
```

Also worth knowing: `master` is how your `Students` table ended up in a system
database earlier. **Never create user objects there** — it must be readable at
start-up, and custom tables can break upgrades.
</details>

### Q2. Name the four system databases and one job of each.

<details><summary>Answer</summary>

| Database | Job |
|---|---|
| `master` | logins, databases, metadata. **SQL Server cannot start without it.** |
| `model` | **template** — every new database is cloned from it |
| `msdb` | jobs, schedules, backup history |
| `tempdb` | temp tables and sorts. **Rebuilt from scratch every restart.** |
</details>

### Q3. What does `compatibility_level = 170` tell you, and what should you check against your manuals?

<details><summary>Answer</summary>

`170` = SQL Server 2025. Your manuals describe **90** = SQL Server 2005.

The *concepts* are still current. The *syntax* is not always so. Example you
already hit: the `DATE` type **did not exist in 2005** (introduced in 2008), so
your old script could never have run on the version the manual teaches.

```sql
SELECT name, compatibility_level FROM sys.databases WHERE database_id > 4;
```
</details>

---

## 🟡 Level 2 — Data types & columns

### Q4. What is the largest value `DECIMAL(8,3)` can hold? `DECIMAL(3,8)`?

<details><summary>Answer</summary>

- `DECIMAL(8,3)` → **99999.999** (8 digits total, 3 after the point → 5 before)
- `DECIMAL(3,8)` → **invalid.** Error: *"The number of digits to the right of
  the decimal point and scale must be between 0 and the number of digits to the
  left."* 8 > 3, so it cannot fit.

The first argument is the **total**, not the whole part.
</details>

### Q5. Why should `dbo.AddressType.AddressTypeID` be `tinyint` and not `int`?

<details><summary>Answer</summary>

`tinyint` holds 0–255 in **1 byte**; `int` holds ±2.1 billion in **4 bytes**.

There are only ever a handful of address types (Home, Work, Billing), so
`tinyint` stores every expected value in the least space possible — exactly the
manual's rule. You save 3 bytes on every row, in every table that references it,
forever.
</details>

### Q6. Your query returns nothing and there is no error. You wrote:
```sql
SELECT * FROM dbo.Customer WHERE CreditLimit = NULL;
```
**What went wrong, and what are the two correct ways to write it?**

<details><summary>Answer</summary>

`NULL` is not a value, so `= NULL` evaluates to **UNKNOWN**, never TRUE. `WHERE`
only returns TRUE rows. It fails **silently** — the most dangerous kind of bug.

```sql
WHERE CreditLimit IS NULL
WHERE CreditLimit IS NOT NULL
```

(`IS DISTINCT FROM` also works, and treats NULL as comparable.)
</details>

### Q7. `CREATE TABLE #Temp (...)` in window A, then `CREATE TABLE #Temp (...)`
again in window B. What error, and why?

<details><summary>Answer</summary>

`Msg 2714`: *"There is already an object named '#Temp' in the database."*

A **local** `#temp` persists for your whole **session**, not per batch. So a
second `CREATE` with the same name collides.

Fixes: `DROP TABLE #Temp;` first, or name them uniquely (`#Temp_A`,
`#Temp_20260930`). It does **not** collide if both `CREATE`s are in the *same*
batch — SQL Server allows that.
</details>

---

## 🟠 Level 3 — Constraints & relationships

### Q8. You need "every order, and the customer's name if there is one." Which join, and why not the other?

<details><summary>Answer</summary>

`LEFT JOIN` from Orders (the side you cannot lose rows from):

```sql
SELECT o.OrderID, c.CustomerName
FROM dbo.Orders o
LEFT JOIN dbo.Customer c ON c.CustomerID = o.CustomerID;
```

`INNER JOIN` would drop every order whose customer row is missing — exactly the
rows you asked to keep. `RIGHT JOIN` gives the same rows but reads right-to-left;
prefer `LEFT JOIN` with the tables reordered.
</details>

### Q9. What is wrong with this table?
```sql
CREATE TABLE dbo.Orders (
    OrderID    int PRIMARY KEY,
    CustomerID int NOT NULL,
    Total      decimal(10,2)
);
```

<details><summary>Answer</summary>

**Two problems.**

1. `OrderID` is not `IDENTITY`, so you must supply every value by hand —
   reintroducing exactly the collision problem `IDENTITY` exists to solve.

2. `CustomerID` has **no foreign key**. Nothing stops you storing `CustomerID = 9999`
   for a customer who does not exist — the referential integrity the manual
   requires.

```sql
CREATE TABLE dbo.Orders (
    OrderID    int IDENTITY(1,1) PRIMARY KEY,
    CustomerID int NOT NULL
        CONSTRAINT FK_Orders_Customer
        REFERENCES dbo.Customer(CustomerID),
    Total      decimal(10,2) NOT NULL
);
```
</details>

### Q10. One customer has many addresses; one address serves many customers.
**How do you model it, and why can a single foreign key not do it?**

<details><summary>Answer</summary>

A single FK supports **one-to-many** or **one-to-one** only. This is
**many-to-many**, so you need a **third table** — a junction table — whose rows
*are* the links.

```sql
CREATE TABLE dbo.CustomerToCustomerAddress (
    CustomerID        int NOT NULL REFERENCES dbo.Customer(CustomerID),
    CustomerAddressID int NOT NULL REFERENCES dbo.CustomerAddress(CustomerAddressID),
    CONSTRAINT PK_CTCA PRIMARY KEY (CustomerID, CustomerAddressID)
);
```

The composite PK also stops the same address being linked to the same customer
twice. This pattern is behind every many-to-many relationship you will meet.
</details>

---

## 🔴 Level 4 — Debugging & troubleshooting

### Q11. A query suddenly got 100× slower. Nothing in the application changed.
**List your first four checks, in order.**

<details><summary>Answer</summary>

1. **Is it even the database?** Check `sys.dm_exec_requests` — high
   `wait_time` + low `cpu_time` means it is *waiting*, not computing.
2. **What is it waiting on?** `sys.dm_os_wait_stats`, filtered to
   `current_waiting_tasks_count > 0`.
   - `PAGEIOLATCH` → **memory**, not a missing index
   - `LCK_M_*` → blocking; go to Q12
3. **Has the plan changed?** `Ctrl+M` → Actual Execution Plan. Find the widest
   bar. A statistic update or an index change can flip a seek to a scan with no
   code change at all.
4. **Is there an open transaction?** `DBCC OPENTRAN` /
   `sys.dm_tran_active_transactions`. A forgotten transaction pins locks and
   blocks an entire database — and it is the most common cause of
   "it suddenly got slow".

**Do not** add an index first. That is step 6 of the ladder, not step 1.
</details>

### Q12. Session 61 has been "running" for 40 minutes and blocking everything.
**What do you do, and what do you do NOT do?**

<details><summary>Answer</summary>

1. **Find out what it is doing** — `sys.dm_exec_requests` joined to
   `sys.dm_exec_sql_text` gives the exact statement
2. **Check `blocking_session_id`** to confirm the chain
3. **Ask why it is holding the lock** — a long report that should be re-written,
   an uncommitted transaction that should be committed
4. **If you must**, `KILL 61` twice (the first is a warning)

**Do not** just kill it as step one. You destroy that session's uncommitted work
and gain nothing about the cause, so it happens again tomorrow.

Also try `SET LOCK_TIMEOUT` so requests fail fast instead of piling up.
</details>

### Q13. You get `Msg 1205`. **What happened, what did SQL Server do, and what
must your application do about it?**

<details><summary>Answer</summary>

A **deadlock**: two transactions each held what the other needed, forming a
cycle that could never resolve.

SQL Server **chose one as the deadlock victim and rolled it back** — it must, or
the database stops serving queries. It picks the victim by **rollback cost**
(cheapest to undo).

Your application **must catch 1205 and retry.** A deadlock is a normal event
under concurrency, not a fault.

The **real** fix is prevention: make every transaction touch tables in the same
order, keep transactions short, and index every FK column.
</details>

### Q14. Blocking, a lock timeout, and a deadlock. **How do you tell them apart?**

<details><summary>Answer</summary>

| | Blocking | Timeout | Deadlock |
|---|---|---|---|
| **Cause** | waits for a session still working | blocking that went on too long | a **cycle** |
| **Resolves itself?** | yes | no | **never** |
| **Error** | none — it just hangs | `Msg 1222` | `Msg 1205` |
| **Cause of the error** | — | `SET LOCK_TIMEOUT` exceeded | victim chosen |

Deadlock: `Msg 1205`. Timeout: `Msg 1222`. Blocking: no error at all, just a
query that will not finish.
</details>

### Q15. A report reads `CreditLimit` twice and gets two different values inside
one transaction. Which isolation level fixes it, and what is the catch on SQL Server?

<details><summary>Answer</summary>

`REPEATABLE READ` — it holds shared locks until the transaction ends, so the
same row always returns the same value.

⚠️ **The catch:** SQL Server only *truly* enforces this for rows that have been
**modified**. For unmodified rows it uses row versioning and the behaviour is
documented differently. This is a well-known and much-criticised gap.

If the concern is a consistent *picture* across many rows, you want `SERIALIZABLE`
(range locks, prevents phantoms) or `SNAPSHOT` (no read locks at all, at the cost
of row versions in `tempdb`).
</details>

### Q16. Two sessions both read a stock count, both add 1, both write.
**What is this called, and what actually fixes it?**

<details><summary>Answer</summary>

A **lost update**. The second write silently discards the first.

**No isolation level fixes it properly** — `SERIALIZABLE` "fixes" it by locking
far too much.

The correct fix is a **lock hint**:
```sql
UPDATE dbo.Product WITH (UPDLOCK, ROWLOCK)
   SET Stock = Stock + 1
 WHERE ProductID = 5;
```
`UPDLOCK` takes an Update lock at the **start** of the statement instead of
escalating from Shared at write time, closing the race window.
</details>

---

## 🔵 Level 5 — Snapshots & Replication

### Q17. A 400 GB database snapshot completes in one second. **Nothing was
copied — so where did the data come from?**

<details><summary>Answer</summary>

**Copy-on-write.** The snapshot records which pages the source holds, and shares
them.

1. The snapshot notes the source's current pages — no copying
2. The source keeps working normally
3. When a source page **changes**, SQL Server copies the **original** page into
   the snapshot file
4. Pages that never change are never duplicated

So a snapshot starts near zero size and **grows as the source changes**. A
source that changes constantly produces a snapshot approaching database size.
</details>

### Q18. Your DBA asks you to recover a table someone accidentally dropped.
**Can you `RESTORE` a snapshot? What do you actually do?**

<details><summary>Answer</summary>

**No.** A snapshot cannot be restored from — it is not a backup. It has no
transaction log, cannot be attached or detached, and `RESTORE` will not accept it.

You **read from the snapshot and write into the live database**:

1. `SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.Customer'))` **in the snapshot
   context**, to get the definition as it was
2. Re-`CREATE` the table in the live database
3. Copy the rows across, with `SET IDENTITY_INSERT ... ON` if the key is
   `IDENTITY`
4. Verify, then `DROP` the snapshot when you no longer need it

That row-by-row copy with a visible `WHERE` clause is the whole workflow. There
is no single "revert" operation.
</details>

### Q19. Replication stopped working at 2am and nobody is on site.
**Name the four agents, and which one do you check first?**

<details><summary>Answer</summary>

| Agent | Role |
|---|---|
| **Snapshot Agent** | runs once at initialisation, copies everything |
| **Log Reader Agent** | reads the publisher's **transaction log** → distribution |
| **Distribution Agent** | distribution → subscriber |
| **Merge Agent** | resolves conflicts (merge only) |

**Check the Log Reader Agent first** — it is the only agent that reads the
transaction log, and if it stops nothing flows at all.

The chain is:
```
Publisher log → Log Reader → distribution DB → Distribution Agent → Subscriber
```
**Find which link in that chain stopped.**
</details>

### Q20. Transactional or merge? A branch office edits records offline and
later reconnects. **Which, and what is the hard part?**

<details><summary>Answer</summary>

**Merge replication** — it is the only type where changes flow both ways and
every node keeps its own copy.

The hard part is **conflicts**. Two users edited the same row while offline.
The Merge Agent must pick a winner, and that resolution is a genuine design
problem: you have to decide whether "last write wins" is acceptable, or whether
you need to keep both and reconcile.

For comparison: transactional replication has subscribers that are **read only**,
which is the single fact distinguishing it.
</details>

---

## 🏁 Final self-check

Can you answer these without looking?

1. The four system databases, and which one is a template?
2. Six questions you can answer about any SQL Server instance?
3. The seven data-type categories — and why `FLOAT` is wrong for money?
4. Three rules of `IDENTITY`?
5. Why does `WHERE col = NULL` return nothing?
6. Temporary table vs table variable — which survives a rollback?
7. What is a junction table, and what relationship does it resolve?
8. `GRANT`, `REVOKE`, `DENY` — which one always wins?
9. Lock modes — which two wait against each other, and why does that cause deadlocks?
10. `PAGEIOLATCH` — what does it mean, and what is the *actual* fix?
11. Copy-on-write — what does it mean and when does a snapshot grow?
12. Which replication agent reads the transaction log?

---

**Back to:** [README](../README.md) · [Manual 1](01_manual_1_installation.md) ·
[Manual 2](02_manual_2_tables.md) · [Manual 3](03_manual_3_snapshots_replication.md) ·
[Manual 4](04_manual_4_monitoring.md)
