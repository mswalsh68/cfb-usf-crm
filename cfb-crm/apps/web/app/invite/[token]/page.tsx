'use client';

import React, { useEffect, useState } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { globalApi } from '@/lib/api';
import { theme } from '@/lib/theme';
import { Button, Input, Alert } from '@/components';
import { useTeamConfig } from '@/lib/teamConfig';

type Step = 'loading' | 'invalid' | 'form' | 'done';

export default function AcceptInvitePage() {
  const router              = useRouter();
  const { token }           = useParams<{ token: string }>();
  const { teamName, teamAbbr } = useTeamConfig();

  const [step,      setStep]      = useState<Step>('loading');
  const [userInfo,  setUserInfo]  = useState<{ firstName: string; lastName: string; email: string } | null>(null);
  const [password,  setPassword]  = useState('');
  const [confirm,   setConfirm]   = useState('');
  const [saving,    setSaving]    = useState(false);
  const [error,     setError]     = useState('');

  useEffect(() => {
    if (!token) return;
    globalApi.get(`/auth/invite/${token}`)
      .then(({ data }) => { setUserInfo(data.data); setStep('form'); })
      .catch(() => setStep('invalid'));
  }, [token]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (password.length < 10) { setError('Password must be at least 10 characters.'); return; }
    if (password !== confirm)  { setError('Passwords do not match.');                  return; }
    setSaving(true);
    setError('');
    try {
      const { data } = await globalApi.post('/auth/accept-invite', { token, password });
      setStep('done');
      // Redirect to login with email prefilled after a short delay
      setTimeout(() => router.push(`/?email=${encodeURIComponent(data.data.email)}`), 2000);
    } catch (err: any) {
      setError(err?.response?.data?.error ?? 'Something went wrong. The link may have expired.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div style={{
      minHeight: '100vh',
      backgroundColor: 'var(--color-primary)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      padding: 24,
    }}>
      <div style={{
        backgroundColor: theme.white,
        borderRadius: 'var(--radius-lg)',
        boxShadow: 'var(--shadow-xl)',
        padding: '40px 36px',
        width: '100%',
        maxWidth: 400,
      }}>
        {/* Logo / brand */}
        <div style={{ textAlign: 'center', marginBottom: 28 }}>
          <div style={{
            width: 56, height: 56, borderRadius: 14,
            backgroundColor: 'var(--color-accent)',
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 20, fontWeight: 800, color: 'var(--color-primary)',
            marginBottom: 12,
          }}>
            {teamAbbr}
          </div>
          <h1 style={{ fontSize: 20, fontWeight: 700, color: theme.gray900, margin: 0 }}>
            {teamName}
          </h1>
        </div>

        {step === 'loading' && (
          <p style={{ textAlign: 'center', color: theme.gray400, fontSize: 14 }}>Validating invite link…</p>
        )}

        {step === 'invalid' && (
          <>
            <Alert message="This invite link is invalid or has expired. Contact your program administrator for a new one." variant="error" />
            <div style={{ marginTop: 16 }}>
              <Button label="Back to Login" variant="outline" fullWidth onClick={() => router.push('/')} />
            </div>
          </>
        )}

        {step === 'form' && userInfo && (
          <>
            <p style={{ fontSize: 15, color: theme.gray700, textAlign: 'center', marginBottom: 24 }}>
              Welcome, <strong>{userInfo.firstName}</strong>! Set your password to activate your account.
            </p>
            {error && <Alert message={error} variant="error" onClose={() => setError('')} />}
            <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <div style={{ backgroundColor: theme.gray50, borderRadius: 8, padding: '10px 14px', fontSize: 13, color: theme.gray600 }}>
                {userInfo.email}
              </div>
              <Input
                label="New Password"
                type="password"
                value={password}
                onChange={setPassword}
                placeholder="Minimum 10 characters"
                required
              />
              <Input
                label="Confirm Password"
                type="password"
                value={confirm}
                onChange={setConfirm}
                placeholder="Re-enter password"
                required
              />
              <Button
                label={saving ? 'Setting password…' : 'Set Password & Continue'}
                type="submit"
                loading={saving}
                fullWidth
              />
            </form>
          </>
        )}

        {step === 'done' && (
          <div style={{ textAlign: 'center' }}>
            <div style={{ fontSize: 40, marginBottom: 12 }}>✓</div>
            <h2 style={{ fontSize: 18, fontWeight: 700, color: theme.gray900, margin: '0 0 8px' }}>
              Password set!
            </h2>
            <p style={{ fontSize: 14, color: theme.gray500 }}>Redirecting to login…</p>
          </div>
        )}
      </div>
    </div>
  );
}
