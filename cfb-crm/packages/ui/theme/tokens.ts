// ============================================================
// GLOBAL THEME — CFB CRM
// All colors, spacing, typography, and shadows in one place.
// Import this anywhere in the app or shared packages.
// ============================================================

export const Colors = {
  // ─── Brand ────────────────────────────────────────────────
  primary:        '#1A3A6B',   // Deep navy
  primaryLight:   '#2C5FA8',
  primaryDark:    '#0F2244',
  accent:         '#C8991A',   // Gold
  accentLight:    '#E8B832',
  accentDark:     '#9A7010',

  // ─── App-specific tints ────────────────────────────────────
  rosterTint:     '#1D6B3A',   // Green — Roster CRM
  rosterLight:    '#D4EDDA',
  alumniTint:     '#6B3A1D',   // Burnt orange — Alumni CRM
  alumniLight:    '#F5DFD0',
  adminTint:      '#1A3A6B',   // Same as primary

  // ─── Status ────────────────────────────────────────────────
  success:        '#1D8A4E',
  successLight:   '#D4EDDA',
  warning:        '#B97A10',
  warningLight:   '#FFF3CD',
  danger:         '#C0392B',
  dangerLight:    '#FDECEA',
  info:           '#1565C0',
  infoLight:      '#E3F0FF',

  // ─── Neutral ───────────────────────────────────────────────
  white:          '#FFFFFF',
  black:          '#000000',
  gray50:         '#F9FAFB',
  gray100:        '#F3F4F6',
  gray200:        '#E5E7EB',
  gray300:        '#D1D5DB',
  gray400:        '#9CA3AF',
  gray500:        '#6B7280',
  gray600:        '#4B5563',
  gray700:        '#374151',
  gray800:        '#1F2937',
  gray900:        '#111827',

  // ─── Surfaces ──────────────────────────────────────────────
  background:     '#F5F6FA',
  surface:        '#FFFFFF',
  surfaceAlt:     '#F0F2F8',
  border:         '#E5E7EB',
  borderStrong:   '#D1D5DB',

  // ─── Text ──────────────────────────────────────────────────
  textPrimary:    '#111827',
  textSecondary:  '#4B5563',
  textTertiary:   '#9CA3AF',
  textInverse:    '#FFFFFF',
  textLink:       '#2C5FA8',
} as const;

export const Typography = {
  // Font families
  fontRegular:    'System',   // swap for a custom font (e.g. Inter) if needed
  fontMedium:     'System',
  fontBold:       'System',
  fontMono:       'Courier New',

  // Size scale
  xs:   11,
  sm:   13,
  base: 15,
  md:   17,
  lg:   20,
  xl:   24,
  xxl:  30,
  xxxl: 38,

  // Line heights
  tight:    1.2,
  normal:   1.5,
  relaxed:  1.75,

  // Font weights
  regular:  '400' as const,
  medium:   '500' as const,
  semibold: '600' as const,
  bold:     '700' as const,
} as const;

export const Spacing = {
  xxs:  2,
  xs:   4,
  sm:   8,
  md:   12,
  base: 16,
  lg:   20,
  xl:   24,
  xxl:  32,
  xxxl: 48,
  huge: 64,
} as const;

export const Radii = {
  xs:   4,
  sm:   8,
  md:   12,
  lg:   16,
  xl:   24,
  full: 9999,
} as const;

export const Shadows = {
  none: {
    shadowColor: 'transparent',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0,
    shadowRadius: 0,
    elevation: 0,
  },
  sm: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.06,
    shadowRadius: 3,
    elevation: 2,
  },
  md: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.10,
    shadowRadius: 6,
    elevation: 4,
  },
  lg: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.14,
    shadowRadius: 12,
    elevation: 8,
  },
} as const;

// Player status → color mapping
export const PlayerStatusColor: Record<string, string> = {
  active:      Colors.success,
  injured:     Colors.warning,
  suspended:   Colors.danger,
  graduated:   Colors.alumniTint,
  transferred: Colors.gray500,
  walkOn:      Colors.info,
};

// Alumni status → color mapping
export const AlumniStatusColor: Record<string, string> = {
  active:        Colors.success,
  lostContact:   Colors.warning,
  deceased:      Colors.gray500,
  doNotContact:  Colors.danger,
};
