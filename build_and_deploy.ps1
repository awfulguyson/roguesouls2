# PowerShell build script for deploying RogueSouls
# Usage: .\build_and_deploy.ps1 <backend-url>
# Example: .\build_and_deploy.ps1 https://roguesouls-backend.railway.app

param(
    [Parameter(Mandatory=$true)]
    [string]$BackendUrl
)

Write-Host "Building Flutter web app with backend URL: $BackendUrl" -ForegroundColor Cyan

Set-Location client

flutter build web --release `
  --dart-define=API_BASE_URL=$BackendUrl `
  --dart-define=WEBSOCKET_URL=$BackendUrl

Write-Host "Build complete! Output in client/build/web" -ForegroundColor Green
Write-Host "Deploy the client/build/web folder to Netlify, Vercel, or any static hosting" -ForegroundColor Yellow

Set-Location ..

