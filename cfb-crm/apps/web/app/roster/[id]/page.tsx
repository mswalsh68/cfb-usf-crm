'use client';

import React, { useEffect, useState } from 'react';
import { useRouter, useParams } from 'next/navigation';
import type { Player, AppPermission } from '@cfb-crm/types';
import { appApi, getApiError } from '@/lib/api';
import { theme } from '@/lib/theme';
import { getUser, isGlobalAdmin } from '@/lib/auth';
import { PageLayout, Button, Input, Select, Badge, Alert, Card } from '@/components';
import { useTeamConfig } from '@/lib/teamConfig';

interface PlayerStat {
  id:          string;
  seasonYear:  number;
  gamesPlayed?: number;
  statsJson?:  string;
}

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
  const { positions, academicYears, level } = useTeamConfig();

  const [player,  setPlayer]  = useState<Player | null>(null);
  const [stats,   setStats]   = useState<PlayerStat[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState(false);
  const [saving,  setSaving]  = useState(false);
  const [alert,   setAlert]   = useState<{ msg: string; type: 'success' | 'error' } | null>(null);
  const [form,    setForm]    = useState<Partial<Player>>({});

  useEffect(() => { if (id) fetchPlayer(); }, [id]);

  const fetchPlayer = async () => {
    try {
      const { data } = await appApi.get(`/players/${id}`);
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
      await appApi.patch(`/players/${id}`, {
        jerseyNumber:           form.jerseyNumber   ? parseInt(form.jerseyNumber) : undefined,
        position:               form.position       || undefined,
        academicYear:           form.academicYear   || undefined,
        status:                 form.status         || undefined,
        major:                  form.major          || undefined,
        phone:                  form.phone          || undefined,
        email:                  form.email          || undefined,
        instagram:              form.instagram       || undefined,
        twitter:                form.twitter         || undefined,
        weightLbs:              form.weightLbs      ? parseInt(form.weightLbs) : undefined,
        emergencyContactName:   form.emergencyContactName  || undefined,
        emergencyContactPhone:  form.emergencyContactPhone || undefined,
        parent1Name:            form.parent1Name    || undefined,
        parent1Phone:           form.parent1Phone   || undefined,
        parent1Email:           form.parent1Email   || undefined,
        parent2Name:            form.parent2Name    || undefined,
        parent2Phone:           form.parent2Phone   || undefined,
        parent2Email:           form.parent2Email   || undefined,
        notes:                  form.notes          || undefined,
      });
      setAlert({ msg: 'Player updated successfully', type: 'success' });
      setEditing(false);
      fetchPlayer();
    } catch (err: unknown) {
      setAlert({ msg: getApiError(err, 'Update failed'), type: 'error' });
    } finally {
      setSaving(false);
    }
  };

  const set = (key: keyof Player) => (val: string) => setForm((p) => ({ ...p, [key]: val }));

  if (loading) return (
    <PageLayout currentPage="Roster">
      <div style={{ textAlign: 'center', padding: 80, color: theme.gray400 }}>Loading...</div>
    </PageLayout>
  );

  const user        = getUser();
  const isWriter    = isGlobalAdmin() || user?.appPermissions?.some((p: AppPermission) => p.app === 'roster' && ['global_admin','app_admin','coach_staff'].includes(p.role));
  const canEdit     = isWriter || user?.sub === player?.userId;

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
          {canEdit && (editing ? (
            <>
              <Button label="Cancel"       variant="ghost"   onClick={() => { setEditing(false); setForm(player); }} />
              <Button label="Save Changes" loading={saving}  onClick={handleSave} />
            </>
          ) : (
            <Button label="Edit Player" variant="outline" onClick={() => setEditing(true)} />
          ))}
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
                {level === 'college' && (
                  <Input label="Major" value={form.major ?? ''} onChange={set('major')} />
                )}
                <Select label="Academic Year" value={form.academicYear ?? ''} onChange={set('academicYear')} options={academicYears} />
              </>
            ) : (
              <>
                {level === 'college' && <InfoRow label="Major" value={player.major} />}
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
                <Input label="Email" type="email" value={form.email ?? ''} onChange={set('email')} />
                <Input label="Emergency Contact" value={form.emergencyContactName ?? ''} onChange={set('emergencyContactName')} />
                <Input label="Emergency Phone"   value={form.emergencyContactPhone ?? ''} onChange={set('emergencyContactPhone')} type="tel" />
              </>
            ) : (
              <>
                <InfoRow label="Phone"             value={player.phone}                />
                <InfoRow label="Email"             value={player.email}                />
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
                {isWriter && (
                  <Select label="Position"  value={form.position ?? ''} onChange={set('position')} options={positions.map(p => ({ value: p, label: p }))} />
                )}
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
              onChange={(e) => setForm((p) => ({ ...p, notes: e.target.value }))}
              rows={6}
              style={{ width: '100%', border: `1.5px solid ${theme.gray200}`, borderRadius: 10, padding: '10px 14px', fontSize: 14, color: theme.gray900, resize: 'vertical', outline: 'none', boxSizing: 'border-box' }}
            />
          ) : (
            <p style={{ fontSize: 14, color: player.notes ? theme.gray700 : theme.gray400, lineHeight: 1.6, margin: 0 }}>
              {player.notes || 'No notes.'}
            </p>
          )}
        </Card>

        {/* Parent / Guardian Contact */}
        <Card style={{ gridColumn: '1 / -1' }}>
          <h2 style={{ fontSize: 15, fontWeight: 600, color: theme.gray900, marginBottom: 16, marginTop: 0 }}>Parent / Guardian Contact</h2>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 24 }}>
            <div>
              <p style={{ fontSize: 12, fontWeight: 600, color: theme.gray500, textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: 12, marginTop: 0 }}>Parent / Guardian 1</p>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                {editing ? (
                  <>
                    <Input label="Name"  value={form.parent1Name  ?? ''} onChange={set('parent1Name')}  />
                    <Input label="Phone" value={form.parent1Phone ?? ''} onChange={set('parent1Phone')} type="tel" />
                    <Input label="Email" value={form.parent1Email ?? ''} onChange={set('parent1Email')} type="email" />
                  </>
                ) : (
                  <>
                    <InfoRow label="Name"  value={player.parent1Name}  />
                    <InfoRow label="Phone" value={player.parent1Phone} />
                    <InfoRow label="Email" value={player.parent1Email} />
                  </>
                )}
              </div>
            </div>
            <div>
              <p style={{ fontSize: 12, fontWeight: 600, color: theme.gray500, textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: 12, marginTop: 0 }}>Parent / Guardian 2</p>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                {editing ? (
                  <>
                    <Input label="Name"  value={form.parent2Name  ?? ''} onChange={set('parent2Name')}  />
                    <Input label="Phone" value={form.parent2Phone ?? ''} onChange={set('parent2Phone')} type="tel" />
                    <Input label="Email" value={form.parent2Email ?? ''} onChange={set('parent2Email')} type="email" />
                  </>
                ) : (
                  <>
                    <InfoRow label="Name"  value={player.parent2Name}  />
                    <InfoRow label="Phone" value={player.parent2Phone} />
                    <InfoRow label="Email" value={player.parent2Email} />
                  </>
                )}
              </div>
            </div>
          </div>
        </Card>

        {/* Social Media */}
        <Card>
          <h2 style={{ fontSize: 15, fontWeight: 600, color: theme.gray900, marginBottom: 16, marginTop: 0 }}>Social Media</h2>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            {editing ? (
              <>
                <Input label="Instagram" value={form.instagram ?? ''} onChange={set('instagram')} placeholder="@username" />
                <Input label="Twitter / X" value={form.twitter ?? ''} onChange={set('twitter')} placeholder="@username" />
              </>
            ) : (
              <>
                <InfoRow label="Instagram"  value={player.instagram} />
                <InfoRow label="Twitter / X" value={player.twitter} />
              </>
            )}
          </div>
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
              {stats.map((s) => (
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