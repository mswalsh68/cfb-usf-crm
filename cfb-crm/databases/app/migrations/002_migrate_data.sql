-- ============================================================
-- APP DB — ONE-TIME DATA MIGRATION (ALREADY RUN — DO NOT RE-RUN)
-- Migrated existing data from separate Roster + Alumni DBs
-- into the unified AppDB (roster schema + alumni schema).
--
-- !! This script was a one-time migration and has already been
-- !! applied to USFBullsApp and PHSPanthersApp. Do NOT run this
-- !! on a fresh tenant DB — use 001_app_db_schema.sql instead.
--
-- Run on: the AppDB (e.g. USFBullsApp)
-- Prerequisites:
--   1. AppDB created and 001_app_db_schema.sql has been run
--   2. Old CfbRoster and CfbAlumni DBs are still accessible
--   3. Run from the AppDB context (USE USFBullsApp; or connect to it)
--
-- ADMIN: Update @OldRosterDb and @OldAlumniDb below before running.
-- ============================================================

-- ─── ADMIN: Set these ────────────────────────────────────────
DECLARE @OldRosterDb NVARCHAR(100) = 'CfbRoster';   -- e.g. CfbRoster or HSFC_Roster
DECLARE @OldAlumniDb NVARCHAR(100) = 'CfbAlumni';   -- e.g. CfbAlumni or HSFC_Alumni
-- ─────────────────────────────────────────────────────────────

DECLARE @sql NVARCHAR(MAX);

-- ─── 1. Migrate roster.players ───────────────────────────────
PRINT 'Migrating players...';

SET @sql = N'
INSERT INTO roster.players (
  id, user_id, jersey_number, first_name, last_name, position, academic_year, status,
  height_inches, weight_lbs, home_town, home_state, high_school, recruiting_class,
  gpa, major, phone, email, instagram, twitter, snapchat,
  emergency_contact_name, emergency_contact_phone, notes,
  graduated_at, created_at, updated_at
)
SELECT
  id, user_id, jersey_number, first_name, last_name, position, academic_year, status,
  height_inches, weight_lbs, home_town, home_state, high_school, recruiting_class,
  gpa, major, phone,
  -- email/instagram/twitter/snapchat were added in migration 002 — use NULL if not present
  TRY_CAST(NULL AS NVARCHAR(255)) AS email,
  TRY_CAST(NULL AS NVARCHAR(100)) AS instagram,
  TRY_CAST(NULL AS NVARCHAR(100)) AS twitter,
  TRY_CAST(NULL AS NVARCHAR(100)) AS snapchat,
  emergency_contact_name, emergency_contact_phone, notes,
  graduated_at, created_at, updated_at
FROM [' + @OldRosterDb + N'].dbo.players
WHERE id NOT IN (SELECT id FROM roster.players);
';

EXEC sp_executesql @sql;
PRINT CONCAT('Inserted ', @@ROWCOUNT, ' player(s)');

-- ─── 2. Migrate roster.player_stats ──────────────────────────
PRINT 'Migrating player_stats...';

SET @sql = N'
INSERT INTO roster.player_stats (id, player_id, season_year, games_played, stats_json, created_at, updated_at)
SELECT id, player_id, season_year, games_played, stats_json, created_at, updated_at
FROM [' + @OldRosterDb + N'].dbo.player_stats
WHERE id NOT IN (SELECT id FROM roster.player_stats);
';
EXEC sp_executesql @sql;
PRINT CONCAT('Inserted ', @@ROWCOUNT, ' player_stat row(s)');

-- ─── 3. Migrate roster.graduation_log ────────────────────────
PRINT 'Migrating graduation_log...';

SET @sql = N'
INSERT INTO roster.graduation_log (id, transaction_id, player_id, graduation_year, graduation_semester, triggered_by, status, notes, performed_at)
SELECT id, transaction_id, player_id, graduation_year, graduation_semester, triggered_by, status, notes, performed_at
FROM [' + @OldRosterDb + N'].dbo.graduation_log
WHERE id NOT IN (SELECT id FROM roster.graduation_log);
';
EXEC sp_executesql @sql;
PRINT CONCAT('Inserted ', @@ROWCOUNT, ' graduation_log row(s)');

-- ─── 4. Migrate alumni.alumni ────────────────────────────────
PRINT 'Migrating alumni...';

SET @sql = N'
INSERT INTO alumni.alumni (
  id, user_id, source_player_id, first_name, last_name,
  graduation_year, graduation_semester, position, recruiting_class, status,
  personal_email, phone, linkedin_url,
  -- twitter_url added in alumni migration 002 — use NULL if not present
  twitter_url,
  current_employer, current_job_title, current_city, current_state, current_country,
  is_donor, last_donation_date, total_donations, engagement_score,
  notes, created_at, updated_at
)
SELECT
  id, user_id, source_player_id, first_name, last_name,
  graduation_year, graduation_semester, position, recruiting_class, status,
  personal_email, phone, linkedin_url,
  TRY_CAST(NULL AS NVARCHAR(100)),
  current_employer, current_job_title, current_city, current_state, current_country,
  is_donor, last_donation_date, total_donations, engagement_score,
  notes, created_at, updated_at
FROM [' + @OldAlumniDb + N'].dbo.alumni
WHERE id NOT IN (SELECT id FROM alumni.alumni);
';
EXEC sp_executesql @sql;
PRINT CONCAT('Inserted ', @@ROWCOUNT, ' alumni record(s)');

-- ─── 5. Migrate alumni.outreach_campaigns ────────────────────
PRINT 'Migrating outreach_campaigns...';

SET @sql = N'
INSERT INTO alumni.outreach_campaigns (id, name, description, target_audience, audience_filters, status, scheduled_at, completed_at, created_by, created_at, updated_at)
SELECT id, name, description, target_audience, audience_filters, status, scheduled_at, completed_at, created_by, created_at, updated_at
FROM [' + @OldAlumniDb + N'].dbo.outreach_campaigns
WHERE id NOT IN (SELECT id FROM alumni.outreach_campaigns);
';
EXEC sp_executesql @sql;
PRINT CONCAT('Inserted ', @@ROWCOUNT, ' campaign(s)');

-- ─── 6. Migrate alumni.outreach_messages ─────────────────────
PRINT 'Migrating outreach_messages...';

SET @sql = N'
INSERT INTO alumni.outreach_messages (id, campaign_id, alumni_id, channel, status, content, sent_at, opened_at, responded_at, created_at)
SELECT id, campaign_id, alumni_id, channel, status, content, sent_at, opened_at, responded_at, created_at
FROM [' + @OldAlumniDb + N'].dbo.outreach_messages
WHERE id NOT IN (SELECT id FROM alumni.outreach_messages);
';
EXEC sp_executesql @sql;
PRINT CONCAT('Inserted ', @@ROWCOUNT, ' outreach_message(s)');

-- ─── 7. Migrate alumni.interaction_log ───────────────────────
PRINT 'Migrating interaction_log...';

SET @sql = N'
INSERT INTO alumni.interaction_log (id, alumni_id, logged_by, channel, summary, outcome, follow_up_at, logged_at)
SELECT id, alumni_id, logged_by, channel, summary, outcome, follow_up_at, logged_at
FROM [' + @OldAlumniDb + N'].dbo.interaction_log
WHERE id NOT IN (SELECT id FROM alumni.interaction_log);
';
EXEC sp_executesql @sql;
PRINT CONCAT('Inserted ', @@ROWCOUNT, ' interaction_log row(s)');

PRINT '=== Data migration complete ===';
GO
