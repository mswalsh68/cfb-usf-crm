'use client';

import { USF } from '@/lib/theme';

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
        <label style={{ fontSize: 13, fontWeight: 500, color: USF.gray600 }}>
          {label}{required && <span style={{ color: USF.danger }}> *</span>}
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
          border: `1.5px solid ${error ? USF.danger : USF.gray200}`,
          borderRadius: 10,
          padding: '10px 14px',
          fontSize: 14,
          color: USF.gray900,
          backgroundColor: disabled ? USF.gray50 : USF.white,
          outline: 'none',
          width: '100%',
          boxSizing: 'border-box',
        }}
      />
      {error  && <span style={{ fontSize: 12, color: USF.danger }}>{error}</span>}
      {helper && !error && <span style={{ fontSize: 12, color: USF.gray400 }}>{helper}</span>}
    </div>
  );
}
