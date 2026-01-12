# RogueSouls Server

Backend server for RogueSouls MMO game.

**This server is designed to run in the cloud.** See [DEPLOYMENT.md](../DEPLOYMENT.md) for cloud setup instructions.

## Quick Setup (Cloud)

1. **Set up cloud services:**
   - PostgreSQL: Supabase, Neon, or Railway (get DATABASE_URL)
   - Redis: Upstash or Railway (get REDIS_URL)

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Set up environment variables**
   ```bash
   # Create .env file with:
   DATABASE_URL=<your-cloud-postgres-url>
   REDIS_URL=<your-cloud-redis-url>
   JWT_SECRET=<generate-strong-random-string>
   STEAM_API_KEY=<your-steam-key>
   STEAM_APP_ID=<your-steam-app-id>
   ```

4. **Run database migrations**
   ```bash
   npm run migrate
   ```

5. **Run development server**
   ```bash
   npm run dev
   ```

## Local Development (Optional)

If you want to run locally for testing:
- Install PostgreSQL and Redis locally
- Use individual DB_HOST, DB_PORT, etc. instead of DATABASE_URL
- See `.env.example` for all options

## Environment Variables

See `.env.example` for required environment variables.

## Project Structure

```
server/
├── src/
│   ├── index.ts              # Entry point
│   ├── config/               # Configuration
│   ├── services/             # Business logic
│   ├── models/               # Data models
│   ├── networking/            # WebSocket/network code
│   ├── database/             # Database migrations, seeds
│   └── utils/                # Utilities
├── dist/                     # Compiled output
└── tests/                    # Tests
```

## Development

- Use `npm run dev` for development with hot reload
- Use `npm run build` to compile TypeScript
- Use `npm run lint` to check code quality
- Use `npm run test` to run tests

