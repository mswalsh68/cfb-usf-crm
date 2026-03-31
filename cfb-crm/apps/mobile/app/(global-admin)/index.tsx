import React, { useState } from 'react';
import {
  View, Text, FlatList, StyleSheet,
  TouchableOpacity, Alert, Switch,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { globalApi } from '../../hooks/useApiClient';
import { useAuth } from '../../hooks/useAuth';
import {
  Card, Button, Badge, Input, SectionHeader, EmptyState, Divider,
  Colors, Typography, Spacing, Radii,
} from '@cfb-crm/ui';
import type { User } from '@cfb-crm/types';

interface AppPerm {
  app_name:   string;
  role:       string;
  revoked_at: string | null;
}

export default function GlobalAdminScreen() {
  const { isGlobalAdmin } = useAuth();
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [selectedUser, setSelectedUser] = useState<User | null>(null);

  const { data: usersData, isLoading } = useQuery({
    queryKey: ['admin-users', search],
    queryFn: async () => {
      const { data } = await globalApi.get('/users', {
        params: search ? { search } : {},
      });
      return data;
    },
    enabled: isGlobalAdmin(),
  });

  const { data: permsData } = useQuery({
    queryKey: ['user-permissions', selectedUser?.id],
    queryFn: async () => {
      const { data } = await globalApi.get(`/permissions/${selectedUser!.id}`);
      return data.data;
    },
    enabled: !!selectedUser,
  });

  const toggleActiveMutation = useMutation({
    mutationFn: async ({ id, isActive }: { id: string; isActive: boolean }) => {
      await globalApi.patch(`/users/${id}`, { isActive });
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin-users'] }),
  });

  const grantPermissionMutation = useMutation({
    mutationFn: async ({ userId, appName, role }: { userId: string; appName: string; role: string }) => {
      await globalApi.post('/permissions', { userId, appName, role });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['user-permissions', selectedUser?.id] });
      queryClient.invalidateQueries({ queryKey: ['admin-users'] });
    },
  });

  const revokePermissionMutation = useMutation({
    mutationFn: async ({ userId, appName }: { userId: string; appName: string }) => {
      await globalApi.delete(`/permissions/${userId}/${appName}`);
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['user-permissions', selectedUser?.id] }),
  });

  if (!isGlobalAdmin()) {
    return (
      <SafeAreaView style={styles.safe}>
        <EmptyState title="Access Denied" message="Global Admin access required." />
      </SafeAreaView>
    );
  }

  const users: User[] = usersData?.data ?? [];

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.header}>
        <Text style={styles.title}>Global Admin</Text>
        <Text style={styles.subtitle}>Users & Permissions</Text>
      </View>

      <Input
        placeholder="Search users..."
        value={search}
        onChangeText={setSearch}
        containerStyle={styles.search}
      />

      <FlatList
        data={users}
        keyExtractor={(u) => u.id}
        contentContainerStyle={styles.list}
        ItemSeparatorComponent={() => <View style={{ height: Spacing.sm }} />}
        ListEmptyComponent={<EmptyState title="No users found" />}
        renderItem={({ item: user }) => (
          <TouchableOpacity onPress={() => setSelectedUser(selectedUser?.id === user.id ? null : user)}>
            <Card style={[styles.userCard, selectedUser?.id === user.id && styles.userCardSelected]}>
              {/* User row */}
              <View style={styles.userRow}>
                <View style={styles.avatar}>
                  <Text style={styles.avatarText}>
                    {user.firstName[0]}{user.lastName[0]}
                  </Text>
                </View>
                <View style={{ flex: 1 }}>
                  <Text style={styles.userName}>{user.firstName} {user.lastName}</Text>
                  <Text style={styles.userEmail}>{user.email}</Text>
                </View>
                <View style={styles.userRight}>
                  <Badge
                    label={user.globalRole.replace('_', ' ')}
                    variant={user.globalRole === 'global_admin' ? 'danger' : 'default'}
                  />
                  <Switch
                    value={user.isActive}
                    onValueChange={(v) => {
                      Alert.alert(
                        v ? 'Activate User' : 'Deactivate User',
                        `${v ? 'Enable' : 'Disable'} access for ${user.firstName} ${user.lastName}?`,
                        [
                          { text: 'Cancel', style: 'cancel' },
                          { text: 'Confirm', onPress: () => toggleActiveMutation.mutate({ id: user.id, isActive: v }) },
                        ],
                      );
                    }}
                    trackColor={{ false: Colors.gray300, true: Colors.rosterTint }}
                    thumbColor={Colors.white}
                    style={{ transform: [{ scaleX: 0.8 }, { scaleY: 0.8 }] }}
                  />
                </View>
              </View>

              {/* Expanded permission panel */}
              {selectedUser?.id === user.id && (
                <View style={styles.permsPanel}>
                  <Divider />
                  <Text style={styles.permsTitle}>App Permissions</Text>

                  {(['roster', 'alumni', 'global-admin'] as const).map((app) => {
                    const existing = (permsData as AppPerm[] | undefined)?.find((p) => p.app_name === app && !p.revoked_at);
                    return (
                      <View key={app} style={styles.permRow}>
                        <View style={{ flex: 1 }}>
                          <Text style={styles.permApp}>{app}</Text>
                          {existing && (
                            <Text style={styles.permRole}>{existing.role}</Text>
                          )}
                        </View>
                        {existing ? (
                          <Button
                            label="Revoke"
                            variant="danger"
                            size="sm"
                            onPress={() => revokePermissionMutation.mutate({ userId: user.id, appName: app })}
                          />
                        ) : (
                          <Button
                            label="Grant"
                            variant="outline"
                            size="sm"
                            onPress={() => grantPermissionMutation.mutate({
                              userId:  user.id,
                              appName: app,
                              role:    'readonly',
                            })}
                          />
                        )}
                      </View>
                    );
                  })}
                </View>
              )}
            </Card>
          </TouchableOpacity>
        )}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe:             { flex: 1, backgroundColor: Colors.background },
  header:           { paddingHorizontal: Spacing.base, paddingVertical: Spacing.base },
  title:            { fontSize: Typography.xxl, fontWeight: Typography.bold, color: Colors.textPrimary },
  subtitle:         { fontSize: Typography.sm, color: Colors.textTertiary, marginTop: 2 },
  search:           { paddingHorizontal: Spacing.base, marginBottom: Spacing.sm },
  list:             { paddingHorizontal: Spacing.base, paddingBottom: Spacing.xxl },
  userCard:         { padding: Spacing.md },
  userCardSelected: { borderColor: Colors.primary, borderWidth: 1.5 },
  userRow:          { flexDirection: 'row', alignItems: 'center', gap: Spacing.md },
  avatar:           { width: 40, height: 40, borderRadius: Radii.full, backgroundColor: Colors.primaryLight, alignItems: 'center', justifyContent: 'center' },
  avatarText:       { fontSize: Typography.sm, fontWeight: Typography.bold, color: Colors.textInverse },
  userName:         { fontSize: Typography.base, fontWeight: Typography.semibold, color: Colors.textPrimary },
  userEmail:        { fontSize: Typography.xs, color: Colors.textTertiary, marginTop: 1 },
  userRight:        { alignItems: 'flex-end', gap: Spacing.xs },
  permsPanel:       { marginTop: Spacing.sm },
  permsTitle:       { fontSize: Typography.sm, fontWeight: Typography.semibold, color: Colors.textSecondary, marginBottom: Spacing.sm, marginTop: Spacing.sm },
  permRow:          { flexDirection: 'row', alignItems: 'center', marginBottom: Spacing.sm },
  permApp:          { fontSize: Typography.sm, fontWeight: Typography.medium, color: Colors.textPrimary, textTransform: 'capitalize' },
  permRole:         { fontSize: Typography.xs, color: Colors.textTertiary, marginTop: 1 },
});
