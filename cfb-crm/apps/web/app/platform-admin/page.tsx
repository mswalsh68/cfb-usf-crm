'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { globalApi } from '@/lib/api';
import { isPlatformOwner, switchTeam } from '@/lib/auth';
import { theme } from '@/lib/theme';
import { triggerThemeRefresh } from '@/components/ThemeProvider';
import { PageLayout, Button, Input, Select, Badge, Modal, Alert } from '@/components';

const SPORT_OPTIONS = [
  { value: 'football',    label: 'Football'    },
  { value: 'basketball',  label: 'Basketball'  },
  { value: 'baseball',    label: 'Baseball'    },
  { value: 'soccer',      label: 'Soccer'      },
  { value: 'softball',    label: 'Softball'    },
  { value: 'volleyball',  label: 'Volleyball'  },
  { value: 'other',       label: 'Other'       },
];

const LEVEL_OPTIONS = [
  { value: 'college',     label: 'College'     },
  { value: 'high_school', label: 'High School' },
  { value: 'club',        label: 'Club'        },
];

const TIER_OPTIONS = [
  { value: 'starter',     label: 'Starter'     },
  { value: 'pro',         label: 'Pro'         },
  { value: 'enterprise',  label: 'Enterprise'  },
];

interface Team {
  id: string; name: string; abbr: string;
  sport: string; level: string;
  subscriptionTier: string; isActive: boolean;
  createdAt: string; rosterDb: string; alumniDb: string;
}

const tierBadge = (tier: string): 'green' | 'warning' | 'gray' => {
  if (tier === 'enterprise') return 'green';
  if (tier === 'pro')        return 'warning';
  return 'gray';
};

export default function PlatformAdminPage() {
  const router = useRouter();
  const [isOwner,      setIsOwner]      = useState(false);
  const [teams,        setTeams]        = useState<Team[]>([]);
  const [loading,      setLoading]      = useState(true);
  const [error,        setError]        = useState('');
  const [success,      setSuccess]      = useState('');
  const [showAddModal, setShowAddModal] = useState(false);
  const [switching,    setSwitching]    = useState<string | null>(null);

  // Add client form state
  const [form, setForm] = useState({
    clientCode: '', clientName: '', clientAbbr: '',
    sport: 'football', level: 'college',
    colorPrimary: '#006747', colorAccent: '#CFC493',
    adminEmail: '', adminPassword: '',
    adminFirstName: '', adminLastName: '',
    subscriptionTier: 'starter',
  });
  const [submitting, setSubmitting] = useState(false);
  const [formError,  setFormError]  = useState('');

  useEffect(() => {
    const owner = isPlatformOwner();
    setIsOwner(owner);
    if (!owner) { router.replace('/dashboard'); return; }
    fetchTeams();
  }, []);

  const fetchTeams = async () => {
    setLoading(true);
    try {
      const { data } = await globalApi.get('/platform/teams');
      setTeams(data.data ?? []);
    } catch {
      setError('Failed to load teams.');
    } finally {
      setLoading(false);
    }
  };

  const handleViewAsClient = async (teamId: string, teamName: string) => {
    setSwitching(teamId);
    const newConfig = await switchTeam(teamId);
    setSwitching(null);
    if (!newConfig) { setError(`Failed to switch to ${teamName}`); return; }
    triggerThemeRefresh(newConfig);
    router.push('/dashboard');
  };

  const handleToggleActive = async (team: Team) => {
    try {
      await globalApi.patch(`/platform/teams/${team.id}`, { isActive: !team.isActive });
      setSuccess(`${team.name} ${team.isActive ? 'deactivated' : 'reactivated'} successfully.`);
      fetchTeams();
    } catch {
      setError('Failed to update team status.');
    }
  };

  const handleAddClient = async (e: React.FormEvent) => {
    e.preventDefault();
    setFormError('');
    setSubmitting(true);
    try {
      await globalApi.post('/platform/onboard-client', {
        clientCode:      form.clientCode.toUpperCase().trim(),
        clientName:      form.clientName.trim(),
        clientAbbr:      form.clientAbbr.toUpperCase().trim(),
        sport:           form.sport,
        level:           form.level,
        colorPrimary:    form.colorPrimary,
        colorAccent:     form.colorAccent,
        adminEmail:      form.adminEmail.trim().toLowerCase(),
        adminPassword:   form.adminPassword,
        adminFirstName:  form.adminFirstName.trim(),
        adminLastName:   form.adminLastName.trim(),
        subscriptionTier: form.subscriptionTier,
      });
      setShowAddModal(false);
      setSuccess(`${form.clientName} provisioned successfully! Admin user created at ${form.adminEmail}.`);
      setForm({
        clientCode: '', clientName: '', clientAbbr: '',
        sport: 'football', level: 'college',
        colorPrimary: '#006747', colorAccent: '#CFC493',
        adminEmail: '', adminPassword: '',
        adminFirstName: '', adminLastName: '',
        subscriptionTier: 'starter',
      });
      fetchTeams();
    } catch (err: any) {
      setFormError(err?.response?.data?.error ?? 'Failed to provision client.');
    } finally {
      setSubmitting(false);
    }
  };

  const setF = (k: keyof typeof form) => (v: string) => setForm(p => ({ ...p, [k]: v }));

  if (!isOwner) return null;

  const activeCount   = teams.filter(t => t.isActive).length;
  const inactiveCount = teams.length - activeCount;

  return (
    <PageLayout currentPage="Platform Admin">

      {/* Header */}
      <div style={{ marginBottom: 24 }}>
        <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>Platform Admin</h1>
        <p style={{ fontSize: 14, color: theme.gray500, marginTop: 4 }}>LegacyLink — all client teams</p>
      </div>

      {error   && <Alert message={error}   variant="error"   onClose={() => setError('')}   />}
      {success && <Alert message={success} variant="success" onClose={() => setSuccess('')} />}

      {/* Stats row */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16, marginBottom: 28 }}>
        {[
          { label: 'Active Clients',   value: activeCount   },
          { label: 'Inactive Clients', value: inactiveCount },
          { label: 'Total Clients',    value: teams.length  },
        ].map(s => (
          <div key={s.label} style={{ backgroundColor: theme.cardBg, borderRadius: 'var(--radius-lg)', border: `1px solid ${theme.cardBorder}`, padding: '20px 24px' }}>
            <div style={{ fontSize: 28, fontWeight: 700, color: theme.primary }}>{s.value}</div>
            <div style={{ fontSize: 13, color: theme.gray500, marginTop: 4 }}>{s.label}</div>
          </div>
        ))}
      </div>

      {/* Clients table */}
      <div style={{ backgroundColor: theme.cardBg, borderRadius: 'var(--radius-lg)', border: `1px solid ${theme.cardBorder}`, overflow: 'hidden' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 20px', borderBottom: `1px solid ${theme.gray100}` }}>
          <h2 style={{ fontSize: 16, fontWeight: 600, color: theme.gray900, margin: 0 }}>Client Teams</h2>
          <Button label="+ Add New Client" onClick={() => setShowAddModal(true)} />
        </div>

        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ backgroundColor: theme.gray50, borderBottom: `1px solid ${theme.gray200}` }}>
              {['Team', 'Sport / Level', 'Databases', 'Tier', 'Status', 'Created', 'Actions'].map(h => (
                <th key={h} style={{ textAlign: 'left', padding: '12px 20px', fontSize: 11, fontWeight: 600, color: theme.gray500, textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={7} style={{ textAlign: 'center', padding: 48, color: theme.gray400 }}>Loading...</td></tr>
            ) : teams.length === 0 ? (
              <tr><td colSpan={7} style={{ textAlign: 'center', padding: 48, color: theme.gray400 }}>No teams yet</td></tr>
            ) : teams.map((t, i) => (
              <tr key={t.id} style={{ borderBottom: `1px solid ${theme.gray100}`, backgroundColor: i % 2 === 0 ? theme.cardBg : theme.gray50 }}>
                <td style={{ padding: '14px 20px' }}>
                  <div style={{ fontWeight: 600, fontSize: 14, color: theme.gray900 }}>{t.name}</div>
                  <div style={{ fontSize: 12, color: theme.gray400 }}>{t.abbr}</div>
                </td>
                <td style={{ padding: '14px 20px', fontSize: 13, color: theme.gray600 }}>
                  <div>{t.sport}</div>
                  <div style={{ fontSize: 11, color: theme.gray400, marginTop: 2 }}>{t.level}</div>
                </td>
                <td style={{ padding: '14px 20px', fontSize: 12, color: theme.gray500 }}>
                  <div>{t.rosterDb}</div>
                  <div>{t.alumniDb}</div>
                </td>
                <td style={{ padding: '14px 20px' }}>
                  <Badge label={t.subscriptionTier} variant={tierBadge(t.subscriptionTier)} />
                </td>
                <td style={{ padding: '14px 20px' }}>
                  <Badge label={t.isActive ? 'Active' : 'Inactive'} variant={t.isActive ? 'green' : 'gray'} />
                </td>
                <td style={{ padding: '14px 20px', fontSize: 13, color: theme.gray500 }}>
                  {new Date(t.createdAt).toLocaleDateString()}
                </td>
                <td style={{ padding: '14px 20px' }}>
                  <div style={{ display: 'flex', gap: 8 }}>
                    <Button
                      label={switching === t.id ? '...' : 'View as Client'}
                      variant="outline"
                      size="sm"
                      disabled={!t.isActive || switching === t.id}
                      onClick={() => handleViewAsClient(t.id, t.name)}
                    />
                    <Button
                      label={t.isActive ? 'Deactivate' : 'Reactivate'}
                      variant="outline"
                      size="sm"
                      onClick={() => handleToggleActive(t)}
                    />
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Add client modal */}
      <Modal
        isOpen={showAddModal}
        onClose={() => { setShowAddModal(false); setFormError(''); }}
        title="Add New Client"
        size="lg"
      >
        <form onSubmit={handleAddClient}>
          {formError && <Alert message={formError} variant="error" onClose={() => setFormError('')} />}

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 16 }}>
            <div>
              <label style={{ fontSize: 13, fontWeight: 500, color: theme.gray700, display: 'block', marginBottom: 6 }}>Client Code *</label>
              <Input value={form.clientCode} onChange={setF('clientCode')} placeholder="HSFC" />
              <p style={{ fontSize: 11, color: theme.gray400, marginTop: 4 }}>Used as DB prefix (e.g. HSFC_Roster)</p>
            </div>
            <div>
              <label style={{ fontSize: 13, fontWeight: 500, color: theme.gray700, display: 'block', marginBottom: 6 }}>Abbreviation *</label>
              <Input value={form.clientAbbr} onChange={setF('clientAbbr')} placeholder="HSFC" />
            </div>
          </div>

          <div style={{ marginBottom: 16 }}>
            <label style={{ fontSize: 13, fontWeight: 500, color: theme.gray700, display: 'block', marginBottom: 6 }}>Team Name *</label>
            <Input value={form.clientName} onChange={setF('clientName')} placeholder="Plant Panthers Football" />
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 16, marginBottom: 16 }}>
            <div>
              <label style={{ fontSize: 13, fontWeight: 500, color: theme.gray700, display: 'block', marginBottom: 6 }}>Sport *</label>
              <Select value={form.sport} onChange={setF('sport')} options={SPORT_OPTIONS} />
            </div>
            <div>
              <label style={{ fontSize: 13, fontWeight: 500, color: theme.gray700, display: 'block', marginBottom: 6 }}>Level *</label>
              <Select value={form.level} onChange={setF('level')} options={LEVEL_OPTIONS} />
            </div>
            <div>
              <label style={{ fontSize: 13, fontWeight: 500, color: theme.gray700, display: 'block', marginBottom: 6 }}>Tier</label>
              <Select value={form.subscriptionTier} onChange={setF('subscriptionTier')} options={TIER_OPTIONS} />
            </div>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 16 }}>
            <div>
              <label style={{ fontSize: 13, fontWeight: 500, color: theme.gray700, display: 'block', marginBottom: 6 }}>Primary Color</label>
              <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                <input type="color" value={form.colorPrimary} onChange={e => setF('colorPrimary')(e.target.value)}
                  style={{ width: 40, height: 36, padding: 2, borderRadius: 6, border: `1px solid ${theme.gray300}`, cursor: 'pointer' }} />
                <Input value={form.colorPrimary} onChange={setF('colorPrimary')} placeholder="#006747" />
              </div>
            </div>
            <div>
              <label style={{ fontSize: 13, fontWeight: 500, color: theme.gray700, display: 'block', marginBottom: 6 }}>Accent Color</label>
              <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                <input type="color" value={form.colorAccent} onChange={e => setF('colorAccent')(e.target.value)}
                  style={{ width: 40, height: 36, padding: 2, borderRadius: 6, border: `1px solid ${theme.gray300}`, cursor: 'pointer' }} />
                <Input value={form.colorAccent} onChange={setF('colorAccent')} placeholder="#CFC493" />
              </div>
            </div>
          </div>

          <div style={{ height: 1, background: theme.gray100, margin: '8px 0 16px' }} />
          <p style={{ fontSize: 13, fontWeight: 600, color: theme.gray700, marginBottom: 12 }}>First Admin User</p>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 16 }}>
            <div>
              <label style={{ fontSize: 13, fontWeight: 500, color: theme.gray700, display: 'block', marginBottom: 6 }}>First Name</label>
              <Input value={form.adminFirstName} onChange={setF('adminFirstName')} placeholder="Jane" />
            </div>
            <div>
              <label style={{ fontSize: 13, fontWeight: 500, color: theme.gray700, display: 'block', marginBottom: 6 }}>Last Name</label>
              <Input value={form.adminLastName} onChange={setF('adminLastName')} placeholder="Smith" />
            </div>
          </div>

          <div style={{ marginBottom: 16 }}>
            <label style={{ fontSize: 13, fontWeight: 500, color: theme.gray700, display: 'block', marginBottom: 6 }}>Admin Email *</label>
            <Input value={form.adminEmail} onChange={setF('adminEmail')} placeholder="admin@school.edu" type="email" />
          </div>

          <div style={{ marginBottom: 24 }}>
            <label style={{ fontSize: 13, fontWeight: 500, color: theme.gray700, display: 'block', marginBottom: 6 }}>Temporary Password * (min 10 chars)</label>
            <Input value={form.adminPassword} onChange={setF('adminPassword')} placeholder="Temp password for admin" type="password" />
          </div>

          <div style={{ display: 'flex', gap: 12, justifyContent: 'flex-end' }}>
            <Button label="Cancel" variant="outline" onClick={() => { setShowAddModal(false); setFormError(''); }} />
            <Button label={submitting ? 'Provisioning...' : 'Provision Client'} disabled={submitting} onClick={() => {}} />
          </div>
        </form>
      </Modal>

    </PageLayout>
  );
}
