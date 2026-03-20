'use client';

import React, { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { isLoggedIn } from '@/lib/auth';
import Nav from './Nav';

interface PageLayoutProps {
  children:     React.ReactNode;
  currentPage?: string;
  requireAuth?: boolean;
  fullWidth?:   boolean;
}

export default function PageLayout({ children, currentPage, requireAuth = true, fullWidth = false }: PageLayoutProps) {
  const router = useRouter();

  useEffect(() => {
    if (requireAuth && !isLoggedIn()) router.push('/');
  }, []);

  return (
    <div style={{ minHeight: '100vh', backgroundColor: 'var(--color-page-bg)' }}>
      <Nav currentPage={currentPage} />
      <div style={{
        maxWidth:  fullWidth ? '100%' : 1200,
        margin:    '0 auto',
        padding:   fullWidth ? '32px 0' : '32px 24px',
      }}>
        {children}
      </div>
    </div>
  );
}