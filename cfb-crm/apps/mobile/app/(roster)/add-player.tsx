import React, { useState } from 'react';
import {
  View, Text, ScrollView, StyleSheet, Alert, TouchableOpacity,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { appApi } from '../../hooks/useApiClient';
import { useAuth } from '../../hooks/useAuth';
import {
  Card, Button, Input, EmptyState,
  Colors, Typography, Spacing, Radii,
} from '@cfb-crm/ui';
import type { PositionGroup, AcademicYear } from '@cfb-crm/types';

const POSITIONS: PositionGroup[] = ['QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH'];
const YEARS: AcademicYear[]      = ['freshman','sophomore','junior','senior','graduate'];

export default function AddPlayerScreen() {
  const router       = useRouter();
  const { canWrite, user } = useAuth();
  const queryClient  = useQueryClient();

  const [form, setForm] = useState({
    firstName:            '',
    lastName:             '',
    jerseyNumber:         '',
    position:             '' as PositionGroup | '',
    academicYear:         '' as AcademicYear | '',
    recruitingClass:      String(new Date().getFullYear()),
    heightFeet:           '',
    heightInches:         '',
    weightLbs:            '',
    homeTown:             '',
    homeState:            '',
    highSchool:           '',
    major:                '',
    gpa:                  '',
    phone:                '',
    emergencyContactName: '',
    emergencyContactPhone:'',
    notes:                '',
  });
  const [errors, setErrors] = useState<Record<string, string>>({});

  const set = (key: keyof typeof form) => (v: string) =>
    setForm((p) => ({ ...p, [key]: v }));

  const validate = (): boolean => {
    const e: Record<string, string> = {};
    if (!form.firstName.trim())  e.firstName  = 'Required';
    if (!form.lastName.trim())   e.lastName   = 'Required';
    if (!form.position)          e.position   = 'Select a position';
    if (!form.academicYear)      e.academicYear= 'Select a year';
    const yr = parseInt(form.recruitingClass);
    if (isNaN(yr) || yr < 2000)  e.recruitingClass = 'Enter a valid year (2000+)';
    setErrors(e);
    return Object.keys(e).length === 0;
  };

  const createMutation = useMutation({
    mutationFn: async () => {
      const heightInches = form.heightFeet && form.heightInches
        ? parseInt(form.heightFeet) * 12 + parseInt(form.heightInches)
        : undefined;

      await appApi.post('/players', {
        userId:               user!.id,
        firstName:            form.firstName.trim(),
        lastName:             form.lastName.trim(),
        jerseyNumber:         form.jerseyNumber ? parseInt(form.jerseyNumber) : undefined,
        position:             form.position,
        academicYear:         form.academicYear,
        recruitingClass:      parseInt(form.recruitingClass),
        heightInches,
        weightLbs:            form.weightLbs ? parseInt(form.weightLbs) : undefined,
        homeTown:             form.homeTown   || undefined,
        homeState:            form.homeState  || undefined,
        highSchool:           form.highSchool || undefined,
        major:                form.major      || undefined,
        gpa:                  form.gpa        ? parseFloat(form.gpa)  : undefined,
        phone:                form.phone      || undefined,
        emergencyContactName: form.emergencyContactName  || undefined,
        emergencyContactPhone:form.emergencyContactPhone || undefined,
        notes:                form.notes      || undefined,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['players'] });
      Alert.alert('Player Added', `${form.firstName} ${form.lastName} has been added to the roster.`, [
        { text: 'OK', onPress: () => router.back() },
      ]);
    },
    onError: (err: any) => Alert.alert('Error', err?.response?.data?.error ?? 'Could not add player.'),
  });

  if (!canWrite('roster')) {
    return (
      <SafeAreaView style={styles.safe}>
        <EmptyState title="Access Restricted" message="You need write access to add players." />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.header}>
        <Text style={styles.title}>Add Player</Text>
      </View>

      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        {/* Required info */}
        <Text style={styles.section}>Required</Text>
        <Card>
          <Input label="First Name *"  value={form.firstName}  onChangeText={set('firstName')}  error={errors.firstName}  autoCapitalize="words" />
          <Input label="Last Name *"   value={form.lastName}   onChangeText={set('lastName')}   error={errors.lastName}   autoCapitalize="words" containerStyle={{ marginTop: Spacing.md }} />
          <Input label="Jersey #"      value={form.jerseyNumber} onChangeText={set('jerseyNumber')} keyboardType="number-pad" containerStyle={{ marginTop: Spacing.md }} />
          <Input label="Recruiting Class *" value={form.recruitingClass} onChangeText={set('recruitingClass')} keyboardType="number-pad" error={errors.recruitingClass} containerStyle={{ marginTop: Spacing.md }} />
        </Card>

        {/* Position */}
        <Text style={styles.section}>Position *</Text>
        <Card>
          {errors.position && <Text style={styles.errorText}>{errors.position}</Text>}
          <View style={styles.pillGrid}>
            {POSITIONS.map((p) => (
              <TouchableOpacity
                key={p}
                style={[styles.pill, form.position === p && styles.pillActive]}
                onPress={() => setForm((prev) => ({ ...prev, position: p }))}
              >
                <Text style={[styles.pillText, form.position === p && styles.pillTextActive]}>{p}</Text>
              </TouchableOpacity>
            ))}
          </View>
        </Card>

        {/* Academic Year */}
        <Text style={styles.section}>Academic Year *</Text>
        <Card>
          {errors.academicYear && <Text style={styles.errorText}>{errors.academicYear}</Text>}
          <View style={styles.pillGrid}>
            {YEARS.map((y) => (
              <TouchableOpacity
                key={y}
                style={[styles.pill, form.academicYear === y && styles.pillActive]}
                onPress={() => setForm((prev) => ({ ...prev, academicYear: y }))}
              >
                <Text style={[styles.pillText, form.academicYear === y && styles.pillTextActive]}>
                  {y.charAt(0).toUpperCase() + y.slice(1)}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        </Card>

        {/* Physical */}
        <Text style={styles.section}>Physical</Text>
        <Card>
          <View style={styles.row}>
            <Input label="Height (ft)" value={form.heightFeet}   onChangeText={set('heightFeet')}   keyboardType="number-pad" containerStyle={{ flex: 1 }} />
            <Input label="Inches"      value={form.heightInches} onChangeText={set('heightInches')} keyboardType="number-pad" containerStyle={{ flex: 1 }} />
          </View>
          <Input label="Weight (lbs)" value={form.weightLbs} onChangeText={set('weightLbs')} keyboardType="number-pad" containerStyle={{ marginTop: Spacing.md }} />
        </Card>

        {/* Background */}
        <Text style={styles.section}>Background</Text>
        <Card>
          <Input label="Hometown"    value={form.homeTown}   onChangeText={set('homeTown')}  autoCapitalize="words" />
          <Input label="State"       value={form.homeState}  onChangeText={set('homeState')} autoCapitalize="characters" containerStyle={{ marginTop: Spacing.md }} />
          <Input label="High School" value={form.highSchool} onChangeText={set('highSchool')} autoCapitalize="words" containerStyle={{ marginTop: Spacing.md }} />
        </Card>

        {/* Academic */}
        <Text style={styles.section}>Academic</Text>
        <Card>
          <Input label="Major" value={form.major} onChangeText={set('major')} autoCapitalize="words" />
          <Input label="GPA"   value={form.gpa}   onChangeText={set('gpa')}   keyboardType="decimal-pad" containerStyle={{ marginTop: Spacing.md }} />
        </Card>

        {/* Contact */}
        <Text style={styles.section}>Contact</Text>
        <Card>
          <Input label="Phone"             value={form.phone}              onChangeText={set('phone')}              keyboardType="phone-pad" />
          <Input label="Emergency Contact" value={form.emergencyContactName} onChangeText={set('emergencyContactName')} autoCapitalize="words" containerStyle={{ marginTop: Spacing.md }} />
          <Input label="Emergency Phone"   value={form.emergencyContactPhone} onChangeText={set('emergencyContactPhone')} keyboardType="phone-pad" containerStyle={{ marginTop: Spacing.md }} />
        </Card>

        {/* Notes */}
        <Text style={styles.section}>Notes</Text>
        <Card>
          <Input label="" value={form.notes} onChangeText={set('notes')} multiline numberOfLines={4} style={{ minHeight: 80 }} placeholder="Any additional notes..." />
        </Card>

        <Button
          label="Add Player to Roster"
          onPress={() => validate() && createMutation.mutate()}
          loading={createMutation.isPending}
          variant="roster"
          fullWidth
          size="lg"
          style={{ marginTop: Spacing.base }}
        />

        <View style={{ height: Spacing.xxxl }} />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe:          { flex: 1, backgroundColor: Colors.background },
  header:        { paddingHorizontal: Spacing.base, paddingVertical: Spacing.base },
  title:         { fontSize: Typography.xxl, fontWeight: Typography.bold, color: Colors.textPrimary },
  scroll:        { paddingHorizontal: Spacing.base },
  section:       { fontSize: Typography.xs, fontWeight: Typography.semibold, color: Colors.textTertiary, textTransform: 'uppercase', letterSpacing: 0.8, marginTop: Spacing.base, marginBottom: Spacing.xs },
  errorText:     { fontSize: Typography.xs, color: Colors.danger, marginBottom: Spacing.xs },
  pillGrid:      { flexDirection: 'row', flexWrap: 'wrap', gap: Spacing.xs },
  pill:          { paddingHorizontal: Spacing.md, paddingVertical: Spacing.xs, borderRadius: Radii.full, backgroundColor: Colors.gray100, borderWidth: 1, borderColor: Colors.border },
  pillActive:    { backgroundColor: Colors.rosterTint, borderColor: Colors.rosterTint },
  pillText:      { fontSize: Typography.sm, fontWeight: Typography.medium, color: Colors.textSecondary },
  pillTextActive:{ color: Colors.textInverse },
  row:           { flexDirection: 'row', gap: Spacing.md },
});
