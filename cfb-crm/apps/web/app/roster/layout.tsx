'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { hasAppAccess, isGlobalAdmin } from '@/lib/auth';

export default function RosterLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();

  useEffect(() => {
    if (!hasAppAccess('roster') && !isGlobalAdmin()) router.push('/dashboard');
  }, []);

  return <>{children}</>;
}
