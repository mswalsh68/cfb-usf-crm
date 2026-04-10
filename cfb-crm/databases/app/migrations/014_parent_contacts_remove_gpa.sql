-- ============================================================
-- Migration 014 — Remove gpa, add parent contact fields,
--                 drop academic_year CHECK constraint
-- Run against: each tenant AppDB
-- ============================================================

-- ─── 1. Drop gpa column (if it still exists) ─────────────────
IF EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('dbo.users') AND name = 'gpa'
)
BEGIN
  ALTER TABLE dbo.users DROP COLUMN gpa;
  PRINT 'Dropped column: gpa';
END
ELSE
  PRINT 'Column gpa not found — skipping';
GO

-- ─── 2. Add parent contact columns (each guarded by IF NOT EXISTS) ────────

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('dbo.users') AND name = 'parent1_name'
)
BEGIN
  ALTER TABLE dbo.users ADD parent1_name NVARCHAR(150) NULL;
  PRINT 'Added column: parent1_name';
END
GO

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('dbo.users') AND name = 'parent1_phone'
)
BEGIN
  ALTER TABLE dbo.users ADD parent1_phone NVARCHAR(20) NULL;
  PRINT 'Added column: parent1_phone';
END
GO

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('dbo.users') AND name = 'parent1_email'
)
BEGIN
  ALTER TABLE dbo.users ADD parent1_email NVARCHAR(255) NULL;
  PRINT 'Added column: parent1_email';
END
GO

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('dbo.users') AND name = 'parent2_name'
)
BEGIN
  ALTER TABLE dbo.users ADD parent2_name NVARCHAR(150) NULL;
  PRINT 'Added column: parent2_name';
END
GO

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('dbo.users') AND name = 'parent2_phone'
)
BEGIN
  ALTER TABLE dbo.users ADD parent2_phone NVARCHAR(20) NULL;
  PRINT 'Added column: parent2_phone';
END
GO

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('dbo.users') AND name = 'parent2_email'
)
BEGIN
  ALTER TABLE dbo.users ADD parent2_email NVARCHAR(255) NULL;
  PRINT 'Added column: parent2_email';
END
GO

-- ─── 3. Drop the academic_year CHECK constraint (if it exists) ────────────
-- The old constraint enforces a fixed enum that does not include redshirt values.
DECLARE @cname NVARCHAR(200);
SELECT @cname = name FROM sys.check_constraints
WHERE parent_object_id = OBJECT_ID('dbo.users')
  AND LOWER(definition) LIKE '%academic_year%';
IF @cname IS NOT NULL
BEGIN
  EXEC('ALTER TABLE dbo.users DROP CONSTRAINT [' + @cname + ']');
  PRINT 'Dropped CHECK constraint: ' + @cname;
END
ELSE
  PRINT 'No academic_year CHECK constraint found — skipping';
GO

-- ─── 4. Record migration ────────────────────────────────────────────────────
IF NOT EXISTS (
  SELECT 1 FROM dbo.migration_history WHERE migration_name = '014_parent_contacts_remove_gpa.sql'
)
BEGIN
  INSERT INTO dbo.migration_history (migration_name) VALUES ('014_parent_contacts_remove_gpa.sql');
  PRINT 'Recorded migration: 014_parent_contacts_remove_gpa.sql';
END
GO
