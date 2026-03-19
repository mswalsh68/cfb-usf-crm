'use client';

import { USF } from '@/lib/theme';

interface AlertProps {
  message:  string;
  variant:  'success' | 'error' | 'warning';
  onClose?: () => void;
}

const alertStyles = {
  success: { backgroundColor: USF.greenLight, color: USF.evergreen, borderColor: '#b7dfc9' },
  error:   { backgroundColor: USF.dangerLight, color: USF.danger,   borderColor: '#f5c6c6' },
  warning: { backgroundColor: USF.sandLight,  color: USF.goldDark,  borderColor: '#e8dfa8' },
};

export default function Alert({ message, variant, onClose }: AlertProps) {
  const style = alertStyles[variant];
  return (
    <div style={{
      ...style,
      border:       `1px solid ${style.borderColor}`,
      borderRadius: 12,
      padding:      '12px 16px',
      fontSize:     14,
      display:      'flex',
      alignItems:   'center',
      justifyContent: 'space-between',
      marginBottom: 16,
    }}>
      <span>{message}</span>
      {onClose && (
        <button onClick={onClose} style={{ background: 'none', border: 'none', cursor: 'pointer', color: style.color, fontWeight: 700, fontSize: 18, lineHeight: 1, marginLeft: 12 }}>
          ×
        </button>
      )}
    </div>
  );
}
