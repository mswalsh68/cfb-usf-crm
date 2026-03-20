'use client';

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

const variantStyles: Record<Variant, React.CSSProperties> = {
  primary:   { backgroundColor: 'var(--color-primary)',       color: '#fff', border: 'none' },
  secondary: { backgroundColor: 'var(--color-accent)',        color: 'var(--color-primary)', border: 'none' },
  danger:    { backgroundColor: 'var(--color-danger-light)',  color: 'var(--color-danger)',  border: 'none' },
  ghost:     { backgroundColor: 'transparent',                color: 'var(--color-primary)', border: 'none' },
  outline:   { backgroundColor: 'transparent',                color: 'var(--color-primary)', border: '1.5px solid var(--color-primary)' },
};

const sizeStyles: Record<Size, React.CSSProperties> = {
  sm: { padding: '5px 12px',  fontSize: 12, borderRadius: 'var(--radius-sm)' },
  md: { padding: '9px 18px',  fontSize: 14, borderRadius: 'var(--radius-md)' },
  lg: { padding: '12px 24px', fontSize: 15, borderRadius: 'var(--radius-md)' },
};

import React from 'react';

export default function Button({
  label, onClick, type = 'button', variant = 'primary',
  size = 'md', disabled = false, loading = false, fullWidth = false,
}: ButtonProps) {
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled || loading}
      style={{
        ...variantStyles[variant],
        ...sizeStyles[size],
        fontWeight:     600,
        cursor:         disabled || loading ? 'not-allowed' : 'pointer',
        opacity:        disabled || loading ? 0.5 : 1,
        width:          fullWidth ? '100%' : undefined,
        transition:     'opacity 0.15s, background-color 0.15s',
        display:        'inline-flex',
        alignItems:     'center',
        justifyContent: 'center',
        whiteSpace:     'nowrap',
        boxSizing:      'border-box',
      }}
    >
      {loading ? 'Loading...' : label}
    </button>
  );
}