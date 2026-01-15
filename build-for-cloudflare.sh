#!/bin/bash

# Build script for Cloudflare Pages deployment
# This builds the Flutter web app locally, then you can upload the built files to Cloudflare Pages

set -e

echo "🔨 Building Flutter web app for Cloudflare Pages..."

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Error: Flutter is not installed or not in PATH"
    echo "Please install Flutter: https://docs.flutter.dev/get-started/install"
    exit 1
fi

# Check if API_BASE_URL and WEBSOCKET_URL are set
if [ -z "$API_BASE_URL" ] || [ -z "$WEBSOCKET_URL" ]; then
    echo "⚠️  Warning: API_BASE_URL or WEBSOCKET_URL not set"
    echo "Using default values. Set these environment variables:"
    echo "  export API_BASE_URL=https://roguesouls.onrender.com"
    echo "  export WEBSOCKET_URL=https://roguesouls.onrender.com"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Navigate to client directory
cd client

echo "📦 Getting Flutter dependencies..."
flutter pub get

echo "🏗️  Building Flutter web app..."
if [ -n "$API_BASE_URL" ] && [ -n "$WEBSOCKET_URL" ]; then
    flutter build web --release \
        --dart-define=API_BASE_URL="${API_BASE_URL}" \
        --dart-define=WEBSOCKET_URL="${WEBSOCKET_URL}"
else
    flutter build web --release \
        --dart-define=API_BASE_URL=https://roguesouls.onrender.com \
        --dart-define=WEBSOCKET_URL=https://roguesouls.onrender.com
fi

echo "✅ Build complete!"
echo ""
echo "📁 Built files are in: client/build/web"
echo ""
echo "🚀 Next steps:"
echo "1. Go to Cloudflare Pages dashboard"
echo "2. Select your project → Settings → Builds & deployments"
echo "3. Click 'Retry deployment' or 'Trigger new deployment'"
echo "4. For Build command, use: (leave empty or use a no-op command)"
echo "5. For Build output directory, use: client/build/web"
echo ""
echo "OR use Direct Upload:"
echo "1. Zip the client/build/web folder"
echo "2. Go to Cloudflare Pages → Create a project → Upload assets"
echo "3. Upload the zip file"

