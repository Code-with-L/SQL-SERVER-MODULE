-- ============================================================================
-- Script: 03_identity_and_keys.sql
-- Manual : Part 2 - IDENTITY, Primary Key, Unique
-- Topic  : how SQL Server guarantees uniqueness
-- ============================================================================
--
-- THE PROBLEM IDENTITY SOLVES
--   Two people share a name. Names change. People leave.
--   A PRIMARY KEY must always identify exactly one row, forever.
--   So a key must be a value SQL Server controls and never reuses.
--
-- THE SOLUTION
--   IDENTITY(seed, increment)  - SQL Server generates the number.
--     IDENTITY(1,1)   -> 1, 2, 3, 4, ...
--     IDENTITY(1,10)  -> 1, 11, 21, 31, ...
--     IDENTITY(100,1) -> 100, 101, 102, ...
--
-- THE THREE RULES
--   1. You cannot supply a value for an IDENTITY column. Ever.
--   2. Numbers are never reused, even after a delete.
--   3. IDENTITY is not a guarantee of contiguity. Rollbacks leave gaps.
-- ============================================================================

USE StudentRecordsDB;
GO

CREATE TABLE dbo.IdentityDemo
(
    DemoID     int IDENTITY(1,1) PRIMARY KEY,
    Label      varchar(50) NOT NULL
);
GO

-- Insert WITHOUT touching DemoID - SQL Server fills it in.
INSERT INTO dbo.IdentityDemo (Label) VALUES ('first');
INSERT INTO dbo.IdentityDemo (Label) VALUES ('second');
INSERT INTO dbo.IdentityDemo (Label) VALUES ('third');
GO

SELECT * FROM dbo.IdentityDemo ORDER BY DemoID;
GO

-- ---------------------------------------------------------------------------
-- WHY RULE 1 EXISTS
--   Two clients inserting at the same instant could both be told "the next
--   value is 4". IDENTITY is how SQL Server guarantees they cannot collide.
-- ---------------------------------------------------------------------------
-- Uncomment to see the error (Msg 544: cannot insert explicit value):
--   INSERT INTO dbo.IdentityDemo (DemoID, Label) VALUES (99, 'nope');

-- If you genuinely need to, you must switch identity off for the statement:
--   SET IDENTITY_INSERT dbo.IdentityDemo ON;
--   INSERT INTO dbo.IdentityDemo (DemoID, Label) VALUES (99, 'forced');
--   SET IDENTITY_INSERT dbo.IdentityDemo OFF;

-- ---------------------------------------------------------------------------
-- DELETING DOES NOT REUSE NUMBERS - rule 2.
-- ---------------------------------------------------------------------------
DELETE FROM dbo.IdentityDemo WHERE DemoID = 2;
GO

INSERT INTO dbo.IdentityDemo (Label) VALUES ('fourth');
GO

SELECT * FROM dbo.IdentityDemo ORDER BY DemoID;
GO
-- You now have IDs 1, 3, 4 - there is NO 2, and none will ever be issued.
-- This is deliberate. A deleted ID must stay deleted so that old invoices,
-- logs and reports referencing it are never silently repointed at a new row.
-- (The exception is TRUNCATE TABLE, which resets the counter - see below.)

-- ---------------------------------------------------------------------------
-- GAPS ARE ALSO CREATED BY ROLLBACKS - rule 3.
--   If an INSERT fails partway through a transaction, the number it burned is
--   not returned to the pool. So never assume MAX(id) + 1 == next id, and
--   never assume COUNT(*) == MAX(id). Always ask: SCOPE_IDENTITY().
-- ---------------------------------------------------------------------------
INSERT INTO dbo.IdentityDemo (Label)
VALUES ('this batch will fail');

SELECT CAST(SCOPE_IDENTITY() AS int) AS LastIdentityInThisScope;
GO
-- The INSERT above raised an error because Label is varchar(50) and this is
-- fine, but the point stands: SCOPE_IDENTITY() is how you learn which number
-- SQL Server just handed out, safely, without guessing.

-- ============================================================================
-- TRUNCATE vs DELETE - a difference worth knowing
--   DELETE FROM dbo.IdentityDemo;      -- rows removed, identity NOT reset
--   TRUNCATE TABLE dbo.IdentityDemo;   -- rows removed, identity RESET to seed
--
--   TRUNCATE is faster (no per-row logging) and resets IDENTITY, but it
--   CANNOT be used if the table is referenced by a FOREIGN KEY.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- PRIMARY KEY vs UNIQUE - related but different
--   PRIMARY KEY  - exactly one per table, NOT NULL, clustered by default
--   UNIQUE       - as many as you like, allows NULL, nonclustered by default
--
--   A PRIMARY KEY is automatically UNIQUE. A UNIQUE constraint is not
--   automatically a primary key.
-- ---------------------------------------------------------------------------

ALTER TABLE dbo.IdentityDemo
    ADD CONSTRAINT UQ_IdentityDemo_Label UNIQUE (Label);
GO

-- Now prove it. The second insert repeats the label 'first':
--   INSERT INTO dbo.IdentityDemo (Label) VALUES ('first');
-- -> Msg 2601: violation of UNIQUE KEY constraint 'UQ_IdentityDemo_Label'

-- ============================================================================
-- CLEANUP
-- ============================================================================
DROP TABLE dbo.IdentityDemo;
GO
