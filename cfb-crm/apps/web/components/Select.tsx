'use client';

import { USF } from '@/lib/theme';

interface SelectOption {
  value: string;
  label: string;
}

interface SelectProps {
  label?:    string;
  value:     string;
  onChange:  (val: string) => void;
  options:   SelectOption[];
  required?: boolean;
  disabled?: boolean;
}

export default function Select({ label, value, onChange, options, required, disabled }: SelectProps) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
      {label && (
        <label style={{ fontSize: 13, fontWeight: 500, color: USF.gray600 }}>
          {label}{required && <span style={{ color: USF.danger }}> *</span>}
        </label>
      )}
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        required={required}
        disabled={disabled}
        style={{
          border: `1.5px solid ${USF.gray200}`,
          borderRadius: 10,
          padding: '10px 14px',
          fontSize: 14,
          color: USF.gray900,
          backgroundColor: disabled ? USF.gray50 : USF.white,
          outline: 'none',
          width: '100%',
          boxSizing: 'border-box',
        }}
      >
        {options.map((opt) => (
          <option key={opt.value} value={opt.value}>{opt.label}</option>
        ))}
      </select>
    </div>
  );
}
