# Cloudflare Deployment Guide

This guide covers deploying RogueSouls using Cloudflare Pages (frontend) and options for the backend.

## Architecture

- **Frontend**: Cloudflare Pages (free, fast CDN)
- **Backend**: Railway/Render (recommended) OR Cloudflare Tunnel (if self-hosting)

## Option 1: Cloudflare Pages + Railway (Recommended)

### Step 1: Deploy Backend to Railway

1. Go to https://railway.app → Sign up
2. New Project → Deploy from GitHub
3. Select repo → Add Service → Set root to `server`
4. Railway auto-deploys
5. Copy the URL: `https://your-backend.railway.app`

### Step 2: Deploy Frontend to Cloudflare Pages

#### Method A: Via GitHub (Recommended)

1. Push your code to GitHub
2. Go to https://dash.cloudflare.com → Pages
3. Click "Create a project" → "Connect to Git"
4. Select your GitHub repo
5. Configure build settings:
   - **Framework preset**: None (or Flutter if available)
   - **Build command**: 
     ```bash
     cd client && flutter build web --release --dart-define=API_BASE_URL=$API_BASE_URL --dart-define=WEBSOCKET_URL=$WEBSOCKET_URL
     ```
   - **Build output directory**: `client/build/web`
   - **Root directory**: `/` (or leave empty)
6. Add environment variables:
   - `API_BASE_URL`: `https://your-backend.railway.app`
   - `WEBSOCKET_URL`: `https://your-backend.railway.app`
7. Click "Save and Deploy"
8. Your app will be live at `https://your-project.pages.dev`

#### Method B: Direct Upload

1. Build locally:
   ```powershell
   cd client
   flutter build web --release --dart-define=API_BASE_URL=https://your-backend.railway.app --dart-define=WEBSOCKET_URL=https://your-backend.railway.app
   ```
2. Go to Cloudflare Pages → Create project → "Upload assets"
3. Upload the `client/build/web` folder
4. Your app is live!

### Step 3: Update Backend CORS

In `server/src/index.ts`, update CORS to allow your Cloudflare Pages domain:

```typescript
const io = new Server(httpServer, {
  cors: {
    origin: [
      'https://your-project.pages.dev',
      'http://localhost:8080' // for local dev
    ],
    methods: ['GET', 'POST'],
    credentials: true
  }
});
```

Redeploy backend after this change.

## Option 2: Cloudflare Pages + Cloudflare Tunnel (Self-Hosted Backend)

If you want to self-host the backend and use Cloudflare Tunnel:

### Step 1: Install Cloudflare Tunnel

```powershell
# Download cloudflared from https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/
```

### Step 2: Create Tunnel

```powershell
cloudflared tunnel create roguesouls-backend
```

### Step 3: Configure Tunnel

Create `cloudflare-tunnel-config.yml`:
```yaml
tunnel: <tunnel-id>
credentials-file: C:\path\to\credentials.json

ingress:
  - hostname: your-backend.yourdomain.com
    service: http://localhost:3000
  - service: http_status:404
```

### Step 4: Run Tunnel

```powershell
cloudflared tunnel --config cloudflare-tunnel-config.yml run
```

### Step 5: Deploy Frontend

Same as Option 1, but use `https://your-backend.yourdomain.com` as backend URL.

## Option 3: Cloudflare Workers (Advanced - Limited WebSocket Support)

Cloudflare Workers can host the backend, but WebSocket support requires Durable Objects which is more complex. Not recommended for MVP.

## Custom Domain Setup

### Add Custom Domain to Cloudflare Pages

1. Go to your Pages project → Custom domains
2. Add your domain (e.g., `roguesouls.com`)
3. Cloudflare will provide DNS records to add
4. Add the records in your domain's DNS settings
5. SSL is automatic with Cloudflare

### Update Backend CORS

Add your custom domain to the CORS origin list in `server/src/index.ts`.

## Environment Variables

### Cloudflare Pages Build Environment

Set these in Cloudflare Pages dashboard:
- `API_BASE_URL`: Your backend URL
- `WEBSOCKET_URL`: Your backend URL (same as API_BASE_URL)

### Backend Environment (Railway/Render)

Set in Railway/Render dashboard:
- `PORT`: Auto-set by platform
- `NODE_ENV`: `production`
- `FRONTEND_URL`: Your Cloudflare Pages URL (for CORS)

## Build Configuration

### For Cloudflare Pages via GitHub

Create `cloudflare-pages-build.sh` in your repo root:

```bash
#!/bin/bash
cd client
flutter pub get
flutter build web --release \
  --dart-define=API_BASE_URL=$API_BASE_URL \
  --dart-define=WEBSOCKET_URL=$WEBSOCKET_URL
```

Then in Cloudflare Pages:
- Build command: `bash cloudflare-pages-build.sh`
- Build output: `client/build/web`

## Testing Production Build Locally

```powershell
# Build with production URLs
cd client
flutter build web --release `
  --dart-define=API_BASE_URL=https://your-backend.railway.app `
  --dart-define=WEBSOCKET_URL=https://your-backend.railway.app

# Serve locally
cd build/web
python -m http.server 8080
```

Visit `http://localhost:8080` to test.

## Troubleshooting

### CORS Errors

- Make sure backend CORS includes your Cloudflare Pages URL
- Check that `FRONTEND_URL` environment variable is set on backend

### WebSocket Connection Failed

- Ensure backend URL uses `https://` (not `http://`)
- Check that WebSocket is enabled on your backend hosting
- Verify CORS settings allow WebSocket connections

### Build Fails on Cloudflare Pages

- Make sure Flutter is available in build environment (may need custom Docker image)
- Check build logs for specific errors
- Consider building locally and uploading assets directly

## Benefits of Cloudflare Pages

- ✅ Free tier with generous limits
- ✅ Global CDN (fast worldwide)
- ✅ Automatic HTTPS
- ✅ Custom domains
- ✅ Preview deployments for PRs
- ✅ Easy rollbacks
- ✅ Analytics included

## Next Steps

1. Deploy backend to Railway
2. Deploy frontend to Cloudflare Pages
3. Test the live app
4. Add custom domain (optional)
5. Set up monitoring/analytics

