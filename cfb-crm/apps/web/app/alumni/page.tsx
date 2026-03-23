'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { alumniApi } from '@/lib/api';
import { theme } from '@/lib/theme';
import { PageLayout, Button, Input, Select, Badge, Alert } from '@/components';

const STATUS_OPTIONS = [
  { value: '',             label: 'All Statuses'  },
  { value: 'active',       label: 'Active'        },
  { value: 'lostContact',  label: 'Lost Contact'  },
  { value: 'doNotContact', label: 'Do Not Contact'},
  { value: 'deceased',     label: 'Deceased'      },
];

const POSITION_OPTIONS = [
  { value: '', label: 'All Positions' },
  ...['QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH'].map(p => ({ value: p, label: p })),
];

const statusBadge = (status: string): 'green' | 'warning' | 'danger' | 'gray' => {
  const map: Record<string, 'green' | 'warning' | 'danger' | 'gray'> = {
    active: 'green', lostContact: 'warning', doNotContact: 'danger', deceased: 'gray',
  };
  return map[status] ?? 'gray';
};

export default function AlumniPage() {
  const router = useRouter();
  const [alumni,    setAlumni]    = useState<any[]>([]);
  const [loading,   setLoading]   = useState(true);
  const [error,     setError]     = useState('');
  const [search,    setSearch]    = useState('');
  const [status,    setStatus]    = useState('');
  const [position,  setPosition]  = useState('');
  const [isDonor,   setIsDonor]   = useState(false);
  const [total,     setTotal]     = useState(0);
  const [page,      setPage]      = useState(1);

  useEffect(() => {
    fetchAlumni();
  }, [search, status, position, isDonor, page]);

  const fetchAlumni = async () => {
    setLoading(true);
    try {
      const params: any = { page, pageSize: 50 };
      if (search)   params.search   = search;
      if (status)   params.status   = status;
      if (position) params.position = position;
      if (isDonor)  params.isDonor  = 'true';
      const { data } = await alumniApi.get('/alumni', { params });
      setAlumni(data.data ?? []);
      setTotal(data.total ?? 0);
    } catch {
      setError('Failed to load alumni. Make sure the Alumni API is running.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <PageLayout currentPage="Alumni CRM">

      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <div>
          <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>Alumni</h1>
          <p style={{ fontSize: 14, color: theme.gray500, marginTop: 4 }}>{total} records</p>
        </div>
        <div style={{ display: 'flex', gap: 10 }}>
          <Button label="Upload Alumni" variant="outline" onClick={() => router.push('/alumni/upload')} />
          <Button label="+ Add Alumni"  onClick={() => router.push('/alumni/add')} />
        </div>
      </div>

      {error && <Alert message={error} variant="error" onClose={() => setError('')} />}

      {/* Filters */}
      <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr 1fr', gap: 12, marginBottom: 16 }}>
        <Input
          value={search}
          onChange={(v) => { setSearch(v); setPage(1); }}
          placeholder="Search name, employer, city..."
        />
        <Select value={status}   onChange={(v) => { setStatus(v);   setPage(1); }} options={STATUS_OPTIONS}   />
        <Select value={position} onChange={(v) => { setPosition(v); setPage(1); }} options={POSITION_OPTIONS} />
      </div>

      {/* Donor filter */}
      <div style={{ marginBottom: 16 }}>
        <button
          onClick={() => { setIsDonor(v => !v); setPage(1); }}
          style={{
            padding:         '6px 16px',
            borderRadius:    'var(--radius-full)',
            border:          `1.5px solid ${isDonor ? theme.primary : theme.gray200}`,
            backgroundColor: isDonor ? theme.primaryLight : theme.cardBg,
            color:           isDonor ? theme.primaryDark : theme.gray600,
            fontSize:        13,
            fontWeight:      600,
            cursor:          'pointer',
          }}
        >
          ⭐ Donors only
        </button>
      </div>

      {/* Alumni table */}
      <div style={{ backgroundColor: theme.cardBg, borderRadius: 'var(--radius-lg)', border: `1px solid ${theme.cardBorder}`, overflow: 'hidden' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ backgroundColor: theme.gray50, borderBottom: `1px solid ${theme.gray200}` }}>
              {['Class', 'Name', 'Position', 'Employer', 'Location', 'Status', 'Donor', ''].map(h => (
                <th key={h} style={{ textAlign: 'left', padding: '12px 20px', fontSize: 11, fontWeight: 600, color: theme.gray500, textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={8} style={{ textAlign: 'center', padding: 48, color: theme.gray400 }}>Loading...</td></tr>
            ) : alumni.length === 0 ? (
              <tr><td colSpan={8} style={{ textAlign: 'center', padding: 48, color: theme.gray400 }}>No alumni found</td></tr>
            ) : alumni.map((a, i) => (
              <tr
                key={a.id}
                onClick={() => router.push(`/alumni/${a.id}`)}
                style={{
                  borderBottom:    `1px solid ${theme.gray100}`,
                  backgroundColor: i % 2 === 0 ? theme.cardBg : theme.gray50,
                  cursor:          'pointer',
                  transition:      'background-color 0.1s',
                }}
                onMouseEnter={e => (e.currentTarget.style.backgroundColor = theme.primaryLight)}
                onMouseLeave={e => (e.currentTarget.style.backgroundColor = i % 2 === 0 ? theme.cardBg : theme.gray50)}
              >
                {/* Class year bubble */}
                <td style={{ padding: '12px 20px' }}>
                  <div style={{ width: 44, height: 44, borderRadius: 10, backgroundColor: theme.accentLight, display: 'flex', alignItems: 'center', justifyContent: 'center', color: theme.accentDark, fontSize: 12, fontWeight: 700 }}>
                    &apos;{String(a.graduationYear).slice(-2)}
                  </div>
                </td>

                {/* Name */}
                <td style={{ padding: '12px 20px' }}>
                  <div style={{ fontWeight: 600, fontSize: 14, color: theme.gray900 }}>
                    {a.lastName}, {a.firstName}
                  </div>
                  <div style={{ fontSize: 12, color: theme.gray400, marginTop: 2 }}>
                    {a.graduationSemester} {a.graduationYear}
                  </div>
                </td>

                {/* Position */}
                <td style={{ padding: '12px 20px' }}>
                  <span style={{ fontWeight: 700, fontSize: 13, color: theme.primary }}>{a.position}</span>
                </td>

                {/* Employer */}
                <td style={{ padding: '12px 20px', fontSize: 13, color: theme.gray600 }}>
                  {a.currentEmployer ?? '—'}
                  {a.currentJobTitle && <div style={{ fontSize: 11, color: theme.gray400, marginTop: 1 }}>{a.currentJobTitle}</div>}
                </td>

                {/* Location */}
                <td style={{ padding: '12px 20px', fontSize: 13, color: theme.gray600 }}>
                  {a.currentCity && a.currentState ? `${a.currentCity}, ${a.currentState}` : '—'}
                </td>

                {/* Status */}
                <td style={{ padding: '12px 20px' }}>
                  <Badge label={a.status} variant={statusBadge(a.status)} />
                </td>

                {/* Donor */}
                <td style={{ padding: '12px 20px' }}>
                  {a.isDonor ? <Badge label="Donor" variant="gold" /> : <span style={{ color: theme.gray300, fontSize: 13 }}>—</span>}
                </td>

                <td style={{ padding: '12px 20px', color: theme.gray300, fontSize: 18 }}>›</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Pagination */}
      {total > 50 && (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 16 }}>
          <span style={{ fontSize: 13, color: theme.gray500 }}>
            Showing {(page - 1) * 50 + 1}–{Math.min(page * 50, total)} of {total}
          </span>
          <div style={{ display: 'flex', gap: 8 }}>
            <Button label="← Previous" variant="outline" size="sm" disabled={page === 1}         onClick={() => setPage(p => p - 1)} />
            <Button label="Next →"     variant="outline" size="sm" disabled={page * 50 >= total} onClick={() => setPage(p => p + 1)} />
          </div>
        </div>
      )}

    </PageLayout>
  );
}