# 📘 Manual 1 — Installation & Configuration

> **Your notes:** *Understanding SQL Server Editions, default/named/multiple instances,
> service accounts, Windows/Mixed authentication, collation, installation decisions.*
>
> **Your server:** SQL Server 2025 Enterprise Developer, default instance `MSSQLSERVER`,
> Windows authentication, `SQL_Latin1_General_CP1_CI_AS`.

---

## Why this manual comes first in the course, but not in our build order

Installation is **conceptual**. You cannot install SQL Server in a class — you did
it once, on this machine. But almost every question in this manual is answerable
by *reading* SQL Server's own catalogue views, which is what
`03_instances_editions_auth.sql` does.

The manual is first because the concepts explain decisions you will meet for the
rest of the course. It is not first in our build order because a database with no
tables teaches nothing practical.

---

## The six questions, and how to answer each

| Question | Command | Your answer |
|---|---|---|
| **What edition?** | `SELECT SERVERPROPERTY('Edition')` | Enterprise Developer Edition |
| **Default or named instance?** | `SELECT SERVERPROPERTY('InstanceName')` | `MSSQLSERVER` → **default** |
| **How many instances?** | `Get-Service`, or Configuration Manager | 1 |
| **What service account?** | `sys.dm_server_services.start_name` | see script output |
| **Windows or Mixed auth?** | `SELECT SERVERPROPERTY('IsIntegratedSecurityOnly')` | `1` → **Windows only** |
| **What collation?** | `sys.databases.collation_name` | `SQL_Latin1_General_CP1_CI_AS` |

If you can answer those six for any server, you have Manual 1.

---

## Editions — what you get for the money

| Edition | Price | Key limits | Use it when |
|---|---|---|---|
| **Enterprise** | Per core | None | Everything: compression, TDE, partitioning |
| **Standard** | Per core | No compression/TDE | Ordinary OLTP |
| **Web** | Free | Small memory ceiling | Simple public sites |
| **Express** | Free | 1 socket, ~10 GB buffer | **Learning, small DBs** |
| **Developer** | Free | Enterprise features | **Development only — not production** |

> ⚠️ Developer Edition is free *and* full-featured, which is exactly why you must
> remember: **it is not licensed for production.** A company running Developer in
> production is violating the licence.

**You have Developer Edition** — so compression, `TDE`, partitioning and snapshot
all work for you. Convenient, and worth being honest about the restriction.

---

## Instances — the concept Part 1 spends most pages on

An **instance** is a completely separate SQL Server. Its own services, databases,
memory, configuration, port.

### Default instance
- Always named `MSSQLSERVER`
- Reached with **no name**: `localhost`
- Services are `MSSQLSERVER`, `SQLSERVERAGENT` — no suffix
- **Only one per computer**

### Named instance
- You choose the name at install
- Reached as `SERVER\NAME` — e.g. `localhost\SQLEXPRESS`
- Services become `MSSQL$NAME` (the `$` means "parameterised service")
- **Many allowed**

### How to tell which you have

Look at your SSMS title bar:
- `localhost (SQL Server 17.0...)` → **default instance**
- `localhost\SQLEXPRESS (SQL Server ...)` → **named instance**

### Why you'd run more than one
1. Test an upgrade without touching production
2. **Run SQL 2005 alongside SQL 2025** — exactly the situation your manuals describe
3. Isolate different customers' data
4. 32-bit alongside 64-bit

### Service accounts
The Windows identity the SQL Server service runs as. It needs rights to the data
folders and the Windows Event Log.

- ❌ Never `LocalSystem` in production — it has far too much privilege
- ✅ Preferred: virtual accounts (`NT SERVICE\MSSQLSERVER`) or a domain **gMSA**

---

## Authentication

| | Windows auth | SQL Server auth |
|---|---|---|
| Password stored by SQL Server? | **No** | Yes (hashed, in `master`) |
| Centralised / group-based? | Yes | No — one login per person |
| Lockout policy? | Inherited from Windows | Not by default |
| Works with non-Windows clients? | No | Yes |

**You are on Windows authentication.** That is why this entire project contains
**zero passwords** — not in `.sql` files, not in `.gitignore`, nowhere. There is
no SQL password to leak, because no SQL password exists.

### Check the login types
```sql
SELECT name, type_desc FROM sys.server_principals WHERE type IN ('S','U','G');
```
- `U` = Windows login ✅ (you)
- `S` = SQL Server login (means mixed mode is on)
- `G` = Windows group

---

## Collation — the one that surprises people

Collation decides **how text is sorted and compared**, and therefore whether two
strings are "equal".

### Reading yours: `SQL_Latin1_General_CP1_CI_AS`

| Part | Meaning |
|---|---|
| `SQL_Latin1_General` | Sort order / character set |
| `CP1` | Code page 1252 (Western European) |
| **`CI`** | **Case-Insensitive** — `WHERE name = 'kenya'` matches `'Kenya'` |
| **`AS`** | **Accent-Sensitive** — `'resume'` ≠ `'résumé'` |

### Why it matters more than it looks
1. It decides whether your `WHERE` clauses match anything
2. It decides index behaviour — a collation mismatch between joined columns
   **disables index seeks** and quietly produces a slow query
3. Every new database inherits it from the **`model`** database

### Where it comes from and where you can change it
- Inherited from `model` at creation time
- Per database: `ALTER DATABASE ... COLLATE ...`
- Per column: `ALTER TABLE ... ALTER COLUMN ... COLLATE ...`
- Per comparison only: `WHERE col COLLATE Latin1_General_100_CI_AI = 'kenya'`

⚠️ Changing a column's collation **rewrites its index**. Heavy on a big table.

---

## Files and filegroups

See `sql/01_databases/02_create_database_filegroups.sql` for the full annotated
version — this is the corrected rebuild of your original `SALES.sql`.

### The four file options

| Option | What it does | Trap |
|---|---|---|
| `NAME` | Logical alias for the file | Renaming does **not** move the file |
| `FILENAME` | Real path on disk | **Must exist** — this broke `SALES.sql` |
| `SIZE` | Initial size, allocated now | Not a cap |
| `MAXSIZE` | Hard ceiling | Too low = "database is full" outage |
| `FILEGROWTH` | Increment when full | Too big wastes space; too small fragments |

### File extensions — one rule
- **`.mdf`** — Master Data File. Exactly **one** per database.
- **`.ndf`** — secondary data file. Any number.
- **`.ldf`** — Log Data File. Exactly **one** per database.

### Filegroups — the reason to know this
1. **Performance** — hot tables on fast storage, cold tables on slow.
   They don't compete for I/O.
2. **Backup size** — back up one filegroup at a time; a static filegroup
   doesn't need backing up repeatedly.
3. **Growth** — a huge archive table with its own `MAXSIZE` can't starve the log.

**The cost:** a table spans *every* file in its filegroup. So a table in a
three-file group may touch all three to read one row. Filegroups spread I/O
across files; they do **not** parallelise a single table within one file.

### The log is special
The `.ldf` is **outside every filegroup** and exists for:
- **Recovery** — undo incomplete transactions
- **Durability** — write-ahead logging flushes the log to disk *before* the
  data page. That is why a committed transaction survives a power cut.

---

## Recovery models

| Model | Log behaviour | Point-in-time restore? |
|---|---|---|
| **FULL** (default) | Fully logged, grows until backup | ✅ Yes |
| **SIMPLE** | Only active transaction logged; auto-truncates | ❌ No — last full backup only |
| **BULK_LOGGED** | Minimal logging for bulk ops | Partially |

### When your log fills up
Do **not** add disk first. Find out *why* it cannot truncate:

```sql
SELECT name, recovery_model_desc, log_reuse_wait_desc
FROM sys.databases WHERE name = DB_NAME();
```

`log_reuse_wait_desc`:
- `NOTHING` — fine
- `LOG_BACKUP` — take a backup
- `ACTIVE_TRANSACTION` — **someone has a transaction open right now.** That is
  the usual cause. Find it with `DBCC OPENTRAN`, end it, and the log truncates
  on its own.
- `CHECKPOINT` — waiting for the next checkpoint

---

## ⚠️ The 2005 → 2025 gap

Your manuals describe **compatibility level 90**. This server is **level 170**.

| Level | Version |
|---|---|
| 90 | **SQL Server 2005 — your manuals** |
| 100 | SQL Server 2008 |
| 110 | SQL Server 2012 |
| 120 / 130 | 2014 / 2016 |
| 140 / 150 | 2017 / 2019 |
| 160 / **170** | 2022 / **2025 — your server** |

**Concrete consequence you have already hit:** `DATE`, `TIME` and `DATETIME2`
did not exist in 2005. Your old `SQLQuery2.sql` used `DATE` — it could never
have run on the version your manual teaches. It works here because you're on 2025.

> **Rule of thumb:** the manual's *concepts* are current. Its *exact syntax* may
> be version-dependent. When something errors, first ask "is this feature newer
> than 2005?"

---

## Self-check

Without opening the GUI, answer for **this** server:
1. Edition?
2. Default or named instance?
3. Windows or Mixed authentication?
4. Collation, and is it case-sensitive?
5. How many data files, and what extension is each?
6. Which recovery model, and is `log_reuse_wait_desc` currently `NOTHING`?

Scripts that answer all six: `02_create_database_filegroups.sql`,
`03_instances_editions_auth.sql`.

---

**Next:** [Manual 2 — Tables & Database Objects](02_manual_2_tables.md)
