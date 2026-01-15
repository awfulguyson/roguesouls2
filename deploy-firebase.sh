#!/bin/bash

# Deploy Flutter app to Firebase Hosting
# Usage: ./deploy-firebase.sh [backend-url]
# Example: ./deploy-firebase.sh https://roguesouls.onrender.com

set -e

BACKEND_URL=${1:-"https://roguesouls.onrender.com"}

echo "🚀 Deploying to Firebase Hosting..."

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found. Install it with: npm install -g firebase-tools"
    exit 1
fi

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found. Install Flutter first."
    exit 1
fi

echo "📦 Building Flutter web app..."
cd client
flutter pub get
flutter build web --release \
    --dart-define=API_BASE_URL="${BACKEND_URL}" \
    --dart-define=WEBSOCKET_URL="${BACKEND_URL}"

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

cd ..

echo "🔥 Deploying to Firebase..."
firebase deploy --only hosting

echo "✅ Deployment successful!"

