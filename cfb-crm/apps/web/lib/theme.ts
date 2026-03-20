// ============================================================
// THEME — CSS Variable References
// All values point to CSS custom properties in globals.css.
// To white-label: update .env.local only. No code changes needed.
// ============================================================

export const theme = {
  // ─── Primary brand ────────────────────────────────────────
  primary:      'var(--color-primary)',
  primaryDark:  'var(--color-primary-dark)',
  primaryLight: 'var(--color-primary-light)',
  primaryHover: 'var(--color-primary-hover)',

  // ─── Accent ───────────────────────────────────────────────
  accent:       'var(--color-accent)',
  accentDark:   'var(--color-accent-dark)',
  accentLight:  'var(--color-accent-light)',

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
  white:   'var(--color-white)',
  gray50:  'var(--color-gray-50)',
  gray100: 'var(--color-gray-100)',
  gray200: 'var(--color-gray-200)',
  gray300: 'var(--color-gray-300)',
  gray400: 'var(--color-gray-400)',
  gray500: 'var(--color-gray-500)',
  gray600: 'var(--color-gray-600)',
  gray700: 'var(--color-gray-700)',
  gray800: 'var(--color-gray-800)',
  gray900: 'var(--color-gray-900)',

  // ─── Surfaces ─────────────────────────────────────────────
  pageBg:     'var(--color-page-bg)',
  cardBg:     'var(--color-card-bg)',
  cardBorder: 'var(--color-card-border)',
} as const;