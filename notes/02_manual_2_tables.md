# 📗 Manual 2 — Tables & Database Objects

> **Your notes:** *Data types, CREATE TABLE, permanent and temporary tables, table
> variables, IDENTITY, NULL/NOT NULL, permissions, GRANT, database objects, security.*
>
> **This is the foundation manual.** Everything in Manuals 3 and 4 needs tables
> to act on.

---

## Build order

Permanent → temporary → table variables → constraints → joins → permissions

The order is not arbitrary:
- You need a real table before a temporary one is meaningful
- You need tables before permissions on tables mean anything
- Manuals 3 and 4 need populated tables

---

## 1. Data types — the most important decision in a database

> *"The data type that you choose for a column is the most critical decision
> that you make within your database."* — your manual

**Too restrictive** → your application cannot store data it must store.
**Too broad** → wasted space on disk and in memory → slower queries, bigger backups.

**The rule:** choose the type that allows every value you expect, in the least
space possible.

### The seven categories (Table 3-1 of your manual)

| # | Category | Stores | Types |
|---|---|---|---|
| 1 | General Purpose | anything, any length | `VARCHAR`, `NVARCHAR`, `INT` |
| 2 | **Exact** Numeric | precise | `INT`, `BIGINT`, `DECIMAL(p,s)` |
| 3 | **Approximate** Numeric | **imprecise** | `FLOAT`, `REAL` |
| 4 | Monetary | currency, ≤4 decimals | `MONEY`, `SMALLMONEY` |
| 5 | Date & Time | rejects February 30 | `DATE`, `DATETIME2`, `TIME` |
| 6 | Binary | strict 0/1 | `BIT`, `BINARY`, `VARBINARY` |
| 7 | Special Purpose | complex | `XML`, `UNIQUEIDENTIFIER` |

### Exact vs approximate — the distinction everyone misses

```sql
SELECT CAST(0.1 AS decimal(10,2)) + CAST(0.2 AS decimal(10,2));  -- 0.30 exactly
SELECT CAST(0.1 AS float)          + CAST(0.2 AS float);         -- looks like 0.3
-- but it is NOT bit-for-bit 0.3
```

`DECIMAL` is exact. `FLOAT` is binary floating point and **cannot represent 0.1
exactly**. **Never use `FLOAT` for money.** Use `DECIMAL(19,4)`.

### `DECIMAL(p,s)` — the argument order trap

`DECIMAL(10,2)` means **10 digits total, 2 after the decimal point**.
Maximum value: `99999999.99`.

The first number is the **total**, not the whole part. So `DECIMAL(5,2)` holds
only `999.99`, not `99999.99`.

### Integer sizes

| Type | Range | Bytes |
|---|---|---|
| `TINYINT` | 0 – 255 | 1 |
| `SMALLINT` | 0 – 32,767 | 2 |
| `INT` | ±2.1 billion | 4 |
| `BIGINT` | ±9.2 quintillion | 8 |

`dbo.AddressType` uses `tinyint` deliberately — there are only ever a handful of
address types, so 1 byte instead of 4 saves a byte per row, forever.

### `VARCHAR` vs `NVARCHAR`

`VARCHAR` = 1 byte per character (ASCII). `NVARCHAR` = 2 bytes (UTF-16), stores
every language. Only pay for `NVARCHAR` when you genuinely need it.

### `BIT` is not TRUE/FALSE

`BIT` stores **0, 1, or NULL**. Modern SQL Server lets you *write* `TRUE`/`FALSE`
and converts them, but what lands in the file is `0`/`1`.

---

## 2. `CREATE TABLE`

```sql
CREATE TABLE [ schema . ] table_name
(
    column_definition | table_constraint  [ , ...n ]
)
[ ON { filegroup | "default" } ]
;
```

### Anatomy of a column definition
```
ColumnName   DATATYPE   constraints...
   │            │            │
FirstName   VARCHAR(40)   NOT NULL
```
Read as a sentence: *"A column called FirstName, up to 40 characters, cannot be empty."*

### The three kinds of table

| Prefix | Kind | Lives in | Dies when |
|---|---|---|---|
| `dbo.` or none | **Permanent** | your database file | you `DROP` it |
| `#` | **Temporary** | `tempdb` | you disconnect |
| `@` | **Table variable** | memory | the batch ends |

No prefix means permanent. That's the default.

---

## 3. `IDENTITY`

`IDENTITY(seed, increment)` — SQL Server generates the number.

- `IDENTITY(1,1)` → 1, 2, 3, 4
- `IDENTITY(1,10)` → 1, 11, 21, 31
- `IDENTITY(100,1)` → 100, 101, 102

### Three rules

1. **You cannot supply the value.** Ever. (Unless `SET IDENTITY_INSERT ... ON`.)
2. **Numbers are never reused**, even after a `DELETE`.
3. **Not contiguous.** A rollback burns a number permanently.

### Why never reuse

If student 2 leaves and ID 2 is reused, every old invoice, log entry and report
referencing student 2 now silently points at a *different person*. IDs must be
permanent labels, not counters.

### Get the number you were given
```sql
SELECT CAST(SCOPE_IDENTITY() AS int);
```
Never guess with `MAX(id) + 1` — that is wrong under concurrency.

### `DELETE` vs `TRUNCATE`

| | `DELETE FROM t` | `TRUNCATE TABLE t` |
|---|---|---|
| Rows removed | yes | yes |
| Resets `IDENTITY` | **no** | **yes** |
| Works with a FK referencing it | yes | **no** |
| Logged | every row | minimal |

---

## 4. `NULL` vs `NOT NULL`

### What `NULL` actually means
**Unknown**, not supplied, or not applicable.

`NULL` is **NOT**:
- `0` — zero is a *known* quantity
- `''` — an empty string is a *known, very short* string
- `'N/A'` — that is text someone typed
- `False` — we don't know; we didn't record it

> **The test:** *"How tall is the customer?"* → `1.80` is known. `0` means they
> are a dwarf (a real answer). `NULL` means we genuinely don't know.

### Three-valued logic — why `NULL` breaks comparisons

```sql
SELECT * FROM t WHERE col = NULL;    -- returns NOTHING. No error, no rows.
```

Every comparison against `NULL` evaluates to **UNKNOWN**, not TRUE.
`WHERE` only returns rows that are **TRUE**.

- `NULL = NULL` → UNKNOWN (not TRUE!)
- `NULL <> NULL` → UNKNOWN (also not TRUE!)
- `NULL > 5` → UNKNOWN

### The only correct way
```sql
WHERE col IS NULL
WHERE col IS NOT NULL
```
Never `= NULL`. It fails silently — the worst kind of bug.

### The aggregate trap
`COUNT(column)` counts **non-NULL only**. `COUNT(*)` counts rows.
`AVG` and `SUM` ignore NULLs, and `AVG` divides by the non-NULL count.

### Use `DEFAULT` instead of `NULL` where possible
If a column should never be null because it has an obvious value, give it a
`DEFAULT`. A default supplies a **real value**; `NULL` means unknown.

---

## 5. The five constraints

| Constraint | Enforces |
|---|---|
| `DEFAULT` | supplies a value when the column is omitted |
| `CHECK` | a rule about the values in a column |
| `UNIQUE` | no two rows may share this value |
| `PRIMARY KEY` | exactly one row per record; never NULL; not repeated |
| `FOREIGN KEY` | the value must exist in another table |

### `PRIMARY KEY` vs `UNIQUE`

| | `PRIMARY KEY` | `UNIQUE` |
|---|---|---|
| Per table | exactly **one** | many |
| `NULL` allowed | **no** | yes |
| Default index | **clustered** | nonclustered |
| Creates an index | yes | yes |

A `PRIMARY KEY` is automatically `UNIQUE`. A `UNIQUE` constraint is not
automatically a primary key.

### Constraints beat application validation

An application can be bypassed — by SSMS, by a script, by another tool, by a
bug. A constraint lives in the database and is enforced **no matter who writes**.
The database is the last line of defence and the only one that cannot be forgotten.

---

## 6. Computed columns

```sql
AvailableCredit AS (CreditLine - OutstandingBalance)
```

- **Not stored.** Recalculated on every read.
- Change `CreditLine` and it is instantly correct — nothing to keep in sync.
- **Cannot be inserted into.**
- Cannot use non-deterministic functions (`GETDATE()`) unless declared
  `PERSISTED` — which stores the value rather than recalculating.

---

## 7. Temporary tables (`#`)

- Stored in **`tempdb`**, not your database
- Local `#Temp` — only **your** session sees it
- Global `##Temp` — **every** session sees it, and can drop it
- Dies when you disconnect
- Local temp object IDs are **negative**

```sql
CREATE TABLE #RecentOrders (OrderID int PRIMARY KEY, ...);
INSERT INTO #RecentOrders VALUES (...);
SELECT * FROM #RecentOrders;
DROP TABLE #RecentOrders;
```

**Re-creating the same name in a later batch** → `Msg 2714`, "already an object
named". Name temp tables uniquely (`#RecentOrders_20260930`) to avoid it.

`##Temp` is a genuine footgun. Prefer `#temp`, or a table variable.

---

## 8. Table variables (`@`)

```sql
DECLARE @Regions TABLE (RegionID tinyint PRIMARY KEY, RegionName varchar(30));
```

`DECLARE` **must be the first statement in a batch** — otherwise a syntax error.

### The comparison that matters

| | Permanent | `#temp` | `@variable` |
|---|---|---|---|
| Lives in | your DB | tempdb | memory |
| Survives commit | yes | yes | **no** |
| Survives disconnect | yes | **no** | **no** |
| Survives rollback | yes | yes | **NO** |
| Has statistics | yes | no | no |
| Indexes | yes | yes | PK/UNIQUE only |
| Triggers see it | yes | yes | **no** |
| Good for | thousands+ rows | hundreds+ rows | **< 100 rows** |

### 🔥 The gotcha
A table variable's contents are **not restored by `ROLLBACK`**. Delete a row,
roll back, and the row stays deleted. Everyone discovers this once.

### Rule of thumb
- **Permanent** — the data is real and must survive
- **`#temp`** — many rows, need indexes, or it must be committed
- **`@var`** — a handful of rows, all-or-nothing, nobody outside this statement
  needs to know

---

## 9. The five joins

| Join | Keeps |
|---|---|
| `INNER JOIN` | rows matching on **both** sides |
| `LEFT JOIN` | **all** left rows + matching right |
| `RIGHT JOIN` | all right rows + matching left |
| `FULL JOIN` | everything from both |
| `CROSS JOIN` | every left × every right (rarely intended) |

Prefer `LEFT JOIN` by reordering rather than `RIGHT JOIN` — readers find
left-to-right easier to follow.

### Finding orphans
```sql
SELECT c.CustomerID
FROM dbo.Customer c
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.CustomerToCustomerAddress x WHERE x.CustomerID = c.CustomerID
);
```
This is the practical reason `LEFT JOIN` / `NOT EXISTS` matters: it finds rows
that a foreign key would have prevented, but that legacy data still contains.

---

## 10. The junction table — many-to-many

**The problem:** one customer → many addresses. One address → many customers.
That is **many-to-many**, and T-SQL cannot express it with a single FK.

**The solution:** a third table whose rows *are* the links.

```
Customer ──┬── CustomerToCustomerAddress ──┬── CustomerAddress
           │   (CustomerID, CustomerAddressID) │
           └────────────────────────────────┘
```

Each row says *"this customer has this address"*. Add rows to add links.

```sql
CONSTRAINT PK_CustomerToCustomerAddress
    PRIMARY KEY (CustomerID, CustomerAddressID)   -- composite
```

The composite PK means: the same address cannot be linked to the same customer
twice. **This pattern is behind every many-to-many relationship you will ever
meet.**

---

## 11. Indexes — and their cost

An index lets SQL Server jump straight to the rows it needs instead of scanning
every row in storage order.

**The cost:** every index must be updated on every `INSERT`, `UPDATE` and
`DELETE`. So **reads get faster, writes get slower.** That trade-off is the whole
discipline.

### Clustered vs nonclustered
- **Clustered** — the physical order of rows. **One per table**, because rows
  can only be stored in one order. This is why `PRIMARY KEY` is clustered by
  default.
- **Nonclustered** — a separate sorted structure with pointers back to rows.
  Many per table.
- **Key lookup** — when a nonclustered index is used and SQL Server still needs
  other columns, it goes back to the clustered index. That extra trip is a
  "lookup".

### Composite index — leftmost prefix rule
`IX (City, StateProvinceID)` serves `WHERE City = ?` **and**
`WHERE City = ? AND StateProvinceID = ?`.

It does **NOT** serve `WHERE StateProvinceID = ?`.

Put your most-filtered column **first**.

### Index a column when ALL of these are true
- [ ] It appears in `WHERE`, `JOIN` or `ORDER BY`
- [ ] It is reasonably selective (not 90% of rows)
- [ ] The table is big enough that a scan hurts
- [ ] It is read far more often than written

**Do not** index: low-selectivity flags, columns only in `SELECT` lists, or
anything already covered by a clustered key prefix.

### Check whether an index is actually used
```sql
SELECT s.name, us.user_seeks, us.user_scans, us.last_user_seek
FROM sys.indexes s
LEFT JOIN sys.dm_db_index_usage_stats us
       ON us.object_id = s.object_id AND us.index_id = s.index_id
      AND us.database_id = DB_ID()
WHERE s.object_id = OBJECT_ID('dbo.YourTable');
```
`user_seeks` = the optimiser chose a seek. `user_scans` = a scan anyway.
These reset on restart — compare `last_user_seek` against when SQL Server started.

---

## 12. Security — the model in one picture

```
SERVER    → LOGIN     → (maps to)
DATABASE  → USER      → member of
DATABASE  → ROLE      → granted
TABLE     → PERMISSION → on
```

- **LOGIN** — needed to connect at all
- **USER** — what you are *inside* a database
- **ROLE** — users get rights by joining roles
- **dbo** — owns everything in the database

### Fixed database roles (exist in every database)

| Role | Can do |
|---|---|
| `db_owner` | everything (you have this) |
| `db_datareader` | `SELECT` everywhere |
| `db_datawriter` | `INSERT`/`UPDATE`/`DELETE` everywhere |
| `db_ddladmin` | create/alter/drop objects, no data access |
| `db_accessadmin` | manage users and roles only |
| `db_securityadmin` | manage permissions only |

### `GRANT` vs `REVOKE` vs `DENY`

| Command | Effect |
|---|---|
| `GRANT` | **adds** a permission. Never overwrites — if you had `SELECT` and grant `UPDATE`, you now have **both**. |
| `REVOKE` | removes a permission you granted |
| `DENY` | adds a **block** that beats any `GRANT`, even from `db_owner` |

**The rule: `DENY` always wins.**

**Hierarchy:** a `DENY` at a high level (database/server) beats a `GRANT` at a
low level (table). Permissions resolve most-specific-first; the first explicit
decision found at a level wins.

```sql
GRANT SELECT ON dbo.Customer TO [SomeUser];
DENY  SELECT ON dbo.CustomerAddress TO [SomeUser];   -- addresses are private
```

### Least privilege
❌ `GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO [app]`
✅ `db_datareader` + explicit per-table grants + `DENY` on sensitive tables

Grant the minimum, name tables explicitly, deny what must not be read.

### Ownership chains — why views are a security tool
If you have permission on a **view**, and the view's **owner** also has
permission on the underlying table, querying the view does **not** require you
to have table permission.

**This is why views are a security control.** Grant `SELECT` on the view, not the
base table, and the table becomes unreachable.

### Auditing
```sql
SELECT r.name AS Principal, dp.permission_name, dp.state_desc
FROM sys.database_permissions dp
JOIN sys.database_principals r ON r.principal_id = dp.grantee_principal_id
WHERE dp.major_id = OBJECT_ID('dbo.Customer');
```

---

## Self-check

1. What does `DECIMAL(10,2)` actually allow as a maximum?
2. Why must you use `IS NULL` rather than `= NULL`?
3. What are the three rules of `IDENTITY`?
4. Temporary or table variable — which one survives a rollback?
5. What breaks if you join two columns with different collations?
6. When is `DENY` more appropriate than simply not granting?
7. Why is a table variable's contents not restored by a rollback?

---

**Next:** [Manual 3 — Snapshots & Replication](03_manual_3_snapshots_replication.md)
