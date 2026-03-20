'use client';

import React, { CSSProperties } from 'react';

interface CardProps {
  children:   React.ReactNode;
  style?:     CSSProperties;
  onClick?:   () => void;
  padded?:    boolean;
}

export default function Card({ children, style, onClick, padded = true }: CardProps) {
  return (
    <div
      onClick={onClick}
      style={{
        backgroundColor: 'var(--color-card-bg)',
        border:          '1px solid var(--color-card-border)',
        borderRadius:    'var(--radius-lg)',
        boxShadow:       'var(--shadow-sm)',
        padding:         padded ? 24 : 0,
        cursor:          onClick ? 'pointer' : 'default',
        transition:      'box-shadow 0.15s, border-color 0.15s',
        ...style,
      }}
    >
      {children}
    </div>
  );
}