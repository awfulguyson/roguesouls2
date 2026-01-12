/**
 * Database Configuration
 * 
 * PostgreSQL connection setup for cloud databases.
 * Supports: Supabase, Neon, Railway, Render, AWS RDS, etc.
 */

import { Pool, PoolConfig, QueryResult } from 'pg';

// Database connection pool
export let dbPool: Pool | null = null;

/**
 * Initialize database connection
 * 
 * Supports both connection string (DATABASE_URL) and individual config values
 * Cloud services typically provide DATABASE_URL
 */
export async function initializeDatabase(): Promise<void> {
  if (dbPool) {
    console.log('Database already initialized');
    return;
  }

  // Prefer DATABASE_URL (used by most cloud services)
  const databaseUrl = process.env.DATABASE_URL;
  
  let config: PoolConfig;
  
  if (databaseUrl) {
    // Use connection string (cloud services like Supabase, Neon, Railway)
    config = {
      connectionString: databaseUrl,
      ssl: process.env.DB_SSL !== 'false' ? { rejectUnauthorized: false } : false,
      max: 20,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 10000,
    };
  } else {
    // Fallback to individual config values
    config = {
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT || '5432', 10),
      database: process.env.DB_NAME || 'roguesouls',
      user: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD || 'postgres',
      ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
      max: 20,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 10000,
    };
  }

  dbPool = new Pool(config);

  // Test the connection
  try {
    const client = await dbPool.connect();
    const result = await client.query('SELECT NOW()');
    console.log('✅ Database connected successfully:', result.rows[0].now);
    client.release();
  } catch (error) {
    console.error('❌ Failed to connect to database:', error);
    throw error;
  }
}

/**
 * Get database pool (throws if not initialized)
 */
export function getDbPool(): Pool {
  if (!dbPool) {
    throw new Error('Database not initialized. Call initializeDatabase() first.');
  }
  return dbPool;
}

/**
 * Execute a query (convenience function)
 */
export async function query(text: string, params?: unknown[]): Promise<QueryResult> {
  const pool = getDbPool();
  return pool.query(text, params);
}

/**
 * Close database connection
 */
export async function closeDatabase(): Promise<void> {
  if (dbPool) {
    await dbPool.end();
    dbPool = null;
    console.log('Database connection closed');
  }
}

