'use client';

import React, { useEffect, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import { appApi } from '@/lib/api';
import { useTeamConfig } from '@/lib/teamConfig';
import { theme } from '@/lib/theme';

// This page is intentionally NOT wrapped in any auth guard.
// It must be accessible to anyone who clicks an unsubscribe link in an email.

type State = 'loading' | 'success' | 'already' | 'error';

export default function UnsubscribePage() {
  const params        = useSearchParams();
  const { teamName }  = useTeamConfig();
  const token         = params.get('token');
  const db            = params.get('db');
  const [state, setState] = useState<State>('loading');
  const [firstName,   setFirstName] = useState('');

  useEffect(() => {
    if (!token || !db) { setState('error'); return; }
    const doUnsubscribe = async () => {
      try {
        const { data } = await appApi.post('/unsubscribe', { token, db }, { withCredentials: false });
        if (data.success) {
          setFirstName(data.data?.firstName ?? '');
          setState('success');
        } else if (data.error === 'INVALID_TOKEN') {
          setState('error');
        } else {
          setState('already');
        }
      } catch {
        setState('error');
      }
    };
    doUnsubscribe();
  }, [token, db]);

  return (
    <div style={{
      minHeight:       '100vh',
      display:         'flex',
      alignItems:      'center',
      justifyContent:  'center',
      backgroundColor: theme.pageBg,
      padding:         24,
    }}>
      <div style={{
        maxWidth:        480,
        width:           '100%',
        backgroundColor: theme.cardBg,
        border:          `1px solid ${theme.cardBorder}`,
        borderRadius:    'var(--radius-lg)',
        padding:         '40px 36px',
        textAlign:       'center',
      }}>
        {/* Logo/brand */}
        <div style={{
          width:           48,
          height:          48,
          borderRadius:    12,
          backgroundColor: 'var(--color-primary)',
          display:         'inline-flex',
          alignItems:      'center',
          justifyContent:  'center',
          marginBottom:    20,
        }}>
          <span style={{ color: '#fff', fontSize: 22, fontWeight: 700 }}>✉</span>
        </div>

        {state === 'loading' && (
          <>
            <h1 style={{ fontSize: 20, fontWeight: 700, color: theme.gray900, margin: '0 0 8px' }}>Processing...</h1>
            <p style={{ color: theme.gray500, fontSize: 14 }}>Please wait while we process your request.</p>
          </>
        )}

        {state === 'success' && (
          <>
            <h1 style={{ fontSize: 20, fontWeight: 700, color: theme.gray900, margin: '0 0 8px' }}>
              {firstName ? `${firstName}, you've been unsubscribed.` : 'You\'ve been unsubscribed.'}
            </h1>
            <p style={{ color: theme.gray500, fontSize: 14, lineHeight: 1.6 }}>
              You will no longer receive mass emails from <strong>{teamName || 'this team portal'}</strong>.
              You may still receive individual messages from your coaching staff.
            </p>
          </>
        )}

        {state === 'already' && (
          <>
            <h1 style={{ fontSize: 20, fontWeight: 700, color: theme.gray900, margin: '0 0 8px' }}>Already unsubscribed</h1>
            <p style={{ color: theme.gray500, fontSize: 14 }}>
              You are already unsubscribed from {teamName || 'this team portal'} emails.
            </p>
          </>
        )}

        {state === 'error' && (
          <>
            <h1 style={{ fontSize: 20, fontWeight: 700, color: theme.danger, margin: '0 0 8px' }}>Invalid link</h1>
            <p style={{ color: theme.gray500, fontSize: 14 }}>
              This unsubscribe link is invalid or has already been used.
              If you continue to receive unwanted emails, please contact your coaching staff directly.
            </p>
          </>
        )}
      </div>
    </div>
  );
}
