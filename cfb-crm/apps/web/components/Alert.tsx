'use client';

import React from 'react';

interface AlertProps {
  message:  string;
  variant:  'success' | 'error' | 'warning';
  onClose?: () => void;
}

const alertStyles: Record<string, React.CSSProperties> = {
  success: { backgroundColor: 'var(--color-success-light)', color: 'var(--color-primary-dark)',  border: '1px solid var(--color-primary-light)' },
  error:   { backgroundColor: 'var(--color-danger-light)',  color: 'var(--color-danger)',        border: '1px solid var(--color-danger-light)'  },
  warning: { backgroundColor: 'var(--color-warning-light)', color: 'var(--color-warning)',       border: '1px solid var(--color-accent-light)'  },
};

export default function Alert({ message, variant, onClose }: AlertProps) {
  return (
    <div
      role="alert"
      aria-live="polite"
      style={{
        ...alertStyles[variant],
        borderRadius:   'var(--radius-md)',
        padding:        '12px 16px',
        fontSize:       14,
        display:        'flex',
        alignItems:     'center',
        justifyContent: 'space-between',
        marginBottom:   16,
      }}
    >
      <span>{message}</span>
      {onClose && (
        <button
          onClick={onClose}
          aria-label="Dismiss"
          style={{ background: 'none', border: 'none', cursor: 'pointer', fontWeight: 700, fontSize: 18, lineHeight: 1, marginLeft: 12, color: 'inherit' }}
        >
          ×
        </button>
      )}
    </div>
  );
}
