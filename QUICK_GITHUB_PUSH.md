# Quick Guide: Push to GitHub with GitHub Desktop

## Quick Steps

1. **Create repo on GitHub.com**
   - Go to https://github.com/new
   - Name: `roguesouls`
   - **Don't** check any boxes (no README, no .gitignore)
   - Click **Create repository**

2. **Open in GitHub Desktop**
   - Open GitHub Desktop
   - **File** → **Add Local Repository**
   - Choose: `C:\My Apps\RogueSouls`
   - Click **Add Repository**

3. **Connect to GitHub**
   - Click **Publish repository** button (if you see it)
   - OR go to **Repository** → **Repository Settings** → **Remote**
   - Set URL: `https://github.com/YOUR_USERNAME/roguesouls.git`

4. **Commit & Push**
   - Type commit message: `Initial commit: Project setup`
   - Click **Commit to main**
   - Click **Push origin**

## ⚠️ Important: Don't Commit These!

Make sure these are NOT in your commit:
- ❌ `server/.env` (contains secrets!)
- ❌ `server/node_modules/`
- ❌ `server/dist/`
- ❌ Unity build files

They should be automatically ignored by `.gitignore`, but double-check in GitHub Desktop before committing!

## Done! 🎉

Your code will be at: `https://github.com/YOUR_USERNAME/roguesouls`

