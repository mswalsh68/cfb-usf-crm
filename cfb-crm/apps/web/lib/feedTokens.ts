/**
 * feedTokens.ts
 *
 * Resolves white-label tokens embedded in feed post HTML.
 * Tokens are substituted at render time using the live TeamConfig —
 * no extra DB call needed, and colors always reflect the current
 * team palette even after admin settings changes.
 *
 * Tokens:
 *   {{TEAM_NAME}}     → teamConfig.teamName
 *   {{PRIMARY_COLOR}} → teamConfig.colorPrimary
 *   {{ACCENT_COLOR}}  → teamConfig.colorAccent
 *   {{SPORT_EMOJI}}   → emoji derived from teamConfig.sport
 *
 * Only applied when isWelcomePost === true to avoid scanning every post.
 */

import { TeamConfig } from './teamConfig';

const SPORT_EMOJI: Record<string, string> = {
  football:   '🏈',
  basketball: '🏀',
  baseball:   '⚾',
  soccer:     '⚽',
  softball:   '🥎',
  volleyball: '🏐',
  other:      '🏆',
};

export function resolvePostTokens(html: string, config: TeamConfig): string {
  const sportEmoji = SPORT_EMOJI[config.sport?.toLowerCase()] ?? '🏆';
  return html
    .replaceAll('{{TEAM_NAME}}',     config.teamName)
    .replaceAll('{{PRIMARY_COLOR}}', config.colorPrimary)
    .replaceAll('{{ACCENT_COLOR}}',  config.colorAccent)
    .replaceAll('{{SPORT_EMOJI}}',   sportEmoji);
}
