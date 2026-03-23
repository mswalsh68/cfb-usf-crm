'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { theme } from '@/lib/theme';
import { Button } from '@/components';

export default function UnauthorizedPage() {
  const router = useRouter();

  return (
    <div style={{
      minHeight: '100vh',
      backgroundColor: theme.pageBg,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      padding: 24,
    }}>
      <div style={{
        backgroundColor: theme.cardBg,
        border: `1px solid ${theme.cardBorder}`,
        borderRadius: 'var(--radius-lg)',
        boxShadow: 'var(--shadow-md)',
        padding: '48px 40px',
        maxWidth: 440,
        width: '100%',
        textAlign: 'center',
      }}>
        <div style={{
          width: 64, height: 64, borderRadius: 16,
          backgroundColor: `color-mix(in srgb, var(--color-danger) 12%, transparent)`,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          margin: '0 auto 20px',
          fontSize: 28,
        }}>
          🔒
        </div>

        <h1 style={{ fontSize: 22, fontWeight: 700, color: theme.gray900, margin: '0 0 10px' }}>
          Access Denied
        </h1>
        <p style={{ fontSize: 14, color: theme.gray500, lineHeight: 1.6, margin: '0 0 28px' }}>
          You don&apos;t have permission to view this page.
          Contact your program administrator if you believe this is a mistake.
        </p>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <Button label="Go to Dashboard" onClick={() => router.push('/dashboard')} fullWidth />
          <Button label="Go Back" variant="ghost" onClick={() => router.back()} fullWidth />
        </div>
      </div>
    </div>
  );
}
