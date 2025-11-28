// Jest setup file
import '@testing-library/react-native/extend-expect';

// Mock react-native-reanimated
jest.mock('react-native-reanimated', () => {
  const Reanimated = require('react-native-reanimated/mock');
  Reanimated.default.call = () => {};
  return Reanimated;
});

// Mock react-native-gesture-handler
jest.mock('react-native-gesture-handler', () => {
  const View = require('react-native').View;
  return {
    GestureHandlerRootView: View,
    GestureDetector: View,
    Gesture: {
      Pan: () => ({
        onUpdate: () => ({
          onEnd: () => ({}),
        }),
        onStart: () => ({
          onUpdate: () => ({
            onEnd: () => ({}),
          }),
        }),
        enabled: () => ({
          onStart: () => ({
            onUpdate: () => ({
              onEnd: () => ({}),
            }),
          }),
        }),
      }),
    },
    Directions: {},
    State: {},
    PanGestureHandler: View,
    TapGestureHandler: View,
  };
});

// Mock react-native-udp
jest.mock('react-native-udp', () => ({
  createSocket: jest.fn(() => ({
    on: jest.fn(),
    bind: jest.fn(),
    send: jest.fn(),
    close: jest.fn(),
  })),
}));

// Mock @react-navigation
jest.mock('@react-navigation/native', () => {
  const actualNav = jest.requireActual('@react-navigation/native');
  return {
    ...actualNav,
    useNavigation: () => ({
      navigate: jest.fn(),
      goBack: jest.fn(),
    }),
    useRoute: () => ({
      params: {},
    }),
  };
});

// Mock react-native-safe-area-context
jest.mock('react-native-safe-area-context', () => {
  const inset = {top: 0, right: 0, bottom: 0, left: 0};
  return {
    SafeAreaProvider: ({children}) => children,
    SafeAreaView: ({children}) => children,
    useSafeAreaInsets: () => inset,
  };
});

// Mock @react-native-community/slider
jest.mock('@react-native-community/slider', () => {
  const {View} = require('react-native');
  return View;
});

// Mock react-native-ble-plx
jest.mock('react-native-ble-plx', () => ({
  BleManager: jest.fn().mockImplementation(() => ({
    onStateChange: jest.fn((callback) => {
      callback('PoweredOn');
      return {remove: jest.fn()};
    }),
    state: jest.fn().mockResolvedValue('PoweredOn'),
    startDeviceScan: jest.fn(),
    stopDeviceScan: jest.fn(),
    connectToDevice: jest.fn().mockResolvedValue({
      id: 'test-device-id',
      name: 'SatoriEye-Test',
      rssi: -50,
      discoverAllServicesAndCharacteristics: jest.fn().mockResolvedValue({}),
      services: jest.fn().mockResolvedValue([
        {
          uuid: '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
          characteristics: jest.fn().mockResolvedValue([
            {
              uuid: '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
              writeWithResponse: jest.fn().mockResolvedValue({}),
            },
            {
              uuid: '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
              monitor: jest.fn(),
            },
          ]),
        },
      ]),
      requestMTU: jest.fn().mockResolvedValue(512),
      onDisconnected: jest.fn(),
      cancelConnection: jest.fn().mockResolvedValue({}),
    }),
    destroy: jest.fn(),
  })),
  State: {
    PoweredOff: 'PoweredOff',
    PoweredOn: 'PoweredOn',
    Resetting: 'Resetting',
    Unauthorized: 'Unauthorized',
    Unknown: 'Unknown',
    Unsupported: 'Unsupported',
  },
}));

// Mock react-native-paper
jest.mock('react-native-paper', () => {
  const {View, Text, TouchableOpacity} = require('react-native');
  const MockButton = ({children, onPress, ...props}) => (
    <TouchableOpacity onPress={onPress} {...props}>
      <Text>{children}</Text>
    </TouchableOpacity>
  );
  return {
    PaperProvider: ({children}) => children,
    Button: MockButton,
    Text: Text,
    Chip: ({children}) => <Text>{children}</Text>,
    Surface: View,
    Card: View,
    'Card.Content': View,
    Switch: View,
    Divider: View,
    List: {
      Item: View,
    },
    Modal: View,
    Portal: ({children}) => children,
    IconButton: View,
    SegmentedButtons: View,
    ActivityIndicator: View,
    useTheme: () => ({
      colors: {
        primary: '#F17EB7',
        background: '#1a1a2e',
      },
    }),
    MD3DarkTheme: {
      colors: {},
    },
  };
});

// Mock react-native-vector-icons
jest.mock('react-native-vector-icons/MaterialCommunityIcons', () => {
  const {Text} = require('react-native');
  return ({name, size, color}) => <Text>{name}</Text>;
});

// Silence console warnings in tests
global.console = {
  ...console,
  warn: jest.fn(),
  error: jest.fn(),
};
