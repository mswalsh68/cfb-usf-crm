import React, { useState } from 'react';
import {
  View, Text, ScrollView, StyleSheet,
  TouchableOpacity, Alert, TextInput,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { appApi, getApiError } from '../../../hooks/useApiClient';
import { useAuth } from '../../../hooks/useAuth';
import {
  Card, Badge, Button, Input, Divider, StatPill,
  Colors, Typography, Spacing, Radii,
  AlumniStatusColor,
} from '@cfb-crm/ui';
import type { Alumni } from '@cfb-crm/types';

interface Interaction {
  id:          string;
  channel:     string;
  summary:     string;
  outcome?:    string;
  logged_at:   string;
  follow_up_at?: string;
}

export default function AlumniDetailScreen() {
  const { id }  = useLocalSearchParams<{ id: string }>();
  const router  = useRouter();
  const { canWrite } = useAuth();
  const queryClient  = useQueryClient();

  const [editing,    setEditing]    = useState(false);
  const [editFields, setEditFields] = useState<Partial<Alumni>>({});
  const [logChannel, setLogChannel] = useState('phone');
  const [logSummary, setLogSummary] = useState('');
  const [showLogForm, setShowLogForm] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['alumni', id],
    queryFn: async () => {
      const { data } = await appApi.get(`/alumni/${id}`);
      return data.data;
    },
    enabled: !!id,
  });

  const updateMutation = useMutation({
    mutationFn: async (fields: Partial<Alumni>) => {
      await appApi.patch(`/alumni/${id}`, fields);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['alumni', id] });
      queryClient.invalidateQueries({ queryKey: ['alumni'] });
      setEditing(false);
      setEditFields({});
    },
    onError: (err: Error) => Alert.alert('Update Failed', getApiError(err, 'Could not update.')),
  });

  const logMutation = useMutation({
    mutationFn: async () => {
      await appApi.post(`/alumni/${id}/interactions`, {
        channel: logChannel,
        summary: logSummary,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['alumni', id] });
      setLogSummary('');
      setShowLogForm(false);
    },
    onError: (err: Error) => Alert.alert('Error', getApiError(err, 'Could not log interaction.')),
  });

  if (isLoading || !data) {
    return (
      <SafeAreaView style={styles.safe}>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
          <Text style={{ color: Colors.textTertiary }}>Loading...</Text>
        </View>
      </SafeAreaView>
    );
  }

  const alumni: Alumni = data;
  const statusColor = AlumniStatusColor[alumni.status] ?? Colors.gray400;

  return (
    <SafeAreaView style={styles.safe}>
      <TouchableOpacity style={styles.backBtn} onPress={() => router.back()}>
        <Text style={styles.backText}>← Alumni</Text>
      </TouchableOpacity>

      <ScrollView contentContainerStyle={styles.scroll}>
        {/* Hero */}
        <Card style={styles.heroCard} shadow="md">
          <View style={styles.heroTop}>
            <View style={[styles.classBubble, { backgroundColor: Colors.alumniTint }]}>
              <Text style={styles.classYear}>'{String(alumni.graduationYear).slice(-2)}</Text>
            </View>
            <View style={{ flex: 1 }}>
              <Text style={styles.heroName}>{alumni.firstName} {alumni.lastName}</Text>
              <Text style={styles.heroSub}>
                {alumni.position} · {alumni.graduationSemester} {alumni.graduationYear}
              </Text>
              <View style={[styles.statusPill, { backgroundColor: statusColor }]}>
                <Text style={styles.statusPillText}>{alumni.status}</Text>
              </View>
            </View>
            <View style={{ alignItems: 'flex-end', gap: Spacing.xs }}>
              {alumni.isDonor && <Badge label="Donor ⭐" variant="default" />}
              {canWrite('alumni') && (
                <Button
                  label={editing ? 'Cancel' : 'Edit'}
                  variant={editing ? 'ghost' : 'outline'}
                  size="sm"
                  onPress={() => { setEditing((v) => !v); setEditFields({}); }}
                />
              )}
            </View>
          </View>

          <View style={styles.statsRow}>
            <StatPill label="Class"       value={alumni.recruitingClass} />
            <StatPill label="Engagement"  value={`${alumni.engagementScore ?? 0}/100`} />
            {alumni.totalDonations != null && alumni.totalDonations > 0 && (
              <StatPill label="Donations" value={`$${alumni.totalDonations.toLocaleString()}`} />
            )}
          </View>
        </Card>

        {/* Career */}
        <Text style={styles.sectionTitle}>Career</Text>
        <Card>
          {[
            { label: 'Employer',  key: 'currentEmployer'  as const },
            { label: 'Title',     key: 'currentJobTitle'  as const },
            { label: 'City',      key: 'currentCity'      as const },
            { label: 'State',     key: 'currentState'     as const },
          ].map(({ label, key }, i, arr) => (
            <View key={key}>
              <View style={styles.infoRow}>
                <Text style={styles.infoLabel}>{label}</Text>
                {editing ? (
                  <Input
                    value={String(editFields[key] ?? alumni[key] ?? '')}
                    onChangeText={(v) => setEditFields((p) => ({ ...p, [key]: v }))}
                    containerStyle={{ flex: 1, gap: 0 }}
                    inputStyle={{ paddingVertical: Spacing.xs, paddingHorizontal: Spacing.sm }}
                  />
                ) : (
                  <Text style={styles.infoValue}>{alumni[key] ?? '—'}</Text>
                )}
              </View>
              {i < arr.length - 1 && <Divider />}
            </View>
          ))}
        </Card>

        {/* Contact */}
        <Text style={styles.sectionTitle}>Contact</Text>
        <Card>
          {[
            { label: 'Email',    key: 'personalEmail' as const },
            { label: 'Phone',    key: 'phone'         as const },
            { label: 'LinkedIn', key: 'linkedInUrl'   as const },
          ].map(({ label, key }, i, arr) => (
            <View key={key}>
              <View style={styles.infoRow}>
                <Text style={styles.infoLabel}>{label}</Text>
                {editing ? (
                  <Input
                    value={String(editFields[key] ?? alumni[key] ?? '')}
                    onChangeText={(v) => setEditFields((p) => ({ ...p, [key]: v }))}
                    containerStyle={{ flex: 1, gap: 0 }}
                    inputStyle={{ paddingVertical: Spacing.xs, paddingHorizontal: Spacing.sm }}
                  />
                ) : (
                  <Text style={[styles.infoValue, key === 'personalEmail' && { color: Colors.textLink }]}>
                    {alumni[key] ?? '—'}
                  </Text>
                )}
              </View>
              {i < arr.length - 1 && <Divider />}
            </View>
          ))}
        </Card>

        {editing && Object.keys(editFields).length > 0 && (
          <Button
            label="Save Changes"
            onPress={() => updateMutation.mutate(editFields)}
            loading={updateMutation.isPending}
            variant="alumni"
            fullWidth
            size="lg"
            style={{ marginTop: Spacing.base }}
          />
        )}

        {/* Interaction Log */}
        <View style={styles.sectionRow}>
          <Text style={styles.sectionTitle}>Interaction Log</Text>
          {canWrite('alumni') && (
            <TouchableOpacity onPress={() => setShowLogForm((v) => !v)}>
              <Text style={styles.addLink}>{showLogForm ? 'Cancel' : '+ Log'}</Text>
            </TouchableOpacity>
          )}
        </View>

        {showLogForm && (
          <Card style={{ marginBottom: Spacing.sm }}>
            <Text style={styles.logFormLabel}>Channel</Text>
            <View style={styles.channelRow}>
              {['phone','email','in_person','event'].map((c) => (
                <TouchableOpacity
                  key={c}
                  style={[styles.channelPill, logChannel === c && styles.channelPillActive]}
                  onPress={() => setLogChannel(c)}
                >
                  <Text style={[styles.channelText, logChannel === c && styles.channelTextActive]}>
                    {c.replace('_', ' ')}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
            <Input
              label="Summary"
              value={logSummary}
              onChangeText={setLogSummary}
              multiline
              numberOfLines={3}
              placeholder="What was discussed?"
              containerStyle={{ marginTop: Spacing.sm }}
            />
            <Button
              label="Save Interaction"
              onPress={() => logMutation.mutate()}
              loading={logMutation.isPending}
              variant="alumni"
              fullWidth
              style={{ marginTop: Spacing.md }}
              disabled={!logSummary.trim()}
            />
          </Card>
        )}

        {(data.interactions ?? []).length === 0 ? (
          <Text style={styles.noInteractions}>No interactions logged yet.</Text>
        ) : (
          (data.interactions as Interaction[]).map((interaction) => (
            <Card key={interaction.id} style={styles.interactionCard}>
              <View style={styles.interactionHeader}>
                <Badge label={interaction.channel} variant="info" />
                <Text style={styles.interactionDate}>
                  {new Date(interaction.logged_at).toLocaleDateString()}
                </Text>
              </View>
              <Text style={styles.interactionSummary}>{interaction.summary}</Text>
              {interaction.outcome && (
                <Text style={styles.interactionOutcome}>Outcome: {interaction.outcome}</Text>
              )}
            </Card>
          ))
        )}

        <View style={{ height: Spacing.xxxl }} />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe:                 { flex: 1, backgroundColor: Colors.background },
  backBtn:              { paddingHorizontal: Spacing.base, paddingVertical: Spacing.sm },
  backText:             { fontSize: Typography.base, color: Colors.primary, fontWeight: Typography.medium },
  scroll:               { paddingHorizontal: Spacing.base, paddingTop: Spacing.sm },
  heroCard:             { marginBottom: Spacing.base },
  heroTop:              { flexDirection: 'row', alignItems: 'flex-start', gap: Spacing.md, marginBottom: Spacing.md },
  classBubble:          { width: 64, height: 64, borderRadius: Radii.md, alignItems: 'center', justifyContent: 'center' },
  classYear:            { fontSize: Typography.xl, fontWeight: Typography.bold, color: Colors.textInverse },
  heroName:             { fontSize: Typography.xl, fontWeight: Typography.bold, color: Colors.textPrimary },
  heroSub:              { fontSize: Typography.sm, color: Colors.textSecondary, marginTop: 2 },
  statusPill:           { alignSelf: 'flex-start', marginTop: Spacing.xs, paddingHorizontal: Spacing.sm, paddingVertical: 2, borderRadius: Radii.full },
  statusPillText:       { fontSize: Typography.xs, fontWeight: Typography.semibold, color: Colors.white, textTransform: 'capitalize' },
  statsRow:             { flexDirection: 'row', gap: Spacing.sm, flexWrap: 'wrap' },
  sectionTitle:         { fontSize: Typography.xs, fontWeight: Typography.semibold, color: Colors.textTertiary, textTransform: 'uppercase', letterSpacing: 0.8, marginTop: Spacing.base, marginBottom: Spacing.xs },
  sectionRow:           { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: Spacing.base, marginBottom: Spacing.xs },
  addLink:              { fontSize: Typography.sm, fontWeight: Typography.semibold, color: Colors.alumniTint },
  infoRow:              { flexDirection: 'row', alignItems: 'center', paddingVertical: Spacing.sm },
  infoLabel:            { width: 80, fontSize: Typography.sm, color: Colors.textTertiary, fontWeight: Typography.medium },
  infoValue:            { flex: 1, fontSize: Typography.base, color: Colors.textPrimary },
  logFormLabel:         { fontSize: Typography.sm, fontWeight: Typography.medium, color: Colors.textSecondary, marginBottom: Spacing.xs },
  channelRow:           { flexDirection: 'row', gap: Spacing.xs, flexWrap: 'wrap' },
  channelPill:          { paddingHorizontal: Spacing.sm, paddingVertical: Spacing.xs, borderRadius: Radii.full, backgroundColor: Colors.gray100, borderWidth: 1, borderColor: Colors.border },
  channelPillActive:    { backgroundColor: Colors.alumniTint, borderColor: Colors.alumniTint },
  channelText:          { fontSize: Typography.xs, fontWeight: Typography.medium, color: Colors.textSecondary, textTransform: 'capitalize' },
  channelTextActive:    { color: Colors.textInverse },
  noInteractions:       { fontSize: Typography.sm, color: Colors.textTertiary, textAlign: 'center', paddingVertical: Spacing.xl },
  interactionCard:      { marginBottom: Spacing.sm, padding: Spacing.md },
  interactionHeader:    { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: Spacing.xs },
  interactionDate:      { fontSize: Typography.xs, color: Colors.textTertiary },
  interactionSummary:   { fontSize: Typography.base, color: Colors.textPrimary, lineHeight: 21 },
  interactionOutcome:   { fontSize: Typography.xs, color: Colors.textSecondary, marginTop: Spacing.xs, fontStyle: 'italic' },
});
