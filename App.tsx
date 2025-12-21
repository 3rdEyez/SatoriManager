import React, {useEffect} from 'react';
import {StatusBar} from 'react-native';
import {SafeAreaProvider} from 'react-native-safe-area-context';
import {GestureHandlerRootView} from 'react-native-gesture-handler';
import {NavigationContainer} from '@react-navigation/native';
import {createBottomTabNavigator} from '@react-navigation/bottom-tabs';
import {PaperProvider} from 'react-native-paper';
import Icon from 'react-native-vector-icons/MaterialCommunityIcons';
import {DashboardScreen, PuppeteerScreen, VisionScreen, TuningLabScreen, EngineerScreen} from './src/screens';
import {useAppStore} from './src/store/appStore';
import {paperTheme, Colors} from './src/theme';

const Tab = createBottomTabNavigator();

const App: React.FC = () => {
  const initialize = useAppStore((state) => state.initialize);

  useEffect(() => {
    initialize();
  }, [initialize]);

  return (
    <PaperProvider theme={paperTheme}>
      <GestureHandlerRootView style={{flex: 1}}>
        <SafeAreaProvider>
          <StatusBar barStyle="light-content" backgroundColor={Colors.background} />
          <NavigationContainer>
            <Tab.Navigator
              screenOptions={{
                headerShown: false,
                tabBarStyle: {
                  backgroundColor: Colors.background,
                  borderTopColor: Colors.border,
                  borderTopWidth: 1,
                  paddingBottom: 8,
                  paddingTop: 8,
                  height: 70,
                },
                tabBarActiveTintColor: Colors.primary,
                tabBarInactiveTintColor: Colors.textMuted,
                tabBarLabelStyle: {
                  fontSize: 11,
                  fontWeight: '600',
                  letterSpacing: 0.5,
                },
              }}>
              <Tab.Screen
                name="Dashboard"
                component={DashboardScreen}
                options={{
                  tabBarLabel: '意识面板',
                  tabBarIcon: ({color, size}) => (
                    <Icon name="monitor-dashboard" size={size} color={color} />
                  ),
                }}
              />
              <Tab.Screen
                name="Puppeteer"
                component={PuppeteerScreen}
                options={{
                  tabBarLabel: '操控连接',
                  tabBarIcon: ({color, size}) => (
                    <Icon name="eye" size={size} color={color} />
                  ),
                }}
              />
              <Tab.Screen
                name="Vision"
                component={VisionScreen}
                options={{
                  tabBarLabel: '视觉追踪',
                  tabBarIcon: ({color, size}) => (
                    <Icon name="video" size={size} color={color} />
                  ),
                }}
              />
              <Tab.Screen
                name="TuningLab"
                component={TuningLabScreen}
                options={{
                  tabBarLabel: '潜意识调优',
                  tabBarIcon: ({color, size}) => (
                    <Icon name="tune-vertical" size={size} color={color} />
                  ),
                }}
              />
              <Tab.Screen
                name="Engineer"
                component={EngineerScreen}
                options={{
                  tabBarLabel: '工程师',
                  tabBarIcon: ({color, size}) => (
                    <Icon name="cog" size={size} color={color} />
                  ),
                }}
              />
            </Tab.Navigator>
          </NavigationContainer>
        </SafeAreaProvider>
      </GestureHandlerRootView>
    </PaperProvider>
  );
};

export default App;
