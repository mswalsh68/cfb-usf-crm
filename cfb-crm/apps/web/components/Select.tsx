'use client';

import React, { useId } from 'react';

interface SelectOption { value: string; label: string; }

interface SelectProps {
  label?:    string;
  value:     string;
  onChange:  (val: string) => void;
  options:   SelectOption[];
  required?: boolean;
  disabled?: boolean;
  error?:    string;
}

export default function Select({ label, value, onChange, options, required, disabled, error }: SelectProps) {
  const id      = useId();
  const errorId = `${id}-error`;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
      {label && (
        <label htmlFor={id} style={{ fontSize: 13, fontWeight: 500, color: 'var(--color-gray-600)' }}>
          {label}{required && <span style={{ color: 'var(--color-danger)' }} aria-hidden="true"> *</span>}
        </label>
      )}
      <select
        id={id}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        required={required}
        disabled={disabled}
        aria-invalid={error ? 'true' : undefined}
        aria-describedby={error ? errorId : undefined}
        style={{
          border:          `1.5px solid ${error ? 'var(--color-danger)' : 'var(--color-gray-200)'}`,
          borderRadius:    'var(--radius-sm)',
          padding:         '10px 14px',
          fontSize:        14,
          color:           'var(--color-gray-900)',
          backgroundColor: disabled ? 'var(--color-gray-50)' : 'var(--color-card-bg)',
          outline:         'none',
          width:           '100%',
          boxSizing:       'border-box',
        }}
      >
        {options.map((opt) => (
          <option key={opt.value} value={opt.value}>{opt.label}</option>
        ))}
      </select>
      {error && <span id={errorId} role="alert" style={{ fontSize: 12, color: 'var(--color-danger)' }}>{error}</span>}
    </div>
  );
}
