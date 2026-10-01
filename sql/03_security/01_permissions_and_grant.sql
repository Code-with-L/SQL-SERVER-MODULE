-- ============================================================================
-- Script: 01_permissions_and_grant.sql
-- Manual : Part 2 - Permissions, GRANT, database objects and security
-- ============================================================================
--
-- THE SECURITY MODEL IN ONE PICTURE
--
--   SERVER        -> LOGIN          -> (maps to)
--   DATABASE      -> USER           -> member of
--   DATABASE      -> ROLE           -> granted
--   TABLE         -> PERMISSION     -> on
--
--   You cannot connect without a LOGIN. Once connected you are a USER.
--   Users are given rights by joining ROLES. Roles are granted permissions.
--   The special user dbo owns everything in the database.
--
--   PRINCIPAL   - the thing being granted to or denied (user or role)
--   PRIVILEGE   - the action (SELECT, INSERT, UPDATE, DELETE, EXECUTE...)
--   OBJECT      - what it applies to (table, view, procedure, schema)
-- ============================================================================

USE StudentRecordsDB;
GO

-- ---------------------------------------------------------------------------
-- 1. WHO am I?  What can I already do?
-- ---------------------------------------------------------------------------
SELECT
    ORIGINAL_LOGIN()        AS WindowsLogin,
    USER_NAME()             AS CurrentUser,
    SUSER_SNAME()           AS ServerLogin,
    IS_ROLEMEMBER('db_owner')   AS IsDbOwner,
    IS_ROLEMEMBER('db_datareader') AS IsDataReader;
GO
-- On your box, SUSER_SNAME() returns LEOKINGXLING\leon2 - a WINDOWS login.
-- That is Windows Authentication: no password exists in SQL Server at all.
-- SSMS showed the same thing in its title bar earlier.

-- ---------------------------------------------------------------------------
-- 2. The fixed ROLES that already exist in every database
-- ---------------------------------------------------------------------------
SELECT
    r.name                     AS FixedRole,
    OBJECTPROPERTY(r.object_id, 'IsFixedRole') AS IsFixed,
    sp.name                    AS IsFixedRole,
    IS_ROLEMEMBER(r.name)      AS AmIMember
FROM sys.database_principals r
LEFT JOIN sys.database_permissions dp ON dp.class = 1
LEFT JOIN sys.server_principals sp ON sp.sid = r.sid
WHERE r.type IN ('R', 'G') AND r.name LIKE 'db_%'
ORDER BY r.name;
GO

-- db_owner           full control - equivalent to dbo. Rarely appropriate.
-- db_accessadmin     can change database users and roles, nothing else
-- db_securityadmin   can change permissions, nothing else
-- db_ddladmin        CREATE/ALTER/DROP objects, but no data access
-- db_datareader      SELECT everywhere
-- db_datawriter      INSERT/UPDATE/DELETE everywhere
-- db_denydatareader  cannot SELECT anywhere (rarely used)
-- db_denydatawriter  cannot write anywhere (rarely used)
--
-- APPLICATION ROLES (created by you, e.g. a Reporting role):
--   add_reader     - SELECT, no writes
--   add_reporting  - SELECT on views only

-- ---------------------------------------------------------------------------
-- 3. What permissions does my login hold here? (Recalled from Part 1)
-- ---------------------------------------------------------------------------
SELECT
    dp.class_desc     AS ObjectClass,
    OBJECT_NAME(dp.major_id) AS ObjectName,
    dp.permission_name AS Permission,
    dp.state_desc     AS State
FROM sys.database_permissions dp
JOIN sys.database_principals r ON r.principal_id = dp.grantee_principal_id
WHERE r.name = USER_NAME()
ORDER BY ObjectClass, ObjectName;
GO
-- You will see db_owner in there, which is why you can create tables freely.
-- The "(75)" you saw in the SSMS title bar was this count.

-- ============================================================================
-- 4. GRANT - giving a permission
-- ============================================================================
--
--   GRANT <permission> ON <object> TO <principal>;
--
--   GRANT is ADDITIVE and NEVER overwrites. If you already had SELECT and you
--   grant UPDATE, you now have both. That surprises people who expect it to
--   behave like a set operation.
--
--   To remove: REVOKE (removes a permission you granted)
--               DENY    (adds a block that beats any GRANT, even from db_owner)
--
--   GRANT  vs  DENY, the rule: DENY wins. Always. Even a DBA cannot grant
--   permission that has been explicitly denied at the same scope.
-- ---------------------------------------------------------------------------

-- Grant SELECT on one table to the built-in public role (every user has it):
--   GRANT SELECT ON dbo.Customer TO public;

-- Grant SELECT on a single COLUMN only. Notice the grant is on the column,
--   not the table - a genuinely fine-grained permission:
--   GRANT SELECT (CustomerName) ON dbo.Customer TO public;

-- Grant at SCHEMA level - applies to every current AND future table:
--   GRANT SELECT ON SCHEMA::reporting TO public;
--   (needs the schema: EXEC('CREATE SCHEMA reporting');)

-- Grant to a USER (change the name to a real login on your server):
--   GRANT SELECT ON dbo.Customer TO [YourLoginHere];
--   -- error 15004 if the user does not exist, or is a Windows login from
--   --    another domain. Check with:
--   SELECT name, type_desc FROM sys.database_principals WHERE name LIKE '%leon%';

-- ============================================================================
-- 5. DENY - the harder permission
-- ============================================================================
--   DENY SELECT ON dbo.CustomerAddress TO public;
--
--   Why you would: an address table holds personal data. If a report only
--   ever needs customer names, granting SELECT on dbo.Customer and denying
--   it on dbo.CustomerAddress is cleaner than granting SELECT on everything.
--
--   After DENY, this DOES NOT work even for db_owner:
--     SELECT * FROM dbo.CustomerAddress;   -- Msg 229: SELECT denied.
--
--   To lift a deny you must explicitly remove it:
--     REVOKE SELECT ON dbo.CustomerAddress TO public;
--
--   HIERARCHY RULE
--     A DENY at a high level (database or server) beats a GRANT at a lower
--     level (table). A GRANT at the server level beats a DENY on one table.
--     Permissions are resolved most-specific-first, and the first explicit
--     decision found at a level wins.
-- ============================================================================

-- ============================================================================
-- 6. The least-privilege pattern the manual is really teaching
-- ============================================================================
--
--   BAD:   GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO [app]
--          -> app can read AND write every table, including ones added later
--
--   GOOD:  db_datareader   (SELECT everywhere)
--          plus one GRANT per table the app must write
--          plus DENY on anything sensitive
--
--   Grant the minimum, name the tables explicitly, deny the sensitive ones.
-- ============================================================================

-- ============================================================================
-- 7. Auditing: who has what?
-- ============================================================================
-- All explicit (non-inherited) permissions on Customer:
SELECT
    dp.permission_name AS Permission,
    dp.state_desc     AS State,
    pr.name           AS Principal
FROM sys.database_permissions dp
JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id
WHERE dp.class = 1
  AND dp.major_id = OBJECT_ID('dbo.Customer')
ORDER BY pr.name, dp.permission_name;
GO

-- Where the principal gets its rights from (the role chain):
SELECT
    u.name AS UserName,
    r.name AS RoleName,
    r.type_desc AS RoleType
FROM sys.database_role_members rm
JOIN sys.database_principals u ON u.principal_id = rm.member_principal_id
JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
ORDER BY u.name;
GO

-- ============================================================================
-- 8. Ownership chains - a subtle and useful fact
-- ============================================================================
--   If you have permission on a VIEW, and the view's owner also has
--   permission on the underlying table, then querying the view does NOT
--   require you to have permission on the table.
--
--   THIS IS THE REASON VIEWS ARE A SECURITY TOOL. Grant SELECT on the view,
--   not on the base table, and the table becomes unreachable.
--
--   But if you write your own view (and thus own it), that chain breaks and
--   you need explicit permission on every table underneath. Owning the view is
--   why you could just SELECT * from dbo.Customer.
-- ============================================================================
