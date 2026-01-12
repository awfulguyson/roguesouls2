# Free Deployment Options for RogueSouls

This guide covers completely free hosting options for both backend and frontend, perfect for collaboration.

## Option 1: Render (Free Tier) + Cloudflare Pages (Free) ⭐ RECOMMENDED

### Backend: Render (Free Tier)
- ✅ **Free tier**: 750 hours/month (enough for 24/7)
- ✅ **Free PostgreSQL database** included
- ✅ **Free Redis** (optional add-on)
- ✅ **Auto-deploy from GitHub**
- ✅ **Team collaboration** (free)
- ✅ **HTTPS included**
- ⚠️ Spins down after 15 min inactivity (wakes up on first request - ~30s delay)

**Setup:**
1. Go to https://render.com → Sign up with GitHub
2. New → Web Service
3. Connect GitHub repo
4. Settings:
   - **Name**: `roguesouls-backend`
   - **Root Directory**: `server`
   - **Build Command**: `npm install && npm run build`
   - **Start Command**: `npm start`
   - **Environment**: Node
5. Add environment variables:
   - `NODE_ENV=production`
   - `FRONTEND_URL=https://your-app.pages.dev` (set after frontend deploy)
6. Deploy → Get URL: `https://roguesouls-backend.onrender.com`

### Frontend: Cloudflare Pages (Free)
- ✅ **Completely free**
- ✅ **Unlimited bandwidth**
- ✅ **Global CDN**
- ✅ **Auto-deploy from GitHub**
- ✅ **Preview deployments**
- ✅ **Team collaboration**

**Setup:** (See CLOUDFLARE_DEPLOYMENT.md)

**Total Cost: $0/month**

---

## Option 2: Fly.io (Free Tier) + Cloudflare Pages

### Backend: Fly.io
- ✅ **Free tier**: 3 shared VMs (256MB RAM each)
- ✅ **Free PostgreSQL** (1GB)
- ✅ **No sleep/spin-down**
- ✅ **Global edge locations**
- ⚠️ Requires credit card (but free tier is generous)

**Setup:**
1. Install Fly CLI: `iwr https://fly.io/install.ps1 -useb | iex`
2. Sign up: `fly auth signup`
3. Create app: `cd server && fly launch`
4. Deploy: `fly deploy`

### Frontend: Cloudflare Pages (same as above)

**Total Cost: $0/month** (with credit card on file)

---

## Option 3: Railway (Limited Free) + Cloudflare Pages

### Backend: Railway
- ⚠️ **Free tier**: $5 credit/month (expires, not cumulative)
- ⚠️ Usually lasts ~1-2 weeks for small apps
- ✅ Easy setup
- ✅ Good for testing/development

**Total Cost: ~$5/month after free credit**

---

## Option 4: Self-Hosted (Completely Free)

### Backend: Your Own Server/VPS
- ✅ **Free options**: Oracle Cloud Free Tier, Google Cloud Free Tier, AWS Free Tier
- ✅ **Full control**
- ⚠️ Requires server management knowledge
- ⚠️ Need to set up SSL, updates, etc.

### Frontend: Cloudflare Pages (free)

**Total Cost: $0/month**

---

## Recommendation for Collaboration

### Best Free Option: **Render + Cloudflare Pages**

**Why:**
- ✅ Both completely free
- ✅ Easy GitHub integration
- ✅ Team collaboration built-in
- ✅ Good documentation
- ✅ Reliable (Render is used by many startups)

**Trade-offs:**
- Render backend spins down after 15 min inactivity (first request takes ~30s to wake up)
- For active development/testing, this is fine
- For production with users, consider paid tier ($7/month for always-on)

---

## Collaboration Setup

### Render Team Collaboration:
1. Go to Render dashboard → Team
2. Invite your friend via email
3. They get access to all services
4. Both can deploy, view logs, manage environment variables

### Cloudflare Pages Collaboration:
1. Cloudflare Pages → Settings → Collaborators
2. Add your friend's email
3. They can deploy, manage domains, view analytics

### GitHub Collaboration:
1. Add your friend as collaborator on GitHub repo
2. Both can push code
3. Auto-deploys trigger on push (if configured)

---

## Cost Comparison

| Service | Free Tier | Paid Tier | Best For |
|---------|-----------|-----------|----------|
| **Render** | 750 hrs/month | $7/month (always-on) | Development, MVP |
| **Fly.io** | 3 VMs, 1GB DB | Pay-as-you-go | Production |
| **Railway** | $5 credit/month | $5+/month | Quick testing |
| **Cloudflare Pages** | Unlimited | Free | Frontend hosting |

---

## Quick Start: Render + Cloudflare Pages

### 1. Deploy Backend to Render (5 minutes)

1. Sign up at https://render.com
2. New → Web Service
3. Connect GitHub → Select repo
4. Configure:
   - **Name**: `roguesouls-backend`
   - **Root Directory**: `server`
   - **Build Command**: `npm install && npm run build`
   - **Start Command**: `npm start`
5. Add environment variable: `NODE_ENV=production`
6. Create → Deploy
7. Copy URL: `https://roguesouls-backend.onrender.com`

### 2. Deploy Frontend to Cloudflare Pages (5 minutes)

1. Sign up at https://dash.cloudflare.com
2. Pages → Create project → Connect Git
3. Select repo
4. Build settings:
   - **Build command**: `cd client && flutter pub get && flutter build web --release --dart-define=API_BASE_URL=$API_BASE_URL --dart-define=WEBSOCKET_URL=$WEBSOCKET_URL`
   - **Output directory**: `client/build/web`
5. Environment variables:
   - `API_BASE_URL`: `https://roguesouls-backend.onrender.com`
   - `WEBSOCKET_URL`: `https://roguesouls-backend.onrender.com`
6. Deploy

### 3. Update Backend CORS

In Render dashboard, add environment variable:
- `FRONTEND_URL`: `https://your-project.pages.dev`

Redeploy backend.

**Done! Your app is live and free!**

---

## Notes

- **Render spin-down**: First request after 15 min inactivity takes ~30s. Subsequent requests are fast.
- **For production**: Consider Render paid tier ($7/month) for always-on backend
- **Database**: Render includes free PostgreSQL (no setup needed)
- **SSL**: Both services provide automatic HTTPS
- **Custom domains**: Both support custom domains (free)

---

## Need Help?

- Render docs: https://render.com/docs
- Cloudflare Pages docs: https://developers.cloudflare.com/pages
- Flutter web deployment: https://docs.flutter.dev/deployment/web

