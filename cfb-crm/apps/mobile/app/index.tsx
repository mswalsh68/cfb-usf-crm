import { Redirect } from 'expo-router';
import { useAuth } from '../hooks/useAuth';
import { View, ActivityIndicator } from 'react-native';
import { Colors } from '@cfb-crm/ui';

export default function Index() {
  const { user, isLoading, isGlobalAdmin, hasAppAccess } = useAuth();

  if (isLoading) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: Colors.background }}>
        <ActivityIndicator size="large" color={Colors.primary} />
      </View>
    );
  }

  if (!user) return <Redirect href="/(auth)/login" />;

  // Global admins and coach/staff land on roster by default
  if (isGlobalAdmin() || hasAppAccess('roster')) return <Redirect href="/(roster)/" />;
  if (hasAppAccess('alumni')) return <Redirect href="/(alumni)/" />;

  // Shouldn't reach here — means user has no app access
  return <Redirect href="/(auth)/login" />;
}
