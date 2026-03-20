// ============================================================
// THEME — CSS Variable References
// All values use CSS custom properties defined in globals.css.
// To white-label: swap the CSS variables, not this file.
// ============================================================

export const USF = {
  // ─── Primary ──────────────────────────────────────────────
  green:        'var(--color-primary)',
  evergreen:    'var(--color-primary-dark)',
  greenLight:   'var(--color-primary-light)',
  greenHover:   'var(--color-primary-hover)',

  // ─── Accent ───────────────────────────────────────────────
  gold:         'var(--color-accent)',
  goldDark:     'var(--color-accent-dark)',
  sand:         'var(--color-accent-light)',

  // ─── Status ───────────────────────────────────────────────
  success:      'var(--color-success)',
  successLight: 'var(--color-success-light)',
  warning:      'var(--color-warning)',
  warningLight: 'var(--color-warning-light)',
  danger:       'var(--color-danger)',
  dangerLight:  'var(--color-danger-light)',
  info:         'var(--color-info)',
  infoLight:    'var(--color-info-light)',

  // ─── Neutrals ─────────────────────────────────────────────
  white:    'var(--color-white)',
  gray50:   'var(--color-gray-50)',
  gray100:  'var(--color-gray-100)',
  gray200:  'var(--color-gray-200)',
  gray300:  'var(--color-gray-300)',
  gray400:  'var(--color-gray-400)',
  gray500:  'var(--color-gray-500)',
  gray600:  'var(--color-gray-600)',
  gray700:  'var(--color-gray-700)',
  gray800:  'var(--color-gray-800)',
  gray900:  'var(--color-gray-900)',

  // ─── Surfaces ─────────────────────────────────────────────
  pageBg:     'var(--color-page-bg)',
  cardBg:     'var(--color-card-bg)',
  cardBorder: 'var(--color-card-border)',
} as const;

export const cardStyle = {
  backgroundColor: USF.cardBg,
  border:          `1px solid ${USF.cardBorder}`,
  borderRadius:    'var(--radius-lg)',
  boxShadow:       'var(--shadow-sm)',
} as const;

export const navStyle = {
  backgroundColor: USF.green,
} as const;

export const primaryBtnStyle = {
  backgroundColor: USF.green,
  color:           USF.white,
  borderRadius:    'var(--radius-md)',
} as const;