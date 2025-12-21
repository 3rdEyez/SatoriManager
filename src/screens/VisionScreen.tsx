import React, {useState, useEffect, useCallback, useRef} from 'react';
import {
  View,
  StyleSheet,
  Text,
  ActivityIndicator,
  Dimensions,
} from 'react-native';
import {Surface, Button, IconButton, SegmentedButtons} from 'react-native-paper';
import {connectionManager} from '../services/ConnectionManager';
import {useAppStore} from '../store/appStore';
import {VideoFrame, VIDEO_STREAM_DEFAULTS} from '../types';
import {
  FaceDetector,
  FaceDetectionResult,
  FaceSelector,
  DEFAULT_FACE_DETECTOR_CONFIG,
} from '../services/FaceDetector';
import {SkiaVideoCanvas} from '../components/SkiaVideoCanvas';
import {TelemetryDashboard} from '../components/TelemetryDashboard';
import {PerformanceMonitor} from '../utils/PerformanceMonitor';
import {theme} from '../theme';

const {width: SCREEN_WIDTH, height: SCREEN_HEIGHT} = Dimensions.get('window');
const VIDEO_ASPECT_RATIO = 4 / 3; // 640x480

/**
 * 视觉追踪主界面
 * 显示视频流、人脸检测和自动追踪控制
 */
export const VisionScreen = () => {
  const {
    isConnected,
    connectionType,
    visionState,
    updateFaceDetection,
    updateVideoStreamState,
    startTracking,
    stopTracking,
    setTrackingMode,
  } = useAppStore(state => ({
    isConnected: state.connection.isConnected,
    connectionType: state.connection.connectionType,
    visionState: state.visionState,
    updateFaceDetection: state.updateFaceDetection,
    updateVideoStreamState: state.updateVideoStreamState,
    startTracking: state.startTracking,
    stopTracking: state.stopTracking,
    setTrackingMode: state.setTrackingMode,
  }));

  const [isStreaming, setIsStreaming] = useState(false);
  const [currentFrame, setCurrentFrame] = useState<VideoFrame | null>(null);
  const [faces, setFaces] = useState<FaceDetectionResult['faces']>([]);
  const [faceDetectionEnabled, setFaceDetectionEnabled] = useState(true);
  const [lastTrackingId, setLastTrackingId] = useState<number | undefined>(undefined);

  const [videoStats, setVideoStats] = useState({
    fps: 0,
    latency: 0,
    droppedFrames: 0,
  });

  const statsUpdateInterval = useRef<ReturnType<typeof setInterval> | null>(null);
  const faceDetector = useRef(new FaceDetector(DEFAULT_FACE_DETECTOR_CONFIG)).current;
  const trackingUpdateInterval = useRef<ReturnType<typeof setInterval> | null>(null);
  const performanceMonitor = useRef(new PerformanceMonitor(60, 30)).current;

  // 启动视频流
  const handleStartStream = useCallback(() => {
    if (!isConnected) {
      console.warn('Not connected to device');
      return;
    }

    connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);
    setIsStreaming(true);

    // 启动统计信息更新
    statsUpdateInterval.current = setInterval(() => {
      const stats = connectionManager.getVideoStreamStats();
      if (stats) {
        setVideoStats({
          fps: stats.currentFPS,
          latency: stats.avgLatency,
          droppedFrames: stats.droppedFrames,
        });
      }
    }, 500);
  }, [isConnected]);

  // 停止视频流
  const handleStopStream = useCallback(() => {
    connectionManager.stopVideoStream();
    setIsStreaming(false);
    setCurrentFrame(null);

    // 停止统计信息更新
    if (statsUpdateInterval.current) {
      clearInterval(statsUpdateInterval.current);
      statsUpdateInterval.current = null;
    }
  }, []);

  // 设置视频帧回调
  useEffect(() => {
    const videoCallback = (frame: VideoFrame) => {
      // 记录性能数据
      performanceMonitor.recordFrame(frame.timestamp || Date.now());

      setCurrentFrame(frame);

      // 如果启用人脸检测，异步检测人脸
      if (faceDetectionEnabled) {
        detectFaces(frame);
      }
    };

    connectionManager.setCallbacks(
      () => {}, // onConnection
      () => {}, // onMode
      () => {}, // onBattery
      undefined, // onScan
      undefined, // onSystemStatus
      videoCallback, // onVideoFrame
    );

    return () => {
      if (isStreaming) {
        handleStopStream();
      }
      faceDetector.destroy();
    };
  }, [isStreaming, handleStopStream, faceDetectionEnabled]);

  // 人脸检测函数
  const detectFaces = useCallback(
    async (frame: VideoFrame) => {
      try {
        const result = await faceDetector.detectFaces(
          frame.data,
          frame.width,
          frame.height,
        );

        setFaces(result.faces);
        updateFaceDetection(result);
      } catch (error) {
        console.error('Face detection error:', error);
      }
    },
    [faceDetector, updateFaceDetection],
  );

  // 视觉伺服追踪更新
  useEffect(() => {
    if (!visionState.tracking.isTracking) {
      return;
    }

    // 每 50ms 更新一次追踪（20Hz）
    trackingUpdateInterval.current = setInterval(() => {
      // 选择要追踪的人脸
      const targetFace = FaceSelector.selectSmart(faces, lastTrackingId);

      if (targetFace) {
        // 更新跟踪 ID
        if (targetFace.trackingId !== undefined) {
          setLastTrackingId(targetFace.trackingId);
        }

        // 调用视觉伺服控制器
        connectionManager.updateVisualServo({
          facePosition: {
            x: targetFace.centerX,
            y: targetFace.centerY,
          },
          joystickInput: {x: 0, y: 0},
          mode: visionState.tracking.trackingMode,
        });
      } else {
        // 无人脸时保持当前位置
        connectionManager.updateVisualServo({
          facePosition: null,
          joystickInput: {x: 0, y: 0},
          mode: visionState.tracking.trackingMode,
        });
      }
    }, 50);

    return () => {
      if (trackingUpdateInterval.current) {
        clearInterval(trackingUpdateInterval.current);
        trackingUpdateInterval.current = null;
      }
    };
  }, [visionState.tracking.isTracking, faces, lastTrackingId, visionState.tracking.trackingMode]);

  // 连接状态变化时自动停止视频流
  useEffect(() => {
    if (!isConnected && isStreaming) {
      handleStopStream();
    }
  }, [isConnected, isStreaming, handleStopStream]);

  // 计算视频显示尺寸（保持宽高比）
  const videoWidth = SCREEN_WIDTH;
  const videoHeight = SCREEN_WIDTH / VIDEO_ASPECT_RATIO;

  return (
    <View style={styles.container}>
      {/* 视频显示区域 */}
      <Surface style={[styles.videoContainer, {height: videoHeight}]} elevation={2}>
        {!isConnected ? (
          <View style={styles.placeholderContainer}>
            <IconButton icon="link-off" size={48} iconColor={theme.colors.textSecondary} />
            <Text style={styles.placeholderText}>未连接到设备</Text>
          </View>
        ) : !isStreaming ? (
          <View style={styles.placeholderContainer}>
            <IconButton icon="video-off" size={48} iconColor={theme.colors.textSecondary} />
            <Text style={styles.placeholderText}>视频流未启动</Text>
          </View>
        ) : !currentFrame ? (
          <View style={styles.placeholderContainer}>
            <ActivityIndicator size="large" color={theme.colors.primary} />
            <Text style={styles.placeholderText}>等待视频帧...</Text>
          </View>
        ) : (
          <SkiaVideoCanvas
            videoFrame={currentFrame}
            faces={faces}
            canvasWidth={videoWidth}
            canvasHeight={videoHeight}
            showConfidence={true}
            showCrosshair={true}
            showTrackingId={visionState.tracking.isTracking}
          />
        )}
      </Surface>

      {/* 统计信息显示 */}
      <Surface style={styles.statsContainer} elevation={1}>
        <View style={styles.statsRow}>
          <View style={styles.statItem}>
            <Text style={styles.statLabel}>连接</Text>
            <Text style={[styles.statValue, isConnected && styles.statValueActive]}>
              {isConnected ? connectionType.toUpperCase() : '未连接'}
            </Text>
          </View>

          <View style={styles.statItem}>
            <Text style={styles.statLabel}>视频FPS</Text>
            <Text style={styles.statValue}>
              {videoStats.fps.toFixed(1)}
            </Text>
          </View>

          <View style={styles.statItem}>
            <Text style={styles.statLabel}>人脸</Text>
            <Text style={[styles.statValue, faces.length > 0 && styles.statValueActive]}>
              {faces.length}
            </Text>
          </View>

          <View style={styles.statItem}>
            <Text style={styles.statLabel}>追踪</Text>
            <Text style={[styles.statValue, visionState.tracking.isTracking && styles.statValueActive]}>
              {visionState.tracking.isTracking ? 'ON' : 'OFF'}
            </Text>
          </View>
        </View>
      </Surface>

      {/* 追踪模式选择 */}
      {isStreaming && (
        <View style={styles.modeContainer}>
          <Text style={styles.sectionTitle}>追踪模式</Text>
          <SegmentedButtons
            value={visionState.tracking.trackingMode}
            onValueChange={(value) => setTrackingMode(value as 'auto' | 'manual' | 'hybrid')}
            buttons={[
              {value: 'auto', label: '自动'},
              {value: 'hybrid', label: '混合'},
              {value: 'manual', label: '手动'},
            ]}
          />
        </View>
      )}

      {/* 控制按钮 */}
      <View style={styles.controlsContainer}>
        <View style={styles.buttonRow}>
          {!isStreaming ? (
            <Button
              mode="contained"
              onPress={handleStartStream}
              disabled={!isConnected}
              icon="play"
              style={[styles.button, styles.buttonFlex]}
              buttonColor={theme.colors.primary}
            >
              启动视频流
            </Button>
          ) : (
            <>
              <Button
                mode="contained"
                onPress={handleStopStream}
                icon="stop"
                style={[styles.button, styles.buttonHalf]}
                buttonColor={theme.colors.error}
              >
                停止
              </Button>
              {!visionState.tracking.isTracking ? (
                <Button
                  mode="contained"
                  onPress={startTracking}
                  disabled={!faceDetectionEnabled || faces.length === 0}
                  icon="crosshairs-gps"
                  style={[styles.button, styles.buttonHalf]}
                  buttonColor={theme.colors.success}
                >
                  开始追踪
                </Button>
              ) : (
                <Button
                  mode="contained"
                  onPress={stopTracking}
                  icon="pause"
                  style={[styles.button, styles.buttonHalf]}
                  buttonColor={theme.colors.warning}
                >
                  停止追踪
                </Button>
              )}
            </>
          )}
        </View>
        {isStreaming && (
          <Button
            mode="outlined"
            onPress={() => setFaceDetectionEnabled(!faceDetectionEnabled)}
            icon={faceDetectionEnabled ? 'eye' : 'eye-off'}
            style={styles.button}
          >
            {faceDetectionEnabled ? '人脸检测：开启' : '人脸检测：关闭'}
          </Button>
        )}
      </View>

      {/* 配置信息 */}
      <Surface style={styles.configContainer} elevation={1}>
        <Text style={styles.configTitle}>配置</Text>
        <Text style={styles.configText}>
          分辨率: {VIDEO_STREAM_DEFAULTS.resolution.width}x
          {VIDEO_STREAM_DEFAULTS.resolution.height}
        </Text>
        <Text style={styles.configText}>
          目标帧率: {VIDEO_STREAM_DEFAULTS.targetFPS} FPS
        </Text>
        <Text style={styles.configText}>
          质量: {VIDEO_STREAM_DEFAULTS.quality}
        </Text>
      </Surface>

      {/* 遥测仪表盘 */}
      {isStreaming && (
        <TelemetryDashboard
          performanceMonitor={performanceMonitor}
          videoStreamStats={{
            currentFPS: videoStats.fps,
            droppedFrames: videoStats.droppedFrames,
            avgLatency: videoStats.latency,
          }}
          faceDetectionStats={
            visionState.faceDetection.lastResult
              ? {
                  avgFPS: visionState.faceDetection.avgFPS,
                  avgLatency: visionState.faceDetection.avgLatency,
                  faceCount: faces.length,
                }
              : undefined
          }
          style={styles.telemetryContainer}
        />
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: theme.colors.background,
  },
  videoContainer: {
    width: SCREEN_WIDTH,
    backgroundColor: theme.colors.surface,
    justifyContent: 'center',
    alignItems: 'center',
    overflow: 'hidden',
  },
  video: {
    width: '100%',
    height: '100%',
  },
  placeholderContainer: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  placeholderText: {
    marginTop: 8,
    color: theme.colors.textSecondary,
    fontSize: 16,
  },
  statsContainer: {
    margin: 16,
    padding: 12,
    backgroundColor: theme.colors.surface,
    borderRadius: theme.roundness,
  },
  statsRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
  },
  statItem: {
    alignItems: 'center',
  },
  statLabel: {
    fontSize: 12,
    color: theme.colors.textSecondary,
    marginBottom: 4,
  },
  statValue: {
    fontSize: 16,
    fontWeight: 'bold',
    color: theme.colors.text,
  },
  statValueActive: {
    color: theme.colors.success,
  },
  controlsContainer: {
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  button: {
    borderRadius: theme.roundness,
    marginVertical: 4,
  },
  buttonRow: {
    flexDirection: 'row',
    gap: 8,
  },
  buttonFlex: {
    flex: 1,
  },
  buttonHalf: {
    flex: 1,
  },
  modeContainer: {
    marginHorizontal: 16,
    marginVertical: 8,
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: 'bold',
    color: theme.colors.text,
    marginBottom: 8,
  },
  configContainer: {
    margin: 16,
    padding: 12,
    backgroundColor: theme.colors.surface,
    borderRadius: theme.roundness,
  },
  configTitle: {
    fontSize: 14,
    fontWeight: 'bold',
    color: theme.colors.text,
    marginBottom: 8,
  },
  configText: {
    fontSize: 12,
    color: theme.colors.textSecondary,
    marginBottom: 4,
  },
  telemetryContainer: {
    margin: 16,
  },
});

export default VisionScreen;
