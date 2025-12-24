/**
 * Mind Reading Screen
 * 读心功能主界面
 */

import React, { useEffect, useState} from 'react';
import {
  View,
  StyleSheet,
  ScrollView,
  Text,
  Dimensions,
} from 'react-native';
import {Surface, Button, Card, useTheme, ProgressBar, IconButton} from 'react-native-paper';
import {useAppStore} from '../store/appStore';
import {getMindReadingService} from '../services/MindReadingService';

const {width: SCREEN_WIDTH} = Dimensions.get('window');

/**
 * Mind Reading Screen Component
 */
export const MindReadingScreen = () => {
  const theme = useTheme();
  const mindReadingConfig = useAppStore(state => state.mindReadingConfig);
  const mindReadingState = useAppStore(state => state.mindReadingState);
  const startMindReading = useAppStore(state => state.startMindReading);
  const stopMindReading = useAppStore(state => state.stopMindReading);

  const [stabilityProgress, setStabilityProgress] = useState(0);

  // 监听服务状态变化
  useEffect(() => {
    const service = getMindReadingService();

    const unsubscribe = service.onStateChange(newState => {
      // 同步到 store
      useAppStore.getState().setMindReadingState(newState);
    });

    return () => {
      unsubscribe();
    };
  }, []);

  // 定期更新稳定度进度
  useEffect(() => {
    if (!mindReadingConfig.enabled || !mindReadingState.isServerRunning) {
      setStabilityProgress(0);
      return;
    }

    const interval = setInterval(() => {
      const service = getMindReadingService();
      const captureManager = service.getFaceCaptureManager();
      const progress = captureManager.getProgress();
      setStabilityProgress(progress);

      // 更新当前状态
      useAppStore.getState().setMindReadingState({
        currentStability: captureManager.getStability(),
        currentTrackingId: captureManager.getCurrentTrackingId(),
      });
    }, 100);

    return () => clearInterval(interval);
  }, [mindReadingConfig.enabled, mindReadingState.isServerRunning]);

  // 启动服务器
  const handleStart = async () => {
    try {
      await startMindReading();
    } catch (error) {
      console.error('Failed to start mind reading:', error);
    }
  };

  // 停止服务器
  const handleStop = () => {
    stopMindReading();
  };

  // 格式化时间戳
  const formatTimestamp = (timestamp: number | null) => {
    if (!timestamp) return '';
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - date.getTime();

    if (diff < 60000) {
      return `${Math.floor(diff / 1000)} 秒前`;
    } else if (diff < 3600000) {
      return `${Math.floor(diff / 60000)} 分钟前`;
    } else {
      return date.toLocaleString('zh-CN');
    }
  };

  return (
    <ScrollView style={styles.container}>
      {/* 服务器状态卡片 */}
      <Card style={styles.card}>
        <Card.Title
          title="服务器状态"
          left={props => <IconButton {...props} icon="server" />}
        />
        <Card.Content>
          <View style={styles.statusRow}>
            <Text style={styles.statusLabel}>状态:</Text>
            <Text
              style={[
                styles.statusValue,
                {color: mindReadingState.isServerRunning ? theme.colors.primary : theme.colors.error},
              ]}>
              {mindReadingState.isServerRunning ? '运行中' : '未启动'}
            </Text>
          </View>

          {mindReadingState.serverUrl && (
            <View style={styles.statusRow}>
              <Text style={styles.statusLabel}>地址:</Text>
              <Text style={styles.statusValue}>{mindReadingState.serverUrl}</Text>
            </View>
          )}

          {mindReadingState.error && (
            <View style={styles.statusRow}>
              <Text style={[styles.statusValue, {color: theme.colors.error}]}>
                错误: {mindReadingState.error}
              </Text>
            </View>
          )}
        </Card.Content>
        <Card.Actions>
          {!mindReadingState.isServerRunning ? (
            <Button mode="contained" onPress={handleStart} icon="play">
              启动服务器
            </Button>
          ) : (
            <Button mode="contained" onPress={handleStop} icon="stop" buttonColor={theme.colors.error}>
              停止服务器
            </Button>
          )}
        </Card.Actions>
      </Card>

      {/* 追踪状态卡片 */}
      {mindReadingConfig.enabled && mindReadingState.isServerRunning && (
        <Card style={styles.card}>
          <Card.Title
            title="追踪状态"
            left={props => <IconButton {...props} icon="crosshairs" />}
          />
          <Card.Content>
            <View style={styles.statusRow}>
              <Text style={styles.statusLabel}>追踪 ID:</Text>
              <Text style={styles.statusValue}>
                {mindReadingState.currentTrackingId ?? '无'}
              </Text>
            </View>

            <View style={styles.statusRow}>
              <Text style={styles.statusLabel}>稳定度:</Text>
              <Text style={styles.statusValue}>
                {Math.round(stabilityProgress * 100)}%
              </Text>
            </View>

            <ProgressBar
              progress={stabilityProgress}
              color={theme.colors.primary}
              style={styles.progressBar}
            />

            <View style={styles.statusRow}>
              <Text style={styles.statusLabel}>捕获:</Text>
              <Text style={styles.statusValue}>
                {mindReadingState.isCapturing ? '进行中' : '等待'}
              </Text>
              <Text style={styles.statusLabel}>  分析:</Text>
              <Text style={styles.statusValue}>
                {mindReadingState.isAnalyzing ? '进行中' : '空闲'}
              </Text>
            </View>
          </Card.Content>
        </Card>
      )}

      {/* 分析结果卡片 */}
      <Card style={styles.card}>
        <Card.Title
          title="最新分析结果"
          left={props => <IconButton {...props} icon="brain" />}
        />
        <Card.Content>
          <Surface style={styles.resultContainer}>
            {mindReadingState.lastResult ? (
              <>
                <Text style={styles.resultText}>{mindReadingState.lastResult.analysis}</Text>
                <Text style={styles.timestamp}>
                  {formatTimestamp(mindReadingState.lastResult.timestamp)}
                </Text>
              </>
            ) : (
              <Text style={[styles.resultText, styles.placeholder]}>
                {mindReadingState.isAnalyzing ? '正在分析中...' : '等待捕获和分析...'}
              </Text>
            )}
          </Surface>
        </Card.Content>
      </Card>

      {/* 使用说明 */}
      <Card style={styles.card}>
        <Card.Title
          title="使用说明"
          left={props => <IconButton {...props} icon="information" />}
        />
        <Card.Content>
          <Text style={styles.instructionText}>
            1. 在设置中配置千问 API Key
          </Text>
          <Text style={styles.instructionText}>
            2. 启动服务器
          </Text>
          <Text style={styles.instructionText}>
            3. 启用读心功能
          </Text>
          <Text style={styles.instructionText}>
            4. 在视觉界面启动视频流和人脸追踪
          </Text>
          <Text style={styles.instructionText}>
            5. 稳定追踪人脸 1 秒后自动触发分析
          </Text>
          <Text style={styles.instructionText}>
            6. 在浏览器中访问服务器地址查看结果
          </Text>
        </Card.Content>
      </Card>
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  card: {
    margin: 16,
    elevation: 2,
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginVertical: 4,
  },
  statusLabel: {
    fontSize: 14,
    color: '#666',
    marginRight: 8,
  },
  statusValue: {
    fontSize: 14,
    fontWeight: 'bold',
  },
  progressBar: {
    marginTop: 8,
    marginBottom: 8,
    height: 8,
    borderRadius: 4,
  },
  resultContainer: {
    padding: 16,
    borderRadius: 8,
    elevation: 1,
    minHeight: 100,
  },
  resultText: {
    fontSize: 16,
    lineHeight: 24,
    color: '#333',
  },
  placeholder: {
    color: '#999',
    fontStyle: 'italic',
  },
  timestamp: {
    fontSize: 12,
    color: '#999',
    marginTop: 12,
    textAlign: 'right',
  },
  instructionText: {
    fontSize: 14,
    color: '#666',
    marginVertical: 4,
  },
});

export default MindReadingScreen;
