/**
 * RogueSouls Server Entry Point
 * 
 * This is the main entry point for the game server.
 * Features are added incrementally and tested before moving to the next.
 */

import dotenv from 'dotenv';
import { initializeDatabase, closeDatabase } from './config/database';
import { initializeRedis, closeRedis } from './config/redis';

// Load environment variables
dotenv.config();

const PORT = process.env.PORT || 3000;

/**
 * Graceful shutdown handler
 */
async function shutdown(): Promise<void> {
  console.log('Shutting down server...');
  await closeDatabase();
  await closeRedis();
  process.exit(0);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

/**
 * Main server initialization
 */
async function startServer(): Promise<void> {
  try {
    console.log('RogueSouls Server starting...');
    console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
    console.log(`Port: ${PORT}`);

    // Initialize database (cloud PostgreSQL)
    await initializeDatabase();

    // Initialize Redis (cloud Redis)
    await initializeRedis();

    // TODO: Initialize other components incrementally
    // 3. HTTP server
    // 4. WebSocket server
    // 5. Game services

    console.log('✅ Server initialized successfully');
  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
}

// Start the server
startServer();

