import React from 'react';
import {
  View, Text, TextInput as RNTextInput, StyleSheet,
  ViewStyle, TextStyle, TextInputProps,
} from 'react-native';
import { Colors, Typography, Spacing, Radii, Shadows } from '../theme/tokens';

// ─── Card ─────────────────────────────────────────────────────

interface CardProps {
  children:    React.ReactNode;
  style?:      ViewStyle;
  padded?:     boolean;
  shadow?:     'none' | 'sm' | 'md' | 'lg';
}

export function Card({ children, style, padded = true, shadow = 'sm' }: CardProps) {
  return (
    <View style={[
      styles.card,
      padded && styles.cardPadded,
      shadow !== 'none' && (Shadows[shadow] as ViewStyle),
      style,
    ]}>
      {children}
    </View>
  );
}

// ─── Badge ────────────────────────────────────────────────────

type BadgeVariant = 'default' | 'success' | 'warning' | 'danger' | 'info' | 'roster' | 'alumni';

interface BadgeProps {
  label:    string;
  variant?: BadgeVariant;
  style?:   ViewStyle;
}

const badgeColors: Record<BadgeVariant, { bg: string; text: string }> = {
  default: { bg: Colors.gray100,      text: Colors.gray700 },
  success: { bg: Colors.successLight, text: Colors.success },
  warning: { bg: Colors.warningLight, text: Colors.warning },
  danger:  { bg: Colors.dangerLight,  text: Colors.danger  },
  info:    { bg: Colors.infoLight,    text: Colors.info    },
  roster:  { bg: Colors.rosterLight,  text: Colors.rosterTint },
  alumni:  { bg: Colors.alumniLight,  text: Colors.alumniTint },
};

export function Badge({ label, variant = 'default', style }: BadgeProps) {
  const { bg, text } = badgeColors[variant];
  return (
    <View style={[styles.badge, { backgroundColor: bg }, style]}>
      <Text style={[styles.badgeText, { color: text }]}>{label}</Text>
    </View>
  );
}

// ─── TextInput ────────────────────────────────────────────────

interface InputProps extends TextInputProps {
  label?:       string;
  error?:       string;
  helper?:      string;
  containerStyle?: ViewStyle;
  inputStyle?:  TextStyle;
}

export function Input({ label, error, helper, containerStyle, inputStyle, ...rest }: InputProps) {
  return (
    <View style={[styles.inputContainer, containerStyle]}>
      {label && <Text style={styles.label}>{label}</Text>}
      <RNTextInput
        placeholderTextColor={Colors.textTertiary}
        style={[
          styles.input,
          error && styles.inputError,
          inputStyle,
        ]}
        {...rest}
      />
      {error  && <Text style={styles.errorText}>{error}</Text>}
      {helper && !error && <Text style={styles.helperText}>{helper}</Text>}
    </View>
  );
}

// ─── SectionHeader ────────────────────────────────────────────

interface SectionHeaderProps {
  title:      string;
  subtitle?:  string;
  right?:     React.ReactNode;
  style?:     ViewStyle;
}

export function SectionHeader({ title, subtitle, right, style }: SectionHeaderProps) {
  return (
    <View style={[styles.sectionHeader, style]}>
      <View style={{ flex: 1 }}>
        <Text style={styles.sectionTitle}>{title}</Text>
        {subtitle && <Text style={styles.sectionSubtitle}>{subtitle}</Text>}
      </View>
      {right && <View>{right}</View>}
    </View>
  );
}

// ─── EmptyState ───────────────────────────────────────────────

interface EmptyStateProps {
  title:       string;
  message?:    string;
  action?:     React.ReactNode;
}

export function EmptyState({ title, message, action }: EmptyStateProps) {
  return (
    <View style={styles.emptyState}>
      <Text style={styles.emptyTitle}>{title}</Text>
      {message && <Text style={styles.emptyMessage}>{message}</Text>}
      {action && <View style={{ marginTop: Spacing.lg }}>{action}</View>}
    </View>
  );
}

// ─── Divider ──────────────────────────────────────────────────

export function Divider({ style }: { style?: ViewStyle }) {
  return <View style={[styles.divider, style]} />;
}

// ─── Styles ───────────────────────────────────────────────────

const styles = StyleSheet.create({
  // Card
  card: {
    backgroundColor: Colors.surface,
    borderRadius:    Radii.md,
    borderWidth:     StyleSheet.hairlineWidth,
    borderColor:     Colors.border,
  },
  cardPadded: {
    padding: Spacing.base,
  },

  // Badge
  badge: {
    alignSelf:     'flex-start',
    paddingHorizontal: Spacing.sm,
    paddingVertical:   Spacing.xxs + 1,
    borderRadius:  Radii.full,
  },
  badgeText: {
    fontSize:   Typography.xs,
    fontWeight: Typography.semibold,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },

  // Input
  inputContainer: {
    gap: Spacing.xs,
  },
  label: {
    fontSize:   Typography.sm,
    fontWeight: Typography.medium,
    color:      Colors.textSecondary,
  },
  input: {
    backgroundColor:  Colors.surface,
    borderWidth:      1.5,
    borderColor:      Colors.border,
    borderRadius:     Radii.sm,
    paddingHorizontal: Spacing.md,
    paddingVertical:  Spacing.md,
    fontSize:         Typography.base,
    color:            Colors.textPrimary,
  },
  inputError: {
    borderColor: Colors.danger,
  },
  errorText: {
    fontSize:  Typography.xs,
    color:     Colors.danger,
  },
  helperText: {
    fontSize:  Typography.xs,
    color:     Colors.textTertiary,
  },

  // Section header
  sectionHeader: {
    flexDirection:  'row',
    alignItems:     'center',
    paddingVertical: Spacing.md,
  },
  sectionTitle: {
    fontSize:   Typography.md,
    fontWeight: Typography.bold,
    color:      Colors.textPrimary,
  },
  sectionSubtitle: {
    fontSize:  Typography.sm,
    color:     Colors.textSecondary,
    marginTop: 2,
  },

  // Empty state
  emptyState: {
    alignItems:  'center',
    paddingVertical: Spacing.xxxl,
    paddingHorizontal: Spacing.xxl,
  },
  emptyTitle: {
    fontSize:   Typography.lg,
    fontWeight: Typography.semibold,
    color:      Colors.textSecondary,
    textAlign:  'center',
  },
  emptyMessage: {
    fontSize:  Typography.base,
    color:     Colors.textTertiary,
    textAlign: 'center',
    marginTop: Spacing.sm,
  },

  // Divider
  divider: {
    height:          StyleSheet.hairlineWidth,
    backgroundColor: Colors.border,
    marginVertical:  Spacing.md,
  },
});
