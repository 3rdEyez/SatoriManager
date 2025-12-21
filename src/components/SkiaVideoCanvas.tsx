import React, {useMemo} from 'react';
import {StyleSheet, ViewStyle} from 'react-native';
import {
  Canvas,
  Image,
  useImage,
  Group,
  Rect,
  Circle,
  Text as SkiaText,
  Line,
  Paint,
  Skia,
} from '@shopify/react-native-skia';
import {FaceDetectionResult} from '../services/FaceDetector';
import {theme} from '../theme';

/**
 * Skia Video Canvas 属性
 */
interface SkiaVideoCanvasProps {
  videoFrame: {
    data: Uint8Array;
    width: number;
    height: number;
  } | null;
  faces: FaceDetectionResult['faces'];
  canvasWidth: number;
  canvasHeight: number;
  style?: ViewStyle;
  showConfidence?: boolean;
  showCrosshair?: boolean;
  showTrackingId?: boolean;
  primaryColor?: string;
  secondaryColor?: string;
}

/**
 * Skia Video Canvas 组件
 * 使用 GPU 加速渲染视频流和人脸检测覆盖层
 * 性能优于 FastImage + SVG 方案
 */
export const SkiaVideoCanvas: React.FC<SkiaVideoCanvasProps> = ({
  videoFrame,
  faces,
  canvasWidth,
  canvasHeight,
  style,
  showConfidence = true,
  showCrosshair = true,
  showTrackingId = false,
  primaryColor = theme.colors.primary,
  secondaryColor = '#00FFFF',
}) => {
  // 将 Uint8Array 转换为 base64 URI 用于 Skia Image
  const imageUri = useMemo(() => {
    if (!videoFrame) {
      return null;
    }
    const base64 = Buffer.from(videoFrame.data).toString('base64');
    return `data:image/jpeg;base64,${base64}`;
  }, [videoFrame]);

  // 加载图像
  const image = useImage(imageUri);

  // 创建 Paint 对象用于文本渲染
  const font = useMemo(() => {
    return Skia.Font(null, 14);
  }, []);

  const smallFont = useMemo(() => {
    return Skia.Font(null, 12);
  }, []);

  return (
    <Canvas style={[styles.canvas, {width: canvasWidth, height: canvasHeight}, style]}>
      {/* 渲染视频帧 */}
      {image && (
        <Image
          image={image}
          x={0}
          y={0}
          width={canvasWidth}
          height={canvasHeight}
          fit="cover"
        />
      )}

      {/* 渲染人脸检测框 */}
      {faces.map((face, index) => {
        const color = index === 0 ? primaryColor : secondaryColor;

        return (
          <Group key={index}>
            {/* 人脸矩形框 */}
            <Rect
              x={face.boundingBox.x}
              y={face.boundingBox.y}
              width={face.boundingBox.width}
              height={face.boundingBox.height}
              color={color}
              style="stroke"
              strokeWidth={2}
            />

            {/* 角标（装饰性） */}
            <RenderCornerMarkers box={face.boundingBox} color={color} />

            {/* 中心点准星 */}
            {showCrosshair && (
              <RenderCrosshair
                centerX={face.boundingBox.x + face.boundingBox.width / 2}
                centerY={face.boundingBox.y + face.boundingBox.height / 2}
                size={10}
                color={color}
              />
            )}

            {/* 置信度文字 */}
            {showConfidence && (
              <SkiaText
                x={face.boundingBox.x + 5}
                y={face.boundingBox.y - 5}
                text={`${(face.confidence * 100).toFixed(0)}%`}
                color={color}
                font={font}
              />
            )}

            {/* 跟踪 ID */}
            {showTrackingId && face.trackingId !== undefined && (
              <SkiaText
                x={face.boundingBox.x + 5}
                y={face.boundingBox.y + face.boundingBox.height + 15}
                text={`ID: ${face.trackingId}`}
                color={color}
                font={smallFont}
              />
            )}

            {/* 主要人脸指示器（第一个人脸） */}
            {index === 0 && (
              <Circle
                cx={face.boundingBox.x + face.boundingBox.width - 10}
                cy={face.boundingBox.y + 10}
                r={4}
                color={color}
              />
            )}
          </Group>
        );
      })}
    </Canvas>
  );
};

/**
 * 渲染角标组件
 */
const RenderCornerMarkers: React.FC<{
  box: {x: number; y: number; width: number; height: number};
  color: string;
}> = ({box, color}) => {
  const cornerLength = 15;

  return (
    <Group>
      {/* 左上角 */}
      <Line
        p1={{x: box.x, y: box.y}}
        p2={{x: box.x + cornerLength, y: box.y}}
        color={color}
        strokeWidth={3}
      />
      <Line
        p1={{x: box.x, y: box.y}}
        p2={{x: box.x, y: box.y + cornerLength}}
        color={color}
        strokeWidth={3}
      />

      {/* 右上角 */}
      <Line
        p1={{x: box.x + box.width, y: box.y}}
        p2={{x: box.x + box.width - cornerLength, y: box.y}}
        color={color}
        strokeWidth={3}
      />
      <Line
        p1={{x: box.x + box.width, y: box.y}}
        p2={{x: box.x + box.width, y: box.y + cornerLength}}
        color={color}
        strokeWidth={3}
      />

      {/* 左下角 */}
      <Line
        p1={{x: box.x, y: box.y + box.height}}
        p2={{x: box.x + cornerLength, y: box.y + box.height}}
        color={color}
        strokeWidth={3}
      />
      <Line
        p1={{x: box.x, y: box.y + box.height}}
        p2={{x: box.x, y: box.y + box.height - cornerLength}}
        color={color}
        strokeWidth={3}
      />

      {/* 右下角 */}
      <Line
        p1={{x: box.x + box.width, y: box.y + box.height}}
        p2={{x: box.x + box.width - cornerLength, y: box.y + box.height}}
        color={color}
        strokeWidth={3}
      />
      <Line
        p1={{x: box.x + box.width, y: box.y + box.height}}
        p2={{x: box.x + box.width, y: box.y + box.height - cornerLength}}
        color={color}
        strokeWidth={3}
      />
    </Group>
  );
};

/**
 * 渲染准星组件
 */
const RenderCrosshair: React.FC<{
  centerX: number;
  centerY: number;
  size: number;
  color: string;
}> = ({centerX, centerY, size, color}) => {
  return (
    <Group>
      {/* 中心圆 */}
      <Circle cx={centerX} cy={centerY} r={size / 4} color={color} />

      {/* 十字线 */}
      <Line
        p1={{x: centerX - size, y: centerY}}
        p2={{x: centerX + size, y: centerY}}
        color={color}
        strokeWidth={2}
      />
      <Line
        p1={{x: centerX, y: centerY - size}}
        p2={{x: centerX, y: centerY + size}}
        color={color}
        strokeWidth={2}
      />

      {/* 外圈 */}
      <Circle
        cx={centerX}
        cy={centerY}
        r={size}
        color={color}
        style="stroke"
        strokeWidth={1.5}
      />
    </Group>
  );
};

const styles = StyleSheet.create({
  canvas: {
    backgroundColor: 'transparent',
  },
});

export default SkiaVideoCanvas;
