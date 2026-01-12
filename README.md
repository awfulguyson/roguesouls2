# RogueSouls - Roguelike MMO

A roguelike MMO with shared world, where death resets your level but your accumulated stats and skills persist.

## Project Structure

```
RogueSouls/
├── client/          # Unity game client
├── server/          # Node.js backend server
└── docs/            # Documentation
```

## Getting Started

### Prerequisites
- Unity 2022 LTS
- Node.js 20 LTS
- PostgreSQL 14+
- Redis 7+

### Development Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd RogueSouls
   ```

2. **Set up the backend**
   ```bash
   cd server
   npm install
   cp .env.example .env
   # Edit .env with your database credentials
   npm run migrate
   npm run dev
   ```

3. **Set up the Unity client**
   - Open Unity Hub
   - Open project from `client/` folder
   - Install required packages (see client/README.md)

## Development Principles

- **Clean Code**: Remove obsolete code when fixing or removing features
- **Incremental Development**: Add features one by one, ensure proper implementation
- **Test as You Go**: Test each feature before moving to the next
- **Documentation**: Keep code and architecture documentation up to date

## Architecture

See [TECHNICAL_IMPLEMENTATION_PLAN.md](./TECHNICAL_IMPLEMENTATION_PLAN.md) for detailed architecture and implementation details.

## License

[To be determined]

