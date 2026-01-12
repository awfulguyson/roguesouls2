# Deployment Guide

This guide covers deploying RogueSouls to production.

## Quick Deploy Options

### Option 1: Railway (Easiest - Free Tier Available)

**Backend (Railway):**
1. Go to https://railway.app
2. Sign up/login
3. Click "New Project" → "Deploy from GitHub repo"
4. Connect your GitHub repo
5. Select the `server` folder as the root
6. Railway will auto-detect Node.js and deploy
7. Add environment variables:
   - `PORT` (Railway sets this automatically)
   - `NODE_ENV=production`
8. Copy the deployed URL (e.g., `https://your-app.railway.app`)

**Frontend (Netlify/Vercel):**
1. Build Flutter web: `flutter build web --release`
2. Deploy the `client/build/web` folder to Netlify or Vercel
3. Set environment variables during build:
   - `API_BASE_URL=https://your-backend.railway.app`
   - `WEBSOCKET_URL=https://your-backend.railway.app`

### Option 2: Render (Free Tier)

**Backend:**
1. Go to https://render.com
2. Create new Web Service
3. Connect GitHub repo
4. Set:
   - Build Command: `cd server && npm install && npm run build`
   - Start Command: `cd server && npm start`
   - Root Directory: `server`
5. Add environment variables
6. Deploy

**Frontend:**
1. Build: `flutter build web --release`
2. Deploy `client/build/web` to Render Static Site or Netlify

### Option 3: Heroku (Paid, but reliable)

**Backend:**
```bash
cd server
heroku create your-app-name
heroku config:set NODE_ENV=production
git push heroku main
```

**Frontend:**
Deploy `client/build/web` to Netlify/Vercel with environment variables

## Step-by-Step: Railway + Netlify

### 1. Deploy Backend to Railway

1. Push code to GitHub
2. Go to Railway.app → New Project → GitHub
3. Select repo → Add Service → Select `server` folder
4. Railway auto-deploys
5. Copy the URL (e.g., `https://roguesouls-backend.railway.app`)

### 2. Build Flutter Web App

```bash
cd client
flutter build web --release --dart-define=API_BASE_URL=https://your-backend.railway.app --dart-define=WEBSOCKET_URL=https://your-backend.railway.app
```

This creates `client/build/web` folder with production build.

### 3. Deploy Frontend to Netlify

1. Go to https://netlify.com
2. Sign up/login
3. Drag and drop `client/build/web` folder
4. Or connect GitHub and set build command:
   - Build command: `cd client && flutter build web --release --dart-define=API_BASE_URL=https://your-backend.railway.app --dart-define=WEBSOCKET_URL=https://your-backend.railway.app`
   - Publish directory: `client/build/web`

### 4. Update CORS on Backend

In `server/src/index.ts`, update CORS to allow your frontend domain:

```typescript
const io = new Server(httpServer, {
  cors: {
    origin: ['https://your-app.netlify.app', 'http://localhost:8080'],
    methods: ['GET', 'POST']
  }
});
```

## Environment Variables

### Backend (.env)
```
PORT=3000
NODE_ENV=production
DB_HOST=your-db-host
DB_PORT=5432
DB_NAME=roguesouls
DB_USER=your-user
DB_PASSWORD=your-password
REDIS_HOST=your-redis-host
REDIS_PORT=6379
JWT_SECRET=your-secret-key
```

### Frontend (Build-time)
```
API_BASE_URL=https://your-backend.railway.app
WEBSOCKET_URL=https://your-backend.railway.app
```

## Testing Production Build Locally

```bash
# Build
cd client
flutter build web --release --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=WEBSOCKET_URL=http://localhost:3000

# Serve
cd build/web
python -m http.server 8080
# Or use any static file server
```

## Notes

- WebSocket connections require HTTPS in production
- Update CORS settings to match your frontend domain
- Database and Redis need to be set up separately (Railway offers add-ons)
- For MVP, you can skip database/Redis and use in-memory storage

