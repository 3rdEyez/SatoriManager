/**
 * QianwenClient Tests
 */

import { QianwenClient } from '../../src/services/QianwenClient';
import { MindReadingResult } from '../../src/types';

// Mock fetch globally
const mockFetch = jest.fn();
global.fetch = mockFetch;

describe('QianwenClient', () => {
  let client: QianwenClient;
  const mockApiKey = 'test-api-key-12345';
  const mockImageData = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]);
  const mockPrompt = 'Analyze this face';

  // Mock delay function for testing (resolves immediately)
  const mockDelay = jest.fn((ms: number) => Promise.resolve());

  beforeEach(() => {
    jest.clearAllMocks();
    mockDelay.mockClear();
    client = new QianwenClient('', mockDelay);
  });

  afterEach(() => {
    jest.clearAllMocks();
    mockDelay.mockClear();
  });

  describe('Initialization', () => {
    it('should initialize with empty API key', () => {
      expect(client.getApiKey()).toBe('');
    });

    it('should accept and store API key', () => {
      client.setApiKey(mockApiKey);

      expect(client.getApiKey()).toBe(mockApiKey);
    });
  });

  describe('API Key Management', () => {
    it('should update API key', () => {
      client.setApiKey('first-key');
      expect(client.getApiKey()).toBe('first-key');

      client.setApiKey('second-key');
      expect(client.getApiKey()).toBe('second-key');
    });

    it('should return current API key', () => {
      expect(client.getApiKey()).toBe('');

      client.setApiKey(mockApiKey);
      expect(client.getApiKey()).toBe(mockApiKey);
    });
  });

  describe('Image Analysis', () => {
    it('should throw error when API key not set', async () => {
      await expect(client.analyzeImage(mockImageData, mockPrompt)).rejects.toThrow('API key not set');
    });

    it('should convert image data to base64', async () => {
      client.setApiKey(mockApiKey);

      mockFetch.mockResolvedValue({
        ok: true,
        json: async () => ({
          output: {
            choices: [{
              message: {
                content: [{
                  text: 'Analysis result',
                }],
              },
            }],
          },
        }),
      });

      await client.analyzeImage(mockImageData, mockPrompt);

      const requestBody = JSON.parse(mockFetch.mock.calls[0][1].body);
      const base64Image = requestBody.input.messages[0].content[0].image;

      expect(base64Image).toMatch(/^data:image\/jpeg;base64,/);
      expect(base64Image).toContain(Buffer.from(mockImageData).toString('base64'));
    });

    it('should build correct request body', async () => {
      client.setApiKey(mockApiKey);

      mockFetch.mockResolvedValue({
        ok: true,
        json: async () => ({
          output: {
            choices: [{
              message: {
                content: [{
                  text: 'Result',
                }],
              },
            }],
          },
        }),
      });

      await client.analyzeImage(mockImageData, mockPrompt);

      const fetchCall = mockFetch.mock.calls[0];
      expect(fetchCall[0]).toBe('https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation');

      const requestBody = JSON.parse(fetchCall[1].body);
      expect(requestBody.model).toBe('qwen-vl-max');
      expect(requestBody.input.messages).toHaveLength(1);
      expect(requestBody.input.messages[0].role).toBe('user');
    });

    it('should include Authorization header', async () => {
      client.setApiKey(mockApiKey);

      mockFetch.mockResolvedValue({
        ok: true,
        json: async () => ({
          output: {
            choices: [{
              message: {
                content: [{
                  text: 'Result',
                }],
              },
            }],
          },
        }),
      });

      await client.analyzeImage(mockImageData, mockPrompt);

      const headers = mockFetch.mock.calls[0][1].headers;
      expect(headers.Authorization).toBe(`Bearer ${mockApiKey}`);
    });

    it('should include both image and prompt in request', async () => {
      client.setApiKey(mockApiKey);

      mockFetch.mockResolvedValue({
        ok: true,
        json: async () => ({
          output: {
            choices: [{
              message: {
                content: [{
                  text: 'Analysis complete',
                }],
              },
            }],
          },
        }),
      });

      await client.analyzeImage(mockImageData, mockPrompt);

      const content = JSON.parse(mockFetch.mock.calls[0][1].body).input.messages[0].content;

      expect(content[0]).toHaveProperty('image');
      expect(content[1]).toHaveProperty('text', mockPrompt);
    });

    it('should handle successful API response', async () => {
      client.setApiKey(mockApiKey);
      const analysisText = 'This person appears happy and confident.';

      mockFetch.mockResolvedValue({
        ok: true,
        json: async () => ({
          output: {
            choices: [{
              message: {
                content: [{
                  text: analysisText,
                }],
              },
            }],
          },
        }),
      });

      const result = await client.analyzeImage(mockImageData, mockPrompt);

      expect(result.analysis).toBe(analysisText);
      expect(result.model).toBe('qwen-vl-max');
      expect(result.timestamp).toBeDefined();
    });

    it('should handle API error response', async () => {
      client.setApiKey(mockApiKey);

      mockFetch.mockResolvedValue({
        ok: false,
        status: 401,
        text: async () => 'Unauthorized',
      });

      await expect(client.analyzeImage(mockImageData, mockPrompt)).rejects.toThrow('API error: 401');
    });

    it('should handle network error', async () => {
      client.setApiKey(mockApiKey);

      mockFetch.mockRejectedValue(new Error('Network error'));

      await expect(client.analyzeImage(mockImageData, mockPrompt)).rejects.toThrow('Network error');
    });

    it('should handle timeout', async () => {
      client.setApiKey(mockApiKey);

      // Create an abort error
      const abortError = new Error('Request timeout');
      abortError.name = 'AbortError';
      mockFetch.mockRejectedValue(abortError);

      await expect(client.analyzeImage(mockImageData, mockPrompt)).rejects.toThrow('Request timeout');
    });

    it('should handle invalid API response format', async () => {
      client.setApiKey(mockApiKey);

      mockFetch.mockResolvedValue({
        ok: true,
        json: async () => ({
          output: {
            // Missing choices
          },
        }),
      });

      await expect(client.analyzeImage(mockImageData, mockPrompt)).rejects.toThrow('Invalid API response format');
    });
  });

  describe('Retry Logic', () => {
    it('should retry on transient failures', async () => {
      client.setApiKey(mockApiKey);

      // First two calls fail, third succeeds
      mockFetch
        .mockRejectedValueOnce(new Error('Network error'))
        .mockRejectedValueOnce(new Error('Network error'))
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({
            output: {
              choices: [{
                message: {
                  content: [{
                    text: 'Success after retries',
                  }],
                },
              }],
            },
          }),
        });

      const result = await client.analyzeImage(mockImageData, mockPrompt);

      expect(result.analysis).toBe('Success after retries');
      expect(mockFetch).toHaveBeenCalledTimes(3);
      // Verify delay was called after 1st and 2nd failures
      expect(mockDelay).toHaveBeenCalledTimes(2);
    });

    it('should respect max retry limit', async () => {
      client.setApiKey(mockApiKey);

      // All calls fail
      mockFetch.mockRejectedValue(new Error('Persistent error'));

      await expect(client.analyzeImage(mockImageData, mockPrompt)).rejects.toThrow('Persistent error');
      expect(mockFetch).toHaveBeenCalledTimes(3); // maxRetries = 3, so 3 total attempts
      expect(mockDelay).toHaveBeenCalledTimes(2); // delays before attempts 1 and 2
    });

    it('should use exponential backoff timing', async () => {
      client.setApiKey(mockApiKey);

      // First two calls fail, third succeeds (maxRetries=3, so we have 3 attempts)
      mockFetch
        .mockRejectedValueOnce(new Error('Error 1'))
        .mockRejectedValueOnce(new Error('Error 2'))
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({
            output: {
              choices: [{
                message: {
                  content: [{ text: 'Success' }],
                },
              }],
            },
          }),
        });

      await client.analyzeImage(mockImageData, mockPrompt);

      // Verify exponential backoff: 1s, 2s (2 delays for 3 total attempts)
      expect(mockDelay).toHaveBeenNthCalledWith(1, 1000);
      expect(mockDelay).toHaveBeenNthCalledWith(2, 2000);
    });
  });

  describe('Callbacks', () => {
    it('should call response callbacks on success', async () => {
      client.setApiKey(mockApiKey);
      const mockResponse: MindReadingResult = {
        timestamp: Date.now(),
        analysis: 'Test result',
        model: 'qwen-vl-max',
      };

      mockFetch.mockResolvedValue({
        ok: true,
        json: async () => ({
          output: {
            choices: [{
              message: {
                content: [{
                  text: mockResponse.analysis,
                }],
              },
            }],
          },
        }),
      });

      const callback = jest.fn();
      client.onResponse(callback);

      await client.analyzeImage(mockImageData, mockPrompt);

      expect(callback).toHaveBeenCalledWith(
        expect.objectContaining({
          analysis: mockResponse.analysis,
        }),
      );
    });

    it('should call error callbacks on failure', async () => {
      client.setApiKey(mockApiKey);
      const error = new Error('API Error');

      mockFetch.mockRejectedValue(error);

      const errorCallback = jest.fn();
      client.onError(errorCallback);

      try {
        await client.analyzeImage(mockImageData, mockPrompt);
      } catch (e) {
        // Expected to throw
      }

      expect(errorCallback).toHaveBeenCalledWith(error);
    });

    it('should support multiple callback registration', async () => {
      client.setApiKey(mockApiKey);

      mockFetch.mockResolvedValue({
        ok: true,
        json: async () => ({
          output: {
            choices: [{
              message: {
                content: [{
                  text: 'Result',
                }],
              },
            }],
          },
        }),
      });

      const callback1 = jest.fn();
      const callback2 = jest.fn();

      client.onResponse(callback1);
      client.onResponse(callback2);

      await client.analyzeImage(mockImageData, mockPrompt);

      expect(callback1).toHaveBeenCalled();
      expect(callback2).toHaveBeenCalled();
    });

    it('should unregister callbacks correctly', async () => {
      client.setApiKey(mockApiKey);

      mockFetch.mockResolvedValue({
        ok: true,
        json: async () => ({
          output: {
            choices: [{
              message: {
                content: [{
                  text: 'Result',
                }],
              },
            }],
          },
        }),
      });

      const callback = jest.fn();
      const unsubscribe = client.onResponse(callback);
      unsubscribe();

      await client.analyzeImage(mockImageData, mockPrompt);

      expect(callback).not.toHaveBeenCalled();
    });
  });

  describe('Multiple Requests', () => {
    it('should handle concurrent requests', async () => {
      client.setApiKey(mockApiKey);

      mockFetch.mockResolvedValue({
        ok: true,
        json: async () => ({
          output: {
            choices: [{
              message: {
                content: [{
                  text: 'Result',
                }],
              },
            }],
          },
        }),
      });

      const promise1 = client.analyzeImage(mockImageData, 'Prompt 1');
      const promise2 = client.analyzeImage(mockImageData, 'Prompt 2');

      await Promise.all([promise1, promise2]);

      expect(mockFetch).toHaveBeenCalledTimes(2);
    });
  });
});
