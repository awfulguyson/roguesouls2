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

## Part 2: Deploy Frontend (Choose one option)

### Option A: Firebase Hosting (Recommended - Best for Flutter) ⭐

Firebase Hosting is the best free option for Flutter web apps. It's specifically designed for this use case.

#### Step 1: Sign Up for Firebase and Create Project

⚠️ **Important**: You must create the project via the web console first to accept Terms of Service.

1. Go to https://console.firebase.google.com
2. Click "Get Started" (free account)
3. Sign in with Google
4. Click "Create a project" (or "Add project")
5. **Accept the Terms of Service** when prompted (this is required!)
6. Enter project name: `roguesouls` (or any name)
7. Accept/disable Google Analytics as you prefer
8. Click "Create project"
9. Wait for project creation to complete
10. Click "Continue" to go to the project dashboard

#### Step 2: Install Firebase CLI

**Windows (PowerShell as Admin):**
```powershell
npm install -g firebase-tools
```

**Mac/Linux:**
```bash
npm install -g firebase-tools
```

#### Step 3: Login to Firebase

```bash
firebase login
```

#### Step 4: Initialize Firebase Hosting

1. In your project root directory, run:
   ```bash
   firebase init hosting
   ```

2. When prompted:
   - **Select an option**: Choose **"Use an existing project"** (the one you just created in Step 1)
   - Select your project from the list
   - **What do you want to use as your public directory?** → `client/build/web`
   - **Configure as a single-page app?** → `Yes`
   - **Set up automatic builds and deploys with GitHub?** → `No` (or Yes if you want auto-deploy)
   - **File client/build/web/index.html already exists. Overwrite?** → `No` (keep existing)

#### Step 5: Build Flutter App

**Windows:**
```powershell
$env:API_BASE_URL="https://roguesouls.onrender.com"
$env:WEBSOCKET_URL="https://roguesouls.onrender.com"
cd client
flutter pub get
flutter build web --release --dart-define=API_BASE_URL=$env:API_BASE_URL --dart-define=WEBSOCKET_URL=$env:WEBSOCKET_URL
cd ..
```

**Mac/Linux:**
```bash
export API_BASE_URL=https://roguesouls.onrender.com
export WEBSOCKET_URL=https://roguesouls.onrender.com
cd client
flutter pub get
flutter build web --release --dart-define=API_BASE_URL=$API_BASE_URL --dart-define=WEBSOCKET_URL=$WEBSOCKET_URL
cd ..
```

#### Step 6: Deploy to Firebase

```bash
firebase deploy --only hosting
```

You'll get a URL like: `https://roguesouls.web.app` or `https://roguesouls.firebaseapp.com`

✅ **Done!** Your app is live and will auto-deploy when you run `firebase deploy` after building.

---

### Option B: Netlify (Easy Drag-and-Drop) 

#### Step 1: Sign Up for Netlify

1. Go to https://app.netlify.com/signup
2. Sign up with GitHub (free account)

#### Step 2: Build Flutter App

Build your app locally (same as Firebase Step 5 above)

#### Step 3: Deploy to Netlify

**Drag and Drop Method:**
1. Go to https://app.netlify.com/drop
2. Drag the `client/build/web` folder onto the page
3. Your site is live instantly!

**Git Integration (for auto-deploy):**
1. In Netlify dashboard, click "Add new site" → "Import an existing project"
2. Connect your GitHub repo
3. Build settings:
   - **Base directory**: `client`
   - **Build command**: `flutter build web --release --dart-define=API_BASE_URL=$API_BASE_URL --dart-define=WEBSOCKET_URL=$WEBSOCKET_URL`
   - **Publish directory**: `client/build/web`
4. Add environment variables:
   - `API_BASE_URL` = `https://roguesouls.onrender.com`
   - `WEBSOCKET_URL` = `https://roguesouls.onrender.com`
5. Deploy!

⚠️ **Note**: Netlify doesn't have Flutter in their build environment, so you'll need to build locally first OR use GitHub Actions to build automatically.

---

### Option C: Cloudflare Pages (Manual Upload Required)

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

### Step 3: Build Flutter App Locally

⚠️ **Important**: Cloudflare Pages doesn't support Flutter builds directly. You need to build locally first.

1. **Install Flutter** (if not already installed):
   - Download from: https://docs.flutter.dev/get-started/install
   - Make sure `flutter` command works in your terminal

2. **Build the app** (run from project root):
   ```bash
   export API_BASE_URL=https://roguesouls.onrender.com
   export WEBSOCKET_URL=https://roguesouls.onrender.com
   cd client
   flutter pub get
   flutter build web --release --dart-define=API_BASE_URL=$API_BASE_URL --dart-define=WEBSOCKET_URL=$WEBSOCKET_URL
   ```
   
   Or use the build script:
   ```bash
   export API_BASE_URL=https://roguesouls.onrender.com
   export WEBSOCKET_URL=https://roguesouls.onrender.com
   chmod +x build-for-cloudflare.sh
   ./build-for-cloudflare.sh
   ```

3. **Verify build output**: Check that `client/build/web` directory exists with your built files

### Step 4: Deploy to Cloudflare Pages (Direct Upload)

1. **Create a zip file** of the `client/build/web` folder:
   - On Windows: Right-click `client/build/web` → Send to → Compressed (zipped) folder
   - On Mac/Linux: `cd client/build && zip -r roguesouls-web.zip web/`

2. **Upload to Cloudflare Pages**:
   - In Cloudflare dashboard, go to "Workers & Pages"
   - Click "Create application" → "Pages" → "Upload assets"
   - Upload your zip file
   - Click "Deploy site"

3. **Get your URL**: You'll get a URL like `https://roguesouls.pages.dev`
4. **Copy this URL** - you'll need it for the next step!

### Alternative: Connect to Git (for automatic deployments)

If you want automatic deployments, you can connect to Git but need to build locally and commit the built files:

1. Build locally (as in Step 3)
2. Commit the `client/build/web` folder to git
3. In Cloudflare Pages, connect to your GitHub repo
4. Set **Build output directory**: `client/build/web`
5. Set **Build command**: `echo "Using pre-built files"` (or leave empty)
6. Deploy

⚠️ **Note**: You'll need to rebuild and commit the `client/build/web` folder every time you make changes.

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

