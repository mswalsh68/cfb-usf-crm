'use client';

import dynamic from 'next/dynamic';
import { PageLayout } from '@/components';
import { theme } from '@/lib/theme';

const DashboardContent = dynamic(() => import('./DashboardContent'), {
  ssr: false,
  loading: () => (
    <div style={{ padding: '40px', textAlign: 'center', color: theme.primaryDark }}>
      Loading your dashboard...
    </div>
  ),
});

export default function DashboardPage() {
  return (
    <PageLayout>
      <DashboardContent />
    </PageLayout>
  );
}