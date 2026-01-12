#!/bin/bash

# Build script for deploying RogueSouls
# Usage: ./build_and_deploy.sh <backend-url>
# Example: ./build_and_deploy.sh https://roguesouls-backend.railway.app

if [ -z "$1" ]; then
    echo "Usage: ./build_and_deploy.sh <backend-url>"
    echo "Example: ./build_and_deploy.sh https://roguesouls-backend.railway.app"
    exit 1
fi

BACKEND_URL=$1

echo "Building Flutter web app with backend URL: $BACKEND_URL"

cd client
flutter build web --release \
  --dart-define=API_BASE_URL=$BACKEND_URL \
  --dart-define=WEBSOCKET_URL=$BACKEND_URL

echo "Build complete! Output in client/build/web"
echo "Deploy the client/build/web folder to Netlify, Vercel, or any static hosting"

