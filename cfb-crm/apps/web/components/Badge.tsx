'use client';

import { USF } from '@/lib/theme';

type BadgeVariant = 'green' | 'gold' | 'danger' | 'warning' | 'gray';

interface BadgeProps {
  label:    string;
  variant?: BadgeVariant;
}

const badgeStyles: Record<BadgeVariant, { backgroundColor: string; color: string }> = {
  green:   { backgroundColor: USF.greenLight, color: USF.evergreen },
  gold:    { backgroundColor: USF.sand,       color: USF.goldDark  },
  danger:  { backgroundColor: USF.dangerLight, color: USF.danger   },
  warning: { backgroundColor: USF.sandLight,  color: USF.goldDark  },
  gray:    { backgroundColor: USF.gray100,    color: USF.gray600   },
};

export default function Badge({ label, variant = 'gray' }: BadgeProps) {
  const style = badgeStyles[variant];
  return (
    <span style={{
      ...style,
      display:       'inline-block',
      padding:       '3px 10px',
      borderRadius:  9999,
      fontSize:      11,
      fontWeight:    600,
      textTransform: 'uppercase',
      letterSpacing: '0.4px',
      whiteSpace:    'nowrap',
    }}>
      {label}
    </span>
  );
}
