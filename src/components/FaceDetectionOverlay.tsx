import React from 'react';
import {StyleSheet, ViewStyle} from 'react-native';
import Svg, {Rect, Circle, Text as SvgText, G, Line} from 'react-native-svg';
import {FaceDetectionResult} from '../services/FaceDetector';
import {theme} from '../theme';

/**
 * 人脸检测覆盖层属性
 */
interface FaceDetectionOverlayProps {
  faces: FaceDetectionResult['faces'];
  imageWidth: number;
  imageHeight: number;
  style?: ViewStyle;
  showConfidence?: boolean;
  showCrosshair?: boolean;
  showTrackingId?: boolean;
  primaryColor?: string;
  secondaryColor?: string;
}

/**
 * 人脸检测覆盖层组件
 * 在视频流上绘制人脸检测框和相关信息
 */
export const FaceDetectionOverlay: React.FC<FaceDetectionOverlayProps> = ({
  faces,
  imageWidth,
  imageHeight,
  style,
  showConfidence = true,
  showCrosshair = true,
  showTrackingId = false,
  primaryColor = theme.colors.primary,
  secondaryColor = '#00FFFF',
}) => {
  if (faces.length === 0) {
    return null;
  }

  return (
    <Svg
      width={imageWidth}
      height={imageHeight}
      style={[StyleSheet.absoluteFill, style]}
      viewBox={`0 0 ${imageWidth} ${imageHeight}`}>
      {faces.map((face, index) => (
        <G key={index}>
          {/* 人脸矩形框 */}
          <Rect
            x={face.boundingBox.x}
            y={face.boundingBox.y}
            width={face.boundingBox.width}
            height={face.boundingBox.height}
            stroke={index === 0 ? primaryColor : secondaryColor}
            strokeWidth={2}
            fill="none"
          />

          {/* 角标（装饰性） */}
          <RenderCornerMarkers
            box={face.boundingBox}
            color={index === 0 ? primaryColor : secondaryColor}
          />

          {/* 中心点准星 */}
          {showCrosshair && (
            <RenderCrosshair
              centerX={face.boundingBox.x + face.boundingBox.width / 2}
              centerY={face.boundingBox.y + face.boundingBox.height / 2}
              size={10}
              color={index === 0 ? primaryColor : secondaryColor}
            />
          )}

          {/* 置信度文字 */}
          {showConfidence && (
            <SvgText
              x={face.boundingBox.x + 5}
              y={face.boundingBox.y - 5}
              fill={index === 0 ? primaryColor : secondaryColor}
              fontSize={14}
              fontWeight="bold">
              {(face.confidence * 100).toFixed(0)}%
            </SvgText>
          )}

          {/* 跟踪 ID */}
          {showTrackingId && face.trackingId !== undefined && (
            <SvgText
              x={face.boundingBox.x + 5}
              y={face.boundingBox.y + face.boundingBox.height + 15}
              fill={index === 0 ? primaryColor : secondaryColor}
              fontSize={12}
              fontWeight="bold">
              ID: {face.trackingId}
            </SvgText>
          )}

          {/* 主要人脸指示器（第一个人脸） */}
          {index === 0 && (
            <Circle
              cx={face.boundingBox.x + face.boundingBox.width - 10}
              cy={face.boundingBox.y + 10}
              r={4}
              fill={primaryColor}
            />
          )}
        </G>
      ))}
    </Svg>
  );
};

/**
 * 渲染角标
 */
const RenderCornerMarkers: React.FC<{
  box: {x: number; y: number; width: number; height: number};
  color: string;
}> = ({box, color}) => {
  const cornerLength = 15;

  return (
    <G>
      {/* 左上角 */}
      <Line
        x1={box.x}
        y1={box.y}
        x2={box.x + cornerLength}
        y2={box.y}
        stroke={color}
        strokeWidth={3}
      />
      <Line
        x1={box.x}
        y1={box.y}
        x2={box.x}
        y2={box.y + cornerLength}
        stroke={color}
        strokeWidth={3}
      />

      {/* 右上角 */}
      <Line
        x1={box.x + box.width}
        y1={box.y}
        x2={box.x + box.width - cornerLength}
        y2={box.y}
        stroke={color}
        strokeWidth={3}
      />
      <Line
        x1={box.x + box.width}
        y1={box.y}
        x2={box.x + box.width}
        y2={box.y + cornerLength}
        stroke={color}
        strokeWidth={3}
      />

      {/* 左下角 */}
      <Line
        x1={box.x}
        y1={box.y + box.height}
        x2={box.x + cornerLength}
        y2={box.y + box.height}
        stroke={color}
        strokeWidth={3}
      />
      <Line
        x1={box.x}
        y1={box.y + box.height}
        x2={box.x}
        y2={box.y + box.height - cornerLength}
        stroke={color}
        strokeWidth={3}
      />

      {/* 右下角 */}
      <Line
        x1={box.x + box.width}
        y1={box.y + box.height}
        x2={box.x + box.width - cornerLength}
        y2={box.y + box.height}
        stroke={color}
        strokeWidth={3}
      />
      <Line
        x1={box.x + box.width}
        y1={box.y + box.height}
        x2={box.x + box.width}
        y2={box.y + box.height - cornerLength}
        stroke={color}
        strokeWidth={3}
      />
    </G>
  );
};

/**
 * 渲染准星
 */
const RenderCrosshair: React.FC<{
  centerX: number;
  centerY: number;
  size: number;
  color: string;
}> = ({centerX, centerY, size, color}) => {
  return (
    <G>
      {/* 中心圆 */}
      <Circle cx={centerX} cy={centerY} r={size / 4} fill={color} />

      {/* 十字线 */}
      <Line
        x1={centerX - size}
        y1={centerY}
        x2={centerX + size}
        y2={centerY}
        stroke={color}
        strokeWidth={2}
      />
      <Line
        x1={centerX}
        y1={centerY - size}
        x2={centerX}
        y2={centerY + size}
        stroke={color}
        strokeWidth={2}
      />

      {/* 外圈 */}
      <Circle
        cx={centerX}
        cy={centerY}
        r={size}
        stroke={color}
        strokeWidth={1.5}
        fill="none"
      />
    </G>
  );
};

export default FaceDetectionOverlay;
