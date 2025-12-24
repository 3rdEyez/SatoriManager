/**
 * Qianwen API Client
 * 阿里云千问 API 客户端
 */

import { MindReadingResult } from '../types';
import { QIANWEN_API_CONFIG as API_CONFIG } from '../constants/MindReadingDefaults';

type ResponseCallback = (result: MindReadingResult) => void;
type ErrorCallback = (error: Error) => void;
type DelayFunction = (ms: number) => Promise<void>;

/**
 * Qianwen API Client Class
 */
export class QianwenClient {
  private apiKey: string;
  private responseCallbacks: Set<ResponseCallback> = new Set();
  private errorCallbacks: Set<ErrorCallback> = new Set();
  private delayFn: DelayFunction;

  constructor(apiKey: string = '', delayFn?: DelayFunction) {
    this.apiKey = apiKey;
    // 使用注入的delay函数，或使用默认实现
    this.delayFn = delayFn || ((ms: number) => new Promise(resolve => setTimeout(resolve, ms)));
  }

  /**
   * 设置 API Key
   */
  setApiKey(key: string): void {
    this.apiKey = key;
    console.log('[QianwenClient] API key updated');
  }

  /**
   * 获取 API Key
   */
  getApiKey(): string {
    return this.apiKey;
  }

  /**
   * 注册响应回调
   */
  onResponse(callback: ResponseCallback): () => void {
    this.responseCallbacks.add(callback);
    return () => {
      this.responseCallbacks.delete(callback);
    };
  }

  /**
   * 注册错误回调
   */
  onError(callback: ErrorCallback): () => void {
    this.errorCallbacks.add(callback);
    return () => {
      this.errorCallbacks.delete(callback);
    };
  }

  /**
   * 分析图像
   */
  async analyzeImage(imageData: Uint8Array, prompt: string): Promise<MindReadingResult> {
    if (!this.apiKey) {
      throw new Error('API key not set');
    }

    console.log('[QianwenClient] Starting image analysis...');

    try {
      // 转换为 base64
      const base64Image = Buffer.from(imageData).toString('base64');

      // 构建请求体
      const requestBody = {
        model: API_CONFIG.model,
        input: {
          messages: [
            {
              role: 'user',
              content: [
                {
                  image: `data:image/jpeg;base64,${base64Image}`,
                },
                {
                  text: prompt,
                },
              ],
            },
          ],
        },
      };

      // 带重试的请求
      const result = await this.makeRequestWithRetry(requestBody);

      console.log('[QianwenClient] Analysis completed successfully');

      // 通知所有回调
      this.notifyResponse(result);

      return result;
    } catch (error) {
      console.error('[QianwenClient] Analysis failed:', error);
      this.notifyError(error as Error);
      throw error;
    }
  }

  /**
   * 带重试的请求
   */
  private async makeRequestWithRetry(
    requestBody: any,
    maxRetries: number = API_CONFIG.maxRetries,
  ): Promise<MindReadingResult> {
    let lastError: Error | null = null;

    for (let attempt = 0; attempt < maxRetries; attempt++) {
      try {
        const result = await this.makeRequest(requestBody);
        return result;
      } catch (error) {
        lastError = error as Error;

        if (attempt < maxRetries - 1) {
          // 指数退避
          const delay = Math.pow(2, attempt) * 1000;
          console.log(`[QianwenClient] Retry ${attempt + 1}/${maxRetries} after ${delay}ms`);
          await this.delay(delay);
        }
      }
    }

    throw lastError;
  }

  /**
   * 发送 HTTP 请求
   */
  private async makeRequest(requestBody: any): Promise<MindReadingResult> {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), API_CONFIG.timeout);

    try {
      const response = await fetch(API_CONFIG.baseURL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify(requestBody),
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`API error: ${response.status} - ${errorText}`);
      }

      const data = await response.json();

      // 解析响应
      if (data.output?.choices?.[0]?.message?.content?.[0]?.text) {
        const analysis = data.output.choices[0].message.content[0].text;

        return {
          timestamp: Date.now(),
          analysis,
          model: API_CONFIG.model,
        };
      } else {
        throw new Error('Invalid API response format');
      }
    } catch (error) {
      if ((error as Error).name === 'AbortError') {
        throw new Error('Request timeout');
      }
      throw error;
    }
  }

  /**
   * 通知响应回调
   */
  private notifyResponse(result: MindReadingResult): void {
    this.responseCallbacks.forEach(callback => {
      try {
        callback(result);
      } catch (error) {
        console.error('[QianwenClient] Error in response callback:', error);
      }
    });
  }

  /**
   * 通知错误回调
   */
  private notifyError(error: Error): void {
    this.errorCallbacks.forEach(callback => {
      try {
        callback(error);
      } catch (err) {
        console.error('[QianwenClient] Error in error callback:', err);
      }
    });
  }

  /**
   * 延迟函数
   */
  private delay(ms: number): Promise<void> {
    return this.delayFn(ms);
  }
}
