'use client';

import { USF } from '@/lib/theme';

type Variant = 'primary' | 'secondary' | 'danger' | 'ghost' | 'outline';
type Size    = 'sm' | 'md' | 'lg';

interface ButtonProps {
  label:      string;
  onClick?:   (e?: any) => void;
  type?:      'button' | 'submit' | 'reset';
  variant?:   Variant;
  size?:      Size;
  disabled?:  boolean;
  loading?:   boolean;
  fullWidth?: boolean;
}

const variantStyles: Record<Variant, { backgroundColor: string; color: string; border?: string }> = {
  primary:   { backgroundColor: USF.green,       color: USF.white },
  secondary: { backgroundColor: USF.gold,        color: USF.green },
  danger:    { backgroundColor: USF.dangerLight,  color: USF.danger },
  ghost:     { backgroundColor: 'transparent',   color: USF.green },
  outline:   { backgroundColor: 'transparent',   color: USF.green, border: `1.5px solid ${USF.green}` },
};

const sizeStyles: Record<Size, { padding: string; fontSize: string; borderRadius: string }> = {
  sm: { padding: '6px 14px',  fontSize: '12px', borderRadius: '8px'  },
  md: { padding: '10px 20px', fontSize: '14px', borderRadius: '10px' },
  lg: { padding: '12px 24px', fontSize: '15px', borderRadius: '12px' },
};

export default function Button({
  label, onClick, type = 'button', variant = 'primary',
  size = 'md', disabled = false, loading = false, fullWidth = false,
}: ButtonProps) {
  const vStyle = variantStyles[variant];
  const sStyle = sizeStyles[size];

  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled || loading}
      style={{
        ...vStyle,
        ...sStyle,
        fontWeight: 600,
        cursor: disabled || loading ? 'not-allowed' : 'pointer',
        opacity: disabled || loading ? 0.5 : 1,
        width: fullWidth ? '100%' : undefined,
        transition: 'opacity 0.15s',
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      {loading ? 'Loading...' : label}
    </button>
  );
}
