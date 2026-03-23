'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { isGlobalAdmin } from '@/lib/auth';

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();

  useEffect(() => {
    if (!isGlobalAdmin()) router.push('/dashboard');
  }, []);

  return <>{children}</>;
}
