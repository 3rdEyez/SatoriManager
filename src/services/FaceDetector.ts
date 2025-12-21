import FaceDetection, {
  Face,
  FaceDetectorContourMode,
  FaceDetectorLandmarkMode,
  FaceDetectorPerformanceMode,
  FaceDetectorClassificationMode,
} from '@react-native-ml-kit/face-detection';

/**
 * 人脸检测结果
 */
export interface FaceDetectionResult {
  faces: Array<{
    boundingBox: {
      x: number; // 像素坐标
      y: number;
      width: number;
      height: number;
    };
    centerX: number; // 归一化 -1~1（相对于图像中心）
    centerY: number;
    confidence: number; // 置信度 0-1
    trackingId?: number; // ML Kit 跟踪 ID
  }>;
  imageWidth: number;
  imageHeight: number;
  timestamp: number;
  processingTime: number; // 检测耗时（ms）
}

/**
 * 人脸检测器配置
 */
export interface FaceDetectorConfig {
  performanceMode: 'fast' | 'accurate';
  landmarkMode: 'none' | 'all';
  contourMode: 'none' | 'all';
  classificationMode: 'none' | 'all';
  minFaceSize: number; // 0-1，相对于图像大小
  enableTracking: boolean; // 启用人脸跟踪
}

/**
 * 默认人脸检测器配置
 */
export const DEFAULT_FACE_DETECTOR_CONFIG: FaceDetectorConfig = {
  performanceMode: 'fast',
  landmarkMode: 'none',
  contourMode: 'none',
  classificationMode: 'none',
  minFaceSize: 0.15,
  enableTracking: true,
};

/**
 * 人脸检测器
 * 封装 ML Kit Face Detection API
 */
export class FaceDetector {
  private config: FaceDetectorConfig;
  private isInitialized: boolean = false;

  constructor(config: FaceDetectorConfig = DEFAULT_FACE_DETECTOR_CONFIG) {
    this.config = config;
  }

  /**
   * 初始化检测器
   * ML Kit 会在首次调用时自动初始化，这里主要用于预热
   */
  async initialize(): Promise<void> {
    if (this.isInitialized) {
      return;
    }

    try {
      // 预热：检测一个小的测试图像
      console.log('Initializing Face Detector...');
      this.isInitialized = true;
      console.log('Face Detector initialized with config:', this.config);
    } catch (error) {
      console.error('Failed to initialize Face Detector:', error);
      throw error;
    }
  }

  /**
   * 检测单张图像中的人脸
   * @param imageData JPEG 图像数据 (Uint8Array 或 base64 string)
   * @param width 图像宽度
   * @param height 图像高度
   * @returns 检测结果
   */
  async detectFaces(
    imageData: Uint8Array | string,
    width: number,
    height: number,
  ): Promise<FaceDetectionResult> {
    const startTime = Date.now();

    try {
      // 转换为 base64（如果不是）
      const base64Image =
        typeof imageData === 'string'
          ? imageData
          : Buffer.from(imageData).toString('base64');

      // 构造图像 URI
      const imageUri = `data:image/jpeg;base64,${base64Image}`;

      // 调用 ML Kit 检测
      const detectedFaces = await FaceDetection.detect(imageUri, {
        performanceMode: this.mapPerformanceMode(this.config.performanceMode),
        landmarkMode: this.mapLandmarkMode(this.config.landmarkMode),
        contourMode: this.mapContourMode(this.config.contourMode),
        classificationMode: this.mapClassificationMode(
          this.config.classificationMode,
        ),
        minFaceSize: this.config.minFaceSize,
      });

      // 转换结果格式
      const faces = detectedFaces.map(face => this.convertFace(face, width, height));

      const processingTime = Date.now() - startTime;

      return {
        faces,
        imageWidth: width,
        imageHeight: height,
        timestamp: Date.now(),
        processingTime,
      };
    } catch (error) {
      console.error('Face detection error:', error);

      // 返回空结果
      return {
        faces: [],
        imageWidth: width,
        imageHeight: height,
        timestamp: Date.now(),
        processingTime: Date.now() - startTime,
      };
    }
  }

  /**
   * 批量检测（用于提高效率）
   * 注意：ML Kit 当前不支持批量检测，这里是顺序处理
   */
  async detectFacesBatch(
    frames: Array<{data: Uint8Array | string; width: number; height: number}>,
  ): Promise<FaceDetectionResult[]> {
    const results: FaceDetectionResult[] = [];

    for (const frame of frames) {
      const result = await this.detectFaces(frame.data, frame.width, frame.height);
      results.push(result);
    }

    return results;
  }

  /**
   * 更新配置
   */
  updateConfig(config: Partial<FaceDetectorConfig>): void {
    this.config = {...this.config, ...config};
    console.log('Face Detector config updated:', this.config);
  }

  /**
   * 获取当前配置
   */
  getConfig(): FaceDetectorConfig {
    return {...this.config};
  }

  /**
   * 销毁检测器
   */
  destroy(): void {
    this.isInitialized = false;
    console.log('Face Detector destroyed');
  }

  // ========== 私有辅助方法 ==========

  /**
   * 转换 ML Kit Face 对象为我们的格式
   */
  private convertFace(
    face: Face,
    imageWidth: number,
    imageHeight: number,
  ): FaceDetectionResult['faces'][0] {
    const box = face.frame;

    // 计算人脸中心点（像素坐标）
    const centerPixelX = box.x + box.width / 2;
    const centerPixelY = box.y + box.height / 2;

    // 转换为归一化坐标（相对于图像中心，范围 -1 到 1）
    // 图像中心为 (0, 0)，左上为 (-1, -1)，右下为 (1, 1)
    const centerX = ((centerPixelX - imageWidth / 2) / (imageWidth / 2));
    const centerY = ((centerPixelY - imageHeight / 2) / (imageHeight / 2));

    return {
      boundingBox: {
        x: box.x,
        y: box.y,
        width: box.width,
        height: box.height,
      },
      centerX,
      centerY,
      confidence: 1.0, // ML Kit 不提供置信度，默认为 1.0
      trackingId: face.trackingId,
    };
  }

  /**
   * 映射性能模式枚举
   */
  private mapPerformanceMode(
    mode: FaceDetectorConfig['performanceMode'],
  ): FaceDetectorPerformanceMode {
    switch (mode) {
      case 'fast':
        return FaceDetectorPerformanceMode.FAST;
      case 'accurate':
        return FaceDetectorPerformanceMode.ACCURATE;
      default:
        return FaceDetectorPerformanceMode.FAST;
    }
  }

  /**
   * 映射地标模式枚举
   */
  private mapLandmarkMode(
    mode: FaceDetectorConfig['landmarkMode'],
  ): FaceDetectorLandmarkMode {
    switch (mode) {
      case 'none':
        return FaceDetectorLandmarkMode.NONE;
      case 'all':
        return FaceDetectorLandmarkMode.ALL;
      default:
        return FaceDetectorLandmarkMode.NONE;
    }
  }

  /**
   * 映射轮廓模式枚举
   */
  private mapContourMode(
    mode: FaceDetectorConfig['contourMode'],
  ): FaceDetectorContourMode {
    switch (mode) {
      case 'none':
        return FaceDetectorContourMode.NONE;
      case 'all':
        return FaceDetectorContourMode.ALL;
      default:
        return FaceDetectorContourMode.NONE;
    }
  }

  /**
   * 映射分类模式枚举
   */
  private mapClassificationMode(
    mode: FaceDetectorConfig['classificationMode'],
  ): FaceDetectorClassificationMode {
    switch (mode) {
      case 'none':
        return FaceDetectorClassificationMode.NONE;
      case 'all':
        return FaceDetectorClassificationMode.ALL;
      default:
        return FaceDetectorClassificationMode.NONE;
    }
  }
}

/**
 * 人脸选择策略
 * 当检测到多个人脸时，选择哪一个进行追踪
 */
export class FaceSelector {
  /**
   * 选择最大的人脸
   */
  static selectLargest(
    faces: FaceDetectionResult['faces'],
  ): FaceDetectionResult['faces'][0] | null {
    if (faces.length === 0) {
      return null;
    }

    return faces.reduce((largest, current) => {
      const largestArea =
        largest.boundingBox.width * largest.boundingBox.height;
      const currentArea =
        current.boundingBox.width * current.boundingBox.height;

      return currentArea > largestArea ? current : largest;
    });
  }

  /**
   * 选择最接近中心的人脸
   */
  static selectClosestToCenter(
    faces: FaceDetectionResult['faces'],
  ): FaceDetectionResult['faces'][0] | null {
    if (faces.length === 0) {
      return null;
    }

    return faces.reduce((closest, current) => {
      const closestDistance = Math.sqrt(
        closest.centerX * closest.centerX + closest.centerY * closest.centerY,
      );
      const currentDistance = Math.sqrt(
        current.centerX * current.centerX + current.centerY * current.centerY,
      );

      return currentDistance < closestDistance ? current : closest;
    });
  }

  /**
   * 根据跟踪 ID 选择人脸（保持跟踪同一个人）
   */
  static selectByTrackingId(
    faces: FaceDetectionResult['faces'],
    trackingId: number,
  ): FaceDetectionResult['faces'][0] | null {
    return faces.find(face => face.trackingId === trackingId) || null;
  }

  /**
   * 智能选择：优先根据跟踪 ID，如果没有则选择最大的
   */
  static selectSmart(
    faces: FaceDetectionResult['faces'],
    lastTrackingId?: number,
  ): FaceDetectionResult['faces'][0] | null {
    if (faces.length === 0) {
      return null;
    }

    // 如果有上一次的跟踪 ID，优先选择
    if (lastTrackingId !== undefined) {
      const tracked = this.selectByTrackingId(faces, lastTrackingId);
      if (tracked) {
        return tracked;
      }
    }

    // 否则选择最大的人脸
    return this.selectLargest(faces);
  }
}
