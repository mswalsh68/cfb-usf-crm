import React, { useState } from 'react';
import {
  View, Text, StyleSheet, KeyboardAvoidingView,
  Platform, ScrollView, Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useAuth } from '../../hooks/useAuth';
import { getApiError } from '../../hooks/useApiClient';
import { Button, Input, Colors, Typography, Spacing, Radii } from '@cfb-crm/ui';

export default function LoginScreen() {
  const { signIn } = useAuth();
  const [email,    setEmail]    = useState('');
  const [password, setPassword] = useState('');
  const [loading,  setLoading]  = useState(false);
  const [errors,   setErrors]   = useState<{ email?: string; password?: string }>({});

  const validate = (): boolean => {
    const e: typeof errors = {};
    if (!email.includes('@'))       e.email    = 'Enter a valid email';
    if (password.length < 8)        e.password = 'Password must be 8+ characters';
    setErrors(e);
    return Object.keys(e).length === 0;
  };

  const handleLogin = async () => {
    if (!validate()) return;
    setLoading(true);
    try {
      await signIn(email.trim().toLowerCase(), password);
      // AuthContext route guard handles redirect automatically
    } catch (err: unknown) {
      Alert.alert(
        'Sign In Failed',
        getApiError(err, 'Please check your credentials and try again.'),
      );
    } finally {
      setLoading(false);
    }
  };

  return (
    <SafeAreaView style={styles.safe}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={{ flex: 1 }}
      >
        <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
          {/* Header */}
          <View style={styles.header}>
            <View style={styles.logoMark}>
              <Text style={styles.logoText}>CFB</Text>
            </View>
            <Text style={styles.title}>Team Portal</Text>
            <Text style={styles.subtitle}>Sign in to continue</Text>
          </View>

          {/* Form */}
          <View style={styles.form}>
            <Input
              label="Email"
              value={email}
              onChangeText={setEmail}
              keyboardType="email-address"
              autoCapitalize="none"
              autoComplete="email"
              placeholder="coach@yourprogram.com"
              error={errors.email}
            />
            <Input
              label="Password"
              value={password}
              onChangeText={setPassword}
              secureTextEntry
              autoComplete="password"
              placeholder="••••••••"
              error={errors.password}
              containerStyle={{ marginTop: Spacing.base }}
            />
            <Button
              label="Sign In"
              onPress={handleLogin}
              loading={loading}
              fullWidth
              size="lg"
              style={{ marginTop: Spacing.xl }}
            />
          </View>

          <Text style={styles.footer}>
            Contact your program administrator for access.
          </Text>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: Colors.primary,
  },
  scroll: {
    flexGrow:          1,
    justifyContent:    'center',
    paddingHorizontal: Spacing.xl,
    paddingVertical:   Spacing.xxl,
  },
  header: {
    alignItems:   'center',
    marginBottom: Spacing.xxxl,
  },
  logoMark: {
    width:           72,
    height:          72,
    borderRadius:    Radii.md,
    backgroundColor: Colors.accent,
    alignItems:      'center',
    justifyContent:  'center',
    marginBottom:    Spacing.base,
  },
  logoText: {
    fontSize:   Typography.xl,
    fontWeight: Typography.bold,
    color:      Colors.primary,
  },
  title: {
    fontSize:   Typography.xxl,
    fontWeight: Typography.bold,
    color:      Colors.textInverse,
  },
  subtitle: {
    fontSize:  Typography.base,
    color:     'rgba(255,255,255,0.65)',
    marginTop: Spacing.xs,
  },
  form: {
    backgroundColor: Colors.surface,
    borderRadius:    Radii.lg,
    padding:         Spacing.xl,
  },
  footer: {
    textAlign:  'center',
    color:      'rgba(255,255,255,0.45)',
    fontSize:   Typography.sm,
    marginTop:  Spacing.xl,
  },
});
