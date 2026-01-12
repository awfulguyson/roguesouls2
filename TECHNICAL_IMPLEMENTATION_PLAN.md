# Technical Implementation Plan: Roguelike MMO (RogueSouls)

## Document Version
- **Version**: 2.0
- **Date**: 2024
- **Target Team Size**: 1-5 developers
- **Platform**: Web (initial), Steam distribution (future)
- **Game Type**: Roguelike MMO with shared world
- **Tech Stack**: Flutter (Dart) for client, Node.js for backend

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [High-Level Architecture](#high-level-architecture)
3. [Technology Stack](#technology-stack)
4. [Client Architecture](#client-architecture)
5. [Server Architecture](#server-architecture)
6. [Networking Model](#networking-model)
7. [Database Schema](#database-schema)
8. [Account & Authentication Flow](#account--authentication-flow)
9. [Steam Integration](#steam-integration)
10. [Gameplay Systems](#gameplay-systems)
11. [UI System Architecture](#ui-system-architecture)
12. [Security Considerations](#security-considerations)
13. [Scalability Plan](#scalability-plan)
14. [Development Roadmap](#development-roadmap)
15. [Team Role Breakdown](#team-role-breakdown)
16. [Risk Assessment](#risk-assessment)
17. [Complexity Estimates](#complexity-estimates)
18. [Assumptions & Tradeoffs](#assumptions--tradeoffs)
19. [MVP vs Long-Term](#mvp-vs-long-term)
20. [Next Steps](#next-steps)
21. [Clarifying Questions](#clarifying-questions)

---

## Executive Summary

This document outlines a technical implementation plan for building **RogueSouls**, a roguelike MMO with a shared world, distributed via Steam. The game combines roguelike progression (death resets level but preserves accumulated stats) with persistent MMO elements (shared world, multiplayer interactions). The architecture prioritizes:

- **Fast iteration**: Modular systems, hot-reload capabilities, comprehensive testing
- **Low operational cost**: Cloud-native, pay-as-you-scale infrastructure
- **Stability**: Server-authoritative design, robust error handling
- **Maintainability**: Clean architecture, comprehensive documentation, version control

**Core Technology Decisions:**
- **Game Engine**: Flutter (Dart) - Web-based initially, packaged for Steam later
- **Backend**: Node.js + TypeScript (Express/Fastify)
- **Database**: PostgreSQL (primary) + Redis (caching/sessions)
- **Networking**: WebSocket (Socket.io or ws) for real-time multiplayer
- **Hosting**: AWS/GCP with containerized deployment (Docker + Kubernetes)
- **Steam Integration**: Flutter Steam integration (flutter_steam or custom implementation)

**Key Architectural Principles:**
1. Server-authoritative game logic
2. Horizontal scaling capability
3. Microservices-ready (monolith-first, modular for future split)
4. Event-driven architecture for game events
5. Client-side prediction with server reconciliation

**Core Game Mechanics:**
- **Roguelike Progression**: Death resets level to 1, but accumulated stats persist
- **Skill Discovery**: Skills found on ground, right-click reveals 3 choices
- **Playstyle Focus**: Choose tanking, DPS, or healing (affects skill choices, can change anytime)
- **Starting Skills**: New characters get 3 skill choices based on selected playstyle
- **Shared World**: Multiple players in same persistent world

**Roguelike Systems Overview:**
1. **Death & Respawn**: When player dies, level resets to 1, experience resets to 0, but:
   - Accumulated stats (strength, dexterity, intelligence, vitality) persist
   - Learned skills persist
   - Inventory persists
   - Player respawns at starting zone
2. **Skill Discovery**: 
   - Skills are found as items on the ground (dropped by enemies, ~10% chance)
   - Right-clicking a skill discovery item opens a choice UI with 3 skill options
   - Skills are filtered by current playstyle focus (tank/dps/healing)
   - Player selects 1 skill from the 3 choices
   - Once learned, skills are permanent (persist through death)
3. **Playstyle System**:
   - Selected during character creation (Tank, DPS, or Healing)
   - Can be changed at any time (affects future skill discoveries only)
   - Determines which skills appear in skill choice options
4. **Starting Skills**: 
   - When character first loads, receives 3 skill choices based on playstyle
   - Player selects 1 skill to start with

---

## High-Level Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        CLIENT LAYER                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Flutter Web  │  │ Steam Client │  │  Web Browser │      │
│  │   (Game)     │  │   (Auth)     │  │  (Account)   │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│         │                 │                  │              │
└─────────┼─────────────────┼──────────────────┼──────────────┘
          │                 │                  │
          │ HTTPS/WSS       │ Steam API        │ HTTPS
          │                 │                  │
┌─────────┼─────────────────┼──────────────────┼──────────────┐
│         │                 │                  │              │
│  ┌──────▼─────────────────▼──────────────────▼──────┐       │
│  │           API GATEWAY / LOAD BALANCER            │       │
│  │         (NGINX / AWS ALB / Cloudflare)           │       │
│  └──────┬───────────────────────────────────────────┘       │
│         │                                                    │
│  ┌──────▼───────────────────────────────────────────┐       │
│  │         AUTHENTICATION SERVICE                    │       │
│  │  (Steam Auth, JWT Token Management, Sessions)     │       │
│  └──────┬───────────────────────────────────────────┘       │
│         │                                                    │
│  ┌──────▼───────────────────────────────────────────┐       │
│  │           GAME SERVER CLUSTER                     │       │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐  │       │
│  │  │ Zone 1     │  │ Zone 2     │  │ Zone N     │  │       │
│  │  │ Server     │  │ Server     │  │ Server     │  │       │
│  │  └────────────┘  └────────────┘  └────────────┘  │       │
│  └──────┬───────────────────────────────────────────┘       │
│         │                                                    │
│  ┌──────▼───────────────────────────────────────────┐       │
│  │         PERSISTENCE LAYER                          │       │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐  │       │
│  │  │ PostgreSQL │  │   Redis    │  │  S3/Blob   │  │       │
│  │  │  (Primary) │  │  (Cache)   │  │  (Assets)  │  │       │
│  │  └────────────┘  └────────────┘  └────────────┘  │       │
│  └───────────────────────────────────────────────────┘       │
│                                                               │
│                    BACKEND LAYER                              │
└───────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

**Client Layer:**
- Flutter web client (rendering, input, local prediction)
- Steam client (authentication, ownership verification) - for Steam builds
- Web browser (account creation, character management, game client)

**API Gateway:**
- Request routing
- Rate limiting
- SSL termination
- DDoS protection

**Authentication Service:**
- Steam ticket validation
- JWT token generation/validation
- Session management
- Account linking

**Game Server Cluster:**
- Zone-based game logic
- Player movement synchronization
- Combat calculations
- Loot distribution
- Chat routing

**Persistence Layer:**
- PostgreSQL: Accounts, characters, inventory, world state
- Redis: Session cache, player presence, real-time data
- S3/Blob Storage: Game assets, patches, logs

---

## Technology Stack

### Game Engine: Flutter (Dart)

**Justification:**
- **Web-first development**: Build for web initially, test multiplayer easily
- **Single codebase**: Same codebase for web and desktop (Steam packaging)
- **Dart language**: Type-safe, performant, modern language
- **Rich ecosystem**: Extensive package ecosystem (pub.dev)
- **2D rendering**: Excellent support for 2D sprites, animations, and canvas rendering
- **Hot reload**: Fast iteration during development
- **Steam packaging**: Can package Flutter web app for Steam using Electron or native desktop builds
- **Cross-platform**: Web, Windows, Mac, Linux from single codebase
- **Real-time networking**: Excellent WebSocket support for multiplayer

**Alternatives Considered:**
- **Unity**: More mature game engine, but requires separate builds for web/desktop
- **Godot**: Good for games, but web export less mature
- **Custom Engine**: Too time-consuming for indie team

### Backend: Node.js + TypeScript

**Justification:**
- **Fast development**: JavaScript/TypeScript ecosystem, rapid prototyping
- **Real-time**: Excellent WebSocket support (Socket.io, ws)
- **Scalability**: Event-driven, non-blocking I/O
- **Cost-effective**: Can run on low-cost VPS initially
- **Developer availability**: Large talent pool
- **Microservices-ready**: Easy to split into services later

**Stack Details:**
- **Runtime**: Node.js 20 LTS
- **Framework**: Fastify (faster than Express, similar API)
- **WebSocket**: Socket.io (rooms, namespaces) or ws (lightweight)
- **ORM**: Prisma or TypeORM (type-safe database access)
- **Validation**: Zod (runtime type validation)

**Alternatives Considered:**
- **C#/.NET**: Good for Unity developers, but heavier infrastructure
- **Go**: Excellent performance, but smaller ecosystem
- **Python**: Slower, less suitable for real-time games

### Database: PostgreSQL + Redis

**PostgreSQL (Primary Database):**
- **ACID compliance**: Critical for character data integrity
- **JSON support**: Flexible schema for game data
- **Scalability**: Can handle millions of rows efficiently
- **Open-source**: No licensing costs
- **Extensions**: PostGIS for spatial queries if needed

**Redis (Caching & Sessions):**
- **In-memory performance**: Sub-millisecond latency
- **Pub/Sub**: Real-time event broadcasting
- **Session storage**: Fast session lookups
- **Player presence**: Track online players per zone
- **Rate limiting**: Prevent abuse

**Schema Strategy:**
- **Accounts/Characters**: PostgreSQL (persistent, relational)
- **Sessions**: Redis (ephemeral, fast)
- **Player state**: Hybrid (PostgreSQL for persistence, Redis for active sessions)

### Networking: WebSocket (Socket.io or ws)

**Justification:**
- **Web-native**: Perfect for web-based game client
- **Real-time**: Low-latency bidirectional communication
- **Cross-platform**: Works on web, desktop, and mobile
- **Mature libraries**: Socket.io (rooms, namespaces) or ws (lightweight)
- **Authoritative server**: Server controls all game state
- **Client prediction**: Can implement client-side prediction in Flutter
- **Scalability**: Supports multiple server instances, room-based architecture

**Protocol:**
- **Transport**: WebSocket (WSS for secure)
- **Message format**: JSON (easy debugging) or Binary (MessagePack for efficiency)
- **Compression**: Built-in WebSocket compression or custom compression

**Alternatives:**
- **Custom TCP/UDP**: More control but requires native plugins
- **gRPC-Web**: More complex, overkill for game networking
- **Server-Sent Events**: One-way only, not suitable for games

### Hosting Infrastructure

**Cloud Provider: AWS or GCP**

**Initial Setup (MVP):**
- **Compute**: EC2/Compute Engine (t3.medium for game server, t3.small for API)
- **Database**: RDS PostgreSQL (db.t3.micro) or Cloud SQL
- **Cache**: ElastiCache Redis (cache.t3.micro) or Cloud Memorystore
- **Storage**: S3 or Cloud Storage (game assets, logs)
- **CDN**: CloudFront or Cloud CDN (asset delivery)

**Scaling Path:**
- **Containerization**: Docker containers
- **Orchestration**: Kubernetes (EKS/GKE) or ECS/Fargate
- **Auto-scaling**: Horizontal pod autoscaling based on player count
- **Load balancing**: Application Load Balancer or Cloud Load Balancing

**Cost Optimization:**
- **Reserved instances**: 1-year commitment for predictable workloads
- **Spot instances**: For non-critical services
- **Serverless**: Lambda/Cloud Functions for account management (pay-per-use)

### CI/CD Pipeline

**Version Control**: Git (GitHub/GitLab)

**CI/CD Tools:**
- **GitHub Actions** or **GitLab CI** (free for open-source, low cost for private)
- **Docker**: Container builds
- **Automated testing**: Unit tests, integration tests
- **Deployment**: Blue-green or rolling updates

**Pipeline Stages:**
1. **Build**: Build Flutter web project, build Docker images
2. **Test**: Run automated tests
3. **Deploy Staging**: Deploy to staging environment
4. **Deploy Production**: Manual approval → deploy to production

### Asset Pipeline

**Tools:**
- **Sprite creation**: Aseprite, Photoshop, or GIMP
- **Animation**: Flutter animation framework, Aseprite timeline
- **Tilemaps**: Custom tilemap system or flutter_tile_map package
- **Version control**: Git LFS for large assets
- **Compression**: Web-optimized image formats (WebP), sprite atlasing

---

## Client Architecture

### Flutter Project Structure

```
lib/
├── main.dart                        # Entry point
├── core/
│   ├── game_manager.dart            # Main game loop
│   ├── network_manager.dart         # WebSocket connection handling
│   └── scene_manager.dart           # Scene/routes transitions
├── models/
│   ├── player.dart                  # Player data model
│   ├── character.dart               # Character data model
│   ├── item.dart                    # Item data model
│   └── skill.dart                   # Skill data model
├── services/
│   ├── auth_service.dart            # Authentication (login)
│   ├── game_service.dart            # Game state management
│   └── network_service.dart         # WebSocket service
├── screens/
│   ├── login_screen.dart            # Login page
│   ├── character_select_screen.dart # Character selection
│   ├── character_creation_screen.dart # Character creation
│   └── game_world_screen.dart       # Main game screen
├── widgets/
│   ├── player/
│   │   ├── player_widget.dart      # Player rendering
│   │   └── player_controller.dart   # Movement, input
│   ├── world/
│   │   ├── game_world.dart          # World rendering
│   │   ├── camera_controller.dart   # Isometric camera, zoom
│   │   └── tilemap_widget.dart      # Tilemap rendering
│   ├── ui/
│   │   ├── health_mana_bar.dart     # HP/MP display
│   │   ├── action_bar.dart          # Hotkey bars
│   │   ├── inventory_ui.dart        # Inventory display
│   │   ├── chat_ui.dart             # Chat window
│   │   └── skill_choice_ui.dart     # Skill choice modal
│   └── enemies/
│       └── enemy_widget.dart        # Enemy rendering
├── networking/
│   ├── websocket_client.dart        # WebSocket client wrapper
│   ├── message_handlers.dart        # Message deserialization
│   └── steam_auth.dart              # Steam authentication (for Steam builds)
├── data/
│   ├── game_data.dart               # Game data (items, skills)
│   └── serialization.dart           # JSON/MessagePack serialization
└── utils/
    ├── constants.dart               # Game constants
    └── helpers.dart                 # Utility functions

assets/
├── sprites/
│   ├── player/
│   ├── enemies/
│   └── items/
├── audio/
└── data/
    └── game_data.json               # Static game data
```

### Client-Side Systems

#### 1. Input System
- **Flutter GestureDetector/Listener**: Handle keyboard (WASD) and mouse input
- **Action mapping**: Configurable keybindings stored in state
- **Input buffering**: Queue actions during network lag
- **Web support**: Keyboard and mouse events work natively in web

#### 2. Rendering System
- **CustomPainter/Canvas**: 2D sprite rendering using Flutter's canvas API
- **Sprite sheets**: Load and render sprite animations
- **Z-ordering**: Proper layering for isometric view (sort by Y position)
- **Camera**: Transform matrix for camera position and zoom (mouse wheel)
- **Tilemap**: Custom tilemap rendering or use flutter_tile_map package

#### 3. Network Client
- **WebSocket connection**: Connect to game server via WebSocket (socket_io_client or web_socket_channel)
- **Message serialization**: JSON (easy) or Binary (MessagePack via msgpack_dart)
- **Client prediction**: Predict movement/combat locally before server confirmation
- **Server reconciliation**: Correct prediction errors when server state arrives
- **Interpolation**: Smooth other players' movement between updates

#### 4. Local State Management
- **State management**: Provider, Riverpod, or Bloc for state management
- **Player state**: Current position, HP, MP, inventory (cached locally)
- **World state**: Nearby players, enemies (server-authoritative, synced via WebSocket)
- **UI state**: Open windows, selected targets (local state)

### Client-Server Communication Flow

```
Client Input → Local Prediction → Send to Server
                                    ↓
Server Validation → Server State Update → Broadcast to Clients
                                    ↓
Client Receives Update → Reconcile with Prediction → Render
```

---

## Server Architecture

### Server Project Structure

```
server/
├── src/
│   ├── index.ts                    # Entry point
│   ├── config/
│   │   ├── database.ts             # DB connection
│   │   └── redis.ts                # Redis connection
│   ├── services/
│   │   ├── auth/
│   │   │   ├── steamAuth.ts        # Steam ticket validation
│   │   │   ├── jwtService.ts       # JWT generation/validation
│   │   │   └── sessionService.ts   # Session management
│   │   ├── game/
│   │   │   ├── gameServer.ts       # Main game server loop
│   │   │   ├── zoneManager.ts     # Zone instance management
│   │   │   ├── playerManager.ts    # Player state management
│   │   │   ├── combatService.ts    # Server-authoritative combat
│   │   │   ├── lootService.ts      # Loot generation/distribution
│   │   │   └── chatService.ts      # Chat routing
│   │   └── persistence/
│   │       ├── characterService.ts # Character CRUD
│   │       ├── inventoryService.ts # Inventory management
│   │       └── worldService.ts     # World state persistence
│   ├── models/
│   │   ├── Player.ts               # Player data model
│   │   ├── Character.ts            # Character data model
│   │   ├── Item.ts                 # Item data model
│   │   └── Combat.ts               # Combat data model
│   ├── networking/
│   │   ├── server.ts               # WebSocket server
│   │   ├── messageHandler.ts       # Message routing
│   │   └── roomManager.ts          # Zone-based rooms
│   ├── database/
│   │   ├── migrations/             # DB migrations
│   │   └── seeds/                  # Initial data
│   └── utils/
│       ├── logger.ts               # Logging utility
│       └── validation.ts           # Input validation
├── tests/
│   ├── unit/
│   └── integration/
└── docker/
    ├── Dockerfile
    └── docker-compose.yml
```

### Server-Side Systems

#### 1. Game Server Core
- **Event loop**: Process game ticks (30-60 TPS)
- **Player updates**: Broadcast position, state changes
- **Combat resolution**: Authoritative damage calculation
- **Loot spawning**: Generate loot on enemy death
- **Zone management**: Load/unload zones, player distribution

#### 2. Zone System
- **Zone instances**: Separate game worlds (e.g., "Forest", "Dungeon")
- **Player capacity**: Max players per zone (e.g., 100-500)
- **Dynamic scaling**: Spin up new zone instances when full
- **Cross-zone chat**: Global chat routed through central service

#### 3. Combat Service
- **Hit validation**: Verify attack range, line of sight
- **Damage calculation**: Server-authoritative formulas
- **Cooldown tracking**: Prevent skill spam
- **Status effects**: Buffs, debuffs, DoT
- **Combat log**: Record all combat events for DPS meters

#### 4. Persistence Service
- **Character saves**: Periodic saves (every 30s, on logout, on death)
- **Inventory sync**: Save inventory changes immediately
- **World state**: Save enemy spawns, loot drops (optional)

### Server Deployment Architecture

**Single Server (MVP):**
```
┌─────────────────────────────────┐
│     Game Server Process         │
│  ┌───────────────────────────┐  │
│  │  Zone Manager             │  │
│  │  ┌─────┐  ┌─────┐  ┌─────┐│  │
│  │  │Zone1│  │Zone2│  │Zone3││  │
│  │  └─────┘  └─────┘  └─────┘│  │
│  └───────────────────────────┘  │
│  ┌───────────────────────────┐  │
│  │  Auth Service              │  │
│  └───────────────────────────┘  │
│  ┌───────────────────────────┐  │
│  │  Persistence Service       │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

**Scaled Architecture (Future):**
```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ Game Server  │  │ Game Server  │  │ Game Server  │
│  (Zone 1-3)  │  │  (Zone 4-6)  │  │  (Zone 7-9)  │
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       │                  │                  │
       └──────────────────┼──────────────────┘
                          │
              ┌───────────▼───────────┐
              │   Auth Service        │
              │   (Separate Service)  │
              └───────────┬───────────┘
                          │
              ┌───────────▼───────────┐
              │   Database            │
              │   (Shared)            │
              └───────────────────────┘
```

---

## Networking Model

### Communication Protocol

**Transport Layer:**
- **WebSocket (WSS)**: Primary communication channel
- **TCP fallback**: For environments blocking WebSocket
- **Message format**: Binary (MessagePack) for efficiency

**Message Types:**
```typescript
// Client → Server
- PlayerMove { x, y, timestamp }
- PlayerAttack { targetId, skillId, timestamp }
- PlayerUseItem { itemId, slot }
- ChatMessage { channel, message }
- RequestInventory { }
- RequestCharacterList { }

// Server → Client
- PlayerUpdate { playerId, x, y, hp, mp, state }
- CombatEvent { sourceId, targetId, damage, type }
- LootSpawn { itemId, x, y, rarity }
- ChatBroadcast { playerId, channel, message }
- InventoryUpdate { items[] }
- ZoneChange { zoneId, players[] }
```

### Network Optimization

**1. Delta Compression**
- Send only changed data (position deltas, not absolute positions)
- Snapshot interpolation for smooth movement

**2. Interest Management**
- Only send updates for players/enemies within view distance
- Cull updates for entities behind walls

**3. Prioritization**
- High priority: Player position, combat events
- Medium priority: Other players' positions
- Low priority: Environmental effects, distant entities

**4. Bandwidth Limits**
- Client: ~50-100 KB/s per player
- Server: ~500 KB/s per zone (scales with player count)

### Latency Handling

**Client Prediction:**
- Client predicts movement/combat immediately
- Server corrects if prediction is wrong
- Smooth interpolation for corrections

**Lag Compensation:**
- Server rewinds time for hit detection
- Accounts for client latency in combat

**Interpolation:**
- Smooth other players' movement between updates
- Reduces jitter from network variance

---

## Database Schema

### PostgreSQL Tables

#### Accounts Table
```sql
CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL, -- bcrypt
    steam_id BIGINT UNIQUE,
    created_at TIMESTAMP DEFAULT NOW(),
    last_login TIMESTAMP,
    is_banned BOOLEAN DEFAULT FALSE,
    ban_reason TEXT
);

CREATE INDEX idx_accounts_steam_id ON accounts(steam_id);
CREATE INDEX idx_accounts_email ON accounts(email);
```

#### Characters Table
```sql
CREATE TABLE characters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name VARCHAR(50) NOT NULL,
    playstyle_focus VARCHAR(20) NOT NULL DEFAULT 'dps', -- 'tank', 'dps', 'healing'
    current_level INTEGER DEFAULT 1, -- Resets to 1 on death
    experience BIGINT DEFAULT 0, -- Resets to 0 on death
    death_count INTEGER DEFAULT 0, -- Total number of deaths
    zone_id VARCHAR(50) DEFAULT 'starting_zone',
    position_x FLOAT,
    position_y FLOAT,
    health INTEGER,
    max_health INTEGER,
    mana INTEGER,
    max_mana INTEGER,
    -- Accumulated stats (persist through death)
    accumulated_strength INTEGER DEFAULT 0,
    accumulated_dexterity INTEGER DEFAULT 0,
    accumulated_intelligence INTEGER DEFAULT 0,
    accumulated_vitality INTEGER DEFAULT 0,
    -- Base stats (reset to defaults on death, but accumulated stats are added)
    base_strength INTEGER DEFAULT 10,
    base_dexterity INTEGER DEFAULT 10,
    base_intelligence INTEGER DEFAULT 10,
    base_vitality INTEGER DEFAULT 10,
    -- Computed total stats = base + accumulated
    -- These are calculated server-side, not stored
    has_received_starting_skills BOOLEAN DEFAULT FALSE, -- Track if player got initial 3 skills
    created_at TIMESTAMP DEFAULT NOW(),
    last_played TIMESTAMP,
    last_death TIMESTAMP, -- Track last death time
    is_deleted BOOLEAN DEFAULT FALSE,
    UNIQUE(account_id, name)
);

CREATE INDEX idx_characters_account_id ON characters(account_id);
CREATE INDEX idx_characters_name ON characters(name);
CREATE INDEX idx_characters_playstyle ON characters(playstyle_focus);
```

#### Inventory Table
```sql
CREATE TABLE inventory_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    item_template_id VARCHAR(50) NOT NULL, -- References game data
    slot INTEGER, -- Inventory slot (0-99, NULL for equipment)
    equipment_slot VARCHAR(20), -- 'weapon', 'armor_head', etc., NULL for inventory
    quantity INTEGER DEFAULT 1,
    durability INTEGER, -- NULL for non-degradable items
    max_durability INTEGER,
    properties JSONB, -- Custom properties (enchantments, etc.)
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_inventory_character_id ON inventory_items(character_id);
CREATE INDEX idx_inventory_slot ON inventory_items(character_id, slot);
```

#### Items Table (Item Templates)
```sql
CREATE TABLE item_templates (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    type VARCHAR(20) NOT NULL, -- 'weapon', 'armor', 'consumable', etc.
    rarity VARCHAR(20) NOT NULL, -- 'trash', 'common', 'uncommon', 'rare', 'epic', 'legendary', 'artifact'
    base_value INTEGER, -- Gold value
    min_level INTEGER DEFAULT 1,
    properties JSONB, -- Base stats, requirements
    created_at TIMESTAMP DEFAULT NOW()
);
```

#### Character Skills Table
```sql
CREATE TABLE character_skills (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    skill_template_id VARCHAR(50) NOT NULL, -- References skill_templates
    learned_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(character_id, skill_template_id)
);

CREATE INDEX idx_character_skills_character_id ON character_skills(character_id);
```

#### Skill Templates Table
```sql
CREATE TABLE skill_templates (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    playstyle_tags VARCHAR(50)[], -- Array: ['tank', 'dps', 'healing'] - can have multiple
    type VARCHAR(20) NOT NULL, -- 'melee', 'ranged', 'spell', 'buff', 'debuff'
    cast_time FLOAT DEFAULT 0, -- Seconds, 0 for instant
    cooldown FLOAT NOT NULL, -- Seconds
    mana_cost INTEGER DEFAULT 0,
    range FLOAT DEFAULT 0, -- 0 for self-target
    damage_multiplier FLOAT DEFAULT 1.0,
    heal_amount INTEGER DEFAULT 0,
    effects JSONB, -- Buffs, debuffs, DoT, etc.
    icon_path VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_skill_templates_playstyle ON skill_templates USING GIN(playstyle_tags);
```

#### Skill Discovery Items Table (Ground Spawns)
```sql
CREATE TABLE skill_discovery_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    zone_id VARCHAR(50) NOT NULL,
    position_x FLOAT NOT NULL,
    position_y FLOAT NOT NULL,
    spawned_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP, -- NULL for permanent, or set expiration time
    discovered_by_character_id UUID REFERENCES characters(id), -- NULL if not yet discovered
    is_active BOOLEAN DEFAULT TRUE, -- False when player picks it up
    UNIQUE(zone_id, position_x, position_y, is_active) -- Prevent duplicate spawns
);

CREATE INDEX idx_skill_discovery_zone ON skill_discovery_items(zone_id, is_active);
CREATE INDEX idx_skill_discovery_position ON skill_discovery_items(zone_id, position_x, position_y);
```

#### Combat Log Table
```sql
CREATE TABLE combat_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    character_id UUID REFERENCES characters(id),
    event_type VARCHAR(20) NOT NULL, -- 'damage_dealt', 'damage_taken', 'heal', etc.
    source_id UUID, -- Character or enemy ID
    target_id UUID,
    damage INTEGER,
    skill_id VARCHAR(50),
    timestamp TIMESTAMP DEFAULT NOW(),
    zone_id VARCHAR(50)
);

CREATE INDEX idx_combat_logs_character_id ON combat_logs(character_id, timestamp);
CREATE INDEX idx_combat_logs_timestamp ON combat_logs(timestamp);
-- Partition by date for performance (optional)
```

#### Sessions Table (Redis - Ephemeral)
```typescript
// Redis key structure
sessions:{sessionId} = {
    accountId: UUID,
    characterId: UUID,
    zoneId: string,
    serverId: string,
    lastActivity: timestamp,
    expiresAt: timestamp
}

// TTL: 24 hours
```

#### Player Presence (Redis)
```typescript
// Track online players per zone
presence:zone:{zoneId} = Set<playerId>
presence:account:{accountId} = {
    characterId: UUID,
    zoneId: string,
    serverId: string
}
```

### Database Migrations

**Tool**: Prisma or TypeORM migrations
- Version control for schema changes
- Rollback capability
- Team synchronization

---

## Account & Authentication Flow

### Website Account Creation

**Flow:**
1. User visits https://www.talentbuilds.com
2. User creates account (email + password)
3. Account stored in PostgreSQL
4. Email verification (optional for MVP)
5. User can log in via website to view characters, stats

**Technology:**
- **Frontend**: React/Next.js or simple HTML forms
- **Backend**: Same Node.js API
- **Password hashing**: bcrypt (cost factor 10-12)

### Game Login Flow

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│  Steam   │────▶│ Flutter  │────▶│   Auth   │────▶│   Game   │
│  Client  │     │  Client  │     │ Service  │     │  Server  │
└──────────┘     └──────────┘     └──────────┘     └──────────┘
     │                │                  │                │
     │ Launch Game    │                  │                │
     │────────────────┼──────────────────┼────────────────┤
     │                │                  │                │
     │ Get Steam      │                  │                │
     │ Ticket         │                  │                │
     │────────────────┼──────────────────┼────────────────┤
     │                │                  │                │
     │                │ Validate Ticket  │                │
     │                │──────────────────┼────────────────┤
     │                │                  │                │
     │                │                  │ Verify         │
     │                │                  │ Ownership      │
     │                │                  │────────────────┤
     │                │                  │                │
     │                │                  │ Generate JWT   │
     │                │                  │────────────────┤
     │                │                  │                │
     │                │ Return JWT       │                │
     │                │◀──────────────────┼────────────────┤
     │                │                  │                │
     │                │ Connect to       │                │
     │                │ Game Server      │                │
     │                │──────────────────┼────────────────┤
     │                │                  │                │
     │                │ Load Characters  │                │
     │                │◀──────────────────┼────────────────┤
```

### Detailed Steps

**1. Web Login (Initial MVP):**
- Player visits web URL
- Simple email/password login or guest login for testing
- Client obtains JWT token

**2. Steam Launch (Future):**
- Player launches game from Steam (packaged Flutter app)
- Flutter client initializes Steam integration
- Client obtains Steam authentication ticket

**3. Authentication Request:**
```dart
// Flutter client sends to Auth Service
POST /api/auth/login
{
    email: string,
    password: string
}

// Or for Steam (future):
POST /api/auth/steam
{
    steamTicket: string,  // Steam authentication ticket
    steamId: number       // Player's Steam ID
}
```

**3. Steam Ticket Validation:**
```typescript
// Server validates with Steam Web API
GET https://api.steampowered.com/ISteamUserAuth/AuthenticateUserTicket/v1/
?key={API_KEY}
&appid={APP_ID}
&ticket={steamTicket}
```

**4. Account Linking:**
- If Steam ID exists in database → return account
- If not → create new account linked to Steam ID
- Store Steam ID in accounts table

**5. JWT Token Generation:**
```typescript
// Server generates JWT
{
    accountId: UUID,
    steamId: number,
    iat: timestamp,
    exp: timestamp + 24h
}
```

**6. Character Selection:**
- Client requests character list: `GET /api/characters?accountId={id}`
- If no characters → show character creation screen
- If characters exist → show character select screen
- **MVP Focus**: Simple character creation with name only (playstyle can be added later)

**7. Character Creation Flow:**
- Player enters character name
- Player selects playstyle focus: **Tank**, **DPS**, or **Healing**
- Server creates character with selected playstyle
- Server generates 3 starting skill choices based on playstyle
- Client displays skill choice UI (3 options)
- Player selects 1 skill from the 3 choices
- Server assigns selected skill to character
- Character is ready to play

**8. Game Server Connection:**
- Client connects to game server WebSocket
- Sends JWT token for authentication
- Server validates JWT, loads character data
- If character hasn't received starting skills → trigger starting skill choice
- Server assigns player to zone

### Session Management

**JWT Token:**
- **Lifetime**: 24 hours
- **Refresh**: New token on character selection
- **Storage**: Client memory (not localStorage for security)

**Redis Session:**
- **Key**: `sessions:{sessionId}`
- **Data**: Account ID, character ID, zone, server
- **TTL**: 24 hours
- **Purpose**: Fast session lookups, kick duplicate logins

**Duplicate Login Handling:**
- If same account logs in twice → invalidate old session
- Notify old client to disconnect
- Prevent account sharing

---

## Steam Integration (Future - Post-MVP)

### Steam SDK Setup

**Flutter Package**: Custom Steam integration or native plugin
- For web: Not applicable (Steam is desktop-only)
- For desktop: Use native Steamworks SDK via Flutter FFI or platform channels
- Alternative: Package Flutter web app with Electron and integrate Steam

### Required Steam Features

#### 1. Steam App ID
- Register game on Steamworks
- Obtain App ID
- Configure in Flutter: Environment variables or config file

#### 2. Steam Authentication (Desktop Only)
```dart
// Flutter Client (Desktop build)
import 'dart:ffi'; // For native Steamworks integration

class SteamAuth {
  // Initialize Steam (requires native plugin or FFI)
  Future<void> initialize() async {
    // Call native Steamworks SDK
    // Get Steam ID
    // Get authentication ticket
    // Send to backend
  }
}
```

**Note**: For MVP, focus on web-based login. Steam integration can be added later when packaging for Steam.

#### 3. Steam Ownership Verification
```typescript
// Backend validation
async function validateSteamOwnership(steamId: number, appId: number): Promise<boolean> {
    const response = await fetch(
        `https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key=${API_KEY}&steamids=${steamId}`
    );
    const data = await response.json();
    
    // Additional check: Verify user owns the game
    // This is implicit in ticket validation, but can add explicit check
    return data.response.players[0]?.gameid === appId.toString();
}
```

#### 4. Steam Overlay
- Enable Steam overlay in Unity
- Players can access Steam friends, achievements (future)

### Steam Build Pipeline (Future)

**Flutter Web to Desktop:**
- Option 1: Package Flutter web app with Electron
- Option 2: Build Flutter desktop app (Windows/Mac/Linux)
- Set up depots for game content
- Configure update channels (beta, release)

**CI/CD Integration:**
```yaml
# GitHub Actions example
- name: Build Flutter Web
  run: |
    flutter build web --release

- name: Package for Steam (Electron)
  run: |
    # Package web build with Electron
    # Include Steam integration

- name: Upload to Steam
  run: |
    steamcmd +login $STEAM_USER $STEAM_PASS +app_build $APP_ID +quit
```

### Steam Requirements Checklist (Future - Post-MVP)

- [ ] Steam App ID configured
- [ ] Steam authentication implemented
- [ ] Ownership verification enforced
- [ ] Steam overlay enabled (if using Electron or native desktop)
- [ ] Build pipeline configured (Flutter web → Electron/Desktop)
- [ ] Steam DRM (optional, for anti-piracy)
- [ ] Steam achievements (future)
- [ ] Steam leaderboards (future)

**MVP Focus**: Web-based login only. Steam integration deferred to post-MVP phase.

---

## Gameplay Systems

### Combat System

#### Server-Authoritative Combat

**Damage Calculation (Server):**
```typescript
function calculateDamage(attacker: Character, target: Character, skill: Skill): number {
    let baseDamage = attacker.strength; // Or intelligence for spells
    
    // Apply skill multiplier
    baseDamage *= skill.damageMultiplier;
    
    // Apply target armor/resistance
    const mitigation = target.armor / (target.armor + 100);
    baseDamage *= (1 - mitigation);
    
    // Random variance (90-110%)
    const variance = 0.9 + Math.random() * 0.2;
    baseDamage *= variance;
    
    // Critical hit chance
    if (Math.random() < attacker.critChance) {
        baseDamage *= attacker.critMultiplier;
    }
    
    return Math.floor(baseDamage);
}
```

**Hit Detection:**
- **Melee**: Range check (distance between attacker and target)
- **Ranged**: Raycast from attacker to target (check line of sight)
- **Spells**: Area of effect (AOE) or targeted

**Combat Flow:**
1. Client sends attack request with timestamp
2. Server validates: range, cooldown, target exists
3. Server calculates damage
4. Server applies damage to target
5. Server broadcasts combat event to nearby players
6. Client receives event, plays animation/effects

#### Skill System (Roguelike Discovery)

**Skill Data Structure:**
```typescript
interface SkillTemplate {
    id: string;
    name: string;
    description: string;
    playstyleTags: ('tank' | 'dps' | 'healing')[]; // Can have multiple tags
    type: 'melee' | 'ranged' | 'spell' | 'buff' | 'debuff';
    castTime: number; // 0 for instant
    cooldown: number;
    manaCost: number;
    range: number;
    damageMultiplier: number;
    healAmount?: number; // For healing skills
    effects: Effect[]; // Buffs, debuffs, DoT
}
```

**Skill Discovery System:**

**1. Starting Skills (Character Creation):**
```typescript
// When character is first created or first loads in
function generateStartingSkillChoices(playstyleFocus: 'tank' | 'dps' | 'healing'): SkillTemplate[] {
    // Query skills that match the playstyle focus
    const matchingSkills = await db.skillTemplates.findMany({
        where: {
            playstyleTags: { contains: [playstyleFocus] }
        },
        // Exclude skills already learned (if any)
        // For new characters, this will be empty
    });
    
    // Randomly select 3 skills
    const shuffled = matchingSkills.sort(() => 0.5 - Math.random());
    return shuffled.slice(0, 3);
}

// Client displays 3 choices, player selects 1
// Server assigns selected skill to character
```

**2. Ground Skill Discovery:**
```typescript
// Skill discovery items spawn on ground (similar to loot)
function spawnSkillDiscovery(zoneId: string, x: number, y: number) {
    // Create skill discovery item at location
    await db.skillDiscoveryItems.create({
        zoneId,
        positionX: x,
        positionY: y,
        isActive: true
    });
}

// When player right-clicks skill discovery item
async function interactWithSkillDiscovery(
    characterId: string, 
    discoveryItemId: string
): Promise<SkillTemplate[]> {
    const character = await getCharacter(characterId);
    const playstyleFocus = character.playstyleFocus;
    
    // Get skills player doesn't already know
    const knownSkillIds = await getCharacterSkills(characterId);
    
    // Generate 3 skill choices based on playstyle
    const availableSkills = await db.skillTemplates.findMany({
        where: {
            playstyleTags: { contains: [playstyleFocus] },
            id: { notIn: knownSkillIds } // Exclude already learned
        }
    });
    
    // If not enough skills for playstyle, include other playstyles
    if (availableSkills.length < 3) {
        const allSkills = await db.skillTemplates.findMany({
            where: {
                id: { notIn: knownSkillIds }
            }
        });
        availableSkills.push(...allSkills.filter(s => 
            !availableSkills.find(as => as.id === s.id)
        ));
    }
    
    // Randomly select 3
    const shuffled = availableSkills.sort(() => 0.5 - Math.random());
    return shuffled.slice(0, 3);
}

// Client displays choice UI, player selects 1
// Server assigns skill and removes discovery item
```

**3. Playstyle Change:**
```typescript
// Player can change playstyle at any time
async function changePlaystyle(
    characterId: string, 
    newPlaystyle: 'tank' | 'dps' | 'healing'
) {
    await db.characters.update({
        where: { id: characterId },
        data: { playstyleFocus: newPlaystyle }
    });
    
    // Future skill discoveries will use new playstyle
    // Already learned skills remain
}
```

**Cooldown Management:**
- Server tracks cooldowns per player
- Client shows cooldown UI (grayed out skill, timer)
- Server rejects skill use if on cooldown

**Skill Learning:**
- Skills are permanent once learned (persist through death)
- Skills are stored in `character_skills` table
- Player can have unlimited skills learned
- Action bar can hold any learned skills

#### Combat Log System

**Event Types:**
- `damage_dealt`: Player deals damage
- `damage_taken`: Player takes damage
- `heal`: Player heals
- `skill_used`: Player uses skill
- `kill`: Player kills enemy
- `death`: Player dies

**Storage:**
- Recent events in memory (last 100 events per player)
- Persist to database (last 24 hours)
- Client requests combat log for DPS meter calculation

**DPS Calculation:**
```typescript
function calculateDPS(combatLog: CombatEvent[], timeWindow: number): number {
    const recentEvents = combatLog.filter(e => 
        e.timestamp > Date.now() - timeWindow
    );
    const totalDamage = recentEvents
        .filter(e => e.eventType === 'damage_dealt')
        .reduce((sum, e) => sum + e.damage, 0);
    return totalDamage / (timeWindow / 1000); // DPS
}
```

### Death & Respawn System (Roguelike)

#### Death Handling

**When Player Dies:**
```typescript
async function handlePlayerDeath(characterId: string) {
    const character = await getCharacter(characterId);
    
    // Reset level and experience
    await db.characters.update({
        where: { id: characterId },
        data: {
            currentLevel: 1,
            experience: 0,
            deathCount: { increment: 1 },
            lastDeath: new Date(),
            // Reset position to spawn point
            zoneId: 'starting_zone',
            positionX: 0, // Spawn coordinates
            positionY: 0,
            // Reset HP/MP to full
            health: character.maxHealth,
            mana: character.maxMana
        }
    });
    
    // Accumulated stats persist (not reset)
    // Skills persist (not reset)
    // Inventory persists (not reset)
    
    // Notify client of death
    sendToClient(characterId, {
        type: 'death',
        message: 'You have died and returned to level 1. Your accumulated stats and skills remain.'
    });
}

// Calculate total stats (base + accumulated)
function getTotalStats(character: Character) {
    return {
        strength: character.baseStrength + character.accumulatedStrength,
        dexterity: character.baseDexterity + character.accumulatedDexterity,
        intelligence: character.baseIntelligence + character.accumulatedIntelligence,
        vitality: character.baseVitality + character.accumulatedVitality
    };
}
```

**Stat Accumulation:**
- Stats can be gained from items, level-ups (before death), or special events
- Accumulated stats are permanent and persist through death
- Base stats reset to defaults on death, but accumulated stats are added back

### Loot System

#### Loot Generation

**On Enemy Death:**
```typescript
function generateLoot(enemy: Enemy, killer: Character): LootItem[] {
    const loot: LootItem[] = [];
    
    // Guaranteed gold drop
    const goldAmount = enemy.level * (10 + Math.random() * 20);
    loot.push({ type: 'gold', amount: goldAmount });
    
    // Item drop chance (based on enemy level, rarity)
    const dropChance = 0.3; // 30% chance
    if (Math.random() < dropChance) {
        const item = generateRandomItem(enemy.level, killer.currentLevel);
        loot.push(item);
    }
    
    // Skill discovery item drop chance (rarer than regular items)
    const skillDiscoveryChance = 0.1; // 10% chance
    if (Math.random() < skillDiscoveryChance) {
        // Spawn skill discovery item at enemy death location
        spawnSkillDiscovery(enemy.zoneId, enemy.positionX, enemy.positionY);
    }
    
    return loot;
}

function generateRandomItem(enemyLevel: number, playerLevel: number): Item {
    // Determine rarity (weighted)
    const rarity = rollRarity();
    
    // Select item template from database
    const templates = await getItemTemplates({
        minLevel: Math.max(1, playerLevel - 5),
        maxLevel: playerLevel + 5,
        rarity: rarity
    });
    
    const template = templates[Math.floor(Math.random() * templates.length)];
    
    // Create item instance
    return {
        templateId: template.id,
        rarity: rarity,
        properties: generateItemProperties(template, rarity)
    };
}

function rollRarity(): Rarity {
    const roll = Math.random();
    if (roll < 0.5) return 'common';
    if (roll < 0.75) return 'uncommon';
    if (roll < 0.90) return 'rare';
    if (roll < 0.98) return 'epic';
    if (roll < 0.999) return 'legendary';
    return 'artifact'; // 0.1% chance
}
```

#### Loot Distribution

**Drop on Ground:**
- Server spawns loot at enemy death location
- Loot persists for 5 minutes (configurable)
- Multiple players can see same loot
- First player to pick up gets it

**Pickup Logic:**
- Client sends pickup request
- Server validates: player in range, loot exists
- Server adds item to player inventory
- Server removes loot from world
- Server broadcasts update to nearby players

### Movement System

#### Client-Side Movement
- **Input**: WASD keys
- **Prediction**: Move immediately on client
- **Smoothing**: Interpolate between server updates

#### Server-Side Validation
- **Speed limit**: Enforce max movement speed
- **Collision**: Check for walls, obstacles
- **Anti-cheat**: Detect teleportation, speed hacks

**Movement Sync:**
```typescript
// Client sends every 100ms or on direction change
{
    type: 'player_move',
    x: number,
    y: number,
    timestamp: number
}

// Server validates and broadcasts to nearby players
{
    type: 'player_update',
    playerId: UUID,
    x: number,
    y: number,
    timestamp: number
}
```

### Enemy AI System

**Basic AI (MVP):**
- **Idle**: Wander randomly
- **Aggro**: Detect player within range, chase
- **Attack**: Attack player when in range
- **Return**: Return to spawn if player leaves aggro range

**Future Enhancements:**
- Pathfinding (A* algorithm)
- Group behavior (enemies work together)
- Advanced states (flee when low HP)

---

## UI System Architecture

### UI Component Structure

```
UI/
├── Canvas (Screen Space - Overlay)
│   ├── MainHUD
│   │   ├── HealthBar
│   │   ├── ManaBar
│   │   ├── TargetFrame (shows selected enemy HP)
│   │   └── ExperienceBar
│   ├── ActionBars
│   │   ├── ActionBar1 (Keys 1-9, 0, -, =)
│   │   ├── ActionBar2 (Ctrl + keys)
│   │   └── ActionBar3 (Shift + keys)
│   ├── ChatWindow
│   │   ├── ChatTabs (Global, Local, Party)
│   │   ├── ChatInput
│   │   └── ChatLog
│   ├── InventoryWindow
│   │   ├── InventoryGrid (slots)
│   │   ├── EquipmentSlots
│   │   └── ItemTooltip
│   ├── SkillChoiceWindow
│   │   ├── SkillOption1 (Icon, Name, Description, Select Button)
│   │   ├── SkillOption2 (Icon, Name, Description, Select Button)
│   │   └── SkillOption3 (Icon, Name, Description, Select Button)
│   └── Menus
│       ├── CharacterSelect
│       ├── CharacterCreation (Name Input, Playstyle Selection)
│       ├── PlaystyleChange (Change playstyle anytime)
│       └── Settings
```

### Action Bar System

**Hotkey Binding:**
```dart
// Flutter
class ActionBar extends StatefulWidget {
  @override
  _ActionBarState createState() => _ActionBarState();
}

class _ActionBarState extends State<ActionBar> {
  final Map<LogicalKeyboardKey, int> keyBindings = {
    LogicalKeyboardKey.digit1: 0,
    LogicalKeyboardKey.digit2: 1,
    // ... etc
  };
  
  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (keyBindings.containsKey(key)) {
            final ctrl = HardwareKeyboard.instance.isControlPressed;
            final shift = HardwareKeyboard.instance.isShiftPressed;
            
            final barIndex = ctrl ? 1 : (shift ? 2 : 0);
            final slotIndex = keyBindings[key]!;
            
            useSkill(barIndex, slotIndex);
          }
        }
      },
      child: // Action bar UI
    );
  }
}
```

**Skill Icons:**
- Drag-and-drop skills to action bar
- Show cooldown overlay (gray + timer)
- Show mana cost (disable if insufficient mana)

### Chat System

**Channels:**
- **Global**: Server-wide chat
- **Local**: Chat within view distance (50 units)
- **Party**: Party chat (future)
- **Whisper**: Direct message to player

**Implementation:**
```typescript
// Client
function sendChatMessage(channel: string, message: string) {
    socket.emit('chat_message', { channel, message });
}

// Server
socket.on('chat_message', (data) => {
    if (data.channel === 'global') {
        // Broadcast to all players
        io.emit('chat_broadcast', { playerId, channel: 'global', message });
    } else if (data.channel === 'local') {
        // Broadcast to players in same zone, within range
        const nearbyPlayers = getPlayersInRange(player.position, 50);
        nearbyPlayers.forEach(p => {
            p.socket.emit('chat_broadcast', { playerId, channel: 'local', message });
        });
    }
});
```

### Skill Choice UI System

**Skill Choice Window:**
- Modal overlay that appears when:
  - Character first loads (starting skills)
  - Player right-clicks skill discovery item
- Displays 3 skill options side-by-side
- Each option shows:
  - Skill icon
  - Skill name
  - Description
  - Playstyle tags (tank/dps/healing icons)
  - Stats (damage, cooldown, mana cost)
- Player clicks one option to select
- Window closes after selection
- Server assigns skill to character

**Implementation:**
```dart
// Flutter
class SkillChoiceWindow extends StatelessWidget {
  final List<SkillTemplate> skills;
  final Function(String skillId) onSkillSelected;
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Row(
        children: [
          SkillOptionCard(
            skill: skills[0],
            onTap: () => onSkillSelected(skills[0].id),
          ),
          SkillOptionCard(
            skill: skills[1],
            onTap: () => onSkillSelected(skills[1].id),
          ),
          SkillOptionCard(
            skill: skills[2],
            onTap: () => onSkillSelected(skills[2].id),
          ),
        ],
      ),
    );
  }
  
  void showSkillChoices(BuildContext context, List<SkillTemplate> skills) {
    showDialog(
      context: context,
      builder: (context) => SkillChoiceWindow(
        skills: skills,
        onSkillSelected: (skillId) {
          // Send selection to server via WebSocket
          networkService.sendSkillChoice(skillId);
          Navigator.of(context).pop();
        },
      ),
    );
  }
}
```

**Right-Click Interaction:**
- When player right-clicks skill discovery item on ground
- Client sends interaction request to server
- Server generates 3 skill choices based on playstyle
- Server sends choices to client
- Client displays skill choice window
- Player selects, server assigns skill and removes discovery item

### Character Creation UI

**Flow:**
1. **Name Input**: Text field for character name
2. **Playstyle Selection**: Three buttons/cards:
   - **Tank**: Icon + description ("Focus on defense and protection")
   - **DPS**: Icon + description ("Focus on dealing damage")
   - **Healing**: Icon + description ("Focus on supporting and healing")
3. **Create Button**: Creates character and triggers starting skill choice
4. **Skill Choice Window**: Appears immediately after creation

**Playstyle Change UI:**
- Accessible from main menu or in-game settings
- Same three-option selection as character creation
- Changes affect future skill discoveries only
- Already learned skills remain

### Inventory System

**Grid Layout:**
- 10x10 grid (100 slots)
- Drag-and-drop items
- Equipment slots (weapon, armor pieces)
- Item stacking (consumables)

**Item Tooltip:**
- Show on hover
- Display: name, rarity, stats, description
- Color-coded by rarity

**Skill Discovery Item Visual:**
- Distinct visual appearance (glowing, special icon)
- Tooltip: "Right-click to discover a new skill"
- Can be picked up by any player (first come, first served)

---

## Security Considerations

### Anti-Cheat Measures

#### 1. Server Authority
- **Combat**: All damage calculated server-side
- **Movement**: Server validates position, speed
- **Inventory**: Server manages all item transactions
- **Stats**: Server tracks player stats, prevents modification

#### 2. Input Validation
- **Range checks**: Verify attack range, pickup range
- **Cooldown enforcement**: Server tracks cooldowns
- **Rate limiting**: Limit requests per second per player

#### 3. Detection Systems
- **Speed monitoring**: Detect movement speed hacks
- **Teleportation detection**: Flag impossible position changes
- **Damage anomaly detection**: Flag unrealistic damage values

#### 4. Penalties
- **Warnings**: First offense → warning message
- **Temporary ban**: Repeat offense → 24h ban
- **Permanent ban**: Severe offense → account ban

### Data Protection

#### 1. Password Security
- **Hashing**: bcrypt with cost factor 10-12
- **No plaintext**: Never store or log passwords
- **Password requirements**: Minimum 8 characters, complexity

#### 2. Session Security
- **JWT expiration**: 24-hour tokens
- **HTTPS only**: All API communication encrypted
- **Steam validation**: Enforce Steam ownership on every login

#### 3. SQL Injection Prevention
- **Parameterized queries**: Use ORM (Prisma/TypeORM)
- **Input sanitization**: Validate all user input

#### 4. DDoS Protection
- **Rate limiting**: Per IP, per account
- **Cloudflare**: Use CDN with DDoS protection
- **Connection limits**: Max connections per IP

### Logging & Monitoring

**Security Events:**
- Failed login attempts
- Suspicious activity (speed hacks, teleportation)
- Account creation/deletion
- Admin actions

**Tools:**
- **Application logs**: Winston (Node.js) or similar
- **Monitoring**: Datadog, New Relic, or self-hosted (Grafana + Prometheus)
- **Alerts**: Email/Slack notifications for critical events

---

## Scalability Plan

### Horizontal Scaling Strategy

#### Phase 1: Single Server (MVP)
- **Capacity**: 100-500 concurrent players
- **Architecture**: Monolithic server (all zones on one process)
- **Cost**: ~$50-100/month (single EC2 instance)

#### Phase 2: Zone-Based Scaling
- **Capacity**: 1,000-5,000 concurrent players
- **Architecture**: Separate server processes per zone
- **Load balancer**: Routes players to appropriate zone server
- **Cost**: ~$200-500/month (multiple EC2 instances)

#### Phase 3: Microservices (10,000+ players)
- **Capacity**: 10,000-100,000+ concurrent players
- **Architecture**: 
  - Game servers (stateless, auto-scaling)
  - Auth service (separate)
  - Persistence service (separate)
  - Chat service (separate)
- **Orchestration**: Kubernetes
- **Cost**: ~$1,000-5,000/month (scales with player count)

### Scaling Components

#### 1. Database Scaling
- **Read replicas**: Distribute read queries
- **Connection pooling**: PgBouncer or similar
- **Caching**: Redis for frequently accessed data
- **Partitioning**: Partition combat_logs by date

#### 2. Game Server Scaling
- **Zone instances**: Spin up new zone servers when capacity reached
- **Player distribution**: Load balancer assigns players to zones
- **Cross-zone communication**: Message queue (Redis Pub/Sub or RabbitMQ)

#### 3. Asset Delivery
- **CDN**: CloudFront/Cloudflare for game assets
- **Compression**: Gzip/Brotli for asset downloads
- **Caching**: Long cache headers for static assets

### Auto-Scaling Configuration

**Kubernetes HPA (Horizontal Pod Autoscaler):**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: game-server-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: game-server
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

**Custom Metrics (Player Count):**
- Monitor player count per zone
- Scale up when zone >80% capacity
- Scale down when zone <30% capacity

### Cost Optimization

**Strategies:**
1. **Reserved instances**: 1-year commitment for base capacity (30-40% savings)
2. **Spot instances**: For non-critical services (up to 90% savings)
3. **Right-sizing**: Monitor and adjust instance sizes
4. **Database optimization**: Index optimization, query tuning
5. **Caching**: Aggressive caching to reduce database load

---

## Development Roadmap

### Phase 1: Foundation (Weeks 1-4) - MVP Focus: Login & Game Space

**Week 1-2: Project Setup**
- [ ] Set up Flutter project (web configuration)
- [ ] Set up backend project (Node.js)
- [ ] Configure database (PostgreSQL + Redis)
- [ ] Set up version control (Git)
- [ ] Create basic Flutter project structure
- [ ] Set up CI/CD pipeline (basic)

**Week 3-4: Authentication & Basic Game Space**
- [ ] Implement simple login system (email/password or guest login for testing)
- [ ] Implement JWT token system
- [ ] Implement basic character creation (name only - playstyle can be added later)
- [ ] Implement character selection
- [ ] Create simple game world (basic tilemap or canvas)
- [ ] Implement basic player rendering (simple sprite or colored rectangle)
- [ ] Implement basic movement (WASD keys)
- [ ] Test login and basic game space in browser

**Deliverable**: Players can log in, create a character, and see a simple game space where they can move around. Focus on testing multiplayer and gamespace functionality.

### Phase 2: Multiplayer & Game Space Testing (Weeks 5-8)

**Week 5-6: Multiplayer Foundation**
- [ ] Implement WebSocket connection to game server
- [ ] Implement player position synchronization (multiple players visible)
- [ ] Implement server-client movement sync
- [ ] Add player name labels above characters
- [ ] Test multiple players in same game space
- [ ] Implement basic camera system (follow player, zoom)

**Week 7-8: Enhanced Game Space**
- [ ] Improve world rendering (better tilemap or canvas graphics)
- [ ] Add basic collision detection (walls, boundaries)
- [ ] Implement simple chat system (see other players' messages)
- [ ] Add visual feedback for player actions
- [ ] Test multiplayer interactions (players can see each other move)
- [ ] Performance testing with multiple concurrent players

**Deliverable**: Multiple players can log in, see each other in the game space, move around, and interact. Core multiplayer and gamespace functionality is working.

### Phase 3: Advanced Features (Weeks 9-16) - Post-MVP

**Week 11-12: Roguelike Systems & Skill Discovery**
- [ ] Implement death/respawn system (reset level, keep stats)
- [ ] Implement accumulated stats system (persist through death)
- [ ] Implement skill discovery system (ground spawns)
- [ ] Implement skill choice UI (3 options on right-click)
- [ ] Implement playstyle-based skill generation
- [ ] Implement playstyle change system (changeable anytime)
- [ ] Implement skill learning/persistence (skills persist through death)
- [ ] Implement cooldown system
- [ ] Implement mana costs
- [ ] Add multiple skills with playstyle tags
- [ ] Implement ranged attacks
- [ ] Implement spell casting

**Week 13-14: Loot System & Skill Discovery Drops**
- [ ] Implement item templates
- [ ] Implement loot generation
- [ ] Implement item rarities
- [ ] Implement skill discovery item drops (from enemies)
- [ ] Implement skill discovery item spawning
- [ ] Implement inventory management
- [ ] Implement item pickup
- [ ] Test loot distribution
- [ ] Test skill discovery flow end-to-end

**Week 15-16: Polish & Optimization**
- [ ] Implement combat log
- [ ] Implement DPS meter (client-side)
- [ ] Optimize network messages
- [ ] Add visual feedback (damage numbers, etc.)
- [ ] Performance testing
- [ ] Bug fixes

**Deliverable**: Full combat loop with skills, loot, inventory

### Phase 4: Steam Packaging & Launch Prep (Weeks 17-20)

**Week 17-18: Steam Packaging**
- [ ] Research Flutter web to desktop packaging (Electron or native)
- [ ] Set up Steam App ID (if ready)
- [ ] Package Flutter web app for Windows desktop
- [ ] Test desktop build locally
- [ ] Set up Steam build pipeline (if applicable)
- [ ] Create Steam store page (draft) - optional for MVP

**Week 19-20: Testing & Launch**
- [ ] Load testing (multiple concurrent players in web version)
- [ ] Security audit
- [ ] Bug fixing
- [ ] Documentation
- [ ] Prepare launch materials
- [ ] Web deployment (host game on web server)
- [ ] Soft launch (closed beta) - web-based initially

**Deliverable**: Game playable on web, ready for testing. Steam packaging can be refined post-MVP.

### Post-Launch Roadmap

**Months 1-3:**
- Additional zones
- More enemy types
- More items/skills
- Player feedback integration

**Months 4-6:**
- Party system
- Trading system
- Achievements
- Leaderboards

**Months 7-12:**
- PvP system
- Guild system
- Raids/dungeons
- Expansion content

---

## Team Role Breakdown

### Recommended Team Structure (5 developers)

#### 1. Lead Developer / Technical Director
- **Responsibilities**:
  - Architecture decisions
  - Code reviews
  - Technical planning
  - Team coordination
- **Skills**: Full-stack, game development, system design

#### 2. Backend Engineer
- **Responsibilities**:
  - Server development
  - Database design
  - API development
  - Infrastructure setup
- **Skills**: Node.js, PostgreSQL, Redis, AWS/GCP, networking

#### 3. Gameplay Programmer
- **Responsibilities**:
  - Flutter client development
  - Gameplay systems (combat, movement)
  - UI implementation
  - Client-server integration
- **Skills**: Flutter, Dart, game development, networking

#### 4. Game Designer / Programmer
- **Responsibilities**:
  - Game design
  - Balance tuning
  - Content creation (items, skills)
  - Player experience
- **Skills**: Game design, scripting, data analysis

#### 5. Artist / Technical Artist
- **Responsibilities**:
  - Sprite creation
  - Animation
  - UI art
  - Asset optimization
- **Skills**: 2D art, pixel art, animation, web-optimized assets

### Smaller Team Adaptations

**3 Developers:**
- Lead (full-stack)
- Backend Engineer
- Gameplay Programmer (also does UI/art integration)

**2 Developers:**
- Lead (full-stack + backend)
- Gameplay Programmer (client + some backend)

**1 Developer (Solo):**
- Full-stack developer
- Use asset store for art
- Focus on MVP features only

---

## Risk Assessment

### Technical Risks

#### 1. Networking Complexity
- **Risk**: High latency, desync issues
- **Mitigation**: 
  - Use proven networking library (Mirror)
  - Extensive testing with multiple clients
  - Client prediction + server reconciliation
- **Probability**: Medium
- **Impact**: High

#### 2. Scalability Challenges
- **Risk**: Server can't handle player load
- **Mitigation**:
  - Design for horizontal scaling from start
  - Load testing early and often
  - Monitor performance metrics
- **Probability**: Medium
- **Impact**: High

#### 3. Security Vulnerabilities
- **Risk**: Cheating, hacking, data breaches
- **Mitigation**:
  - Server-authoritative design
  - Security audits
  - Regular dependency updates
- **Probability**: Medium
- **Impact**: High

#### 4. Steam Integration Issues (Post-MVP)
- **Risk**: Authentication failures, build pipeline problems, Flutter web to desktop packaging challenges
- **Mitigation**:
  - Test Steam integration when ready (not needed for MVP)
  - Research Flutter packaging options early (Electron vs native)
  - Have web-based fallback (primary for MVP)
- **Probability**: Medium (packaging complexity)
- **Impact**: Medium (not blocking MVP)

### Business Risks

#### 1. Development Timeline
- **Risk**: Project takes longer than expected
- **Mitigation**:
  - Agile development (2-week sprints)
  - Regular milestone reviews
  - Scope management (MVP first)
- **Probability**: High
- **Impact**: Medium

#### 2. Budget Overruns
- **Risk**: Infrastructure costs exceed budget
- **Mitigation**:
  - Start with low-cost infrastructure
  - Monitor costs closely
  - Optimize before scaling
- **Probability**: Medium
- **Impact**: Medium

#### 3. Player Acquisition
- **Risk**: Not enough players to sustain game
- **Mitigation**:
  - Marketing plan
  - Steam visibility rounds
  - Community building
- **Probability**: Medium
- **Impact**: High

### Operational Risks

#### 1. Server Downtime
- **Risk**: Game unavailable, player frustration
- **Mitigation**:
  - Redundancy (multiple servers)
  - Monitoring and alerts
  - Quick incident response
- **Probability**: Low
- **Impact**: High

#### 2. Data Loss
- **Risk**: Character data corruption or loss
- **Mitigation**:
  - Regular database backups
  - Transaction logging
  - Disaster recovery plan
- **Probability**: Low
- **Impact**: Critical

---

## Complexity Estimates

### Subsystem Complexity Ratings

**Scale: 1 (Trivial) - 10 (Extremely Complex)**

#### Client-Side Systems
- **Input System**: 4/10 (Flutter keyboard/mouse handling, requires some setup)
- **Rendering System**: 5/10 (Custom canvas rendering or packages, more manual than Unity)
- **Movement System**: 5/10 (Client prediction adds complexity)
- **Combat System (Client)**: 6/10 (Prediction, animation sync) - Post-MVP
- **UI System**: 4/10 (Flutter widgets, good but requires state management)
- **Network Client**: 7/10 (WebSocket message handling, reconciliation)

#### Server-Side Systems
- **Authentication Service**: 4/10 (Standard JWT + Steam)
- **Game Server Core**: 8/10 (Complex state management)
- **Combat System (Server)**: 7/10 (Authoritative calculations)
- **Zone Management**: 6/10 (Load balancing, distribution)
- **Persistence Service**: 5/10 (Database operations)
- **Chat System**: 4/10 (Message routing)

#### Infrastructure
- **Database Setup**: 3/10 (Standard PostgreSQL)
- **Redis Setup**: 3/10 (Standard Redis)
- **Docker/Containerization**: 4/10 (Learning curve)
- **Kubernetes Setup**: 7/10 (Complex orchestration)
- **CI/CD Pipeline**: 5/10 (Configuration complexity)

#### Steam Integration (Post-MVP)
- **Steam Authentication**: 6/10 (Requires native integration or Electron wrapper)
- **Steam Build Pipeline**: 7/10 (Flutter web → Electron/Desktop packaging)
- **Steam Overlay**: 5/10 (Requires native integration)

### Development Time Estimates

**Per Developer, Full-Time:**

- **Phase 1 (Foundation - Login & Game Space)**: 4 weeks
- **Phase 2 (Multiplayer & Game Space Testing)**: 4 weeks
- **Phase 3 (Advanced Features)**: 6 weeks (post-MVP)
- **Phase 4 (Steam Packaging & Launch)**: 4 weeks (post-MVP)

**Total: ~8 weeks (2 months) for MVP (login + multiplayer game space)**

*Note: These are optimistic estimates. Add 20-30% buffer for unexpected issues.*

---

## Assumptions & Tradeoffs

### Assumptions

1. **Team has Flutter/Dart experience**: If not, add 2-4 weeks for learning
2. **Team has backend experience**: If not, add 2-4 weeks for learning
3. **Art assets available**: Either team member or asset store
4. **Steam approval granted**: Assumes game meets Steam requirements
5. **Budget for cloud hosting**: ~$100-500/month initially
6. **Players have stable internet**: 100+ ms latency acceptable

### Tradeoffs

#### 1. Flutter vs Unity vs Custom Engine
- **Flutter**: Web-first, single codebase for web/desktop, good for rapid iteration
- **Unity**: More mature game engine, but requires separate builds for web/desktop
- **Custom**: Full control, but much longer development time
- **Decision**: Flutter (web-first approach, easier multiplayer testing, can package for Steam later)

#### 2. Node.js vs C# Backend
- **Node.js**: Fast development, large ecosystem, excellent WebSocket support
- **C#/.NET**: Better performance, but heavier infrastructure
- **Decision**: Node.js (faster iteration, excellent for real-time web games, can optimize later)

#### 3. PostgreSQL vs NoSQL
- **PostgreSQL**: ACID compliance, relational data, but requires schema
- **NoSQL (MongoDB)**: Flexible schema, but eventual consistency issues
- **Decision**: PostgreSQL (data integrity critical for MMORPG)

#### 4. Monolith vs Microservices
- **Monolith**: Simpler deployment, easier debugging, but harder to scale
- **Microservices**: Better scalability, but more complexity
- **Decision**: Monolith first, modular design for future split

#### 5. TCP vs UDP
- **TCP**: Reliable, but higher latency
- **UDP**: Lower latency, but packet loss
- **Decision**: TCP for critical data, UDP for non-critical (future optimization)

#### 6. Client Prediction vs Server-Only
- **Client Prediction**: Better feel, but more complex
- **Server-Only**: Simpler, but feels laggy
- **Decision**: Client prediction (essential for good feel)

---

## MVP vs Long-Term

### MVP Scope (Launch-Ready)

**Must Have (MVP - Focus on Login & Game Space):**
- Simple login system (email/password or guest login for testing)
- Character creation (name only - simplified for MVP)
- Character selection
- Basic movement (WASD)
- Multiplayer visibility (see other players in game space)
- Basic game world (simple tilemap or canvas)
- WebSocket connection and synchronization
- Basic chat (see other players' messages)
- Server-authoritative movement

**Nice to Have (Post-MVP):**
- Steam authentication
- Character creation with playstyle selection (Tank/DPS/Healing)
- Starting skill choice system (3 choices based on playstyle)
- Basic combat (melee + skills)
- **Roguelike death system**: Death resets level to 1, keeps accumulated stats
- **Accumulated stats system**: Stats persist through death
- **Skill discovery system**: Skills found on ground, right-click for 3 choices
- Enemy AI (basic)
- Loot system (gold + items)
- Inventory (basic)
- Health/mana bars
- Action bar
- Skills persist through death

**Nice to Have (Post-MVP):**
- Character customization (visual)
- More skills (20+ skills with playstyle tags)
- More zones
- More enemy types
- Party system
- Trading
- Stat accumulation from level-ups (before death)

### Long-Term Vision

**Year 1:**
- 10+ zones
- 20+ enemy types
- 50+ skills
- 100+ items
- Party system
- Trading system
- Achievements
- Leaderboards

**Year 2:**
- PvP system
- Guild system
- Raids/dungeons
- Crafting system
- Housing system
- Expansion content

**Year 3+:**
- Mobile companion app
- Cross-platform (Mac/Linux)
- Console ports (if successful)
- Major expansions

---

## Next Steps

### Immediate Actions (This Week)

1. **Review this document** with team
2. **Set up development environment**:
   - Install Flutter SDK (latest stable)
   - Enable Flutter web support: `flutter config --enable-web`
   - Install Node.js 20 LTS
   - Set up PostgreSQL + Redis locally
   - Create GitHub/GitLab repository
3. **Create project structure**:
   - Initialize Flutter project: `flutter create --platforms web .`
   - Initialize Node.js project
   - Set up database schema
4. **Steam registration (optional for MVP)**:
   - Can be deferred until ready to package for Steam
   - Focus on web deployment first
5. **Set up basic CI/CD**:
   - GitHub Actions or GitLab CI
   - Basic Flutter web build pipeline

### Week 1-2 Goals

1. **Flutter Project Setup**:
   - Create Flutter project with web support
   - Set up basic game screen
   - Create simple player widget (colored rectangle or sprite)
   - Implement basic movement (WASD) with keyboard input
   - Set up basic camera/viewport

2. **Backend Setup**:
   - Set up Express/Fastify server
   - Connect to PostgreSQL
   - Connect to Redis
   - Create basic API endpoints (health check, login, character creation)
   - Set up WebSocket server (Socket.io or ws)

3. **Database Setup**:
   - Create accounts table
   - Create characters table (simplified for MVP)
   - Run migrations

4. **Version Control**:
   - Initialize Git repository
   - Set up .gitignore (include Flutter build artifacts)
   - Create initial commit

### Questions to Answer Before Starting

1. **Team composition**: How many developers? What skills?
2. **Budget**: Monthly hosting budget?
3. **Timeline**: Target launch date?
4. **Art style**: Pixel art? Hand-drawn? Asset store?
5. **Monetization**: Free-to-play? One-time purchase? (affects design)

---

## Clarifying Questions

### Technical Questions

1. **WebSocket Library**: Do you have a preference between Socket.io and ws? Socket.io has more features (rooms, namespaces), ws is lighter.

2. **Database Hosting**: Do you prefer managed databases (RDS, Cloud SQL) or self-hosted? Managed is easier but more expensive.

3. **Art Assets**: Do you have an artist, or will you use placeholder graphics? For MVP, simple colored shapes are fine.

4. **Zone Design**: Should zones be instanced (separate copies) or shared (all players in same world)? Instanced is easier to scale.

5. **Flutter State Management**: Do you prefer Provider, Riverpod, Bloc, or another state management solution?

### Business Questions

1. **Monetization Model**: Free-to-play with microtransactions? One-time purchase? Subscription? This affects design decisions.

2. **Target Player Count**: What's the target concurrent players at launch? This affects infrastructure planning.

3. **Geographic Focus**: Global servers or regional? Affects latency and infrastructure.

4. **Content Scope**: How many zones/enemies/items for MVP? This affects development time.

5. **Steam Early Access**: Launch in Early Access or full release? Early Access allows iteration based on feedback.

### Operational Questions

1. **Support**: Who handles player support? Affects account management features.

2. **Moderation**: How will chat moderation work? Automated? Manual? Affects chat system design.

3. **Backups**: How often should database backups run? Affects persistence design.

4. **Monitoring**: What level of monitoring is needed? Affects infrastructure setup.

5. **Disaster Recovery**: What's the RTO (Recovery Time Objective)? Affects backup strategy.

---

## Conclusion

This technical implementation plan provides a comprehensive roadmap for building a Diablo-2 style MMORPG using Flutter (web-based) with eventual Steam packaging. The architecture is designed to be:

- **Scalable**: Can grow from 100 to 100,000+ players
- **Maintainable**: Clean code, good documentation
- **Cost-effective**: Low initial costs, scales with success
- **Secure**: Server-authoritative, anti-cheat measures
- **Iterative**: MVP-first approach, continuous improvement

**Key Success Factors:**
1. Start small (MVP)
2. Test early and often
3. Monitor performance
4. Iterate based on feedback
5. Scale gradually

**Remember**: This is a living document. Update it as you learn and iterate. Good luck with your game development journey!

---

## Appendix: Useful Resources

### Documentation
- [Flutter Documentation](https://docs.flutter.dev/)
- [Flutter Web](https://docs.flutter.dev/platform-integration/web)
- [Socket.io](https://socket.io/) - WebSocket library
- [Steamworks Documentation](https://partner.steamgames.com/doc/home) - For future Steam integration
- [Node.js Best Practices](https://github.com/goldbergyoni/nodebestpractices)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

### Tools
- [Prisma](https://www.prisma.io/) - Type-safe ORM
- [Socket.io Client for Dart](https://pub.dev/packages/socket_io_client) or [web_socket_channel](https://pub.dev/packages/web_socket_channel)
- [Winston](https://github.com/winstonjs/winston) - Logging
- [Docker](https://www.docker.com/) - Containerization
- [Kubernetes](https://kubernetes.io/) - Orchestration

### Learning Resources
- [Game Networking](https://gafferongames.com/) - Excellent networking tutorials
- [MMO Architecture](https://www.gamedeveloper.com/) - Industry articles
- [Flutter Game Development](https://docs.flutter.dev/games) - Flutter game development guide
- [Flutter Canvas Tutorial](https://api.flutter.dev/flutter/dart-ui/Canvas-class.html) - For 2D rendering

---

**Document End**

