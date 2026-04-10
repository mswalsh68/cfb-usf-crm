import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ViewStyle } from 'react-native';
import { Colors, Typography, Spacing, Radii, Shadows } from '../theme/tokens';
import { Badge } from './Primitives';
import { PlayerStatusColor, AlumniStatusColor } from '../theme/tokens';
import type { Player, Alumni } from '@cfb-crm/types';

// ─── Player Row Card (Roster CRM) ─────────────────────────────

interface PlayerCardProps {
  player:   Player;
  onPress?: () => void;
  style?:   ViewStyle;
}

export function PlayerCard({ player, onPress, style }: PlayerCardProps) {
  const statusColor = PlayerStatusColor[player.status] ?? Colors.gray400;

  return (
    <TouchableOpacity
      onPress={onPress}
      activeOpacity={0.78}
      style={[styles.card, style]}
    >
      {/* Jersey number bubble */}
      <View style={[styles.jerseyBubble, { backgroundColor: Colors.rosterTint }]}>
        <Text style={styles.jerseyNumber}>{player.jerseyNumber ?? '–'}</Text>
      </View>

      {/* Main info */}
      <View style={styles.info}>
        <Text style={styles.name} numberOfLines={1}>
          {player.lastName}, {player.firstName}
        </Text>
        <Text style={styles.sub}>
          {player.position} · {player.academicYear ?? '—'}
          {player.major ? ` · ${player.major}` : ''}
        </Text>
      </View>

      {/* Status badge */}
      <View style={styles.right}>
        <Badge
          label={player.status}
          variant={
            player.status === 'active'     ? 'success'  :
            player.status === 'injured'    ? 'warning'  :
            player.status === 'suspended'  ? 'danger'   :
            player.status === 'graduated'  ? 'alumni'   : 'default'
          }
        />
      </View>
    </TouchableOpacity>
  );
}

// ─── Alumni Row Card (Alumni CRM) ─────────────────────────────

interface AlumniCardProps {
  alumni:   Alumni;
  onPress?: () => void;
  style?:   ViewStyle;
}

export function AlumniCard({ alumni, onPress, style }: AlumniCardProps) {
  return (
    <TouchableOpacity
      onPress={onPress}
      activeOpacity={0.78}
      style={[styles.card, style]}
    >
      {/* Class year bubble */}
      <View style={[styles.jerseyBubble, { backgroundColor: Colors.alumniTint }]}>
        <Text style={styles.classYear}>'{String(alumni.graduationYear).slice(-2)}</Text>
      </View>

      {/* Main info */}
      <View style={styles.info}>
        <Text style={styles.name} numberOfLines={1}>
          {alumni.lastName}, {alumni.firstName}
        </Text>
        <Text style={styles.sub} numberOfLines={1}>
          {alumni.position} · {alumni.graduationSemester} {alumni.graduationYear}
          {alumni.currentEmployer ? ` · ${alumni.currentEmployer}` : ''}
        </Text>
      </View>

      {/* Engagement / donor indicator */}
      <View style={styles.right}>
        <Badge
          label={alumni.status}
          variant={
            alumni.status === 'active'       ? 'success' :
            alumni.status === 'lostContact'  ? 'warning' :
            alumni.status === 'doNotContact' ? 'danger'  : 'default'
          }
        />
        {alumni.isDonor && (
          <View style={styles.donorDot} />
        )}
      </View>
    </TouchableOpacity>
  );
}

// ─── Stat Pill (for quick stats on a card) ────────────────────

interface StatPillProps {
  label:  string;
  value:  string | number;
}

export function StatPill({ label, value }: StatPillProps) {
  return (
    <View style={styles.statPill}>
      <Text style={styles.statValue}>{value}</Text>
      <Text style={styles.statLabel}>{label}</Text>
    </View>
  );
}

// ─── Styles ───────────────────────────────────────────────────

const styles = StyleSheet.create({
  card: {
    flexDirection:   'row',
    alignItems:      'center',
    backgroundColor: Colors.surface,
    borderRadius:    Radii.md,
    paddingHorizontal: Spacing.md,
    paddingVertical:   Spacing.md,
    borderWidth:     StyleSheet.hairlineWidth,
    borderColor:     Colors.border,
    ...Shadows.sm,
  },
  jerseyBubble: {
    width:          44,
    height:         44,
    borderRadius:   Radii.sm,
    alignItems:     'center',
    justifyContent: 'center',
    marginRight:    Spacing.md,
  },
  jerseyNumber: {
    fontSize:   Typography.md,
    fontWeight: Typography.bold,
    color:      Colors.textInverse,
  },
  classYear: {
    fontSize:   Typography.sm,
    fontWeight: Typography.bold,
    color:      Colors.textInverse,
  },
  info: {
    flex: 1,
    gap:  3,
  },
  name: {
    fontSize:   Typography.base,
    fontWeight: Typography.semibold,
    color:      Colors.textPrimary,
  },
  sub: {
    fontSize:  Typography.sm,
    color:     Colors.textSecondary,
  },
  right: {
    alignItems:  'flex-end',
    gap:          Spacing.xs,
    marginLeft:   Spacing.sm,
  },
  donorDot: {
    width:           8,
    height:          8,
    borderRadius:    4,
    backgroundColor: Colors.accent,
  },
  statPill: {
    alignItems:      'center',
    backgroundColor: Colors.gray100,
    borderRadius:    Radii.sm,
    paddingHorizontal: Spacing.sm,
    paddingVertical:   Spacing.xxs,
  },
  statValue: {
    fontSize:   Typography.md,
    fontWeight: Typography.bold,
    color:      Colors.textPrimary,
  },
  statLabel: {
    fontSize:  Typography.xs,
    color:     Colors.textTertiary,
  },
});
