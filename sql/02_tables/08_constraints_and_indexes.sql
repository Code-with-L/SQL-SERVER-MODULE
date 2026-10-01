-- ============================================================================
-- Script: 08_constraints_and_indexes.sql
-- Manual : Part 2 - Constraints, database objects
-- Topic  : the full set of constraints, and what indexes really are
-- ============================================================================

USE StudentRecordsDB;
GO

-- ============================================================================
-- THE FIVE CONSTRAINT TYPES
--   DEFAULT       supplies a value when a column is omitted
--   CHECK         a rule about the VALUES in a column
--   UNIQUE        no two rows may share this value
--   PRIMARY KEY   one row per record, never NULL, not repeated
--   FOREIGN KEY   the value must exist in another table
--
-- WHY CONSTRAINTS BEAT VALIDATION IN APPLICATION CODE
--   An application can be bypassed - SSMS, a script, another tool, a bug.
--   A constraint lives in the database and is enforced no matter who writes.
--   The database is the last line of defence, and it is the only one that
--   cannot be forgotten.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- CHECK constraints - value-level rules
-- ---------------------------------------------------------------------------
ALTER TABLE dbo.Customer
    ADD CONSTRAINT CK_Customer_OutstandingBalance
        CHECK (OutstandingBalance >= 0);
GO
-- Now try: INSERT ... OutstandingBalance = -500
--   -> Msg 547: The INSERT statement conflicted with the CHECK constraint

-- A CHECK can reference several columns, and can look at other tables:
ALTER TABLE dbo.CustomerAddress
    ADD CONSTRAINT CK_CustomerAddress_Line2NeedsLine1
        CHECK (AddressLine1 IS NOT NULL);
GO

-- ---------------------------------------------------------------------------
-- Reading the constraints you already have
-- ---------------------------------------------------------------------------
SELECT
    OBJECT_NAME(cc.parent_object_id) AS TableName,
    cc.name                          AS ConstraintName,
    cc.definition                    AS Definition
FROM sys.check_constraints cc
ORDER BY TableName;
GO

-- ============================================================================
-- INDEXES - what they actually do
--
--   Without an index, SQL Server does a TABLE SCAN: reads every row, in
--   storage order, to find what you asked for. On 1,000 rows that is fine.
--   On 10 million, it is a bottleneck.
--
--   With an index, SQL Server can jump straight to the relevant rows.
--
--   THE COST: every index must be updated on every INSERT, UPDATE and DELETE.
--   So an index makes reads faster and writes slower. That trade-off is the
--   whole discipline.
--
--   CLUSTERED vs NONCLUSTERED
--     Clustered     - the physical order of the rows. ONE per table, because
--                     rows can only be stored in one order. This is why a
--                     PRIMARY KEY is clustered by default.
--     Nonclustered  - a separate structure holding sorted keys plus pointers
--                     back to the rows. Many per table.
--     Lookup        - when a nonclustered index is used, SQL Server may still
--                     have to go to the clustered index to get the other
--                     columns. That extra trip is a "lookup" or "key lookup".
-- ============================================================================

-- Which indexes exist on Customer?
SELECT
    i.name                                                  AS IndexName,
    i.type_desc                                             AS Type,
    i.is_unique                                              AS IsUnique,
    i.is_primary_key                                         AS IsPrimaryKey,
    c.name                                                  AS ColumnName,
    ic.key_ordinal                                           AS OrdinalInIndex
FROM sys.indexes i
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns     c  ON c.object_id  = ic.object_id AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID('dbo.Customer')
ORDER BY i.name, ic.key_ordinal;
GO

-- ---------------------------------------------------------------------------
-- Create the indexes the lecturer's schema implies.
--
--   dbo.Customer: PRIMARY KEY is clustered on CustomerID (automatic).
--                 UQ_Customer_CustomerName is already a nonclustered unique
--                 index. So Customer is already well covered - no extra work.
--
--   dbo.CustomerAddress: only the clustered PK exists. The common query is
--                         "addresses in city X", so index City.
-- ---------------------------------------------------------------------------
CREATE NONCLUSTERED INDEX IX_CustomerAddress_City
    ON dbo.CustomerAddress (City);
GO

CREATE NONCLUSTERED INDEX IX_CustomerAddress_StateProvinceID
    ON dbo.CustomerAddress (StateProvinceID);
GO
-- Why the second one: the FOREIGN KEY column needs an index on the CHILD
-- table or every delete/update on the parent has to scan the child.

-- ---------------------------------------------------------------------------
-- COMPOSITE index - column ORDER matters enormously.
--   IX (City, StateProvinceID) serves  : WHERE City = ?  AND StateProvinceID = ?
--                                        WHERE City = ?
--   It does NOT serve               : WHERE StateProvinceID = ?
--   Leftmost-prefix rule: you can only use the columns from the left onward.
--   Put the column you filter on most in the first position.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- What the optimiser is actually doing
--   Two identical queries, forced down different plans.
-- ---------------------------------------------------------------------------
SET STATISTICS IO ON;
GO

SELECT CustomerID, CustomerName FROM dbo.Customer WHERE CustomerName = 'Alice Mwangi';
GO
-- Logical reads will be small: it used the unique index on CustomerName.

SELECT CustomerID, CustomerName FROM dbo.Customer WHERE CreditLine > 100;
GO
-- Logical reads will be larger: no index on CreditLine, so a table scan.
-- That is what a missing index costs you.

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- DECISION CHECKLIST - should this column be indexed?
--   Index a column when ALL of these are true:
--     [ ] it appears in WHERE, JOIN, or ORDER BY
--     [ ] it is reasonably selective (not 90% of rows)
--     [ ] the table is large enough for a scan to hurt
--     [ ] it is read far more often than it is written
--   Do NOT index: low-selectivity flags, columns only used in SELECT lists,
--   or anything already covered by a clustered key prefix.
-- ============================================================================

-- ============================================================================
-- CHECK CONSTRAINTS vs TRIGGERS - both enforce rules, differently
--   CHECK     - declarative, simple, evaluated per row, cannot touch other
--               tables, cannot be bypassed
--   TRIGGER   - procedural, runs T-SQL, CAN touch other tables, CAN roll back
--               the whole statement, but can also be bypassed by
--               BULK INSERT / bcp and fires once per statement not per row
--   Prefer CHECK when it expresses the rule. Reach for a trigger only when the
--   rule genuinely spans rows or tables.
-- ============================================================================
