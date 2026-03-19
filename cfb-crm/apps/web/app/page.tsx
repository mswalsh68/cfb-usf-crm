'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { globalApi } from '@/lib/api';
import { setTokens } from '@/lib/auth';

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const { data } = await globalApi.post('/auth/login', { email, password });
      setTokens(data.data.accessToken, data.data.refreshToken);
      router.push('/dashboard');
    } catch (err: any) {
      setError(err?.response?.data?.error ?? 'Login failed. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center px-4" style={{ backgroundColor: '#006747' }}>
      <div className="w-full max-w-md">

        {/* Logo */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-20 h-20 rounded-xl mb-4" style={{ backgroundColor: '#CFC493' }}>
            <span className="text-2xl font-bold" style={{ color: '#006747' }}>USF</span>
          </div>
          <h1 className="text-white text-3xl font-bold">Bulls Team Portal</h1>
          <p className="mt-1" style={{ color: 'rgba(255,255,255,0.65)' }}>Sign in to continue</p>
        </div>

        {/* Form */}
        <div className="bg-white rounded-2xl p-8 shadow-xl">
          <form onSubmit={handleLogin} className="space-y-5">

            {error && (
              <div className="px-4 py-3 rounded-lg text-sm" style={{ backgroundColor: '#FDECEA', color: '#C0392B', border: '1px solid #f5c6c6' }}>
                {error}
              </div>
            )}

            <div>
              <label className="block text-sm font-medium mb-1" style={{ color: '#4B5563' }}>
                Email
              </label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="coach@usf.edu"
                required
                className="w-full rounded-lg px-4 py-3 text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2"
                style={{ border: '1.5px solid #E5E7EB'}}
              />
            </div>

            <div>
              <label className="block text-sm font-medium mb-1" style={{ color: '#4B5563' }}>
                Password
              </label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                required
                className="w-full rounded-lg px-4 py-3 text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2"
                style={{ border: '1.5px solid #E5E7EB' }}
              />
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full text-white py-3 rounded-lg font-semibold text-base transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
              style={{ backgroundColor: loading ? '#005432' : '#006747' }}
            >
              {loading ? 'Signing in...' : 'Sign In'}
            </button>

          </form>

          <p className="text-center text-sm mt-6" style={{ color: '#9CA3AF' }}>
            Contact your program administrator for access.
          </p>
        </div>

      </div>
    </div>
  );
}