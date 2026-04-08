-- ============================================================
-- MIGRATION 011 — Drop current_country from users
-- Run on: all AppDBs (LegacyLinkApp, DevLegacyLinkApp, etc.)
-- Column was never intentionally added; removing to keep
-- schema clean and in sync with the defined data model.
-- ============================================================

IF EXISTS (
  SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'dbo'
    AND TABLE_NAME   = 'users'
    AND COLUMN_NAME  = 'current_country'
)
BEGIN
  -- Drop any default constraint on the column first (auto-named, look up dynamically)
  DECLARE @con NVARCHAR(200);
  SELECT @con = dc.name
  FROM   sys.default_constraints dc
  JOIN   sys.columns c
    ON   c.object_id  = dc.parent_object_id
   AND   c.column_id  = dc.parent_column_id
  WHERE  OBJECT_SCHEMA_NAME(dc.parent_object_id) = 'dbo'
    AND  OBJECT_NAME(dc.parent_object_id)         = 'users'
    AND  c.name                                   = 'current_country';

  IF @con IS NOT NULL
    EXEC('ALTER TABLE dbo.users DROP CONSTRAINT [' + @con + ']');

  ALTER TABLE dbo.users DROP COLUMN current_country;
  PRINT 'Migration 011: Dropped current_country from dbo.users';
END
ELSE
  PRINT 'Migration 011: current_country not present — skipping';
GO
