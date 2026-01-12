# Cloud Deployment Guide

This project is designed to run entirely in the cloud, allowing multiple developers to collaborate without running servers locally.

## Recommended Cloud Services

### Database: PostgreSQL

**Option 1: Supabase (Recommended for Indie)**
- Free tier: 500MB database, 2GB bandwidth
- Easy setup, great developer experience
- Built-in connection pooling
- URL: https://supabase.com

**Option 2: Neon**
- Free tier: 3GB storage, serverless PostgreSQL
- Great for scaling
- URL: https://neon.tech

**Option 3: Railway**
- Simple PostgreSQL addon
- Pay-as-you-go
- URL: https://railway.app

**Setup:**
1. Create account and database
2. Copy connection string (DATABASE_URL)
3. Add to environment variables

### Redis

**Option 1: Upstash (Recommended)**
- Free tier: 10K commands/day
- Serverless Redis
- URL: https://upstash.com

**Option 2: Railway Redis**
- Simple Redis addon
- URL: https://railway.app

**Setup:**
1. Create account and Redis database
2. Copy connection string (REDIS_URL)
3. Add to environment variables

### Server Hosting

**Option 1: Railway (Recommended for Simplicity)**
- Free tier: $5 credit/month
- Easy deployment from GitHub
- Automatic HTTPS
- URL: https://railway.app

**Option 2: Render**
- Free tier available (with limitations)
- Easy GitHub integration
- URL: https://render.com

**Option 3: Fly.io**
- Generous free tier
- Global edge deployment
- URL: https://fly.io

## Deployment Steps

### Railway Deployment

1. **Create Railway Account**
   - Go to https://railway.app
   - Sign up with GitHub

2. **Create New Project**
   - Click "New Project"
   - Select "Deploy from GitHub repo"
   - Select your RogueSouls repository

3. **Add PostgreSQL**
   - Click "+ New" → "Database" → "PostgreSQL"
   - Railway automatically creates DATABASE_URL

4. **Add Redis**
   - Click "+ New" → "Database" → "Redis"
   - Railway automatically creates REDIS_URL

5. **Configure Environment Variables**
   - Go to project settings → Variables
   - Add:
     - `NODE_ENV=production`
     - `JWT_SECRET=<generate-strong-random-string>`
     - `STEAM_API_KEY=<your-steam-key>`
     - `STEAM_APP_ID=<your-steam-app-id>`
     - `CORS_ORIGIN=<your-frontend-url>`

6. **Deploy**
   - Railway auto-deploys on git push
   - Or click "Deploy" button

### Render Deployment

1. **Create Render Account**
   - Go to https://render.com
   - Sign up with GitHub

2. **Create Web Service**
   - New → Web Service
   - Connect GitHub repo
   - Build command: `cd server && npm install && npm run build`
   - Start command: `cd server && npm start`

3. **Add PostgreSQL**
   - New → PostgreSQL
   - Copy DATABASE_URL to environment variables

4. **Add Redis**
   - New → Redis
   - Copy REDIS_URL to environment variables

5. **Configure Environment Variables**
   - Add all required variables (see .env.example)

### Environment Variables for Production

Required variables:
```bash
NODE_ENV=production
PORT=3000
DATABASE_URL=<from-cloud-provider>
REDIS_URL=<from-cloud-provider>
JWT_SECRET=<strong-random-string>
STEAM_API_KEY=<your-key>
STEAM_APP_ID=<your-app-id>
CORS_ORIGIN=<your-frontend-url>
```

## Multi-Developer Setup

### Shared Development Database

**Option 1: Shared Cloud Database (Recommended)**
- Use same cloud database for all developers
- Everyone connects to same DATABASE_URL
- Changes are visible to all immediately
- Use different schema prefixes if needed

**Option 2: Individual Databases**
- Each developer gets their own database
- Use different DATABASE_URL per developer
- More isolated, but requires more setup

### Environment Variables Management

**For Team Collaboration:**
1. Use Railway/Render's shared environment variables
2. Or use `.env.shared` file (don't commit secrets)
3. Document required variables in `.env.example`

### Database Migrations

Run migrations on shared database:
```bash
npm run migrate
```

Or use Railway's CLI:
```bash
railway run npm run migrate
```

## Cost Estimate (Indie-Friendly)

**Free Tier Setup:**
- Supabase PostgreSQL: Free (up to 500MB)
- Upstash Redis: Free (10K commands/day)
- Railway Server: $5 credit/month (usually free for small projects)

**Total: ~$0-5/month for development**

**Production (when scaling):**
- Database: $10-25/month
- Redis: $10-20/month
- Server: $10-50/month (scales with usage)

**Total: ~$30-95/month for small production**

## Security Notes

1. **Never commit `.env` files** - Use `.env.example` as template
2. **Use strong JWT_SECRET** - Generate with: `openssl rand -base64 32`
3. **Enable SSL for databases** - Most cloud providers do this automatically
4. **Use environment variables** - Never hardcode secrets
5. **Rotate secrets regularly** - Especially in production

## Monitoring

Most cloud providers offer:
- Logs dashboard
- Metrics (CPU, memory, requests)
- Error tracking
- Uptime monitoring

Set up alerts for:
- Server crashes
- Database connection failures
- High error rates

