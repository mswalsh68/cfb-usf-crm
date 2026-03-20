'use client';

import React from 'react';

type BadgeVariant = 'green' | 'gold' | 'danger' | 'warning' | 'gray';

interface BadgeProps {
  label:    string;
  variant?: BadgeVariant;
}

const badgeStyles: Record<BadgeVariant, React.CSSProperties> = {
  green:   { backgroundColor: 'var(--color-primary-light)', color: 'var(--color-primary-dark)' },
  gold:    { backgroundColor: 'var(--color-accent-light)',  color: 'var(--color-accent-dark)'  },
  danger:  { backgroundColor: 'var(--color-danger-light)',  color: 'var(--color-danger)'       },
  warning: { backgroundColor: 'var(--color-warning-light)', color: 'var(--color-warning)'      },
  gray:    { backgroundColor: 'var(--color-gray-100)',      color: 'var(--color-gray-600)'     },
};

export default function Badge({ label, variant = 'gray' }: BadgeProps) {
  return (
    <span style={{
      ...badgeStyles[variant],
      display:       'inline-block',
      padding:       '3px 10px',
      borderRadius:  'var(--radius-full)',
      fontSize:      11,
      fontWeight:    700,
      textTransform: 'uppercase',
      letterSpacing: '0.4px',
      whiteSpace:    'nowrap',
    }}>
      {label}
    </span>
  );
}