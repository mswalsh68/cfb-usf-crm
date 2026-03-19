// ============================================================
// USF BULLS — Official Brand Colors
// Source: usf.edu/ucm/marketing/colors.aspx
// ============================================================

export const USF = {
  // ─── Primary Brand ────────────────────────────────────────
  green:       '#006747',   // USF Green  — PMS 342
  gold:        '#CFC493',   // USF Gold   — PMS 4535
  evergreen:   '#005432',   // Evergreen  — PMS 3435 (darker green)
  sand:        '#EDEBD1',   // Sand       — PMS 614  (lighter gold)
  white:       '#FFFFFF',

  // ─── Accent ───────────────────────────────────────────────
  goldDark:    '#A89C6A',   // darker gold for text on light bg
  greenLight:  '#E0F0EA',   // light green surface / badge bg
  sandLight:   '#F5F2E4',   // light sand surface

  // ─── UI Semantic ──────────────────────────────────────────
  danger:      '#C0392B',
  dangerLight: '#FDECEA',
  warning:     '#A89C6A',
  warningLight:'#F5F2E4',

  // ─── Neutral ──────────────────────────────────────────────
  gray50:      '#F9FAFB',
  gray100:     '#F3F4F6',
  gray200:     '#E5E7EB',
  gray300:     '#D1D5DB',
  gray400:     '#9CA3AF',
  gray500:     '#6B7280',
  gray600:     '#4B5563',
  gray700:     '#374151',
  gray800:     '#1F2937',
  gray900:     '#111827',

  // ─── Surfaces ─────────────────────────────────────────────
  pageBg:      '#F5F6FA',
  cardBg:      '#FFFFFF',
  cardBorder:  '#E5E7EB',
} as const;

// ─── Reusable style objects ───────────────────────────────────

export const navStyle = {
  backgroundColor: USF.green,
} as const;

export const primaryButtonStyle = {
  backgroundColor: USF.green,
  color:           USF.white,
} as const;

export const secondaryButtonStyle = {
  backgroundColor: USF.gold,
  color:           USF.green,
} as const;

export const badgeGreenStyle = {
  backgroundColor: USF.greenLight,
  color:           USF.evergreen,
} as const;

export const badgeGoldStyle = {
  backgroundColor: USF.sand,
  color:           USF.goldDark,
} as const;

export const cardStyle = {
  backgroundColor: USF.cardBg,
  border:          `1px solid ${USF.cardBorder}`,
  borderRadius:    16,
  boxShadow:       '0 1px 3px rgba(0,0,0,0.06)',
} as const;