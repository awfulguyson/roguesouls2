# Pre-Deployment Checklist

Before deploying, make sure:

## ✅ Code is Ready

- [ ] Code is pushed to GitHub
- [ ] All files are committed
- [ ] No local-only files (like `.env` with secrets)

## ✅ Backend (Render) Requirements

- [ ] `server/package.json` has `build` and `start` scripts ✅
- [ ] `server/tsconfig.json` exists ✅
- [ ] `server/src/index.ts` exists ✅
- [ ] TypeScript compiles: `cd server && npm run build` works

## ✅ Frontend (Cloudflare Pages) Requirements

- [ ] `client/pubspec.yaml` exists ✅
- [ ] `client/lib/main.dart` exists ✅
- [ ] Flutter builds: `cd client && flutter build web --release` works
- [ ] Environment variables are configured in code ✅

## ✅ Configuration Files

- [ ] `.gitignore` includes `node_modules/`, `dist/`, `.env` ✅
- [ ] No secrets in code (use environment variables)

---

## Quick Test Before Deploying

### Test Backend Build Locally:

```powershell
cd server
npm install
npm run build
npm start
```

Should start on port 3000. Test: `http://localhost:3000/health`

### Test Frontend Build Locally:

```powershell
cd client
flutter pub get
flutter build web --release
```

Should create `client/build/web` folder.

---

## Ready to Deploy?

If all checks pass, follow **RENDER_SETUP.md** for step-by-step instructions!

