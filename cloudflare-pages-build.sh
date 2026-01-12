#!/bin/bash

# Build script for Cloudflare Pages
# This script is used by Cloudflare Pages to build the Flutter web app

echo "Installing Flutter dependencies..."
cd client
flutter pub get

echo "Building Flutter web app..."
flutter build web --release \
  --dart-define=API_BASE_URL=$API_BASE_URL \
  --dart-define=WEBSOCKET_URL=$WEBSOCKET_URL

echo "Build complete! Output in client/build/web"

