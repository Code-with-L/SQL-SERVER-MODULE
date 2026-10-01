-- ============================================================================
-- Script: 07_joins_and_relationships.sql
-- Manual : Part 2 - Foreign keys, referential integrity
-- Topic  : JOIN types, and the junction table in action
-- ============================================================================
--
-- FIRST, SEED THE SCHEMA
--   07_constraints_and_indexes.sql and everything downstream needs data, and
--   so do the JOIN examples. Run this block once, in this order.
--   CREATE TABLE is idempotent-unsafe: if the tables already exist, wrap each
--   CREATE in IF OBJECT_ID(...) IS NULL, or drop the database and rebuild.
-- ============================================================================

USE StudentRecordsDB;
GO

-- ---------------------------------------------------------------------------
-- Minimal seed data so JOINs have something to chew on
-- ---------------------------------------------------------------------------
INSERT INTO dbo.Country (Country) VALUES ('Kenya'), ('South Africa'), ('Uganda');
INSERT INTO dbo.StateProvince (StateProvince) VALUES ('Nairobi'), ('Mombasa'), ('Cape Town'), ('Kampala');
INSERT INTO dbo.AddressType (AddressType) VALUES ('Home'), ('Work'), ('Billing');
GO

-- WATCH FOR THIS CLASS OF MISTAKE
--   A stray semicolon inside a multi-row VALUES list:
--         VALUES ('Carol Wanjala', 80000.00, 0.00;   <-- semicolon here
--                ('David Kimani', 15000.00, 9000.00);
--   The semicolon ENDS the statement there, so the following comma is a
--   syntax error: Msg 102, "Incorrect syntax near ','".
--   Semicolons belong at the END of a statement, never inside one.

INSERT INTO dbo.Customer (CustomerName, CreditLine, OutstandingBalance)
VALUES ('Alice Mwangi',  50000.00,  12000.00),
       ('Brian Otieno',  20000.00,  19500.00),
       ('Carol Wanjala', 80000.00,      0.00),
       ('David Kimani',  15000.00,   9000.00);
GO

INSERT INTO dbo.CustomerAddress (AddressLine1, AddressLine2, City, PostalCode,
                                 StateProvinceID, CountryID, AddressTypeID)
VALUES ('12 Kenyatta Ave', NULL,       'Nairobi',   '00100', 1, 1, 1),
       ('45 Moi Avenue',   'Flat 3B',  'Nairobi',   '00200', 1, 1, 2),
       ('7 Dock Road',     NULL,       'Cape Town', '8001',  3, 2, 1),
       ('9 Kampala Rd',    'PO Box 44','Kampala',   NULL,    4, 3, 3);
GO

-- The junction table: who has which address
INSERT INTO dbo.CustomerToCustomerAddress (CustomerID, CustomerAddressID)
VALUES (1, 1),   -- Alice  -> 12 Kenyatta Ave (Home)
       (1, 2),   -- Alice  -> 45 Moi Avenue  (Work)   <- many-to-many in action
       (2, 1),   -- Brian  -> 12 Kenyatta Ave (shared company address)
       (3, 3),   -- Carol  -> 7 Dock Road
       (4, 4);   -- David  -> 9 Kampala Rd
GO

-- ============================================================================
-- THE FIVE JOIN TYPES
-- ============================================================================

-- 1. INNER JOIN - only rows that match on BOTH sides.
--    "Which customers have an address in Nairobi?"
SELECT
    c.CustomerName,
    a.AddressLine1,
    a.City
FROM dbo.Customer c
INNER JOIN dbo.CustomerToCustomerAddress x ON x.CustomerID     = c.CustomerID
INNER JOIN dbo.CustomerAddress           a ON a.CustomerAddressID = x.CustomerAddressID
WHERE a.City = 'Nairobi'
ORDER BY c.CustomerName;
GO

-- 2. LEFT JOIN - every row from the left, plus matches from the right.
--    "List every customer, even ones with no address."
SELECT
    c.CustomerID,
    c.CustomerName,
    a.AddressLine1
FROM dbo.Customer c
LEFT JOIN dbo.CustomerToCustomerAddress x ON x.CustomerID     = c.CustomerID
LEFT JOIN dbo.CustomerAddress           a ON a.CustomerAddressID = x.CustomerAddressID
ORDER BY c.CustomerID;
GO

-- 3. RIGHT JOIN - mirror image. Rarely used; prefer LEFT JOIN by reordering,
--    because most readers find left-to-right easier to follow.
SELECT
    c.CustomerName,
    a.AddressLine1
FROM dbo.Customer c
RIGHT JOIN dbo.CustomerToCustomerAddress x ON x.CustomerID = c.CustomerID
RIGHT JOIN dbo.CustomerAddress a ON a.CustomerAddressID = x.CustomerAddressID
ORDER BY c.CustomerName;
GO

-- 4. FULL JOIN - both sides preserved, unmatched rows show NULL.
SELECT
    c.CustomerName,
    a.City
FROM dbo.Customer c
FULL JOIN dbo.CustomerToCustomerAddress x ON x.CustomerID     = c.CustomerID
FULL JOIN dbo.CustomerAddress           a ON a.CustomerAddressID = x.CustomerAddressID
ORDER BY c.CustomerName;
GO

-- 5. CROSS JOIN - every row paired with every row. Produces
--    4 customers x 4 addresses = 16 combinations. Almost always a mistake,
--    occasionally exactly what you want (calendar x rates, product x region).
SELECT
    c.CustomerName,
    t.AddressType
FROM dbo.Customer c
CROSS JOIN dbo.AddressType t
ORDER BY c.CustomerName, t.AddressType;
GO

-- ============================================================================
-- FINDING ORPHANS - the practical reason LEFT JOIN matters
--   Rows on the right that nothing on the left points at. These are exactly
--   the rows a foreign key prevents, but legacy data can still contain them.
-- ============================================================================
SELECT
    'Customer with no address' AS OrphanType,
    CAST(c.CustomerID AS varchar(20)) AS OrphanID
FROM dbo.Customer c
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.CustomerToCustomerAddress x WHERE x.CustomerID = c.CustomerID
)
UNION ALL
SELECT
    'Address not linked to any customer',
    CAST(a.CustomerAddressID AS varchar(20))
FROM dbo.CustomerAddress a
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.CustomerToCustomerAddress x WHERE x.CustomerAddressID = a.CustomerAddressID
);
GO

-- ============================================================================
-- REFERENTIAL INTEGRITY IN PRACTICE
--   The foreign key stops this insert, because StateProvinceID 99 does not
--   exist in dbo.StateProvince.
-- ============================================================================
--   INSERT INTO dbo.CustomerAddress
--       (AddressLine1, City, StateProvinceID, CountryID, AddressTypeID)
--   VALUES ('Nowhere', 'Nowhere', 99, 1, 1);
--   -> Msg 547: The INSERT statement conflicted with the FOREIGN KEY
--      constraint "FK_CustomerAddress_StateProvince".

-- And ON DELETE behaviour, which prevents the mirror-image problem
-- (an address row deleted while a customer still points at it).

SELECT
    fk.name                                AS ForeignKey,
    OBJECT_NAME(fk.parent_object_id)       AS OnTable,
    fk.delete_referential_action_desc      AS OnDeleteBehaviour,
    fk.update_referential_action_desc      AS OnUpdateBehaviour
FROM sys.foreign_keys fk
ORDER BY OnTable;
GO
-- NO ACTION    = refuse the delete if children exist (the safe default)
-- CASCADE       = delete the children too (dangerous with two-level chains)
-- SET NULL      = orphan the children by setting the FK column to NULL
-- SET DEFAULT   = set the FK column back to its DEFAULT
--
-- These are declared as ON DELETE / ON UPDATE clauses at CREATE TABLE time
-- or via ALTER TABLE ... ON DELETE CASCADE.
