/**
 * Redis Configuration
 * 
 * Redis connection setup for cloud Redis services.
 * Supports: Upstash, Railway Redis, Redis Cloud, etc.
 */

import { createClient, RedisClientType } from 'redis';

// Redis client
export let redisClient: RedisClientType | null = null;

/**
 * Initialize Redis connection
 * 
 * Supports both REDIS_URL (cloud services) and individual config values
 */
export async function initializeRedis(): Promise<void> {
  if (redisClient) {
    console.log('Redis already initialized');
    return;
  }

  // Prefer REDIS_URL (used by most cloud services like Upstash, Railway)
  const redisUrl = process.env.REDIS_URL;
  
  if (redisUrl) {
    // Use connection string (cloud services)
    redisClient = createClient({
      url: redisUrl,
    });
  } else {
    // Fallback to individual config values
    redisClient = createClient({
      socket: {
        host: process.env.REDIS_HOST || 'localhost',
        port: parseInt(process.env.REDIS_PORT || '6379', 10),
      },
      password: process.env.REDIS_PASSWORD || undefined,
    });
  }

  // Error handling
  redisClient.on('error', (err) => {
    console.error('Redis Client Error:', err);
  });

  // Connect
  try {
    await redisClient.connect();
    console.log('✅ Redis connected successfully');
  } catch (error) {
    console.error('❌ Failed to connect to Redis:', error);
    throw error;
  }
}

/**
 * Get Redis client (throws if not initialized)
 */
export function getRedisClient(): RedisClientType {
  if (!redisClient) {
    throw new Error('Redis not initialized. Call initializeRedis() first.');
  }
  return redisClient;
}

/**
 * Close Redis connection
 */
export async function closeRedis(): Promise<void> {
  if (redisClient) {
    await redisClient.quit();
    redisClient = null;
    console.log('Redis connection closed');
  }
}

