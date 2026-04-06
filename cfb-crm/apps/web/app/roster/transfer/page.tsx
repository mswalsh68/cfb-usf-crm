'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import type { Player } from '@cfb-crm/types';
import { isGlobalAdmin } from '@/lib/auth';
import { appApi, getApiError } from '@/lib/api';
import { theme } from '@/lib/theme';
import { PageLayout, Button, Select, Alert, Badge } from '@/components';

const SEMESTER_OPTIONS = [
  { value: 'spring', label: 'Spring' },
  { value: 'fall',   label: 'Fall'   },
  { value: 'summer', label: 'Summer' },
];

const currentYear = new Date().getFullYear();
const YEAR_OPTIONS = Array.from({ length: 10 }, (_, i) => ({
  value: String(currentYear - i),
  label: String(currentYear - i),
}));

export default function TransferPage() {
  const router = useRouter();
  const [players,         setPlayers]         = useState<Player[]>([]);
  const [loading,         setLoading]         = useState(true);
  const [selectedIds,     setSelectedIds]     = useState<Set<string>>(new Set());
  const [transferYear,    setTransferYear]    = useState(String(currentYear));
  const [transferSemester,setTransferSemester]= useState('spring');
  const [submitting,      setSubmitting]      = useState(false);
  const [alert,           setAlert]           = useState<{ msg: string; type: 'success' | 'error' | 'warning' } | null>(null);
  const [result,          setResult]          = useState<{ transferredCount: number; failures: Array<{ reason: string }> } | null>(null);
  const [search,          setSearch]          = useState('');

  useEffect(() => {
    if (!isGlobalAdmin()) {
      router.push('/unauthorized');
      return;
    }
    fetchPlayers();
  }, []);

  const fetchPlayers = async () => {
    try {
      const { data } = await appApi.get('/players', {
        params: { pageSize: 200, status: 'active' },
      });
      setPlayers(data.data ?? []);
    } catch {
      setAlert({ msg: 'Failed to load players. Make sure the app API is running.', type: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const toggleSelect = (id: string) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const toggleAll = () => {
    if (selectedIds.size === filteredPlayers.length) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(filteredPlayers.map(p => p.id)));
    }
  };

  const handleTransfer = async () => {
    if (selectedIds.size === 0) {
      setAlert({ msg: 'Select at least one player.', type: 'warning' });
      return;
    }
    setSubmitting(true);
    try {
      const { data } = await appApi.post('/players/transfer', {
        playerIds:        Array.from(selectedIds),
        transferYear:     parseInt(transferYear),
        transferSemester,
      });
      setResult(data.data);
      setSelectedIds(new Set());
      fetchPlayers();
      setAlert({
        msg: `${data.data.transferredCount} player(s) moved to Alumni successfully.`,
        type: data.data.failures?.length > 0 ? 'warning' : 'success',
      });
    } catch (err: unknown) {
      setAlert({ msg: getApiError(err, 'Transfer failed. No changes were made.'), type: 'error' });
    } finally {
      setSubmitting(false);
    }
  };

  const filteredPlayers = players.filter(p =>
    !search || `${p.firstName} ${p.lastName} ${p.jerseyNumber}`.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <PageLayout currentPage="Transfer to Alumni">

      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <div>
          <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>Transfer to Alumni</h1>
          <p style={{ fontSize: 14, color: theme.gray500, marginTop: 4 }}>
            Move players from the active roster to the Alumni CRM
          </p>
        </div>
        <Button label="← Back to Roster" variant="outline" onClick={() => router.push('/roster')} />
      </div>

      {alert && <Alert message={alert.msg} variant={alert.type} onClose={() => setAlert(null)} />}

      <div style={{ display: 'grid', gridTemplateColumns: '320px 1fr', gap: 20, alignItems: 'start' }}>

        {/* Left: Transfer config */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>

          {/* Year + semester */}
          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 20, boxShadow: 'var(--shadow-sm)' }}>
            <h2 style={{ fontSize: 14, fontWeight: 600, color: theme.gray500, textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: 14, marginTop: 0 }}>
              Departure Period
            </h2>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <Select label="Year"     value={transferYear}     onChange={setTransferYear}     options={YEAR_OPTIONS}    />
              <Select label="Semester" value={transferSemester} onChange={setTransferSemester} options={SEMESTER_OPTIONS} />
            </div>
          </div>

          {/* Submit button */}
          {selectedIds.size > 0 && (
            <div style={{ backgroundColor: theme.primaryLight, border: `1.5px solid var(--color-primary)`, borderRadius: 'var(--radius-lg)', padding: 16 }}>
              <p style={{ fontSize: 13, color: theme.primaryDark, fontWeight: 600, margin: '0 0 12px 0' }}>
                Ready to transfer {selectedIds.size} player{selectedIds.size !== 1 ? 's' : ''}
              </p>
              <p style={{ fontSize: 12, color: theme.primaryDark, margin: '0 0 14px 0', opacity: 0.8 }}>
                {transferSemester} {transferYear}
              </p>
              <Button
                label={submitting ? 'Transferring...' : `Transfer ${selectedIds.size} Player${selectedIds.size !== 1 ? 's' : ''} to Alumni`}
                loading={submitting}
                fullWidth
                onClick={handleTransfer}
              />
              <p style={{ fontSize: 11, color: theme.gray500, textAlign: 'center', marginTop: 10, marginBottom: 0 }}>
                This action moves players to Alumni CRM and removes roster access.
              </p>
            </div>
          )}
        </div>

        {/* Right: Player selection */}
        <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', overflow: 'hidden', boxShadow: 'var(--shadow-sm)' }}>

          {/* Table header */}
          <div style={{ padding: '16px 20px', borderBottom: `1px solid ${theme.gray200}`, display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, flex: 1 }}>
              <input
                type="text"
                placeholder="Search players..."
                value={search}
                onChange={e => setSearch(e.target.value)}
                style={{ border: `1.5px solid ${theme.gray200}`, borderRadius: 'var(--radius-sm)', padding: '7px 12px', fontSize: 13, outline: 'none', width: 200 }}
              />
              <span style={{ fontSize: 13, color: theme.gray500 }}>
                {selectedIds.size} of {filteredPlayers.length} selected
              </span>
            </div>
            <button
              onClick={toggleAll}
              style={{ fontSize: 13, fontWeight: 600, color: theme.primary, background: 'none', border: 'none', cursor: 'pointer' }}
            >
              {selectedIds.size === filteredPlayers.length && filteredPlayers.length > 0 ? 'Deselect All' : 'Select All'}
            </button>
          </div>

          {/* Player list */}
          {loading ? (
            <div style={{ textAlign: 'center', padding: 48, color: theme.gray400 }}>Loading players...</div>
          ) : filteredPlayers.length === 0 ? (
            <div style={{ textAlign: 'center', padding: 48, color: theme.gray400 }}>No active players found</div>
          ) : (
            <div style={{ maxHeight: 600, overflowY: 'auto' }}>
              {filteredPlayers.map((player, i) => {
                const selected = selectedIds.has(player.id);
                return (
                  <div
                    key={player.id}
                    onClick={() => toggleSelect(player.id)}
                    style={{
                      display:         'flex',
                      alignItems:      'center',
                      gap:             14,
                      padding:         '12px 20px',
                      borderBottom:    `1px solid ${theme.gray100}`,
                      backgroundColor: selected ? theme.primaryLight : (i % 2 === 0 ? theme.cardBg : theme.gray50),
                      cursor:          'pointer',
                      transition:      'background-color 0.1s',
                    }}
                  >
                    {/* Checkbox */}
                    <div style={{
                      width:           20,
                      height:          20,
                      borderRadius:    5,
                      border:          `2px solid ${selected ? 'var(--color-primary)' : theme.gray300}`,
                      backgroundColor: selected ? 'var(--color-primary)' : 'transparent',
                      display:         'flex',
                      alignItems:      'center',
                      justifyContent:  'center',
                      flexShrink:      0,
                      transition:      'all 0.15s',
                    }}>
                      {selected && <span style={{ color: '#fff', fontSize: 12, fontWeight: 700 }}>✓</span>}
                    </div>

                    {/* Jersey */}
                    <div style={{ width: 36, height: 36, borderRadius: 8, backgroundColor: 'var(--color-primary)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: 13, fontWeight: 700, flexShrink: 0 }}>
                      {player.jerseyNumber ?? '—'}
                    </div>

                    {/* Name + details */}
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 14, fontWeight: 600, color: theme.gray900 }}>
                        {player.lastName}, {player.firstName}
                      </div>
                      <div style={{ fontSize: 12, color: theme.gray500, marginTop: 2 }}>
                        {player.position} · {player.academicYear ?? '—'} · Class of {player.recruitingClass}
                      </div>
                    </div>

                    {/* Status */}
                    <Badge label={player.status} variant="green" />
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>

      {/* Result summary */}
      {result && result.failures?.length > 0 && (
        <div style={{ marginTop: 20, backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 20 }}>
          <h2 style={{ fontSize: 15, fontWeight: 600, color: theme.gray900, marginBottom: 12, marginTop: 0 }}>
            Transfer failures ({result.failures.length})
          </h2>
          {result.failures.map((f, i) => (
            <div key={i} style={{ backgroundColor: theme.dangerLight, borderRadius: 8, padding: '8px 12px', marginBottom: 6, fontSize: 13, color: theme.danger }}>
              {f.reason}
            </div>
          ))}
        </div>
      )}

    </PageLayout>
  );
}