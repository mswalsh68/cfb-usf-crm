'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { isLoggedIn } from '@/lib/auth';
import Nav from './Nav';
import { USF } from '@/lib/theme';

interface PageLayoutProps {
  children:      React.ReactNode;
  currentPage?:  string;
  requireAuth?:  boolean;
}

export default function PageLayout({ children, currentPage, requireAuth = true }: PageLayoutProps) {
  const router = useRouter();

  useEffect(() => {
    if (requireAuth && !isLoggedIn()) {
      router.push('/');
    }
  }, []);

  return (
    <div style={{ minHeight: '100vh', backgroundColor: USF.pageBg }}>
      <Nav currentPage={currentPage} />
      <div style={{ maxWidth: 1200, margin: '0 auto', padding: '32px 24px' }}>
        {children}
      </div>
    </div>
  );
}
