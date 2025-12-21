import {PIDParameters, PWM_CONSTANTS} from '../types';

/**
 * PID 控制器配置
 */
export interface VisualServoConfig {
  pid: PIDParameters;
  targetPosition: {x: number; y: number}; // 归一化目标位置（通常是 0, 0）
  deadZone: number; // 死区半径（避免抖动）
  maxOutput: number; // 最大输出限制
  smoothFactor: number; // 输出平滑系数 (0-1)
}

/**
 * 视觉伺服控制器输入
 */
export interface VisualServoInput {
  facePosition: {x: number; y: number} | null; // 归一化 -1~1
  joystickInput: {x: number; y: number}; // 手动输入
  mode: 'auto' | 'manual' | 'hybrid';
}

/**
 * 视觉伺服控制器输出
 */
export interface VisualServoOutput {
  ch1: number; // PWM 500-2500
  ch2: number; // PWM 500-2500
  shouldSend: boolean; // 是否需要发送（避免过度发送）
}

/**
 * PID 调试信息
 */
export interface PIDDebugInfo {
  errorX: number;
  errorY: number;
  integralX: number;
  integralY: number;
  derivativeX: number;
  derivativeY: number;
  outputX: number;
  outputY: number;
}

/**
 * 单轴 PID 控制器
 */
class PIDController {
  private kp: number;
  private ki: number;
  private kd: number;
  private integral: number = 0;
  private lastError: number = 0;
  private maxIntegral: number;
  private lastOutput: number = 0;

  constructor(
    kp: number,
    ki: number,
    kd: number,
    maxIntegral: number = 500,
  ) {
    this.kp = kp;
    this.ki = ki;
    this.kd = kd;
    this.maxIntegral = maxIntegral;
  }

  /**
   * 更新 PID 控制器
   * @param error 误差值
   * @param dt 时间增量（秒）
   * @returns 控制输出
   */
  update(error: number, dt: number): number {
    if (dt <= 0) {
      return this.lastOutput;
    }

    // 比例项
    const proportional = this.kp * error;

    // 积分项（抗饱和）
    this.integral += error * dt;
    this.integral = Math.max(
      -this.maxIntegral,
      Math.min(this.maxIntegral, this.integral),
    );
    const integral = this.ki * this.integral;

    // 微分项
    const derivative = dt > 0 ? this.kd * (error - this.lastError) / dt : 0;

    // 总输出
    const output = proportional + integral + derivative;

    // 更新状态
    this.lastError = error;
    this.lastOutput = output;

    return output;
  }

  /**
   * 重置 PID 控制器状态
   */
  reset(): void {
    this.integral = 0;
    this.lastError = 0;
    this.lastOutput = 0;
  }

  /**
   * 更新 PID 参数
   */
  setParams(kp: number, ki: number, kd: number): void {
    this.kp = kp;
    this.ki = ki;
    this.kd = kd;
  }

  /**
   * 获取当前状态
   */
  getState(): {integral: number; lastError: number; lastOutput: number} {
    return {
      integral: this.integral,
      lastError: this.lastError,
      lastOutput: this.lastOutput,
    };
  }
}

/**
 * 视觉伺服控制器
 * 基于 PID 算法将人脸位置偏差转换为眼球舵机 PWM 控制信号
 */
export class VisualServoController {
  private config: VisualServoConfig;
  private pidX: PIDController;
  private pidY: PIDController;
  private lastUpdateTime: number = Date.now();
  private lastOutput: {ch1: number; ch2: number} = {
    ch1: PWM_CONSTANTS.CENTER_VALUE,
    ch2: PWM_CONSTANTS.CENTER_VALUE,
  };
  private lastSentOutput: {ch1: number; ch2: number} = {
    ch1: PWM_CONSTANTS.CENTER_VALUE,
    ch2: PWM_CONSTANTS.CENTER_VALUE,
  };
  private minSendInterval: number = 50; // 最小发送间隔（ms）
  private lastSendTime: number = 0;

  constructor(config: VisualServoConfig) {
    this.config = config;

    // 初始化 X 轴 PID（水平运动，CH1）
    this.pidX = new PIDController(
      config.pid.p,
      config.pid.i,
      config.pid.d,
      500,
    );

    // 初始化 Y 轴 PID（垂直运动，CH2）
    this.pidY = new PIDController(
      config.pid.p,
      config.pid.i,
      config.pid.d,
      500,
    );
  }

  /**
   * 核心计算方法
   * 根据人脸位置和控制模式计算 PWM 输出
   */
  compute(input: VisualServoInput): VisualServoOutput {
    const now = Date.now();
    const dt = (now - this.lastUpdateTime) / 1000; // 转换为秒
    this.lastUpdateTime = now;

    let ch1 = this.lastOutput.ch1;
    let ch2 = this.lastOutput.ch2;

    switch (input.mode) {
      case 'auto':
        if (input.facePosition) {
          const result = this.computeAutoMode(input.facePosition, dt);
          ch1 = result.ch1;
          ch2 = result.ch2;
        } else {
          // 无人脸检测，保持当前位置
          this.pidX.reset();
          this.pidY.reset();
        }
        break;

      case 'manual':
        const manualResult = this.computeManualMode(input.joystickInput);
        ch1 = manualResult.ch1;
        ch2 = manualResult.ch2;
        // 手动模式重置 PID
        this.pidX.reset();
        this.pidY.reset();
        break;

      case 'hybrid':
        if (input.facePosition) {
          // 自动追踪 + 手动微调
          const autoResult = this.computeAutoMode(input.facePosition, dt);
          const manualOffset = this.computeManualOffset(input.joystickInput);
          ch1 = this.clampPWM(autoResult.ch1 + manualOffset.ch1);
          ch2 = this.clampPWM(autoResult.ch2 + manualOffset.ch2);
        } else {
          // 无人脸时回退到手动模式
          const manualResult = this.computeManualMode(input.joystickInput);
          ch1 = manualResult.ch1;
          ch2 = manualResult.ch2;
          this.pidX.reset();
          this.pidY.reset();
        }
        break;
    }

    // 应用平滑滤波
    ch1 = this.applySmoothFilter(ch1, this.lastOutput.ch1);
    ch2 = this.applySmoothFilter(ch2, this.lastOutput.ch2);

    // 更新输出状态
    this.lastOutput = {ch1, ch2};

    // 判断是否需要发送
    const shouldSend = this.shouldSendOutput({ch1, ch2}, now);

    if (shouldSend) {
      this.lastSentOutput = {ch1, ch2};
      this.lastSendTime = now;
    }

    return {ch1, ch2, shouldSend};
  }

  /**
   * 计算自动追踪模式输出
   */
  private computeAutoMode(
    facePosition: {x: number; y: number},
    dt: number,
  ): {ch1: number; ch2: number} {
    // 计算误差（目标位置 - 当前位置）
    const errorX = this.config.targetPosition.x - facePosition.x;
    const errorY = this.config.targetPosition.y - facePosition.y;

    // 计算误差距离
    const errorDistance = Math.sqrt(errorX * errorX + errorY * errorY);

    // 死区处理
    if (errorDistance < this.config.deadZone) {
      return {
        ch1: this.lastOutput.ch1,
        ch2: this.lastOutput.ch2,
      };
    }

    // PID 计算
    const outputX = this.pidX.update(errorX, dt);
    const outputY = this.pidY.update(errorY, dt);

    // 限制输出幅度
    const limitedOutputX = Math.max(
      -this.config.maxOutput,
      Math.min(this.config.maxOutput, outputX),
    );
    const limitedOutputY = Math.max(
      -this.config.maxOutput,
      Math.min(this.config.maxOutput, outputY),
    );

    // 转换为 PWM 值（中心值 + PID 输出）
    const ch1 = this.clampPWM(
      PWM_CONSTANTS.CENTER_VALUE + limitedOutputX,
    );
    const ch2 = this.clampPWM(
      PWM_CONSTANTS.CENTER_VALUE + limitedOutputY,
    );

    return {ch1, ch2};
  }

  /**
   * 计算手动模式输出
   */
  private computeManualMode(joystickInput: {
    x: number;
    y: number;
  }): {ch1: number; ch2: number} {
    // 将摇杆输入 (-1~1) 映射到 PWM 范围
    const range = PWM_CONSTANTS.MAX_VALUE - PWM_CONSTANTS.MIN_VALUE;

    const ch1 = PWM_CONSTANTS.MIN_VALUE + ((joystickInput.x + 1) / 2) * range;
    const ch2 = PWM_CONSTANTS.MIN_VALUE + ((joystickInput.y + 1) / 2) * range;

    return {
      ch1: this.clampPWM(ch1),
      ch2: this.clampPWM(ch2),
    };
  }

  /**
   * 计算手动输入偏移量（用于混合模式）
   */
  private computeManualOffset(joystickInput: {
    x: number;
    y: number;
  }): {ch1: number; ch2: number} {
    // 将摇杆输入转换为 PWM 偏移量（最大 ±200）
    const maxOffset = 200;

    return {
      ch1: joystickInput.x * maxOffset,
      ch2: joystickInput.y * maxOffset,
    };
  }

  /**
   * PWM 值约束
   */
  private clampPWM(value: number): number {
    return Math.max(
      PWM_CONSTANTS.MIN_VALUE,
      Math.min(PWM_CONSTANTS.MAX_VALUE, value),
    );
  }

  /**
   * 应用平滑滤波
   */
  private applySmoothFilter(newValue: number, oldValue: number): number {
    return (
      oldValue * this.config.smoothFactor +
      newValue * (1 - this.config.smoothFactor)
    );
  }

  /**
   * 判断是否应该发送输出
   * 避免过于频繁的发送和微小变化的发送
   */
  private shouldSendOutput(
    output: {ch1: number; ch2: number},
    now: number,
  ): boolean {
    // 检查时间间隔
    if (now - this.lastSendTime < this.minSendInterval) {
      return false;
    }

    // 检查数值变化（至少变化 5 个 PWM 单位）
    const ch1Delta = Math.abs(output.ch1 - this.lastSentOutput.ch1);
    const ch2Delta = Math.abs(output.ch2 - this.lastSentOutput.ch2);
    const minDelta = 5;

    return ch1Delta >= minDelta || ch2Delta >= minDelta;
  }

  /**
   * 更新 PID 参数
   */
  updatePIDParams(params: Partial<PIDParameters>): void {
    if (params.p !== undefined) {
      this.config.pid.p = params.p;
    }
    if (params.i !== undefined) {
      this.config.pid.i = params.i;
    }
    if (params.d !== undefined) {
      this.config.pid.d = params.d;
    }

    // 更新 PID 控制器
    this.pidX.setParams(
      this.config.pid.p,
      this.config.pid.i,
      this.config.pid.d,
    );
    this.pidY.setParams(
      this.config.pid.p,
      this.config.pid.i,
      this.config.pid.d,
    );
  }

  /**
   * 更新配置
   */
  updateConfig(config: Partial<VisualServoConfig>): void {
    this.config = {...this.config, ...config};

    if (config.pid) {
      this.updatePIDParams(config.pid);
    }
  }

  /**
   * 重置控制器状态
   */
  reset(): void {
    this.pidX.reset();
    this.pidY.reset();
    this.lastOutput = {
      ch1: PWM_CONSTANTS.CENTER_VALUE,
      ch2: PWM_CONSTANTS.CENTER_VALUE,
    };
    this.lastSentOutput = {
      ch1: PWM_CONSTANTS.CENTER_VALUE,
      ch2: PWM_CONSTANTS.CENTER_VALUE,
    };
    this.lastUpdateTime = Date.now();
    this.lastSendTime = 0;
  }

  /**
   * 获取调试信息
   */
  getDebugInfo(): PIDDebugInfo {
    const stateX = this.pidX.getState();
    const stateY = this.pidY.getState();

    return {
      errorX: stateX.lastError,
      errorY: stateY.lastError,
      integralX: stateX.integral,
      integralY: stateY.integral,
      derivativeX: 0, // 需要额外存储
      derivativeY: 0,
      outputX: stateX.lastOutput,
      outputY: stateY.lastOutput,
    };
  }

  /**
   * 获取当前配置
   */
  getConfig(): VisualServoConfig {
    return {...this.config};
  }
}

/**
 * 默认视觉伺服配置
 */
export const DEFAULT_VISUAL_SERVO_CONFIG: VisualServoConfig = {
  pid: {
    p: 200, // 比例系数（PWM 单位）
    i: 10, // 积分系数
    d: 20, // 微分系数
  },
  targetPosition: {x: 0, y: 0}, // 屏幕中心
  deadZone: 0.05, // 5% 死区
  maxOutput: 300, // 最大输出 ±300 PWM 单位
  smoothFactor: 0.3, // 30% 平滑（70% 新值）
};
