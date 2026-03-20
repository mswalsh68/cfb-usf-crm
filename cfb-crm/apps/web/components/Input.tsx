'use client';

import React from 'react';

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
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
      {label && (
        <label style={{ fontSize: 13, fontWeight: 500, color: 'var(--color-gray-600)' }}>
          {label}{required && <span style={{ color: 'var(--color-danger)' }}> *</span>}
        </label>
      )}
      <input
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        required={required}
        disabled={disabled}
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
      {error  && <span style={{ fontSize: 12, color: 'var(--color-danger)' }}>{error}</span>}
      {helper && !error && <span style={{ fontSize: 12, color: 'var(--color-gray-400)' }}>{helper}</span>}
    </div>
  );
}