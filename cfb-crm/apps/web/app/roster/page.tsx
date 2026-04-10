'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import type { Player } from '@cfb-crm/types';
import { appApi } from '@/lib/api';
import { isGlobalAdmin } from '@/lib/auth';
import { theme } from '@/lib/theme';
import { PageLayout, Button, Input, Select, Badge, Alert } from '@/components';
import { useTeamConfig } from '@/lib/teamConfig';


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

interface Sport { id: string; name: string; abbr: string; }

export default function RosterPage() {
  const router = useRouter();
  const { positions, academicYears } = useTeamConfig();
  const [players,  setPlayers]  = useState<Player[]>([]);
  const [loading,  setLoading]  = useState(true);
  const [error,    setError]    = useState('');
  const [search,   setSearch]   = useState('');
  const [position, setPosition] = useState('All');
  const status = 'active';
  const [year,     setYear]     = useState('');
  const [sportId,  setSportId]  = useState('');
  const [sports,   setSports]   = useState<Sport[]>([]);
  const [total,    setTotal]    = useState(0);
  const [page,     setPage]     = useState(1);

  // Fetch available sports once on mount
  useEffect(() => {
    appApi.get('/sports')
      .then(({ data }) => setSports(data.data ?? []))
      .catch(() => { /* sports filter hidden if endpoint unavailable */ });
  }, []);

  useEffect(() => {
    fetchPlayers();
  }, [search, position, year, sportId, page]);

  const fetchPlayers = async () => {
    setLoading(true);
    try {
      const params: Record<string, string | number> = { page, pageSize: 50 };
      if (search)             params.search      = search;
      if (position !== 'All') params.position    = position;
      if (status)             params.status      = status;
      if (year)               params.academicYear = year;
      if (sportId)            params.sportId     = sportId;
      const { data } = await appApi.get('/players', { params });
      setPlayers(data.data ?? []);
      setTotal(data.total ?? 0);
    } catch {
      setError('Failed to load players. Make sure the app API is running.');
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
      <div style={{ display: 'grid', gridTemplateColumns: sports.length > 1 ? '2fr 1fr 1fr 1fr' : '2fr 1fr 1fr', gap: 12, marginBottom: 16 }}>
        <Input
          value={search}
          onChange={(v) => { setSearch(v); setPage(1); }}
          placeholder="Search name or jersey #..."
        />
        {sports.length > 1 && (
          <Select
            value={sportId}
            onChange={(v) => { setSportId(v); setPage(1); }}
            options={[{ value: '', label: 'All Sports' }, ...sports.map(s => ({ value: s.id, label: s.name }))]}
          />
        )}
        <Select
          value={year}
          onChange={(v) => { setYear(v); setPage(1); }}
          options={[{ value: '', label: 'All Years' }, ...academicYears]}
        />
        <Select
          value={position}
          onChange={(v) => { setPosition(v); setPage(1); }}
          options={[{ value: 'All', label: 'All Positions' }, ...positions.map(p => ({ value: p, label: p }))]}
        />
      </div>

      {/* Player table */}
      <div style={{ backgroundColor: theme.white, borderRadius: 16, border: `1px solid ${theme.cardBorder}`, overflow: 'hidden' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }} aria-label="Player roster">
          <thead>
            <tr style={{ backgroundColor: theme.gray50, borderBottom: `1px solid ${theme.gray200}` }}>
              {['#', 'Name', 'Position', 'Year', 'Status', 'GPA', ''].map((h) => (
                <th key={h} scope="col" style={{ textAlign: 'left', padding: '12px 20px', fontSize: 11, fontWeight: 600, color: theme.gray500, textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  {h || <span className="sr-only">Actions</span>}
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
                onKeyDown={e => { if (e.key === 'Enter' || e.key === ' ') router.push(`/roster/${player.id}`); }}
                tabIndex={0}
                role="button"
                aria-label={`View ${player.firstName} ${player.lastName}`}
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