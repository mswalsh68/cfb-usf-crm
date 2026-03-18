import { Tabs, Redirect } from 'expo-router';
import { useAuth } from '../../hooks/useAuth';
import { Colors, Typography } from '@cfb-crm/ui';
import { Text } from 'react-native';

function TabIcon({ label, focused }: { label: string; focused: boolean }) {
  return (
    <Text style={{ fontSize: Typography.xs, color: focused ? Colors.alumniTint : Colors.textTertiary, fontWeight: focused ? Typography.semibold : Typography.regular, marginTop: 2 }}>
      {label}
    </Text>
  );
}

export default function AlumniLayout() {
  const { hasAppAccess, isGlobalAdmin } = useAuth();

  if (!hasAppAccess('alumni') && !isGlobalAdmin()) {
    return <Redirect href="/(roster)/" />;
  }

  return (
    <Tabs screenOptions={{
      headerShown:             false,
      tabBarStyle:             { backgroundColor: Colors.surface, borderTopColor: Colors.border },
      tabBarActiveTintColor:   Colors.alumniTint,
      tabBarInactiveTintColor: Colors.textTertiary,
    }}>
      <Tabs.Screen name="index"        options={{ title: 'Alumni',    tabBarIcon: ({ focused }) => <TabIcon label="🎓" focused={focused} /> }} />
      <Tabs.Screen name="alumni/[id]"  options={{ href: null }} />
      <Tabs.Screen name="outreach"     options={{ title: 'Outreach',  tabBarIcon: ({ focused }) => <TabIcon label="📣" focused={focused} /> }} />
    </Tabs>
  );
}
