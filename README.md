# RogueSouls - 2D MMORPG Roguelike

A web-based multiplayer roguelike game built with Flutter and Node.js.

## Project Structure

```
roguesouls/
├── client/          # Flutter web client
├── server/          # Node.js backend server
└── README.md
```

## Quick Start

### Prerequisites

- Flutter SDK (installed)
- Node.js 20+ 
- PostgreSQL (optional for MVP - using mock data)
- Redis (optional for MVP)

### 1. Start the Backend Server

```bash
cd server
npm install
npm run dev
```

The server will run on `http://localhost:3000`

### 2. Start the Flutter Client

```bash
cd client
flutter pub get
flutter run -d chrome
```

### 3. Test Multiplayer

1. Open the app in Chrome
2. Login with any email/password (mock authentication)
3. Create a character
4. Open another browser tab/window
5. Login with a different email
6. Create another character
7. Both players should see each other moving in the game world!

## Controls

- **WASD** or **Arrow Keys**: Move your character
- Players are represented as colored rectangles:
  - Red = You
  - Blue = Other players

## Current Features (MVP)

- ✅ Simple login system
- ✅ Character creation
- ✅ Basic game world
- ✅ Player movement (WASD)
- ✅ Multiplayer synchronization (see other players)
- ✅ WebSocket real-time communication

## Next Steps

- [ ] Add PostgreSQL database for persistent storage
- [ ] Add Redis for session management
- [ ] Implement proper authentication with JWT
- [ ] Add chat system
- [ ] Improve graphics (sprites instead of rectangles)
- [ ] Add collision detection
- [ ] Add enemies and combat

## Development

### Backend Development

```bash
cd server
npm run dev  # Starts with nodemon (auto-reload)
```

### Flutter Development

```bash
cd client
flutter run -d chrome  # Hot reload enabled
```

## Notes

- The backend uses mock data for MVP testing
- No database required for initial testing
- WebSocket connection handles real-time multiplayer
- CORS is currently open (`*`) - restrict in production

