import React, { useState } from 'react';
import {
  View, Text, FlatList, StyleSheet,
  TouchableOpacity, Modal, Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { alumniApi } from '../../hooks/useApiClient';
import { useAuth } from '../../hooks/useAuth';
import {
  Card, Badge, Button, Input, EmptyState, Divider,
  Colors, Typography, Spacing, Radii, Shadows,
} from '@cfb-crm/ui';
import type { OutreachCampaign } from '@cfb-crm/types';

const TARGET_OPTS = ['all', 'byClass', 'byPosition', 'byStatus', 'custom'] as const;

export default function OutreachScreen() {
  const { isAppAdmin } = useAuth();
  const queryClient   = useQueryClient();
  const [showCreate, setShowCreate] = useState(false);
  const [form, setForm] = useState({
    name:           '',
    description:    '',
    targetAudience: 'all' as typeof TARGET_OPTS[number],
    scheduledAt:    '',
  });

  const { data, isLoading } = useQuery({
    queryKey: ['campaigns'],
    queryFn: async () => {
      const { data } = await alumniApi.get('/campaigns');
      return data.data as (OutreachCampaign & { total_messages: number; sent_count: number; responded_count: number })[];
    },
  });

  const statsQuery = useQuery({
    queryKey: ['alumni-stats'],
    queryFn: async () => {
      const { data } = await alumniApi.get('/stats');
      return data.data;
    },
  });

  const createMutation = useMutation({
    mutationFn: async () => {
      await alumniApi.post('/campaigns', {
        name:           form.name,
        description:    form.description || undefined,
        targetAudience: form.targetAudience,
        scheduledAt:    form.scheduledAt || undefined,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['campaigns'] });
      setShowCreate(false);
      setForm({ name: '', description: '', targetAudience: 'all', scheduledAt: '' });
    },
    onError: (err: any) => Alert.alert('Error', err?.response?.data?.error ?? 'Could not create campaign.'),
  });

  const stats = statsQuery.data;

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.header}>
        <Text style={styles.title}>Outreach</Text>
        {isAppAdmin('alumni') && (
          <Button label="+ Campaign" variant="alumni" size="sm" onPress={() => setShowCreate(true)} />
        )}
      </View>

      {/* Stats strip */}
      {stats && (
        <View style={styles.statsStrip}>
          <StatItem label="Total Alumni" value={stats.total_alumni} />
          <StatItem label="Active"       value={stats.active} />
          <StatItem label="Donors"       value={stats.donors} />
          <StatItem label="Avg Engagement" value={`${Math.round(stats.avg_engagement ?? 0)}%`} />
        </View>
      )}

      <FlatList
        data={data ?? []}
        keyExtractor={(c) => c.id}
        contentContainerStyle={styles.list}
        ItemSeparatorComponent={() => <View style={{ height: Spacing.sm }} />}
        ListEmptyComponent={
          !isLoading ? (
            <EmptyState
              title="No campaigns yet"
              message="Create a campaign to start reaching out to alumni."
            />
          ) : null
        }
        renderItem={({ item: campaign }) => (
          <Card style={styles.campaignCard}>
            <View style={styles.campaignHeader}>
              <View style={{ flex: 1 }}>
                <Text style={styles.campaignName}>{campaign.name}</Text>
                {campaign.description && (
                  <Text style={styles.campaignDesc} numberOfLines={2}>{campaign.description}</Text>
                )}
              </View>
              <Badge
                label={campaign.status}
                variant={
                  campaign.status === 'active'    ? 'success'  :
                  campaign.status === 'completed' ? 'default'  :
                  campaign.status === 'draft'     ? 'warning'  : 'default'
                }
              />
            </View>

            <Divider />

            <View style={styles.metricsRow}>
              <MetricPill label="Audience"  value={campaign.target_audience} />
              <MetricPill label="Sent"      value={campaign.sent_count ?? 0} />
              <MetricPill label="Responded" value={campaign.responded_count ?? 0} />
              <MetricPill
                label="Rate"
                value={campaign.sent_count > 0
                  ? `${Math.round((campaign.responded_count / campaign.sent_count) * 100)}%`
                  : '—'}
              />
            </View>

            {campaign.scheduled_at && (
              <Text style={styles.scheduledText}>
                Scheduled: {new Date(campaign.scheduled_at).toLocaleDateString()}
              </Text>
            )}
          </Card>
        )}
      />

      {/* Create campaign modal */}
      <Modal visible={showCreate} animationType="slide" presentationStyle="pageSheet">
        <SafeAreaView style={styles.modal}>
          <View style={styles.modalHeader}>
            <Text style={styles.modalTitle}>New Campaign</Text>
            <TouchableOpacity onPress={() => setShowCreate(false)}>
              <Text style={styles.modalClose}>Cancel</Text>
            </TouchableOpacity>
          </View>

          <View style={styles.modalBody}>
            <Input
              label="Campaign Name *"
              value={form.name}
              onChangeText={(v) => setForm((p) => ({ ...p, name: v }))}
              placeholder="e.g. Spring Reunion Outreach"
            />
            <Input
              label="Description"
              value={form.description}
              onChangeText={(v) => setForm((p) => ({ ...p, description: v }))}
              placeholder="Optional — what's the goal?"
              multiline
              numberOfLines={2}
              containerStyle={{ marginTop: Spacing.base }}
            />

            <Text style={styles.audienceLabel}>Target Audience</Text>
            <View style={styles.audienceRow}>
              {TARGET_OPTS.map((opt) => (
                <TouchableOpacity
                  key={opt}
                  style={[styles.audiencePill, form.targetAudience === opt && styles.audiencePillActive]}
                  onPress={() => setForm((p) => ({ ...p, targetAudience: opt }))}
                >
                  <Text style={[styles.audienceText, form.targetAudience === opt && styles.audienceTextActive]}>
                    {opt}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>

            <Button
              label="Create Campaign"
              onPress={() => {
                if (!form.name.trim()) { Alert.alert('Name required'); return; }
                createMutation.mutate();
              }}
              loading={createMutation.isPending}
              variant="alumni"
              fullWidth
              size="lg"
              style={{ marginTop: Spacing.xl }}
            />
          </View>
        </SafeAreaView>
      </Modal>
    </SafeAreaView>
  );
}

function StatItem({ label, value }: { label: string; value: string | number }) {
  return (
    <View style={styles.statItem}>
      <Text style={styles.statValue}>{value}</Text>
      <Text style={styles.statLabel}>{label}</Text>
    </View>
  );
}

function MetricPill({ label, value }: { label: string; value: string | number }) {
  return (
    <View style={styles.metricPill}>
      <Text style={styles.metricValue}>{value}</Text>
      <Text style={styles.metricLabel}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  safe:               { flex: 1, backgroundColor: Colors.background },
  header:             { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: Spacing.base, paddingVertical: Spacing.base },
  title:              { fontSize: Typography.xxl, fontWeight: Typography.bold, color: Colors.textPrimary },
  statsStrip:         { flexDirection: 'row', backgroundColor: Colors.alumniTint, marginHorizontal: Spacing.base, borderRadius: Radii.md, padding: Spacing.md, marginBottom: Spacing.base, gap: Spacing.xs },
  statItem:           { flex: 1, alignItems: 'center' },
  statValue:          { fontSize: Typography.lg, fontWeight: Typography.bold, color: Colors.white },
  statLabel:          { fontSize: Typography.xs, color: 'rgba(255,255,255,0.7)', marginTop: 2, textAlign: 'center' },
  list:               { paddingHorizontal: Spacing.base, paddingBottom: Spacing.xxl },
  campaignCard:       { padding: Spacing.md },
  campaignHeader:     { flexDirection: 'row', alignItems: 'flex-start', gap: Spacing.md, marginBottom: Spacing.sm },
  campaignName:       { fontSize: Typography.base, fontWeight: Typography.semibold, color: Colors.textPrimary },
  campaignDesc:       { fontSize: Typography.sm, color: Colors.textSecondary, marginTop: 2 },
  metricsRow:         { flexDirection: 'row', gap: Spacing.sm, flexWrap: 'wrap', paddingTop: Spacing.sm },
  metricPill:         { alignItems: 'center', backgroundColor: Colors.gray50, borderRadius: Radii.sm, paddingHorizontal: Spacing.sm, paddingVertical: Spacing.xs, minWidth: 64 },
  metricValue:        { fontSize: Typography.md, fontWeight: Typography.bold, color: Colors.textPrimary },
  metricLabel:        { fontSize: Typography.xs, color: Colors.textTertiary, marginTop: 1 },
  scheduledText:      { fontSize: Typography.xs, color: Colors.textTertiary, marginTop: Spacing.sm },
  modal:              { flex: 1, backgroundColor: Colors.background },
  modalHeader:        { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: Spacing.base, paddingVertical: Spacing.base, borderBottomWidth: 1, borderBottomColor: Colors.border },
  modalTitle:         { fontSize: Typography.xl, fontWeight: Typography.bold, color: Colors.textPrimary },
  modalClose:         { fontSize: Typography.base, color: Colors.danger, fontWeight: Typography.medium },
  modalBody:          { padding: Spacing.base },
  audienceLabel:      { fontSize: Typography.sm, fontWeight: Typography.medium, color: Colors.textSecondary, marginTop: Spacing.base, marginBottom: Spacing.xs },
  audienceRow:        { flexDirection: 'row', flexWrap: 'wrap', gap: Spacing.xs },
  audiencePill:       { paddingHorizontal: Spacing.md, paddingVertical: Spacing.xs, borderRadius: Radii.full, backgroundColor: Colors.gray100, borderWidth: 1, borderColor: Colors.border },
  audiencePillActive: { backgroundColor: Colors.alumniTint, borderColor: Colors.alumniTint },
  audienceText:       { fontSize: Typography.sm, fontWeight: Typography.medium, color: Colors.textSecondary },
  audienceTextActive: { color: Colors.textInverse },
});
