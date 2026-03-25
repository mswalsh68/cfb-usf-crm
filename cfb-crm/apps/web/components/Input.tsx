'use client';

import React, { useId } from 'react';

interface InputProps {
  label?:       string;
  value:        string;
  onChange:     (val: string) => void;
  type?:        string;
  placeholder?: string;
  required?:    boolean;
  error?:       string;
  helper?:      string;
  disabled?:    boolean;
}

export default function Input({
  label, value, onChange, type = 'text',
  placeholder, required, error, helper, disabled,
}: InputProps) {
  const id      = useId();
  const errorId = `${id}-error`;
  const helpId  = `${id}-help`;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
      {label && (
        <label htmlFor={id} style={{ fontSize: 13, fontWeight: 500, color: 'var(--color-gray-600)' }}>
          {label}{required && <span style={{ color: 'var(--color-danger)' }} aria-hidden="true"> *</span>}
        </label>
      )}
      <input
        id={id}
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        required={required}
        disabled={disabled}
        aria-invalid={error ? 'true' : undefined}
        aria-describedby={error ? errorId : helper ? helpId : undefined}
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
          transition:      'border-color 0.15s',
        }}
        onFocus={e => { if (!error) e.target.style.borderColor = 'var(--color-primary)'; }}
        onBlur={e  => { if (!error) e.target.style.borderColor = 'var(--color-gray-200)'; }}
      />
      {error  && <span id={errorId} role="alert" style={{ fontSize: 12, color: 'var(--color-danger)' }}>{error}</span>}
      {helper && !error && <span id={helpId} style={{ fontSize: 12, color: 'var(--color-gray-400)' }}>{helper}</span>}
    </div>
  );
}
