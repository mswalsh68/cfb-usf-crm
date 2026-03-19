'use client';

import { USF } from '@/lib/theme';
import { CSSProperties } from 'react';

interface CardProps {
  children:   React.ReactNode;
  style?:     CSSProperties;
  onClick?:   () => void;
  padded?:    boolean;
  hoverable?: boolean;
}

export default function Card({ children, style, onClick, padded = true, hoverable = false }: CardProps) {
  return (
    <div
      onClick={onClick}
      style={{
        backgroundColor: USF.white,
        border:          `1px solid ${USF.cardBorder}`,
        borderRadius:    16,
        boxShadow:       '0 1px 3px rgba(0,0,0,0.06)',
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
