import React, { useState } from 'react';
import {
  View, Text, FlatList, StyleSheet,
  TouchableOpacity, Alert, ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { rosterApi } from '../../hooks/useApiClient';
import { useAuth } from '../../hooks/useAuth';
import {
  Button, Card, Badge, SectionHeader, Input, EmptyState,
  Colors, Typography, Spacing, Radii, Shadows,
} from '@cfb-crm/ui';
import type { Player, GraduationResult } from '@cfb-crm/types';

const SEMESTERS = ['spring', 'fall', 'summer'] as const;
type Semester = typeof SEMESTERS[number];

export default function GraduateScreen() {
  const { canWrite, isAppAdmin } = useAuth();
  const queryClient = useQueryClient();

  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [gradYear,    setGradYear]    = useState(String(new Date().getFullYear()));
  const [semester,    setSemester]    = useState<Semester>('spring');
  const [notes,       setNotes]       = useState('');

  // Only show active players eligible for graduation
  const { data, isLoading } = useQuery({
    queryKey: ['players-graduatable'],
    queryFn:  async () => {
      const { data } = await rosterApi.get('/players', {
        params: { status: 'active', pageSize: '200' },
      });
      return data.data as Player[];
    },
  });

  const graduateMutation = useMutation({
    mutationFn: async () => {
      const { data } = await rosterApi.post('/players/graduate', {
        playerIds:          Array.from(selectedIds),
        graduationYear:     parseInt(gradYear),
        graduationSemester: semester,
        notes: notes || undefined,
      });
      return data.data as GraduationResult;
    },
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: ['players'] });
      queryClient.invalidateQueries({ queryKey: ['players-graduatable'] });
      setSelectedIds(new Set());

      const msg = result.failures.length > 0
        ? `${result.graduatedCount} graduated successfully.\n${result.failures.length} failed — check the audit log.`
        : `${result.graduatedCount} player${result.graduatedCount !== 1 ? 's' : ''} graduated successfully and moved to Alumni.`;

      Alert.alert('Graduation Complete', msg);
    },
    onError: (err: any) => {
      Alert.alert('Graduation Failed', err?.response?.data?.error ?? 'An error occurred. No changes were made.');
    },
  });

  const toggleSelect = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const handleGraduate = () => {
    if (selectedIds.size === 0) {
      Alert.alert('No Players Selected', 'Select at least one player to graduate.');
      return;
    }

    const year = parseInt(gradYear);
    if (isNaN(year) || year < 2000 || year > 2100) {
      Alert.alert('Invalid Year', 'Enter a valid graduation year.');
      return;
    }

    Alert.alert(
      'Confirm Graduation',
      `Graduate ${selectedIds.size} player${selectedIds.size !== 1 ? 's' : ''} in ${semester} ${year}?\n\nThis will remove their Roster access and create Alumni records.`,
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Graduate', style: 'destructive', onPress: () => graduateMutation.mutate() },
      ],
    );
  };

  if (!canWrite('roster') && !isAppAdmin('roster')) {
    return (
      <SafeAreaView style={styles.safe}>
        <EmptyState title="Access Restricted" message="You need write access to graduate players." />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.header}>
        <Text style={styles.title}>Graduate Players</Text>
        <Text style={styles.subtitle}>Select players to move to Alumni CRM</Text>
      </View>

      {/* Config card */}
      <Card style={styles.configCard}>
        <Text style={styles.configLabel}>Graduation details</Text>
        <View style={styles.configRow}>
          <Input
            label="Year"
            value={gradYear}
            onChangeText={setGradYear}
            keyboardType="number-pad"
            containerStyle={{ flex: 1 }}
          />
          <View style={styles.semesterGroup}>
            <Text style={styles.semLabel}>Semester</Text>
            <View style={styles.semRow}>
              {SEMESTERS.map((s) => (
                <TouchableOpacity
                  key={s}
                  onPress={() => setSemester(s)}
                  style={[styles.semPill, semester === s && styles.semPillActive]}
                >
                  <Text style={[styles.semText, semester === s && styles.semTextActive]}>
                    {s.charAt(0).toUpperCase() + s.slice(1)}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>
        </View>
        <Input
          label="Notes (optional)"
          value={notes}
          onChangeText={setNotes}
          placeholder="e.g. Spring 2025 graduating class"
          containerStyle={{ marginTop: Spacing.md }}
        />
      </Card>

      {/* Select all row */}
      <View style={styles.selectAllRow}>
        <Text style={styles.selectionCount}>
          {selectedIds.size} of {data?.length ?? 0} selected
        </Text>
        <TouchableOpacity onPress={() => {
          if (selectedIds.size === data?.length) {
            setSelectedIds(new Set());
          } else {
            setSelectedIds(new Set(data?.map((p) => p.id) ?? []));
          }
        }}>
          <Text style={styles.selectAllText}>
            {selectedIds.size === data?.length ? 'Deselect All' : 'Select All'}
          </Text>
        </TouchableOpacity>
      </View>

      {/* Player list */}
      {isLoading ? (
        <ActivityIndicator color={Colors.rosterTint} style={{ marginTop: Spacing.xxl }} />
      ) : (
        <FlatList
          data={data ?? []}
          keyExtractor={(p) => p.id}
          contentContainerStyle={styles.list}
          ItemSeparatorComponent={() => <View style={{ height: Spacing.sm }} />}
          ListEmptyComponent={<EmptyState title="No eligible players" message="All active players have already graduated or no active players exist." />}
          renderItem={({ item }) => {
            const selected = selectedIds.has(item.id);
            return (
              <TouchableOpacity
                onPress={() => toggleSelect(item.id)}
                style={[styles.playerRow, selected && styles.playerRowSelected]}
              >
                <View style={[styles.checkbox, selected && styles.checkboxSelected]}>
                  {selected && <Text style={styles.checkmark}>✓</Text>}
                </View>
                <View style={styles.playerInfo}>
                  <Text style={styles.playerName}>{item.lastName}, {item.firstName}</Text>
                  <Text style={styles.playerSub}>#{item.jerseyNumber} · {item.position} · {item.academicYear}</Text>
                </View>
                <Badge label={item.academicYear ?? '—'} variant="roster" />
              </TouchableOpacity>
            );
          }}
        />
      )}

      {/* CTA */}
      {selectedIds.size > 0 && (
        <View style={styles.ctaBar}>
          <Button
            label={`Graduate ${selectedIds.size} Player${selectedIds.size !== 1 ? 's' : ''}`}
            onPress={handleGraduate}
            loading={graduateMutation.isPending}
            variant="roster"
            fullWidth
            size="lg"
          />
        </View>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe:           { flex: 1, backgroundColor: Colors.background },
  header:         { paddingHorizontal: Spacing.base, paddingVertical: Spacing.base },
  title:          { fontSize: Typography.xxl, fontWeight: Typography.bold, color: Colors.textPrimary },
  subtitle:       { fontSize: Typography.sm, color: Colors.textTertiary, marginTop: 2 },
  configCard:     { marginHorizontal: Spacing.base, marginBottom: Spacing.md },
  configLabel:    { fontSize: Typography.sm, fontWeight: Typography.semibold, color: Colors.textSecondary, marginBottom: Spacing.sm },
  configRow:      { flexDirection: 'row', gap: Spacing.md, alignItems: 'flex-start' },
  semesterGroup:  { flex: 2 },
  semLabel:       { fontSize: Typography.sm, fontWeight: Typography.medium, color: Colors.textSecondary, marginBottom: Spacing.xs },
  semRow:         { flexDirection: 'row', gap: Spacing.xs },
  semPill:        { paddingHorizontal: Spacing.sm, paddingVertical: Spacing.xs + 1, borderRadius: Radii.full, backgroundColor: Colors.gray100, borderWidth: 1, borderColor: Colors.border },
  semPillActive:  { backgroundColor: Colors.rosterTint, borderColor: Colors.rosterTint },
  semText:        { fontSize: Typography.xs, fontWeight: Typography.medium, color: Colors.textSecondary },
  semTextActive:  { color: Colors.textInverse },
  selectAllRow:   { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: Spacing.base, paddingBottom: Spacing.sm },
  selectionCount: { fontSize: Typography.sm, color: Colors.textSecondary },
  selectAllText:  { fontSize: Typography.sm, fontWeight: Typography.semibold, color: Colors.rosterTint },
  list:           { paddingHorizontal: Spacing.base, paddingBottom: 100 },
  playerRow:      { flexDirection: 'row', alignItems: 'center', backgroundColor: Colors.surface, borderRadius: Radii.md, padding: Spacing.md, borderWidth: 1.5, borderColor: Colors.border },
  playerRowSelected: { borderColor: Colors.rosterTint, backgroundColor: Colors.rosterLight },
  checkbox:       { width: 22, height: 22, borderRadius: Radii.xs, borderWidth: 2, borderColor: Colors.border, marginRight: Spacing.md, alignItems: 'center', justifyContent: 'center' },
  checkboxSelected: { backgroundColor: Colors.rosterTint, borderColor: Colors.rosterTint },
  checkmark:      { color: Colors.textInverse, fontSize: Typography.sm, fontWeight: Typography.bold },
  playerInfo:     { flex: 1 },
  playerName:     { fontSize: Typography.base, fontWeight: Typography.semibold, color: Colors.textPrimary },
  playerSub:      { fontSize: Typography.xs, color: Colors.textSecondary, marginTop: 2 },
  ctaBar:         { position: 'absolute', bottom: 0, left: 0, right: 0, padding: Spacing.base, backgroundColor: Colors.surface, borderTopWidth: 1, borderTopColor: Colors.border, ...Shadows.lg as any },
});
