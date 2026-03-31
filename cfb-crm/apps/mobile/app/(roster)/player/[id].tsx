import React, { useState } from 'react';
import {
  View, Text, ScrollView, StyleSheet,
  TouchableOpacity, Alert, type KeyboardTypeOptions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { appApi, getApiError } from '../../../hooks/useApiClient';
import { useAuth } from '../../../hooks/useAuth';
import {
  Card, Badge, Button, Input, Divider, StatPill,
  Colors, Typography, Spacing, Radii, Shadows,
  PlayerStatusColor,
} from '@cfb-crm/ui';
import type { Player } from '@cfb-crm/types';

export default function PlayerDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router  = useRouter();
  const { canWrite, isAppAdmin } = useAuth();
  const queryClient = useQueryClient();

  const [editing, setEditing] = useState(false);
  const [editFields, setEditFields] = useState<Partial<Player>>({});

  const { data, isLoading } = useQuery({
    queryKey: ['player', id],
    queryFn: async () => {
      const { data } = await appApi.get(`/players/${id}`);
      return data.data[0] as Player;
    },
    enabled: !!id,
  });

  const updateMutation = useMutation({
    mutationFn: async (fields: Partial<Player>) => {
      await appApi.patch(`/players/${id}`, fields);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['player', id] });
      queryClient.invalidateQueries({ queryKey: ['players'] });
      setEditing(false);
      setEditFields({});
    },
    onError: (err: Error) => {
      Alert.alert('Update Failed', getApiError(err, 'Could not update player.'));
    },
  });

  if (isLoading || !data) {
    return (
      <SafeAreaView style={styles.safe}>
        <View style={styles.loadingRow}>
          <Text style={styles.loadingText}>Loading...</Text>
        </View>
      </SafeAreaView>
    );
  }

  const statusColor = PlayerStatusColor[data.status] ?? Colors.gray400;
  const field = (key: keyof Player) =>
    editing && editFields[key] !== undefined ? String(editFields[key]) : String(data[key] ?? '');

  return (
    <SafeAreaView style={styles.safe}>
      {/* Back nav */}
      <TouchableOpacity style={styles.backBtn} onPress={() => router.back()}>
        <Text style={styles.backText}>← Roster</Text>
      </TouchableOpacity>

      <ScrollView contentContainerStyle={styles.scroll}>
        {/* Hero card */}
        <Card style={styles.heroCard} shadow="md">
          <View style={styles.heroTop}>
            <View style={[styles.jerseyBig, { backgroundColor: Colors.rosterTint }]}>
              <Text style={styles.jerseyNumBig}>{data.jerseyNumber ?? '–'}</Text>
            </View>
            <View style={{ flex: 1 }}>
              <Text style={styles.heroName}>{data.firstName} {data.lastName}</Text>
              <Text style={styles.heroSub}>{data.position} · {data.academicYear}</Text>
              <View style={[styles.statusDot, { backgroundColor: statusColor }]}>
                <Text style={styles.statusText}>{data.status}</Text>
              </View>
            </View>
            {canWrite('roster') && (
              <Button
                label={editing ? 'Cancel' : 'Edit'}
                variant={editing ? 'ghost' : 'outline'}
                size="sm"
                onPress={() => { setEditing((v) => !v); setEditFields({}); }}
              />
            )}
          </View>

          {/* Quick stats */}
          <View style={styles.statsRow}>
            <StatPill label="Class" value={data.recruitingClass} />
            {data.heightInches && (
              <StatPill label="Height" value={`${Math.floor(data.heightInches / 12)}'${data.heightInches % 12}"`} />
            )}
            {data.weightLbs && <StatPill label="Weight" value={`${data.weightLbs} lbs`} />}
            {data.gpa != null && <StatPill label="GPA" value={data.gpa.toFixed(2)} />}
          </View>
        </Card>

        {/* Academic info */}
        <Text style={styles.sectionTitle}>Academic</Text>
        <Card>
          <InfoRow label="Major"      value={data.major} editable={editing} onEdit={(v) => setEditFields((p) => ({ ...p, major: v }))} />
          <Divider />
          <InfoRow label="GPA"        value={data.gpa?.toFixed(2)} editable={editing} keyboardType="decimal-pad" onEdit={(v) => setEditFields((p) => ({ ...p, gpa: parseFloat(v) }))} />
          <Divider />
          <InfoRow label="Year"       value={data.academicYear} />
          <Divider />
          <InfoRow label="High School" value={data.highSchool} />
        </Card>

        {/* Contact info */}
        <Text style={styles.sectionTitle}>Contact</Text>
        <Card>
          <InfoRow label="Phone"  value={data.phone} editable={editing} keyboardType="phone-pad" onEdit={(v) => setEditFields((p) => ({ ...p, phone: v }))} />
          <Divider />
          <InfoRow label="Hometown" value={data.homeTown ? `${data.homeTown}, ${data.homeState}` : undefined} />
          <Divider />
          <InfoRow label="Emergency Contact" value={data.emergencyContactName} />
          <Divider />
          <InfoRow label="Emergency Phone"   value={data.emergencyContactPhone} editable={editing} keyboardType="phone-pad" onEdit={(v) => setEditFields((p) => ({ ...p, emergencyContactPhone: v }))} />
        </Card>

        {/* Notes */}
        <Text style={styles.sectionTitle}>Notes</Text>
        <Card>
          {editing ? (
            <Input
              value={editFields.notes ?? data.notes ?? ''}
              onChangeText={(v) => setEditFields((p) => ({ ...p, notes: v }))}
              multiline
              numberOfLines={4}
              style={{ minHeight: 80 }}
            />
          ) : (
            <Text style={styles.notesText}>{data.notes || 'No notes.'}</Text>
          )}
        </Card>

        {/* Save button */}
        {editing && Object.keys(editFields).length > 0 && (
          <Button
            label="Save Changes"
            onPress={() => updateMutation.mutate(editFields)}
            loading={updateMutation.isPending}
            variant="roster"
            fullWidth
            size="lg"
            style={{ marginTop: Spacing.base }}
          />
        )}

        {/* Danger zone — admin only */}
        {isAppAdmin('roster') && !editing && (
          <View style={styles.dangerZone}>
            <Text style={styles.dangerTitle}>Status</Text>
            {(['active','injured','suspended','transferred'] as const).map((s) => (
              <TouchableOpacity
                key={s}
                style={[styles.statusBtn, data.status === s && styles.statusBtnActive]}
                onPress={() => {
                  if (data.status === s) return;
                  Alert.alert('Change Status', `Set ${data.firstName} to "${s}"?`, [
                    { text: 'Cancel', style: 'cancel' },
                    { text: 'Confirm', onPress: () => updateMutation.mutate({ status: s }) },
                  ]);
                }}
              >
                <View style={[styles.statusIndicator, { backgroundColor: PlayerStatusColor[s] }]} />
                <Text style={styles.statusBtnText}>{s}</Text>
                {data.status === s && <Text style={styles.statusCheck}>✓</Text>}
              </TouchableOpacity>
            ))}
          </View>
        )}

        <View style={{ height: Spacing.xxxl }} />
      </ScrollView>
    </SafeAreaView>
  );
}

// ─── InfoRow helper ───────────────────────────────────────────
function InfoRow({
  label, value, editable, onEdit, keyboardType,
}: {
  label: string;
  value?: string | number | null;
  editable?: boolean;
  onEdit?: (v: string) => void;
  keyboardType?: KeyboardTypeOptions;
}) {
  return (
    <View style={infoStyles.row}>
      <Text style={infoStyles.label}>{label}</Text>
      {editable && onEdit ? (
        <Input
          value={String(value ?? '')}
          onChangeText={onEdit}
          keyboardType={keyboardType}
          containerStyle={infoStyles.inputContainer}
          inputStyle={infoStyles.inputInline}
        />
      ) : (
        <Text style={infoStyles.value}>{value ?? '—'}</Text>
      )}
    </View>
  );
}

const infoStyles = StyleSheet.create({
  row:            { flexDirection: 'row', alignItems: 'center', paddingVertical: Spacing.sm },
  label:          { width: 130, fontSize: Typography.sm, color: Colors.textTertiary, fontWeight: Typography.medium },
  value:          { flex: 1, fontSize: Typography.base, color: Colors.textPrimary },
  inputContainer: { flex: 1, gap: 0 },
  inputInline:    { paddingVertical: Spacing.xs, paddingHorizontal: Spacing.sm, fontSize: Typography.base },
});

// ─── Styles ───────────────────────────────────────────────────
const styles = StyleSheet.create({
  safe:           { flex: 1, backgroundColor: Colors.background },
  loadingRow:     { flex: 1, alignItems: 'center', justifyContent: 'center' },
  loadingText:    { color: Colors.textTertiary, fontSize: Typography.base },
  backBtn:        { paddingHorizontal: Spacing.base, paddingVertical: Spacing.sm },
  backText:       { fontSize: Typography.base, color: Colors.primary, fontWeight: Typography.medium },
  scroll:         { paddingHorizontal: Spacing.base, paddingTop: Spacing.sm },
  heroCard:       { marginBottom: Spacing.base },
  heroTop:        { flexDirection: 'row', alignItems: 'flex-start', gap: Spacing.md, marginBottom: Spacing.md },
  jerseyBig:      { width: 64, height: 64, borderRadius: Radii.md, alignItems: 'center', justifyContent: 'center' },
  jerseyNumBig:   { fontSize: Typography.xxl, fontWeight: Typography.bold, color: Colors.textInverse },
  heroName:       { fontSize: Typography.xl, fontWeight: Typography.bold, color: Colors.textPrimary },
  heroSub:        { fontSize: Typography.sm, color: Colors.textSecondary, marginTop: 2 },
  statusDot:      { alignSelf: 'flex-start', marginTop: Spacing.xs, paddingHorizontal: Spacing.sm, paddingVertical: 2, borderRadius: Radii.full },
  statusText:     { fontSize: Typography.xs, fontWeight: Typography.semibold, color: Colors.white, textTransform: 'capitalize' },
  statsRow:       { flexDirection: 'row', gap: Spacing.sm, flexWrap: 'wrap' },
  sectionTitle:   { fontSize: Typography.sm, fontWeight: Typography.semibold, color: Colors.textTertiary, textTransform: 'uppercase', letterSpacing: 0.8, marginTop: Spacing.base, marginBottom: Spacing.xs },
  notesText:      { fontSize: Typography.base, color: Colors.textSecondary, lineHeight: 22 },
  dangerZone:     { marginTop: Spacing.xl, backgroundColor: Colors.surface, borderRadius: Radii.md, borderWidth: 1, borderColor: Colors.border, padding: Spacing.base },
  dangerTitle:    { fontSize: Typography.sm, fontWeight: Typography.semibold, color: Colors.textTertiary, textTransform: 'uppercase', letterSpacing: 0.8, marginBottom: Spacing.sm },
  statusBtn:      { flexDirection: 'row', alignItems: 'center', paddingVertical: Spacing.sm, gap: Spacing.sm },
  statusBtnActive:{ backgroundColor: Colors.gray50, borderRadius: Radii.xs, marginHorizontal: -Spacing.xs, paddingHorizontal: Spacing.xs },
  statusIndicator:{ width: 10, height: 10, borderRadius: 5 },
  statusBtnText:  { flex: 1, fontSize: Typography.base, color: Colors.textPrimary, textTransform: 'capitalize' },
  statusCheck:    { fontSize: Typography.base, color: Colors.rosterTint, fontWeight: Typography.bold },
});
