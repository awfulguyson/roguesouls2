/**
 * Database Migration Runner
 * 
 * Runs database migrations to set up schema.
 * Can be run manually or as part of deployment.
 */

import dotenv from 'dotenv';
import { initializeDatabase, query, closeDatabase } from '../config/database';

// Load environment variables
dotenv.config();

/**
 * Run all migrations
 */
async function runMigrations(): Promise<void> {
  try {
    console.log('Starting database migrations...');
    
    // Initialize database connection
    await initializeDatabase();
    
    // Create migrations table to track which migrations have run
    await query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version VARCHAR(255) PRIMARY KEY,
        applied_at TIMESTAMP DEFAULT NOW()
      )
    `);
    
    // Get list of applied migrations
    const appliedMigrations = await query('SELECT version FROM schema_migrations');
    const appliedVersions = new Set(appliedMigrations.rows.map(r => r.version));
    
    // Run migrations in order
    const migrations = [
      {
        version: '001_initial_schema',
        sql: `
          -- Accounts table
          CREATE TABLE IF NOT EXISTS accounts (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            email VARCHAR(255) UNIQUE NOT NULL,
            password_hash VARCHAR(255) NOT NULL,
            steam_id BIGINT UNIQUE,
            created_at TIMESTAMP DEFAULT NOW(),
            last_login TIMESTAMP,
            is_banned BOOLEAN DEFAULT FALSE,
            ban_reason TEXT
          );

          CREATE INDEX IF NOT EXISTS idx_accounts_steam_id ON accounts(steam_id);
          CREATE INDEX IF NOT EXISTS idx_accounts_email ON accounts(email);

          -- Characters table
          CREATE TABLE IF NOT EXISTS characters (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            name VARCHAR(50) NOT NULL,
            playstyle_focus VARCHAR(20) NOT NULL DEFAULT 'dps',
            current_level INTEGER DEFAULT 1,
            experience BIGINT DEFAULT 0,
            death_count INTEGER DEFAULT 0,
            zone_id VARCHAR(50) DEFAULT 'starting_zone',
            position_x FLOAT,
            position_y FLOAT,
            health INTEGER,
            max_health INTEGER,
            mana INTEGER,
            max_mana INTEGER,
            accumulated_strength INTEGER DEFAULT 0,
            accumulated_dexterity INTEGER DEFAULT 0,
            accumulated_intelligence INTEGER DEFAULT 0,
            accumulated_vitality INTEGER DEFAULT 0,
            base_strength INTEGER DEFAULT 10,
            base_dexterity INTEGER DEFAULT 10,
            base_intelligence INTEGER DEFAULT 10,
            base_vitality INTEGER DEFAULT 10,
            has_received_starting_skills BOOLEAN DEFAULT FALSE,
            created_at TIMESTAMP DEFAULT NOW(),
            last_played TIMESTAMP,
            last_death TIMESTAMP,
            is_deleted BOOLEAN DEFAULT FALSE,
            UNIQUE(account_id, name)
          );

          CREATE INDEX IF NOT EXISTS idx_characters_account_id ON characters(account_id);
          CREATE INDEX IF NOT EXISTS idx_characters_name ON characters(name);
          CREATE INDEX IF NOT EXISTS idx_characters_playstyle ON characters(playstyle_focus);
        `,
      },
    ];
    
    for (const migration of migrations) {
      if (appliedVersions.has(migration.version)) {
        console.log(`⏭️  Migration ${migration.version} already applied, skipping`);
        continue;
      }
      
      console.log(`🔄 Running migration ${migration.version}...`);
      
      // Run migration in transaction
      await query('BEGIN');
      try {
        await query(migration.sql);
        await query('INSERT INTO schema_migrations (version) VALUES ($1)', [migration.version]);
        await query('COMMIT');
        console.log(`✅ Migration ${migration.version} completed`);
      } catch (error) {
        await query('ROLLBACK');
        throw error;
      }
    }
    
    console.log('✅ All migrations completed successfully');
  } catch (error) {
    console.error('❌ Migration failed:', error);
    throw error;
  } finally {
    await closeDatabase();
  }
}

// Run migrations if called directly
if (require.main === module) {
  runMigrations()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

export { runMigrations };

