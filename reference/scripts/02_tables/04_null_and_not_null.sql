-- ============================================================================
-- Script: 04_null_and_not_null.sql
-- Manual : Part 2 - NULL / NOT NULL
-- Topic  : the single most misunderstood concept in all of SQL
-- ============================================================================
--
-- WHAT NULL ACTUALLY MEANS
--   NULL = "unknown", "not supplied", or "not applicable".
--
--   NULL IS NOT:
--     0            (zero is a known quantity)
--     ''           (empty string is a known, very short string)
--     'N/A'        (that is text someone typed)
--     False        (we do not know; we did not record it)
--
--   The mental model: if someone asks "how tall is the customer?"
--     answer 1.80  -> known
--     answer 0     -> they are a dwarf (a real, known answer)
--     answer ''    -> nonsense
--     answer NULL  -> we genuinely do not know, or it does not apply
--
-- WHY IT IS STRANGE
--   NULL is not a value, so ordinary comparison logic does not work.
--   Every comparison against NULL returns UNKNOWN, not TRUE or FALSE.
-- ============================================================================

USE StudentRecordsDB;
GO

CREATE TABLE dbo.NullDemo
(
    RequiredID   int IDENTITY(1,1) PRIMARY KEY,
    RequiredText varchar(30) NOT NULL,     -- a value MUST be supplied
    OptionalText varchar(30) NULL          -- omitting it stores NULL
);
GO

-- ---------------------------------------------------------------------------
-- TEST 1: NULL beats NOT NULL - both succeed
-- ---------------------------------------------------------------------------
INSERT INTO dbo.NullDemo (RequiredText)            VALUES ('second column omitted');
INSERT INTO dbo.NullDemo (RequiredText, OptionalText) VALUES ('second column given', 'hello');
GO

SELECT * FROM dbo.NullDemo;
GO

-- ---------------------------------------------------------------------------
-- TEST 2: omitting a NOT NULL column fails
-- ---------------------------------------------------------------------------
-- Uncomment: Msg 515, "Cannot insert the value NULL into column
--             'RequiredText', table 'dbo.NullDemo'; column does not allow
--             nulls. INSERT fails."
--   INSERT INTO dbo.NullDemo (OptionalText) VALUES ('oops');

-- ---------------------------------------------------------------------------
-- TEST 3: three-valued logic - THE part everyone gets wrong
--
--   Run these one at a time. Every single one returns no rows:
-- ---------------------------------------------------------------------------
SELECT 'NULL = NULL   -> '  + CASE WHEN NULL = NULL     THEN 'TRUE' ELSE 'NOT TRUE' END;
SELECT 'NULL <> NULL  -> '  + CASE WHEN NULL <> NULL    THEN 'TRUE' ELSE 'NOT TRUE' END;
SELECT 'NULL > 5      -> '  + CASE WHEN NULL > 5        THEN 'TRUE' ELSE 'NOT TRUE' END;
--   NULL is not equal to itself, is not not-equal to itself, and no
--   comparison with it is ever TRUE. The answer is UNKNOWN, and WHERE
--   only returns rows where the answer is TRUE.

-- ---------------------------------------------------------------------------
-- THE FIX: IS NULL and IS NOT NULL
--   These are the ONLY correct ways to test for NULL.
--   "= NULL" and "<> NULL" silently return nothing - no error, no rows,
--   which is why it is such a common and expensive bug.
-- ---------------------------------------------------------------------------
INSERT INTO dbo.NullDemo (RequiredText) VALUES ('a');
INSERT INTO dbo.NullDemo (RequiredText, OptionalText) VALUES ('b', '');
INSERT INTO dbo.NullDemo (RequiredText, OptionalText) VALUES ('c', ' ');
GO

SELECT
    RequiredText,
    CASE WHEN OptionalText IS NULL     THEN '<NULL>'
         WHEN OptionalText = ''        THEN '<empty string>'
         WHEN OptionalText = ' '       THEN '<a single space>'
         ELSE '<' + OptionalText + '>'
    END                             AS WhatIsActuallyStored
FROM dbo.NullDemo
ORDER BY RequiredID;
GO
-- Note how all three look similar in the column list but are genuinely
-- different values. That ambiguity is the practical cost of allowing NULL.

-- ---------------------------------------------------------------------------
-- THE AGGREGATE TRAP
--   SUM and COUNT ignore NULLs. AVG divides by the count of NON-NULL values
--   only. This surprises people constantly.
-- ---------------------------------------------------------------------------
DECLARE @Optional varchar(30);
DECLARE @Result  int;

SELECT @Result = COUNT(OptionalText) FROM dbo.NullDemo;
SELECT COUNT(*) AS All_Rows, COUNT(OptionalText) AS Non_Null_Only FROM dbo.NullDemo;
GO

-- ============================================================================
-- DEFAULT CONSTRAINTS - making NULL less likely in the first place
--   Often a column should never be NULL because it has a sensible default.
--   A DEFAULT is not the same as NULL: it supplies a real value when the
--   insert omits the column.
-- ============================================================================

-- Customer.CreationDate already has DEFAULT (GETDATE()) from the schema script.

-- ============================================================================
-- CLEANUP
-- ============================================================================
DROP TABLE dbo.NullDemo;
GO
