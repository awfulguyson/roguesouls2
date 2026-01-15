# Build script for Cloudflare Pages deployment (Windows)
# This builds the Flutter web app locally, then you can upload the built files to Cloudflare Pages

Write-Host "🔨 Building Flutter web app for Cloudflare Pages..." -ForegroundColor Cyan

# Check if Flutter is installed
try {
    $flutterVersion = flutter --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter not found"
    }
} catch {
    Write-Host "❌ Error: Flutter is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Flutter: https://docs.flutter.dev/get-started/install" -ForegroundColor Yellow
    exit 1
}

# Check if API_BASE_URL and WEBSOCKET_URL are set
$apiUrl = $env:API_BASE_URL
$wsUrl = $env:WEBSOCKET_URL

if (-not $apiUrl -or -not $wsUrl) {
    Write-Host "⚠️  Warning: API_BASE_URL or WEBSOCKET_URL not set" -ForegroundColor Yellow
    Write-Host "Using default values. Set these environment variables:" -ForegroundColor Yellow
    Write-Host "  `$env:API_BASE_URL='https://roguesouls.onrender.com'" -ForegroundColor Yellow
    Write-Host "  `$env:WEBSOCKET_URL='https://roguesouls.onrender.com'" -ForegroundColor Yellow
    
    $continue = Read-Host "Continue anyway? (y/n)"
    if ($continue -ne 'y' -and $continue -ne 'Y') {
        exit 1
    }
    $apiUrl = "https://roguesouls.onrender.com"
    $wsUrl = "https://roguesouls.onrender.com"
}

# Navigate to client directory
Set-Location client

Write-Host "📦 Getting Flutter dependencies..." -ForegroundColor Cyan
flutter pub get

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to get dependencies" -ForegroundColor Red
    exit 1
}

Write-Host "🏗️  Building Flutter web app..." -ForegroundColor Cyan
flutter build web --release `
    --dart-define=API_BASE_URL="$apiUrl" `
    --dart-define=WEBSOCKET_URL="$wsUrl"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Build complete!" -ForegroundColor Green
Write-Host ""
Write-Host "📁 Built files are in: client\build\web" -ForegroundColor Cyan
Write-Host ""
Write-Host "🚀 Next steps:" -ForegroundColor Cyan
Write-Host "1. Go to Cloudflare Pages dashboard"
Write-Host "2. Create a project → Upload assets"
Write-Host "3. Zip the client\build\web folder and upload it"
Write-Host ""
Write-Host "To create zip file:" -ForegroundColor Yellow
Write-Host "  Right-click 'client\build\web' → Send to → Compressed (zipped) folder" -ForegroundColor Yellow

# Return to original directory
Set-Location ..

