# Deploy Flutter app to Firebase Hosting (Windows)
# Usage: .\deploy-firebase.ps1

param(
    [string]$BackendUrl = "https://roguesouls.onrender.com"
)

Write-Host "🚀 Deploying to Firebase Hosting..." -ForegroundColor Cyan

# Check if Firebase CLI is installed
try {
    firebase --version | Out-Null
} catch {
    Write-Host "❌ Firebase CLI not found. Install it with: npm install -g firebase-tools" -ForegroundColor Red
    exit 1
}

# Check if Flutter is installed
try {
    flutter --version | Out-Null
} catch {
    Write-Host "❌ Flutter not found. Install Flutter first." -ForegroundColor Red
    exit 1
}

Write-Host "📦 Building Flutter web app..." -ForegroundColor Cyan
Set-Location client
flutter pub get
flutter build web --release `
    --dart-define=API_BASE_URL="$BackendUrl" `
    --dart-define=WEBSOCKET_URL="$BackendUrl"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed" -ForegroundColor Red
    Set-Location ..
    exit 1
}

Set-Location ..

Write-Host "🔥 Deploying to Firebase..." -ForegroundColor Cyan
firebase deploy --only hosting

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Deployment successful!" -ForegroundColor Green
} else {
    Write-Host "❌ Deployment failed" -ForegroundColor Red
    exit 1
}

