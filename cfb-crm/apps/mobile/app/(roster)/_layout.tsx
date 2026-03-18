import { Tabs, Redirect } from 'expo-router';
import { useAuth } from '../../hooks/useAuth';
import { Colors, Typography } from '@cfb-crm/ui';
import { View, Text } from 'react-native';

function TabIcon({ label, focused }: { label: string; focused: boolean }) {
  return (
    <Text style={{
      fontSize:   Typography.xs,
      color:      focused ? Colors.rosterTint : Colors.textTertiary,
      fontWeight: focused ? Typography.semibold : Typography.regular,
      marginTop:  2,
    }}>
      {label}
    </Text>
  );
}

export default function RosterLayout() {
  const { hasAppAccess, isGlobalAdmin } = useAuth();

  if (!hasAppAccess('roster') && !isGlobalAdmin()) {
    return <Redirect href="/(alumni)/" />;
  }

  return (
    <Tabs
      screenOptions={{
        headerShown:      false,
        tabBarStyle:      { backgroundColor: Colors.surface, borderTopColor: Colors.border },
        tabBarActiveTintColor:   Colors.rosterTint,
        tabBarInactiveTintColor: Colors.textTertiary,
        tabBarLabelStyle: { fontSize: Typography.xs },
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title:         'Roster',
          tabBarIcon:    ({ focused }) => <TabIcon label="👥" focused={focused} />,
        }}
      />
      <Tabs.Screen
        name="player/[id]"
        options={{ href: null }} // hidden from tab bar, navigated to programmatically
      />
      <Tabs.Screen
        name="add-player"
        options={{
          title:      'Add Player',
          tabBarIcon: ({ focused }) => <TabIcon label="➕" focused={focused} />,
        }}
      />
      <Tabs.Screen
        name="graduate"
        options={{
          title:      'Graduate',
          tabBarIcon: ({ focused }) => <TabIcon label="🎓" focused={focused} />,
        }}
      />
    </Tabs>
  );
}
