-- ============================================================
-- DATA MIGRATION: CfbRoster + CfbAlumni → USFBullsApp
-- Run this AFTER 001_create_app_db.sql on USFBullsApp.
--
-- Prerequisites:
--   USFBullsApp database created and 001_create_app_db.sql run
--   CfbRoster and CfbAlumni databases accessible on same server
--
-- Usage:
--   USE USFBullsApp;
--   :r 002_migrate_usf_data.sql
-- ============================================================

-- ── roster.players ─────────────────────────────────────────
INSERT INTO roster.players (
  id, user_id, jersey_number, first_name, last_name, position,
  academic_year, status, height_inches, weight_lbs, home_town,
  home_state, high_school, recruiting_class, gpa, major, phone,
  email, instagram, twitter, snapchat,
  emergency_contact_name, emergency_contact_phone, notes,
  graduated_at, created_at, updated_at
)
SELECT
  id, user_id, jersey_number, first_name, last_name, position,
  academic_year, status, height_inches, weight_lbs, home_town,
  home_state, high_school, recruiting_class, gpa, major, phone,
  email, instagram, twitter, snapchat,
  emergency_contact_name, emergency_contact_phone, notes,
  graduated_at, created_at, updated_at
FROM CfbRoster.dbo.players;

-- ── roster.player_stats ────────────────────────────────────
INSERT INTO roster.player_stats (
  id, player_id, season_year, games_played, stats_json, created_at, updated_at
)
SELECT id, player_id, season_year, games_played, stats_json, created_at, updated_at
FROM CfbRoster.dbo.player_stats;

-- ── roster.player_documents ────────────────────────────────
INSERT INTO roster.player_documents (
  id, player_id, doc_type, file_name, azure_blob_url, uploaded_by, uploaded_at, expires_at
)
SELECT id, player_id, doc_type, file_name, azure_blob_url, uploaded_by, uploaded_at, expires_at
FROM CfbRoster.dbo.player_documents;

-- ── dbo.graduation_log ─────────────────────────────────────
INSERT INTO dbo.graduation_log (
  id, transaction_id, player_id, graduation_year, graduation_semester,
  triggered_by, status, notes, performed_at
)
SELECT id, transaction_id, player_id, graduation_year, graduation_semester,
       triggered_by, status, notes, performed_at
FROM CfbRoster.dbo.graduation_log;

-- ── alumni.alumni ──────────────────────────────────────────
INSERT INTO alumni.alumni (
  id, user_id, source_player_id, first_name, last_name,
  graduation_year, graduation_semester, position, recruiting_class,
  status, personal_email, phone, linkedin_url, twitter_url,
  current_employer, current_job_title, current_city, current_state, current_country,
  is_donor, last_donation_date, total_donations, engagement_score,
  notes, created_at, updated_at
)
SELECT
  id, user_id, source_player_id, first_name, last_name,
  graduation_year, graduation_semester, position, recruiting_class,
  status, personal_email, phone, linkedin_url, twitter_url,
  current_employer, current_job_title, current_city, current_state, current_country,
  is_donor, last_donation_date, total_donations, engagement_score,
  notes, created_at, updated_at
FROM CfbAlumni.dbo.alumni;

-- ── alumni.interaction_log ─────────────────────────────────
INSERT INTO alumni.interaction_log (
  id, alumni_id, logged_by, channel, summary, outcome, follow_up_at, logged_at
)
SELECT id, alumni_id, logged_by, channel, summary, outcome, follow_up_at, logged_at
FROM CfbAlumni.dbo.interaction_log;

-- ── alumni.outreach_campaigns ──────────────────────────────
INSERT INTO alumni.outreach_campaigns (
  id, name, description, target_audience, audience_filters,
  status, scheduled_at, completed_at, created_by, created_at, updated_at
)
SELECT
  id, name, description, target_audience, audience_filters,
  status, scheduled_at, completed_at, created_by, created_at, updated_at
FROM CfbAlumni.dbo.outreach_campaigns;

-- ── alumni.outreach_messages ───────────────────────────────
INSERT INTO alumni.outreach_messages (
  id, campaign_id, alumni_id, channel, status, content,
  sent_at, opened_at, responded_at, created_at
)
SELECT
  id, campaign_id, alumni_id, channel, status, content,
  sent_at, opened_at, responded_at, created_at
FROM CfbAlumni.dbo.outreach_messages;

PRINT 'Migration complete.';
SELECT
  (SELECT COUNT(*) FROM roster.players)               AS players,
  (SELECT COUNT(*) FROM alumni.alumni)                AS alumni,
  (SELECT COUNT(*) FROM alumni.interaction_log)       AS interactions,
  (SELECT COUNT(*) FROM alumni.outreach_campaigns)    AS campaigns;
