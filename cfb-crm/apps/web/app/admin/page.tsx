'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { isGlobalAdmin } from '@/lib/auth';
import { globalApi } from '@/lib/api';
import { USF } from '@/lib/theme';
import { PageLayout, Button, Input, Select, Badge, Modal, Alert } from '@/components';

const ROLE_OPTIONS = [
  { value: 'readonly',     label: 'Read Only'    },
  { value: 'coach_staff',  label: 'Coach / Staff' },
  { value: 'app_admin',    label: 'App Admin'     },
  { value: 'global_admin', label: 'Global Admin'  },
];

const APP_OPTIONS = [
  { value: '',             label: 'None'         },
  { value: 'roster',       label: 'Roster'       },
  { value: 'alumni',       label: 'Alumni'       },
  { value: 'global-admin', label: 'Global Admin' },
];

export default function AdminPage() {
  const router = useRouter();
  const [users,        setUsers]        = useState<any[]>([]);
  const [loading,      setLoading]      = useState(true);
  const [search,       setSearch]       = useState('');
  const [selectedUser, setSelectedUser] = useState<any>(null);
  const [permissions,  setPermissions]  = useState<any[]>([]);
  const [showCreate,   setShowCreate]   = useState(false);
  const [error,        setError]        = useState('');
  const [success,      setSuccess]      = useState('');

  const [newUser, setNewUser] = useState({
    email: '', password: '', firstName: '', lastName: '',
    globalRole: 'readonly', grantAppName: '', grantAppRole: 'readonly',
  });

  useEffect(() => {
    if (!isGlobalAdmin()) { router.push('/dashboard'); return; }
    fetchUsers();
  }, []);

  useEffect(() => {
    const timer = setTimeout(() => fetchUsers(), 400);
    return () => clearTimeout(timer);
  }, [search]);

  const fetchUsers = async () => {
    try {
      const params: any = { pageSize: 100 };
      if (search) params.search = search;
      const { data } = await globalApi.get('/users', { params });
      setUsers(data.data ?? []);
    } catch {
      setError('Failed to load users');
    } finally {
      setLoading(false);
    }
  };

  const fetchPermissions = async (userId: string) => {
    try {
      const { data } = await globalApi.get(`/permissions/${userId}`);
      setPermissions(data.data ?? []);
    } catch {
      setPermissions([]);
    }
  };

  const selectUser = (user: any) => {
    if (selectedUser?.id === user.id) {
      setSelectedUser(null);
      setPermissions([]);
    } else {
      setSelectedUser(user);
      fetchPermissions(user.id);
    }
  };

  const flash = (msg: string, type: 'success' | 'error' = 'success') => {
    type === 'success' ? setSuccess(msg) : setError(msg);
    setTimeout(() => type === 'success' ? setSuccess('') : setError(''), 3000);
  };

  const toggleActive = async (user: any) => {
    try {
      await globalApi.patch(`/users/${user.id}`, { isActive: !user.is_active });
      flash(`${user.first_name} ${user.last_name} ${!user.is_active ? 'activated' : 'deactivated'}`);
      fetchUsers();
    } catch { flash('Failed to update user', 'error'); }
  };

  const grantPermission = async (userId: string, appName: string) => {
    try {
      await globalApi.post('/permissions', { userId, appName, role: 'readonly' });
      flash('Permission granted');
      fetchPermissions(userId);
    } catch { flash('Failed to grant permission', 'error'); }
  };

  const revokePermission = async (userId: string, appName: string) => {
    try {
      await globalApi.delete(`/permissions/${userId}/${appName}`);
      flash('Permission revoked');
      fetchPermissions(userId);
    } catch { flash('Failed to revoke permission', 'error'); }
  };

  const createUser = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await globalApi.post('/users', {
        email:        newUser.email,
        password:     newUser.password,
        firstName:    newUser.firstName,
        lastName:     newUser.lastName,
        globalRole:   newUser.globalRole,
        grantAppName: newUser.grantAppName || undefined,
        grantAppRole: newUser.grantAppName ? newUser.grantAppRole : undefined,
      });
      flash(`User ${newUser.firstName} ${newUser.lastName} created`);
      setShowCreate(false);
      setNewUser({ email: '', password: '', firstName: '', lastName: '', globalRole: 'readonly', grantAppName: '', grantAppRole: 'readonly' });
      fetchUsers();
    } catch (err: any) {
      flash(err?.response?.data?.error ?? 'Failed to create user', 'error');
    }
  };

  const activePerms = permissions.filter((p: any) => !p.revokedAt);

  return (
    <PageLayout currentPage="Global Admin">
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <div>
          <h1 style={{ fontSize: 24, fontWeight: 700, color: USF.gray900, margin: 0 }}>User Management</h1>
          <p style={{ fontSize: 14, color: USF.gray500, marginTop: 4 }}>{users.length} total users</p>
        </div>
        <Button label="+ New User" onClick={() => setShowCreate(true)} />
      </div>

      {/* Alerts */}
      {error   && <Alert message={error}   variant="error"   onClose={() => setError('')}   />}
      {success && <Alert message={success} variant="success" onClose={() => setSuccess('')} />}

      {/* Search */}
      <div style={{ marginBottom: 16 }}>
        <Input value={search} onChange={setSearch} placeholder="Search users by name or email..." />
      </div>

      {/* User table */}
      <div style={{ backgroundColor: USF.white, borderRadius: 16, border: `1px solid ${USF.cardBorder}`, overflow: 'hidden' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ backgroundColor: USF.gray50, borderBottom: `1px solid ${USF.gray200}` }}>
              {['Name', 'Email', 'Role', 'Status', 'Actions'].map((h) => (
                <th key={h} style={{ textAlign: 'left', padding: '12px 24px', fontSize: 11, fontWeight: 600, color: USF.gray500, textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={5} style={{ textAlign: 'center', padding: 48, color: USF.gray400 }}>Loading...</td></tr>
            ) : users.length === 0 ? (
              <tr><td colSpan={5} style={{ textAlign: 'center', padding: 48, color: USF.gray400 }}>No users found</td></tr>
            ) : users.map((user, i) => (
              <React.Fragment key={user.id}>
                <tr
                  onClick={() => selectUser(user)}
                  style={{
                    borderBottom: `1px solid ${USF.gray100}`,
                    backgroundColor: selectedUser?.id === user.id ? USF.greenLight : (i % 2 === 0 ? USF.white : USF.gray50),
                    cursor: 'pointer',
                  }}
                >
                  <td style={{ padding: '14px 24px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                      <div style={{ width: 34, height: 34, borderRadius: '50%', backgroundColor: USF.green, display: 'flex', alignItems: 'center', justifyContent: 'center', color: USF.white, fontSize: 13, fontWeight: 600, flexShrink: 0 }}>
                        {user.first_name?.[0]}{user.last_name?.[0]}
                      </div>
                      <span style={{ fontWeight: 500, fontSize: 14, color: USF.gray900 }}>
                        {user.first_name} {user.last_name}
                      </span>
                    </div>
                  </td>
                  <td style={{ padding: '14px 24px', fontSize: 14, color: USF.gray600 }}>{user.email}</td>
                  <td style={{ padding: '14px 24px' }}>
                    <Badge label={user.globalRole?.replace('_', ' ')} variant={user.globalRole === 'global_admin' ? 'green' : 'gray'} />
                  </td>
                  <td style={{ padding: '14px 24px' }}>
                    <Badge label={user.is_active ? 'Active' : 'Inactive'} variant={user.is_active ? 'green' : 'danger'} />
                  </td>
                  <td style={{ padding: '14px 24px' }}>
                    <Button
                      label={user.is_active ? 'Deactivate' : 'Activate'}
                      variant={user.is_active ? 'danger' : 'primary'}
                      size="sm"
                      onClick={(e: any) => { e.stopPropagation(); toggleActive(user); }}
                    />
                  </td>
                </tr>

                {selectedUser?.id === user.id && (
                  <tr style={{ backgroundColor: '#F0F9F5', borderBottom: `1px solid ${USF.gray200}` }}>
                    <td colSpan={5} style={{ padding: '16px 24px' }}>
                      <p style={{ fontSize: 11, fontWeight: 600, color: USF.gray500, textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: 12 }}>
                        App Permissions
                      </p>
                      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
                        {(['roster', 'alumni', 'global-admin'] as const).map((app) => {
                          const existing = activePerms.find((p: any) => p.appName === app);
                          return (
                            <div key={app} style={{ display: 'flex', alignItems: 'center', gap: 8, backgroundColor: USF.white, border: `1px solid ${USF.gray200}`, borderRadius: 10, padding: '8px 14px' }}>
                              <span style={{ fontSize: 13, fontWeight: 500, color: USF.gray800, textTransform: 'capitalize' }}>{app}</span>
                              {existing ? (
                                <>
                                  <Badge label={existing.role} variant="green" />
                                  <Button label="Revoke" variant="danger" size="sm" onClick={() => revokePermission(user.id, app)} />
                                </>
                              ) : (
                                <Button label="Grant" variant="secondary" size="sm" onClick={() => grantPermission(user.id, app)} />
                              )}
                            </div>
                          );
                        })}
                      </div>
                    </td>
                  </tr>
                )}
              </React.Fragment>
            ))}
          </tbody>
        </table>
      </div>

      {/* Create User Modal */}
      {showCreate && (
        <Modal title="Create New User" onClose={() => setShowCreate(false)}>
          <form onSubmit={createUser} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
              <Input label="First Name" required value={newUser.firstName} onChange={(v) => setNewUser({ ...newUser, firstName: v })} />
              <Input label="Last Name"  required value={newUser.lastName}  onChange={(v) => setNewUser({ ...newUser, lastName: v })}  />
            </div>
            <Input label="Email"    required type="email"    value={newUser.email}    onChange={(v) => setNewUser({ ...newUser, email: v })}    />
            <Input label="Password" required type="password" value={newUser.password} onChange={(v) => setNewUser({ ...newUser, password: v })} helper="Minimum 10 characters" />
            <Select label="Global Role" value={newUser.globalRole} onChange={(v) => setNewUser({ ...newUser, globalRole: v })} options={ROLE_OPTIONS} />
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
              <Select label="Grant App Access" value={newUser.grantAppName} onChange={(v) => setNewUser({ ...newUser, grantAppName: v })} options={APP_OPTIONS} />
              {newUser.grantAppName && (
                <Select label="App Role" value={newUser.grantAppRole} onChange={(v) => setNewUser({ ...newUser, grantAppRole: v })} options={ROLE_OPTIONS.filter(r => r.value !== 'global_admin')} />
              )}
            </div>
            <div style={{ display: 'flex', gap: 12, marginTop: 8 }}>
              <Button label="Cancel"      variant="ghost"   fullWidth onClick={() => setShowCreate(false)} />
              <Button label="Create User" variant="primary" fullWidth type="submit" />
            </div>
          </form>
        </Modal>
      )}
    </PageLayout>
  );
}