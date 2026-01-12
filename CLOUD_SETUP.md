# Cloud Setup Quick Start

This project is configured to run entirely in the cloud. Follow these steps to get started.

## Step 1: Set Up Cloud Database (PostgreSQL)

### Option A: Supabase (Recommended - Free Tier)

1. Go to https://supabase.com
2. Sign up and create a new project
3. Go to Settings → Database
4. Copy the "Connection string" (URI format)
5. It looks like: `postgresql://postgres:[PASSWORD]@db.[PROJECT].supabase.co:5432/postgres`

### Option B: Neon (Free Tier)

1. Go to https://neon.tech
2. Sign up and create a new project
3. Copy the connection string from the dashboard
4. It looks like: `postgresql://user:password@ep-xxx.region.neon.tech/dbname`

### Option C: Railway

1. Go to https://railway.app
2. Create new project
3. Add PostgreSQL database
4. Copy DATABASE_URL from variables

## Step 2: Set Up Cloud Redis

### Option A: Upstash (Recommended - Free Tier)

1. Go to https://upstash.com
2. Sign up and create a new Redis database
3. Copy the REST URL or Redis URL
4. It looks like: `redis://default:[PASSWORD]@[HOST]:[PORT]`

### Option B: Railway Redis

1. In your Railway project
2. Add Redis database
3. Copy REDIS_URL from variables

## Step 3: Configure Environment Variables

Create a `.env` file in the `server/` directory:

```bash
# Database (use the connection string from Step 1)
DATABASE_URL=postgresql://user:password@host:port/database

# Redis (use the connection string from Step 2)
REDIS_URL=redis://user:password@host:port

# JWT Secret (generate a strong random string)
# You can generate one with: openssl rand -base64 32
JWT_SECRET=your-strong-random-secret-here

# Server
PORT=3000
NODE_ENV=development

# Steam (get these from Steamworks)
STEAM_API_KEY=your-steam-api-key
STEAM_APP_ID=your-steam-app-id

# CORS (for local development)
CORS_ORIGIN=http://localhost:8080
```

## Step 4: Run Migrations

```bash
cd server
npm install
npm run migrate
```

This will create the initial database schema (accounts, characters tables).

## Step 5: Test Connection

```bash
npm run dev
```

You should see:
```
✅ Database connected successfully
✅ Redis connected successfully
✅ Server initialized successfully
```

## Step 6: Deploy to Cloud (Optional)

See [DEPLOYMENT.md](./DEPLOYMENT.md) for deploying the server to Railway, Render, or Fly.io.

## Troubleshooting

### Database Connection Failed
- Check DATABASE_URL is correct
- Verify database is accessible (not blocked by firewall)
- For Supabase: Make sure to use the connection pooler URL if available

### Redis Connection Failed
- Check REDIS_URL is correct
- Verify Redis database is active
- Check if password is included in URL

### Migration Errors
- Make sure database is empty or migrations haven't been run before
- Check database user has CREATE TABLE permissions

## Next Steps

Once database and Redis are connected:
1. ✅ Database schema created
2. ⏭️ Next: Implement authentication service
3. ⏭️ Next: Implement HTTP server
4. ⏭️ Next: Implement WebSocket server

