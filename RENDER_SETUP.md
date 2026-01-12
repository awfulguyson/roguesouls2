# Step-by-Step: Deploy to Render + Cloudflare Pages

Follow these steps in order.

## Prerequisites

- [ ] Code pushed to GitHub (if not, do that first)
- [ ] GitHub account
- [ ] Render account (free signup)
- [ ] Cloudflare account (free signup)

---

## Part 1: Deploy Backend to Render (10 minutes)

### Step 1: Sign Up for Render

1. Go to https://render.com
2. Click "Get Started for Free"
3. Sign up with GitHub (recommended - easier integration)

### Step 2: Create Web Service

1. In Render dashboard, click "New +"
2. Select "Web Service"
3. Click "Connect account" if you haven't connected GitHub yet
4. Select your GitHub account
5. Find and select your `roguesouls` repository
6. Click "Connect"

### Step 3: Configure Backend Service

Fill in these settings:

- **Name**: `roguesouls-backend` (or any name you like)
- **Region**: Choose closest to you (e.g., `Oregon (US West)`)
- **Branch**: `main` (or `master` if that's your default)
- **Root Directory**: `server` ⚠️ **IMPORTANT: Set this to `server`**
- **Runtime**: `Node`
- **Build Command**: `npm install && npm run build`
- **Start Command**: `npm start`

### Step 4: Add Environment Variables

Click "Advanced" → "Add Environment Variable"

Add this variable:
- **Key**: `NODE_ENV`
- **Value**: `production`

(We'll add `FRONTEND_URL` later after Cloudflare deployment)

### Step 5: Deploy

1. Scroll down and click "Create Web Service"
2. Render will start building and deploying
3. Wait 3-5 minutes for deployment to complete
4. You'll see a URL like: `https://roguesouls-backend.onrender.com`
5. **Copy this URL** - you'll need it for the frontend!

### Step 6: Test Backend

1. Open the URL in browser: `https://your-backend.onrender.com/health`
2. You should see: `{"status":"ok","message":"RogueSouls server is running"}`
3. If you see this, backend is working! ✅

**Note**: First request might take ~30 seconds (waking up from sleep). Subsequent requests are fast.

---

## Part 2: Deploy Frontend to Cloudflare Pages (10 minutes)

### Step 1: Sign Up for Cloudflare

1. Go to https://dash.cloudflare.com/sign-up
2. Sign up (free account)
3. Verify your email

### Step 2: Create Pages Project

1. In Cloudflare dashboard, go to "Workers & Pages"
2. Click "Create application"
3. Click "Pages" tab
4. Click "Connect to Git"
5. Authorize Cloudflare to access GitHub
6. Select your `roguesouls` repository

### Step 3: Configure Build Settings

Fill in:

- **Project name**: `roguesouls` (or any name)
- **Production branch**: `main` (or `master`)
- **Framework preset**: `None` (or leave default)
- **Build command**: 
  ```
  cd client && flutter pub get && flutter build web --release --dart-define=API_BASE_URL=$API_BASE_URL --dart-define=WEBSOCKET_URL=$WEBSOCKET_URL
  ```
- **Build output directory**: `client/build/web`
- **Root directory**: Leave empty (or `/`)

### Step 4: Add Environment Variables

Click "Add variable" and add:

1. **Variable name**: `API_BASE_URL`
   - **Value**: `https://your-backend.onrender.com` (use the URL from Part 1, Step 5)

2. **Variable name**: `WEBSOCKET_URL`
   - **Value**: `https://your-backend.onrender.com` (same URL)

⚠️ **Important**: Replace `your-backend.onrender.com` with your actual Render backend URL!

### Step 5: Deploy

1. Click "Save and Deploy"
2. Cloudflare will build and deploy (takes 5-10 minutes first time)
3. You'll get a URL like: `https://roguesouls.pages.dev`
4. **Copy this URL** - you'll need it for the next step!

### Step 6: Test Frontend

1. Open the Cloudflare Pages URL
2. You should see the login screen
3. Try logging in (it should connect to your Render backend)

---

## Part 3: Connect Frontend and Backend (5 minutes)

### Update Backend CORS

1. Go back to Render dashboard
2. Find your `roguesouls-backend` service
3. Click on it → Go to "Environment" tab
4. Click "Add Environment Variable"
5. Add:
   - **Key**: `FRONTEND_URL`
   - **Value**: `https://your-app.pages.dev` (use your Cloudflare Pages URL)
6. Click "Save Changes"
7. Render will automatically redeploy (takes 2-3 minutes)

### Test Everything

1. Open your Cloudflare Pages URL
2. Login with any email
3. Create a character
4. Open another browser tab with the same URL
5. Login with a different email
6. Create another character
7. **You should see both players in the game world!** 🎉

---

## Troubleshooting

### Backend not responding?

- Check Render logs: Dashboard → Your service → Logs
- First request after 15 min sleep takes ~30s (normal)
- Make sure build completed successfully

### Frontend build failing?

- Check Cloudflare build logs: Pages → Your project → Deployments → Click latest → View build log
- Make sure Flutter is available (Cloudflare might need custom build image)
- Try building locally first to test

### CORS errors?

- Make sure `FRONTEND_URL` is set in Render environment variables
- Make sure it matches your Cloudflare Pages URL exactly
- Redeploy backend after adding the variable

### WebSocket not connecting?

- Make sure both URLs use `https://` (not `http://`)
- Check browser console (F12) for errors
- Verify backend is running (check Render logs)

---

## Next Steps

- ✅ Your app is live!
- Add custom domain (optional)
- Invite your friend as collaborator
- Set up monitoring/analytics

---

## Collaboration

### Add Friend to Render:

1. Render dashboard → Team (top right)
2. "Invite team member"
3. Enter their email
4. They get access to all services

### Add Friend to Cloudflare:

1. Cloudflare Pages → Your project → Settings
2. "Collaborators" tab
3. Add email
4. They can deploy and manage

### GitHub Collaboration:

1. GitHub repo → Settings → Collaborators
2. Add your friend
3. Both can push code
4. Auto-deploys on push (if configured)

---

## URLs You'll Have

- **Backend**: `https://roguesouls-backend.onrender.com`
- **Frontend**: `https://roguesouls.pages.dev`
- **Health Check**: `https://roguesouls-backend.onrender.com/health`

---

## Cost

**Total: $0/month** (completely free!)

- Render: 750 hours/month free (enough for 24/7)
- Cloudflare Pages: Unlimited free tier

Enjoy your free multiplayer game! 🚀

