import React from 'react';
import {View, StyleSheet, ScrollView} from 'react-native';
import {SafeAreaView} from 'react-native-safe-area-context';
import {Text, Switch, Divider, List, useTheme, TextInput} from 'react-native-paper';
import Slider from '@react-native-community/slider';
import {useAppStore} from '../store/appStore';
import {Colors, Spacing} from '../theme';

const SettingScreen: React.FC = () => {
  const theme = useTheme();
  const {settings, setSettings, mindReadingConfig, setMindReadingConfig} = useAppStore();

  // 读心配置的临时状态
  const [apiKey, setApiKey] = React.useState(mindReadingConfig.qianwenApiKey);
  const [customPrompt, setCustomPrompt] = React.useState(mindReadingConfig.customPrompt);
  const [serverPort, setServerPort] = React.useState(mindReadingConfig.serverPort.toString());

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.scrollView} contentContainerStyle={styles.content}>
        <Text variant="headlineSmall" style={styles.title}>
          设置
        </Text>

        {/* PWM 范围设置 */}
        <View style={styles.settingSection}>
          <View style={styles.settingHeader}>
            <Text variant="titleMedium" style={styles.settingLabel}>
              PWM 变化范围
            </Text>
            <Text variant="titleMedium" style={styles.settingValue}>
              ±{settings.pwmRange}
            </Text>
          </View>
          <Slider
            style={styles.slider}
            minimumValue={0}
            maximumValue={500}
            step={10}
            value={settings.pwmRange}
            onValueChange={(value) => setSettings({pwmRange: value})}
            minimumTrackTintColor={Colors.primary}
            maximumTrackTintColor={Colors.border}
            thumbTintColor={Colors.primary}
          />
          <Text variant="bodySmall" style={styles.settingHint}>
            控制自动模式下眼球运动的幅度
          </Text>
        </View>

        <Divider style={styles.divider} />

        {/* 更新间隔设置 */}
        <View style={styles.settingSection}>
          <View style={styles.settingHeader}>
            <Text variant="titleMedium" style={styles.settingLabel}>
              更新间隔
            </Text>
            <Text variant="titleMedium" style={styles.settingValue}>
              {settings.updateInterval}ms
            </Text>
          </View>
          <Slider
            style={styles.slider}
            minimumValue={100}
            maximumValue={5000}
            step={100}
            value={settings.updateInterval}
            onValueChange={(value) => setSettings({updateInterval: value})}
            minimumTrackTintColor={Colors.primary}
            maximumTrackTintColor={Colors.border}
            thumbTintColor={Colors.primary}
          />
          <Text variant="bodySmall" style={styles.settingHint}>
            控制自动模式下 PWM 更新的频率
          </Text>
        </View>

        <Divider style={styles.divider} />

        {/* 开关设置 */}
        <List.Item
          title="松开自动复位"
          description="摇杆释放时自动回到中心位置"
          titleStyle={styles.listTitle}
          descriptionStyle={styles.listDescription}
          right={() => (
            <Switch
              value={settings.resetStickOnRelease}
              onValueChange={(value) => setSettings({resetStickOnRelease: value})}
              color={Colors.primary}
            />
          )}
        />

        <List.Item
          title="启用自动眨眼"
          description="定时自动执行眨眼动作"
          titleStyle={styles.listTitle}
          descriptionStyle={styles.listDescription}
          right={() => (
            <Switch
              value={settings.autoWinkEnabled}
              onValueChange={(value) => setSettings({autoWinkEnabled: value})}
              color={Colors.primary}
            />
          )}
        />

        <Divider style={styles.divider} />

        {/* 读心功能设置 */}
        <Text variant="titleMedium" style={styles.sectionTitle}>
          读心功能设置
        </Text>

        <List.Item
          title="启用读心"
          description="开启后自动捕获人脸并发送 AI 分析"
          titleStyle={styles.listTitle}
          descriptionStyle={styles.listDescription}
          right={() => (
            <Switch
              value={mindReadingConfig.enabled}
              onValueChange={(value) => setMindReadingConfig({enabled: value})}
              color={Colors.primary}
            />
          )}
        />

        <View style={styles.settingSection}>
          <Text variant="titleMedium" style={styles.settingLabel}>
            千问 API Key
          </Text>
          <TextInput
            style={styles.textInput}
            value={apiKey}
            onChangeText={(text) => {
              setApiKey(text);
              setMindReadingConfig({qianwenApiKey: text});
            }}
            placeholder="输入阿里云千问 API Key"
            secureTextEntry
            mode="outlined"
            dense
          />
          <Text variant="bodySmall" style={styles.settingHint}>
            从阿里云 Dashscope 控制台获取 API Key
          </Text>
        </View>

        <View style={styles.settingSection}>
          <Text variant="titleMedium" style={styles.settingLabel}>
            分析提示词
          </Text>
          <TextInput
            style={styles.textInputMultiline}
            value={customPrompt}
            onChangeText={(text) => {
              setCustomPrompt(text);
              setMindReadingConfig({customPrompt: text});
            }}
            placeholder="输入用于分析心理活动的提示词"
            multiline
            numberOfLines={3}
            mode="outlined"
            dense
          />
          <Text variant="bodySmall" style={styles.settingHint}>
            自定义 AI 分析提示词，用于引导分析方向
          </Text>
        </View>

        <View style={styles.settingSection}>
          <View style={styles.settingHeader}>
            <Text variant="titleMedium" style={styles.settingLabel}>
              追踪稳定阈值
            </Text>
            <Text variant="titleMedium" style={styles.settingValue}>
              {mindReadingConfig.stabilityThreshold / 1000}s
            </Text>
          </View>
          <Slider
            style={styles.slider}
            minimumValue={500}
            maximumValue={5000}
            step={100}
            value={mindReadingConfig.stabilityThreshold}
            onValueChange={(value) => setMindReadingConfig({stabilityThreshold: value})}
            minimumTrackTintColor={Colors.primary}
            maximumTrackTintColor={Colors.border}
            thumbTintColor={Colors.primary}
          />
          <Text variant="bodySmall" style={styles.settingHint}>
            追踪同一人脸多久后触发捕获
          </Text>
        </View>

        <View style={styles.settingSection}>
          <Text variant="titleMedium" style={styles.settingLabel}>
            服务器端口
          </Text>
          <TextInput
            style={styles.textInput}
            value={serverPort}
            onChangeText={(text) => {
              setServerPort(text);
              const port = parseInt(text, 10);
              if (!isNaN(port) && port > 0 && port < 65536) {
                setMindReadingConfig({serverPort: port});
              }
            }}
            placeholder="8080"
            keyboardType="number-pad"
            mode="outlined"
            dense
          />
          <Text variant="bodySmall" style={styles.settingHint}>
            WebSocket 服务器监听端口
          </Text>
        </View>

        {/* 版本信息 */}
        <View style={styles.footer}>
          <Text variant="bodyMedium" style={styles.versionText}>
            SatoriManager v1.0.0
          </Text>
          <Text variant="bodySmall" style={styles.versionHint}>
            React Native 跨平台版本
          </Text>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  scrollView: {
    flex: 1,
  },
  content: {
    padding: Spacing.xl,
    paddingBottom: Spacing.xxxl,
  },
  title: {
    color: Colors.text,
    fontWeight: 'bold',
    marginBottom: Spacing.xxl,
  },
  settingSection: {
    marginBottom: Spacing.lg,
  },
  settingHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.sm,
  },
  settingLabel: {
    color: Colors.text,
  },
  settingValue: {
    color: Colors.primary,
    fontWeight: '600',
  },
  slider: {
    width: '100%',
    height: 40,
  },
  settingHint: {
    color: Colors.textMuted,
    marginTop: Spacing.xs,
  },
  divider: {
    backgroundColor: Colors.border,
    marginVertical: Spacing.lg,
  },
  listTitle: {
    color: Colors.text,
  },
  listDescription: {
    color: Colors.textMuted,
  },
  footer: {
    marginTop: Spacing.xxxl,
    alignItems: 'center',
  },
  versionText: {
    color: Colors.textMuted,
  },
  versionHint: {
    color: Colors.textDisabled,
    marginTop: Spacing.xs,
  },
  sectionTitle: {
    color: Colors.text,
    fontWeight: 'bold',
    marginBottom: Spacing.md,
  },
  textInput: {
    marginTop: Spacing.sm,
  },
  textInputMultiline: {
    marginTop: Spacing.sm,
  },
});

export default SettingScreen;
