'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { hasAppAccess, isGlobalAdmin } from '@/lib/auth';

export default function AlumniLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();

  useEffect(() => {
    if (!hasAppAccess('alumni') && !isGlobalAdmin()) router.push('/dashboard');
  }, []);

  return <>{children}</>;
}
