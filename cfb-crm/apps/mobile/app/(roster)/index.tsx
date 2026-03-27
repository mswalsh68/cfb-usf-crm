import React, { useState } from 'react';
import {
  View, Text, FlatList, StyleSheet,
  TextInput, TouchableOpacity, RefreshControl,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { appApi } from '../../hooks/useApiClient';
import { useAuth } from '../../hooks/useAuth';
import {
  PlayerCard, Button, Badge, EmptyState, SectionHeader,
  Colors, Typography, Spacing, Radii,
} from '@cfb-crm/ui';
import type { Player } from '@cfb-crm/types';

const POSITIONS = ['All','QB','RB','WR','TE','OL','DL','LB','DB','K','P'];
const STATUSES  = ['All','active','injured','suspended','walkOn'];

export default function RosterScreen() {
  const router    = useRouter();
  const { isGlobalAdmin, hasAppAccess } = useAuth();
  const [search,   setSearch]   = useState('');
  const [position, setPosition] = useState('All');
  const [status,   setStatus]   = useState('All');
  const [page,     setPage]     = useState(1);

  const { data, isLoading, refetch, isRefetching } = useQuery({
    queryKey: ['players', search, position, status, page],
    queryFn: async () => {
      const params: Record<string, string> = { page: String(page), pageSize: '50' };
      if (search)            params.search   = search;
      if (position !== 'All') params.position = position;
      if (status   !== 'All') params.status   = status;
      const { data } = await appApi.get('/players', { params });
      return data;
    },
  });

  const players: Player[] = data?.data ?? [];

  return (
    <SafeAreaView style={styles.safe}>
      {/* Header */}
      <View style={styles.header}>
        <View>
          <Text style={styles.title}>Roster</Text>
          <Text style={styles.subtitle}>{data?.total ?? 0} players</Text>
        </View>
        {(isGlobalAdmin() || hasAppAccess('alumni')) && (
          <Button
            label="Alumni"
            variant="outline"
            size="sm"
            onPress={() => router.push('/(alumni)/')}
          />
        )}
      </View>

      {/* Search */}
      <View style={styles.searchRow}>
        <TextInput
          style={styles.searchInput}
          placeholder="Search name or jersey #"
          placeholderTextColor={Colors.textTertiary}
          value={search}
          onChangeText={(t) => { setSearch(t); setPage(1); }}
          clearButtonMode="while-editing"
        />
      </View>

      {/* Position filter pills */}
      <FlatList
        data={POSITIONS}
        horizontal
        showsHorizontalScrollIndicator={false}
        keyExtractor={(i) => i}
        contentContainerStyle={styles.filterRow}
        renderItem={({ item }) => (
          <TouchableOpacity
            onPress={() => { setPosition(item); setPage(1); }}
            style={[styles.pill, position === item && styles.pillActive]}
          >
            <Text style={[styles.pillText, position === item && styles.pillTextActive]}>
              {item}
            </Text>
          </TouchableOpacity>
        )}
      />

      {/* Player list */}
      <FlatList
        data={players}
        keyExtractor={(p) => p.id}
        contentContainerStyle={styles.listContent}
        ItemSeparatorComponent={() => <View style={{ height: Spacing.sm }} />}
        refreshControl={<RefreshControl refreshing={isRefetching} onRefresh={refetch} tintColor={Colors.rosterTint} />}
        ListEmptyComponent={
          !isLoading ? (
            <EmptyState
              title="No players found"
              message="Try adjusting your filters or add a new player."
            />
          ) : null
        }
        renderItem={({ item }) => (
          <PlayerCard
            player={item}
            onPress={() => router.push(`/(roster)/player/${item.id}`)}
          />
        )}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  header: {
    flexDirection:   'row',
    alignItems:      'center',
    justifyContent:  'space-between',
    paddingHorizontal: Spacing.base,
    paddingTop:      Spacing.base,
    paddingBottom:   Spacing.sm,
  },
  title: {
    fontSize:   Typography.xxl,
    fontWeight: Typography.bold,
    color:      Colors.textPrimary,
  },
  subtitle: {
    fontSize:  Typography.sm,
    color:     Colors.textTertiary,
    marginTop: 2,
  },
  searchRow: {
    paddingHorizontal: Spacing.base,
    paddingBottom:     Spacing.sm,
  },
  searchInput: {
    backgroundColor:   Colors.surface,
    borderWidth:       1.5,
    borderColor:       Colors.border,
    borderRadius:      Radii.sm,
    paddingHorizontal: Spacing.md,
    paddingVertical:   Spacing.md,
    fontSize:          Typography.base,
    color:             Colors.textPrimary,
  },
  filterRow: {
    paddingHorizontal: Spacing.base,
    paddingBottom:     Spacing.sm,
    gap:               Spacing.xs,
  },
  pill: {
    paddingHorizontal: Spacing.md,
    paddingVertical:   Spacing.xs,
    borderRadius:      Radii.full,
    backgroundColor:   Colors.gray100,
    borderWidth:       1,
    borderColor:       Colors.border,
  },
  pillActive: {
    backgroundColor: Colors.rosterTint,
    borderColor:     Colors.rosterTint,
  },
  pillText: {
    fontSize:   Typography.sm,
    fontWeight: Typography.medium,
    color:      Colors.textSecondary,
  },
  pillTextActive: {
    color: Colors.textInverse,
  },
  listContent: {
    paddingHorizontal: Spacing.base,
    paddingBottom:     Spacing.xxl,
  },
});
