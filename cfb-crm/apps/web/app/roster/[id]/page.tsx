'use client';

import React, { useEffect, useState } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { rosterApi } from '@/lib/api';
import { theme } from '@/lib/theme';
import { PageLayout, Button, Input, Select, Badge, Alert, Card } from '@/components';

const POSITION_OPTIONS = ['QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH'].map(p => ({ value: p, label: p }));
const YEAR_OPTIONS = [
  { value: 'freshman',  label: 'Freshman'  },
  { value: 'sophomore', label: 'Sophomore' },
  { value: 'junior',    label: 'Junior'    },
  { value: 'senior',    label: 'Senior'    },
  { value: 'graduate',  label: 'Graduate'  },
];
const STATUS_OPTIONS = [
  { value: 'active',      label: 'Active'      },
  { value: 'injured',     label: 'Injured'     },
  { value: 'suspended',   label: 'Suspended'   },
  { value: 'transferred', label: 'Transferred' },
  { value: 'walkOn',      label: 'Walk-On'     },
];
const STATUS_BADGE: Record<string, 'green' | 'warning' | 'danger' | 'gray' | 'gold'> = {
  active: 'green', injured: 'warning', suspended: 'danger', transferred: 'gray', walkOn: 'gold',
};

export default function PlayerDetailPage() {
  const router = useRouter();
  const { id } = useParams<{ id: string }>();

  const [player,  setPlayer]  = useState<any>(null);
  const [stats,   setStats]   = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState(false);
  const [saving,  setSaving]  = useState(false);
  const [alert,   setAlert]   = useState<{ msg: string; type: 'success' | 'error' } | null>(null);
  const [form,    setForm]    = useState<any>({});

  useEffect(() => { if (id) fetchPlayer(); }, [id]);

  const fetchPlayer = async () => {
    try {
      const { data } = await rosterApi.get(`/players/${id}`);
      setPlayer(data.data);
      setStats(data.data.stats ?? []);
      setForm(data.data);
    } catch {
      setAlert({ msg: 'Failed to load player', type: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      await rosterApi.patch(`/players/${id}`, {
        jerseyNumber:           form.jerseyNumber   ? parseInt(form.jerseyNumber) : undefined,
        academicYear:           form.academicYear   || undefined,
        status:                 form.status         || undefined,
        gpa:                    form.gpa            ? parseFloat(form.gpa) : undefined,
        major:                  form.major          || undefined,
        phone:                  form.phone          || undefined,
        weightLbs:              form.weightLbs      ? parseInt(form.weightLbs) : undefined,
        emergencyContactName:   form.emergencyContactName  || undefined,
        emergencyContactPhone:  form.emergencyContactPhone || undefined,
        notes:                  form.notes          || undefined,
      });
      setAlert({ msg: 'Player updated successfully', type: 'success' });
      setEditing(false);
      fetchPlayer();
    } catch (err: any) {
      setAlert({ msg: err?.response?.data?.error ?? 'Update failed', type: 'error' });
    } finally {
      setSaving(false);
    }
  };

  const set = (key: string) => (val: string) => setForm((p: any) => ({ ...p, [key]: val }));

  if (loading) return (
    <PageLayout currentPage="Roster">
      <div style={{ textAlign: 'center', padding: 80, color: theme.gray400 }}>Loading...</div>
    </PageLayout>
  );

  if (!player) return (
    <PageLayout currentPage="Roster">
      <Alert message="Player not found" variant="error" />
      <Button label="← Back to Roster" onClick={() => router.push('/roster')} />
    </PageLayout>
  );

  return (
    <PageLayout currentPage="Roster">

      {/* Back + actions */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <Button label="← Back to Roster" variant="outline" onClick={() => router.push('/roster')} />
        <div style={{ display: 'flex', gap: 10 }}>
          {editing ? (
            <>
              <Button label="Cancel" variant="ghost" onClick={() => { setEditing(false); setForm(player); }} />
              <Button label="Save Changes" loading={saving} onClick={handleSave} />
            </>
          ) : (
            <Button label="Edit Player" variant="outline" onClick={() => setEditing(true)} />
          )}
        </div>
      </div>

      {alert && <Alert message={alert.msg} variant={alert.type} onClose={() => setAlert(null)} />}

      {/* Hero card */}
      <Card style={{ marginBottom: 20 }}>
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 20 }}>
          {/* Jersey bubble */}
          <div style={{ width: 72, height: 72, borderRadius: 14, backgroundColor: theme.primary, display: 'flex', alignItems: 'center', justifyContent: 'center', color: theme.white, fontSize: 26, fontWeight: 700, flexShrink: 0 }}>
            {player.jerseyNumber ?? '—'}
          </div>

          {/* Name + meta */}
          <div style={{ flex: 1 }}>
            <h1 style={{ fontSize: 26, fontWeight: 700, color: theme.gray900, margin: 0 }}>
              {player.firstName} {player.lastName}
            </h1>
            <div style={{ display: 'flex', gap: 10, marginTop: 8, flexWrap: 'wrap', alignItems: 'center' }}>
              <span style={{ fontSize: 15, fontWeight: 700, color: theme.primary }}>{player.position}</span>
              <span style={{ color: theme.gray300 }}>·</span>
              <span style={{ fontSize: 14, color: theme.gray600, textTransform: 'capitalize' }}>{player.academicYear ?? '—'}</span>
              <span style={{ color: theme.gray300 }}>·</span>
              <span style={{ fontSize: 14, color: theme.gray600 }}>Class of {player.recruitingClass}</span>
              <Badge label={player.status} variant={STATUS_BADGE[player.status] ?? 'gray'} />
            </div>
          </div>

          {/* Quick stats */}
          <div style={{ display: 'flex', gap: 20, flexShrink: 0 }}>
            {[
              { label: 'Height', value: player.heightInches ? `${Math.floor(player.heightInches / 12)}'${player.heightInches % 12}"` : '—' },
              { label: 'Weight', value: player.weightLbs ? `${player.weightLbs} lbs` : '—' },
              { label: 'GPA',    value: player.gpa != null ? player.gpa.toFixed(2) : '—' },
            ].map(({ label, value }) => (
              <div key={label} style={{ textAlign: 'center' }}>
                <div style={{ fontSize: 20, fontWeight: 700, color: theme.gray900 }}>{value}</div>
                <div style={{ fontSize: 12, color: theme.gray400, marginTop: 2 }}>{label}</div>
              </div>
            ))}
          </div>
        </div>
      </Card>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>

        {/* Academic */}
        <Card>
          <h2 style={{ fontSize: 15, fontWeight: 600, color: theme.gray900, marginBottom: 16, marginTop: 0 }}>Academic</h2>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            {editing ? (
              <>
                <Input label="Major" value={form.major ?? ''} onChange={set('major')} />
                <Input label="GPA" value={form.gpa?.toString() ?? ''} onChange={set('gpa')} type="number" />
                <Select label="Academic Year" value={form.academicYear ?? ''} onChange={set('academicYear')} options={YEAR_OPTIONS} />
              </>
            ) : (
              <>
                <InfoRow label="Major"         value={player.major}        />
                <InfoRow label="GPA"           value={player.gpa?.toFixed(2)} />
                <InfoRow label="Academic Year" value={player.academicYear} capitalize />
                <InfoRow label="High School"   value={player.highSchool}   />
                <InfoRow label="Hometown"      value={player.homeTown && player.homeState ? `${player.homeTown}, ${player.homeState}` : undefined} />
              </>
            )}
          </div>
        </Card>

        {/* Contact */}
        <Card>
          <h2 style={{ fontSize: 15, fontWeight: 600, color: theme.gray900, marginBottom: 16, marginTop: 0 }}>Contact</h2>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            {editing ? (
              <>
                <Input label="Phone" value={form.phone ?? ''} onChange={set('phone')} type="tel" />
                <Input label="Emergency Contact" value={form.emergencyContactName ?? ''} onChange={set('emergencyContactName')} />
                <Input label="Emergency Phone"   value={form.emergencyContactPhone ?? ''} onChange={set('emergencyContactPhone')} type="tel" />
              </>
            ) : (
              <>
                <InfoRow label="Phone"             value={player.phone}                />
                <InfoRow label="Emergency Contact" value={player.emergencyContactName} />
                <InfoRow label="Emergency Phone"   value={player.emergencyContactPhone} />
              </>
            )}
          </div>
        </Card>

        {/* Status */}
        <Card>
          <h2 style={{ fontSize: 15, fontWeight: 600, color: theme.gray900, marginBottom: 16, marginTop: 0 }}>Status & Details</h2>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            {editing ? (
              <>
                <Select label="Status"       value={form.status ?? ''}      onChange={set('status')}      options={STATUS_OPTIONS} />
                <Input  label="Jersey #"     value={form.jerseyNumber?.toString() ?? ''} onChange={set('jerseyNumber')} type="number" />
                <Input  label="Weight (lbs)" value={form.weightLbs?.toString() ?? ''} onChange={set('weightLbs')} type="number" />
              </>
            ) : (
              <>
                <InfoRow label="Status"   value={player.status}      capitalize />
                <InfoRow label="Jersey"   value={player.jerseyNumber != null ? `#${player.jerseyNumber}` : undefined} />
                <InfoRow label="Weight"   value={player.weightLbs ? `${player.weightLbs} lbs` : undefined} />
                <InfoRow label="Height"   value={player.heightInches ? `${Math.floor(player.heightInches / 12)}'${player.heightInches % 12}"` : undefined} />
              </>
            )}
          </div>
        </Card>

        {/* Notes */}
        <Card>
          <h2 style={{ fontSize: 15, fontWeight: 600, color: theme.gray900, marginBottom: 16, marginTop: 0 }}>Notes</h2>
          {editing ? (
            <textarea
              value={form.notes ?? ''}
              onChange={(e) => setForm((p: any) => ({ ...p, notes: e.target.value }))}
              rows={6}
              style={{ width: '100%', border: `1.5px solid ${theme.gray200}`, borderRadius: 10, padding: '10px 14px', fontSize: 14, color: theme.gray900, resize: 'vertical', outline: 'none', boxSizing: 'border-box' }}
            />
          ) : (
            <p style={{ fontSize: 14, color: player.notes ? theme.gray700 : theme.gray400, lineHeight: 1.6, margin: 0 }}>
              {player.notes || 'No notes.'}
            </p>
          )}
        </Card>

      </div>

      {/* Season Stats */}
      {stats.length > 0 && (
        <Card style={{ marginTop: 20 }}>
          <h2 style={{ fontSize: 15, fontWeight: 600, color: theme.gray900, marginBottom: 16, marginTop: 0 }}>Season Stats</h2>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 14 }}>
            <thead>
              <tr style={{ borderBottom: `1px solid ${theme.gray200}` }}>
                {['Season', 'Games Played'].map(h => (
                  <th key={h} style={{ textAlign: 'left', padding: '8px 0', fontWeight: 600, color: theme.gray500, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.5px' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {stats.map((s: any) => (
                <tr key={s.seasonYear} style={{ borderBottom: `1px solid ${theme.gray100}` }}>
                  <td style={{ padding: '10px 0', color: theme.gray900, fontWeight: 500 }}>{s.seasonYear}</td>
                  <td style={{ padding: '10px 0', color: theme.gray600 }}>{s.gamesPlayed ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      )}

    </PageLayout>
  );
}

// ─── InfoRow helper ───────────────────────────────────────────
function InfoRow({ label, value, capitalize }: { label: string; value?: string | number | null; capitalize?: boolean }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center' }}>
      <span style={{ width: 150, fontSize: 13, color: theme.gray400, fontWeight: 500, flexShrink: 0 }}>{label}</span>
      <span style={{ fontSize: 14, color: theme.gray900, textTransform: capitalize ? 'capitalize' : 'none' }}>
        {value ?? '—'}
      </span>
    </div>
  );
}