# RogueSouls Client (Unity)

Unity game client for RogueSouls.

## Setup

1. **Open in Unity**
   - Install Unity 2022 LTS
   - Open Unity Hub
   - Click "Add" and select this folder
   - Open the project

2. **Install Required Packages**
   - Open Package Manager (Window > Package Manager)
   - Install required packages (will be documented as we add them)

## Project Structure

```
Assets/
├── Scripts/
│   ├── Core/           # Core game systems
│   ├── Player/         # Player-related scripts
│   ├── Combat/         # Combat system
│   ├── UI/             # UI components
│   ├── World/          # World/world systems
│   ├── Networking/     # Network client code
│   └── Data/           # ScriptableObjects, data
├── Scenes/             # Unity scenes
├── Prefabs/            # Prefabs
└── Resources/          # Resources (sprites, audio, etc.)
```

## Development

- Features are added incrementally
- Each feature is tested before moving to the next
- Old/obsolete code is removed when features are changed

