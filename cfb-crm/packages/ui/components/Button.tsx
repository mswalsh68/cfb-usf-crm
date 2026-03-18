import React from 'react';
import {
  TouchableOpacity,
  Text,
  ActivityIndicator,
  StyleSheet,
  ViewStyle,
  TextStyle,
  View,
} from 'react-native';
import { Colors, Typography, Spacing, Radii, Shadows } from '../theme/tokens';

type Variant = 'primary' | 'secondary' | 'outline' | 'ghost' | 'danger' | 'roster' | 'alumni';
type Size    = 'sm' | 'md' | 'lg';

interface ButtonProps {
  label:       string;
  onPress:     () => void;
  variant?:    Variant;
  size?:       Size;
  loading?:    boolean;
  disabled?:   boolean;
  leftIcon?:   React.ReactNode;
  rightIcon?:  React.ReactNode;
  fullWidth?:  boolean;
  style?:      ViewStyle;
  textStyle?:  TextStyle;
}

const variantStyles: Record<Variant, { container: ViewStyle; text: TextStyle }> = {
  primary: {
    container: { backgroundColor: Colors.primary },
    text:      { color: Colors.textInverse },
  },
  secondary: {
    container: { backgroundColor: Colors.accentDark },
    text:      { color: Colors.textInverse },
  },
  outline: {
    container: { backgroundColor: 'transparent', borderWidth: 1.5, borderColor: Colors.primary },
    text:      { color: Colors.primary },
  },
  ghost: {
    container: { backgroundColor: 'transparent' },
    text:      { color: Colors.primary },
  },
  danger: {
    container: { backgroundColor: Colors.danger },
    text:      { color: Colors.textInverse },
  },
  roster: {
    container: { backgroundColor: Colors.rosterTint },
    text:      { color: Colors.textInverse },
  },
  alumni: {
    container: { backgroundColor: Colors.alumniTint },
    text:      { color: Colors.textInverse },
  },
};

const sizeStyles: Record<Size, { container: ViewStyle; text: TextStyle }> = {
  sm: {
    container: { paddingHorizontal: Spacing.md,   paddingVertical: Spacing.xs,  borderRadius: Radii.sm },
    text:      { fontSize: Typography.sm, fontWeight: Typography.medium },
  },
  md: {
    container: { paddingHorizontal: Spacing.xl,   paddingVertical: Spacing.md,  borderRadius: Radii.md },
    text:      { fontSize: Typography.base, fontWeight: Typography.semibold },
  },
  lg: {
    container: { paddingHorizontal: Spacing.xxl,  paddingVertical: Spacing.base, borderRadius: Radii.md },
    text:      { fontSize: Typography.md, fontWeight: Typography.semibold },
  },
};

export function Button({
  label, onPress, variant = 'primary', size = 'md',
  loading = false, disabled = false,
  leftIcon, rightIcon, fullWidth = false, style, textStyle,
}: ButtonProps) {
  const isDisabled = disabled || loading;
  const vStyle = variantStyles[variant];
  const sStyle = sizeStyles[size];

  return (
    <TouchableOpacity
      onPress={onPress}
      disabled={isDisabled}
      activeOpacity={0.75}
      style={[
        styles.base,
        vStyle.container,
        sStyle.container,
        fullWidth && styles.fullWidth,
        isDisabled && styles.disabled,
        ...Shadows.sm as any,
        style,
      ]}
    >
      {loading ? (
        <ActivityIndicator
          size="small"
          color={variant === 'outline' || variant === 'ghost' ? Colors.primary : Colors.white}
        />
      ) : (
        <View style={styles.inner}>
          {leftIcon && <View style={styles.iconLeft}>{leftIcon}</View>}
          <Text style={[vStyle.text, sStyle.text, textStyle]}>{label}</Text>
          {rightIcon && <View style={styles.iconRight}>{rightIcon}</View>}
        </View>
      )}
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  base: {
    alignItems:     'center',
    justifyContent: 'center',
    flexDirection:  'row',
  },
  fullWidth: {
    width: '100%',
  },
  disabled: {
    opacity: 0.45,
  },
  inner: {
    flexDirection:  'row',
    alignItems:     'center',
  },
  iconLeft: {
    marginRight: Spacing.xs,
  },
  iconRight: {
    marginLeft: Spacing.xs,
  },
});
