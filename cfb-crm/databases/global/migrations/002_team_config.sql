-- ============================================================
-- GLOBAL DATABASE — TEAM CONFIG
-- Sport- and level-agnostic team configuration.
-- Stores identity, brand colors, positions, terminology labels.
-- Run after: 001_initial_schema.sql
-- ============================================================

CREATE TABLE dbo.team_config (
  id                  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
  team_name           NVARCHAR(100)    NOT NULL DEFAULT 'Team Portal',
  team_abbr           NVARCHAR(10)     NOT NULL DEFAULT 'TEAM',
  sport               NVARCHAR(50)     NOT NULL DEFAULT 'football',
  level               NVARCHAR(20)     NOT NULL DEFAULT 'college'
                        CHECK (level IN ('college', 'high_school', 'club')),
  logo_url            NVARCHAR(500),
  color_primary       NVARCHAR(7)      NOT NULL DEFAULT '#006747',
  color_primary_dark  NVARCHAR(7)      NOT NULL DEFAULT '#005432',
  color_primary_light NVARCHAR(7)      NOT NULL DEFAULT '#E0F0EA',
  color_accent        NVARCHAR(7)      NOT NULL DEFAULT '#CFC493',
  color_accent_dark   NVARCHAR(7)      NOT NULL DEFAULT '#A89C6A',
  color_accent_light  NVARCHAR(7)      NOT NULL DEFAULT '#EDEBD1',
  -- JSON array of position strings, e.g. ["QB","RB","WR"]
  positions_json      NVARCHAR(MAX),
  -- JSON array of {value, label} objects for academic years
  academic_years_json NVARCHAR(MAX),
  alumni_label        NVARCHAR(50)     NOT NULL DEFAULT 'Alumni',
  roster_label        NVARCHAR(50)     NOT NULL DEFAULT 'Roster',
  class_label         NVARCHAR(50)     NOT NULL DEFAULT 'Recruiting Class',
  created_at          DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at          DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ─── Default seed: USF Bulls football (college) ───────────────
INSERT INTO dbo.team_config (
  team_name, team_abbr, sport, level,
  color_primary, color_primary_dark, color_primary_light,
  color_accent,  color_accent_dark,  color_accent_light,
  positions_json,
  academic_years_json,
  alumni_label, roster_label, class_label
) VALUES (
  'USF Bulls', 'USF', 'football', 'college',
  '#006747', '#005432', '#E0F0EA',
  '#CFC493', '#A89C6A', '#EDEBD1',
  '["QB","RB","WR","TE","OL","DL","LB","DB","K","P","LS","ATH"]',
  '[{"value":"freshman","label":"Freshman"},{"value":"sophomore","label":"Sophomore"},{"value":"junior","label":"Junior"},{"value":"senior","label":"Senior"},{"value":"graduate","label":"Graduate"}]',
  'Alumni', 'Roster', 'Recruiting Class'
);

-- ─── Common sport position defaults (for reference / admin seeding) ──
-- Basketball: ["PG","SG","SF","PF","C"]
-- Baseball:   ["P","C","1B","2B","3B","SS","LF","CF","RF","DH"]
-- Soccer:     ["GK","DEF","MID","FWD"]
-- High school academic years: [{"value":"9th","label":"9th Grade"},{"value":"10th","label":"10th Grade"},{"value":"11th","label":"11th Grade"},{"value":"12th","label":"12th Grade"}]
