import React, { useState } from 'react';
import {
  View, Text, FlatList, StyleSheet,
  TextInput, TouchableOpacity, RefreshControl,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { alumniApi } from '../../hooks/useApiClient';
import { useAuth } from '../../hooks/useAuth';
import {
  AlumniCard, Button, EmptyState,
  Colors, Typography, Spacing, Radii,
} from '@cfb-crm/ui';
import type { Alumni } from '@cfb-crm/types';

const STATUS_FILTERS = ['All', 'active', 'lostContact', 'doNotContact'];

export default function AlumniScreen() {
  const router = useRouter();
  const { isGlobalAdmin, hasAppAccess } = useAuth();
  const [search, setSearch]   = useState('');
  const [status, setStatus]   = useState('All');
  const [onlyDonors, setOnlyDonors] = useState(false);

  const { data, isLoading, refetch, isRefetching } = useQuery({
    queryKey: ['alumni', search, status, onlyDonors],
    queryFn: async () => {
      const params: Record<string, string> = { pageSize: '50' };
      if (search)            params.search   = search;
      if (status !== 'All')  params.status   = status;
      if (onlyDonors)        params.isDonor  = 'true';
      const { data } = await alumniApi.get('/alumni', { params });
      return data;
    },
  });

  const alumni: Alumni[] = data?.data ?? [];

  return (
    <SafeAreaView style={styles.safe}>
      {/* Header */}
      <View style={styles.header}>
        <View>
          <Text style={styles.title}>Alumni</Text>
          <Text style={styles.subtitle}>{data?.total ?? 0} records</Text>
        </View>
        {(isGlobalAdmin() || hasAppAccess('roster')) && (
          <Button
            label="Roster"
            variant="outline"
            size="sm"
            onPress={() => router.push('/(roster)/')}
          />
        )}
      </View>

      {/* Search */}
      <View style={styles.searchRow}>
        <TextInput
          style={styles.searchInput}
          placeholder="Search name, employer, city..."
          placeholderTextColor={Colors.textTertiary}
          value={search}
          onChangeText={setSearch}
          clearButtonMode="while-editing"
        />
      </View>

      {/* Filter row */}
      <View style={styles.filterRow}>
        {STATUS_FILTERS.map((s) => (
          <TouchableOpacity
            key={s}
            onPress={() => setStatus(s)}
            style={[styles.pill, status === s && styles.pillActive]}
          >
            <Text style={[styles.pillText, status === s && styles.pillTextActive]}>{s}</Text>
          </TouchableOpacity>
        ))}
        <TouchableOpacity
          onPress={() => setOnlyDonors((v) => !v)}
          style={[styles.pill, onlyDonors && styles.donorPillActive]}
        >
          <Text style={[styles.pillText, onlyDonors && styles.pillTextActive]}>⭐ Donors</Text>
        </TouchableOpacity>
      </View>

      {/* List */}
      <FlatList
        data={alumni}
        keyExtractor={(a) => a.id}
        contentContainerStyle={styles.listContent}
        ItemSeparatorComponent={() => <View style={{ height: Spacing.sm }} />}
        refreshControl={<RefreshControl refreshing={isRefetching} onRefresh={refetch} tintColor={Colors.alumniTint} />}
        ListEmptyComponent={
          !isLoading ? (
            <EmptyState
              title="No alumni found"
              message="Alumni appear here after players graduate from the Roster."
            />
          ) : null
        }
        renderItem={({ item }) => (
          <AlumniCard
            alumni={item}
            onPress={() => router.push(`/(alumni)/alumni/${item.id}`)}
          />
        )}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe:           { flex: 1, backgroundColor: Colors.background },
  header:         { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: Spacing.base, paddingVertical: Spacing.base },
  title:          { fontSize: Typography.xxl, fontWeight: Typography.bold, color: Colors.textPrimary },
  subtitle:       { fontSize: Typography.sm, color: Colors.textTertiary, marginTop: 2 },
  searchRow:      { paddingHorizontal: Spacing.base, paddingBottom: Spacing.sm },
  searchInput:    { backgroundColor: Colors.surface, borderWidth: 1.5, borderColor: Colors.border, borderRadius: Radii.sm, paddingHorizontal: Spacing.md, paddingVertical: Spacing.md, fontSize: Typography.base, color: Colors.textPrimary },
  filterRow:      { flexDirection: 'row', flexWrap: 'wrap', paddingHorizontal: Spacing.base, paddingBottom: Spacing.sm, gap: Spacing.xs },
  pill:           { paddingHorizontal: Spacing.md, paddingVertical: Spacing.xs, borderRadius: Radii.full, backgroundColor: Colors.gray100, borderWidth: 1, borderColor: Colors.border },
  pillActive:     { backgroundColor: Colors.alumniTint, borderColor: Colors.alumniTint },
  donorPillActive:{ backgroundColor: Colors.accentDark, borderColor: Colors.accentDark },
  pillText:       { fontSize: Typography.sm, fontWeight: Typography.medium, color: Colors.textSecondary },
  pillTextActive: { color: Colors.textInverse },
  listContent:    { paddingHorizontal: Spacing.base, paddingBottom: Spacing.xxl },
});
