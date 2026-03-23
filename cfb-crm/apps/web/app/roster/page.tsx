'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { rosterApi } from '@/lib/api';
import { isGlobalAdmin } from '@/lib/auth';
import { theme } from '@/lib/theme';
import { PageLayout, Button, Input, Select, Badge, Alert } from '@/components';

const POSITIONS = ['All','QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH'];
const STATUSES  = [
  { value: '',           label: 'All Statuses' },
  { value: 'active',     label: 'Active'       },
  { value: 'injured',    label: 'Injured'      },
  { value: 'suspended',  label: 'Suspended'    },
  { value: 'transferred',label: 'Transferred'  },
  { value: 'walkOn',     label: 'Walk-On'      },
  { value: 'graduated',  label: 'Graduated'    },
];
const YEARS = [
  { value: '',           label: 'All Years'   },
  { value: 'freshman',   label: 'Freshman'    },
  { value: 'sophomore',  label: 'Sophomore'   },
  { value: 'junior',     label: 'Junior'      },
  { value: 'senior',     label: 'Senior'      },
  { value: 'graduate',   label: 'Graduate'    },
];

const statusBadge = (status: string) => {
  const map: Record<string, 'green' | 'warning' | 'danger' | 'gray' | 'gold'> = {
    active:      'green',
    injured:     'warning',
    suspended:   'danger',
    transferred: 'gray',
    walkOn:      'gold',
  };
  return map[status] ?? 'gray';
};

export default function RosterPage() {
  const router = useRouter();
  const [players,  setPlayers]  = useState<any[]>([]);
  const [loading,  setLoading]  = useState(true);
  const [error,    setError]    = useState('');
  const [search,   setSearch]   = useState('');
  const [position, setPosition] = useState('All');
  const [status,   setStatus]   = useState('active');
  const [year,     setYear]     = useState('');
  const [total,    setTotal]    = useState(0);
  const [page,     setPage]     = useState(1);

  useEffect(() => {
    fetchPlayers();
  }, [search, position, status, year, page]);

  const fetchPlayers = async () => {
    setLoading(true);
    try {
      const params: any = { page, pageSize: 50 };
      if (search)            params.search      = search;
      if (position !== 'All') params.position   = position;
      if (status)            params.status      = status;
      if (year)              params.academicYear = year;
      const { data } = await rosterApi.get('/players', { params });
      setPlayers(data.data ?? []);
      setTotal(data.total ?? 0);
    } catch {
      setError('Failed to load players. Make sure the Roster API is running.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <PageLayout currentPage="Roster CRM">

      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <div>
          <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>Roster</h1>
          <p style={{ fontSize: 14, color: theme.gray500, marginTop: 4 }}>{total} players</p>
        </div>
        {isGlobalAdmin() && (
          <div style={{ display: 'flex', gap: 10 }}>
            <Button label="Upload Players"    variant="outline" onClick={() => router.push('/roster/upload')}   />
            <Button label="Transfer to Alumni" variant="outline" onClick={() => router.push('/roster/transfer')} />
            <Button label="+ Add Player"                        onClick={() => router.push('/roster/add')}      />
          </div>
        )}
      </div>

      {error && <Alert message={error} variant="error" onClose={() => setError('')} />}

      {/* Filters */}
      <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr 1fr 1fr', gap: 12, marginBottom: 16 }}>
        <Input
          value={search}
          onChange={(v) => { setSearch(v); setPage(1); }}
          placeholder="Search name or jersey #..."
        />
        <Select
          value={status}
          onChange={(v) => { setStatus(v); setPage(1); }}
          options={STATUSES}
        />
        <Select
          value={year}
          onChange={(v) => { setYear(v); setPage(1); }}
          options={YEARS}
        />
        <Select
          value={position}
          onChange={(v) => { setPosition(v); setPage(1); }}
          options={[{ value: 'All', label: 'All Positions' }, ...POSITIONS.slice(1).map(p => ({ value: p, label: p }))]}
        />
      </div>

      {/* Player table */}
      <div style={{ backgroundColor: theme.white, borderRadius: 16, border: `1px solid ${theme.cardBorder}`, overflow: 'hidden' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ backgroundColor: theme.gray50, borderBottom: `1px solid ${theme.gray200}` }}>
              {['#', 'Name', 'Position', 'Year', 'Status', 'GPA', ''].map((h) => (
                <th key={h} style={{ textAlign: 'left', padding: '12px 20px', fontSize: 11, fontWeight: 600, color: theme.gray500, textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={7} style={{ textAlign: 'center', padding: 48, color: theme.gray400 }}>Loading...</td></tr>
            ) : players.length === 0 ? (
              <tr><td colSpan={7} style={{ textAlign: 'center', padding: 48, color: theme.gray400 }}>No players found</td></tr>
            ) : players.map((player, i) => (
              <tr
                key={player.id}
                onClick={() => router.push(`/roster/${player.id}`)}
                style={{
                  borderBottom: `1px solid ${theme.gray100}`,
                  backgroundColor: i % 2 === 0 ? theme.white : theme.gray50,
                  cursor: 'pointer',
                  transition: 'background-color 0.1s',
                }}
                onMouseEnter={e => (e.currentTarget.style.backgroundColor = theme.primaryLight)}
                onMouseLeave={e => (e.currentTarget.style.backgroundColor = i % 2 === 0 ? theme.white : theme.gray50)}
              >
                {/* Jersey */}
                <td style={{ padding: '12px 20px' }}>
                  <div style={{ width: 36, height: 36, borderRadius: 8, backgroundColor: theme.primary, display: 'flex', alignItems: 'center', justifyContent: 'center', color: theme.white, fontSize: 13, fontWeight: 700 }}>
                    {player.jerseyNumber ?? '—'}
                  </div>
                </td>

                {/* Name */}
                <td style={{ padding: '12px 20px' }}>
                  <span style={{ fontWeight: 600, fontSize: 14, color: theme.gray900 }}>
                    {player.lastName}, {player.firstName}
                  </span>
                  {player.major && (
                    <div style={{ fontSize: 12, color: theme.gray400, marginTop: 2 }}>{player.major}</div>
                  )}
                </td>

                {/* Position */}
                <td style={{ padding: '12px 20px' }}>
                  <span style={{ fontWeight: 700, fontSize: 13, color: theme.primary }}>{player.position}</span>
                </td>

                {/* Year */}
                <td style={{ padding: '12px 20px', fontSize: 13, color: theme.gray600, textTransform: 'capitalize' }}>
                  {player.academicYear ?? '—'}
                </td>

                {/* Status */}
                <td style={{ padding: '12px 20px' }}>
                  <Badge label={player.status} variant={statusBadge(player.status)} />
                </td>

                {/* GPA */}
                <td style={{ padding: '12px 20px', fontSize: 13, color: theme.gray600 }}>
                  {player.gpa != null ? player.gpa.toFixed(2) : '—'}
                </td>

                {/* Arrow */}
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
            <Button label="← Previous" variant="outline" size="sm" disabled={page === 1}    onClick={() => setPage(p => p - 1)} />
            <Button label="Next →"     variant="outline" size="sm" disabled={page * 50 >= total} onClick={() => setPage(p => p + 1)} />
          </div>
        </div>
      )}

    </PageLayout>
  );
}