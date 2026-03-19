'use client';

import { useRouter } from 'next/navigation';
import { clearTokens } from '@/lib/auth';
import { USF } from '@/lib/theme';

interface NavProps {
  currentPage?: string;
}

export default function Nav({ currentPage }: NavProps) {
  const router = useRouter();

  const handleLogout = () => {
    clearTokens();
    router.push('/');
  };

  return (
    <nav className="px-6 py-4 flex items-center justify-between" style={{ backgroundColor: USF.green }}>
      <div className="flex items-center gap-3">
        <button onClick={() => router.push('/dashboard')} className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-lg flex items-center justify-center" style={{ backgroundColor: USF.gold }}>
            <span className="text-xs font-bold" style={{ color: USF.green }}>USF</span>
          </div>
          <span className="font-semibold text-lg text-white">Bulls Team Portal</span>
        </button>
        {currentPage && (
          <>
            <span className="text-white/40 mx-1">/</span>
            <span className="text-white font-medium">{currentPage}</span>
          </>
        )}
      </div>
      <button
        onClick={handleLogout}
        className="px-4 py-1.5 rounded-lg text-sm text-white transition-colors"
        style={{ backgroundColor: 'rgba(255,255,255,0.15)' }}
      >
        Sign Out
      </button>
    </nav>
  );
}
