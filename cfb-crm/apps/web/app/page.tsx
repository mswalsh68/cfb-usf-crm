'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Image from 'next/image';
import { globalApi, getApiError } from '@/lib/api';
import { setTokens } from '@/lib/auth';
import { triggerThemeRefresh } from '@/components/ThemeProvider';

const GOLD   = '#B8973D';
const GOLD_L = '#D4AF5A';
const BLACK  = '#0D0D0D';
const CARD_D = '#111111';
const BORDER = '#2A2A2A';

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail]       = useState('');
  const [password, setPassword] = useState('');
  const [error, setError]       = useState('');
  const [loading, setLoading]   = useState(false);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const { data } = await globalApi.post('/auth/login', { email, password });
      setTokens(data.data.accessToken, data.data.refreshToken);
      triggerThemeRefresh();
      router.push('/dashboard');
    } catch (err: unknown) {
      setError(getApiError(err, 'Login failed. Please try again.'));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="relative min-h-screen flex items-center justify-center px-4 py-12">

      {/* Full-screen background image */}
      <Image
        src="/login-background.jpg"
        alt=""
        fill
        priority
        unoptimized
        style={{ objectFit: 'cover', objectPosition: 'center' }}
      />

      {/* Dark scrim over background */}
      <div className="absolute inset-0" style={{ backgroundColor: 'rgba(0,0,0,0.62)' }} />

      {/* Card */}
      <div
        className="relative w-full max-w-md rounded-2xl overflow-hidden"
        style={{ boxShadow: '0 32px 80px rgba(0,0,0,0.8)' }}
      >

        {/* ── Top: white logo panel ── */}
        <div
          className="flex items-center justify-center px-6 py-8"
          style={{ backgroundColor: '#FFFFFF' }}
        >
          <Image
            src="/logo-full.jpg"
            alt="LegacyLink — Where rosters become legacies"
            width={420}
            height={160}
            priority
            unoptimized
            style={{ objectFit: 'contain', width: '100%', height: 'auto' }}
          />
        </div>

        {/* Gold divider */}
        <div style={{ height: 3, backgroundColor: GOLD }} />

        {/* ── Bottom: dark form panel ── */}
        <div className="px-8 py-8" style={{ backgroundColor: CARD_D }}>

          <h2
            className="text-base font-semibold mb-6 tracking-wide"
            style={{ color: 'rgba(255,255,255,0.65)' }}
          >
            Sign in to your account
          </h2>

          <form onSubmit={handleLogin} className="space-y-5">

            {error && (
              <div
                className="px-4 py-3 rounded-lg text-sm"
                style={{
                  backgroundColor: 'rgba(192,57,43,0.15)',
                  color: '#E74C3C',
                  border: '1px solid rgba(192,57,43,0.3)',
                }}
              >
                {error}
              </div>
            )}

            <div>
              <label
                className="block text-xs font-semibold uppercase tracking-widest mb-2"
                style={{ color: 'rgba(255,255,255,0.4)' }}
              >
                Email
              </label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@yourprogram.com"
                required
                className="w-full rounded-lg px-4 py-3 text-white placeholder-gray-600 focus:outline-none transition-all"
                style={{ backgroundColor: BLACK, border: `1.5px solid ${BORDER}` }}
                onFocus={e => (e.target.style.borderColor = GOLD)}
                onBlur={e  => (e.target.style.borderColor = BORDER)}
              />
            </div>

            <div>
              <label
                className="block text-xs font-semibold uppercase tracking-widest mb-2"
                style={{ color: 'rgba(255,255,255,0.4)' }}
              >
                Password
              </label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••••"
                required
                className="w-full rounded-lg px-4 py-3 text-white placeholder-gray-600 focus:outline-none transition-all"
                style={{ backgroundColor: BLACK, border: `1.5px solid ${BORDER}` }}
                onFocus={e => (e.target.style.borderColor = GOLD)}
                onBlur={e  => (e.target.style.borderColor = BORDER)}
              />
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full py-3 rounded-lg font-bold text-sm uppercase tracking-widest transition-all disabled:opacity-50 disabled:cursor-not-allowed mt-2"
              style={{ backgroundColor: loading ? '#8a6e2a' : GOLD, color: BLACK }}
              onMouseEnter={e => { if (!loading) (e.currentTarget.style.backgroundColor = GOLD_L); }}
              onMouseLeave={e => { if (!loading) (e.currentTarget.style.backgroundColor = GOLD);   }}
            >
              {loading ? 'Signing in…' : 'Sign In'}
            </button>

          </form>

          <p className="text-center text-xs mt-6" style={{ color: 'rgba(255,255,255,0.2)' }}>
            Contact your program administrator for access.
          </p>

        </div>
      </div>

      {/* Footer */}
      <p
        className="absolute bottom-4 text-xs"
        style={{ color: 'rgba(255,255,255,0.25)' }}
      >
        &copy; {new Date().getFullYear()} LegacyLink &mdash; All rights reserved
      </p>

    </div>
  );
}
