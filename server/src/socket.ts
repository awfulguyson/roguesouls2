import { Server, Socket } from 'socket.io';

interface Player {
  id: string;
  socketId: string;
  name: string;
  spriteType?: string;
  x: number;
  y: number;
}

interface Enemy {
  id: string;
  x: number;
  y: number;
  spriteType: string;
  maxHp: number;
  currentHp: number;
  moveDirectionX: number;
  moveDirectionY: number;
  isMoving: boolean;
  lastStateChangeTime: number;
  lastRotationAngle: number;
}

const players: Map<string, Player> = new Map();
const socketToCharacter: Map<string, string> = new Map();
const enemies: Map<string, Enemy> = new Map();

let io: Server;

// Initialize enemies on server startup
function initializeEnemies() {
  enemies.clear();
  
  // Spawn 20 enemies within 1000 units of origin
  const enemyTypes = ['enemy-1', 'enemy-2', 'enemy-3', 'enemy-4', 'enemy-5'];
  const initialEnemies = [];
  
  for (let i = 1; i <= 20; i++) {
    // Random position within -1000 to 1000 for both X and Y
    const x = (Math.random() * 2000) - 1000; // -1000 to 1000
    const y = (Math.random() * 2000) - 1000; // -1000 to 1000
    // Cycle through enemy types
    const spriteType = enemyTypes[(i - 1) % enemyTypes.length];
    
    initialEnemies.push({
      id: `enemy_${i}`,
      x: x,
      y: y,
      spriteType: spriteType,
    });
  }

  function getHpForSpriteType(spriteType: string): number {
    switch (spriteType) {
      case 'enemy-1': return 100.0;
      case 'enemy-2': return 101.0;
      case 'enemy-3': return 102.0;
      case 'enemy-4': return 103.0;
      case 'enemy-5': return 104.0;
      default: return 100.0;
    }
  }

  initialEnemies.forEach(enemyData => {
    const maxHp = getHpForSpriteType(enemyData.spriteType);
    enemies.set(enemyData.id, {
      id: enemyData.id,
      x: enemyData.x,
      y: enemyData.y,
      spriteType: enemyData.spriteType,
      maxHp: maxHp,
      currentHp: maxHp,
      moveDirectionX: 0,
      moveDirectionY: 0,
      isMoving: false,
      lastStateChangeTime: Date.now(),
      lastRotationAngle: 0,
    });
  });
  
  console.log(`Initialized ${enemies.size} enemies`);
  if (enemies.size > 0) {
    const firstEnemy = Array.from(enemies.values())[0];
    console.log(`Sample enemy: ${firstEnemy.id} at (${firstEnemy.x}, ${firstEnemy.y})`);
  }
}

// Update enemies periodically
function updateEnemies() {
  const now = Date.now();
  const moveSpeed = 1.0;
  const moveDuration = 1000; // 1 second
  const pauseDuration = 2000; // 2 seconds

  enemies.forEach((enemy, enemyId) => {
    if (!enemy.lastStateChangeTime) {
      enemy.lastStateChangeTime = now;
      return;
    }

    const elapsed = now - enemy.lastStateChangeTime;

    if (enemy.isMoving) {
      if (elapsed >= moveDuration) {
        // Stop moving
        enemy.isMoving = false;
        enemy.moveDirectionX = 0;
        enemy.moveDirectionY = 0;
        enemy.lastStateChangeTime = now;
      } else {
        // Move in current direction
        enemy.x += enemy.moveDirectionX * moveSpeed;
        enemy.y += enemy.moveDirectionY * moveSpeed;
      }
    } else {
      if (elapsed >= pauseDuration) {
        // Start moving in random direction
        const angle = Math.random() * 2 * Math.PI;
        enemy.moveDirectionX = Math.cos(angle);
        enemy.moveDirectionY = Math.sin(angle);
        enemy.isMoving = true;
        enemy.lastStateChangeTime = now;
        // Update rotation angle
        if (enemy.spriteType === 'enemy-5') {
          enemy.lastRotationAngle = Math.atan2(enemy.moveDirectionY, enemy.moveDirectionX);
        }
      }
    }
  });
}

export function setupSocketIO(server: Server) {
  io = server;
  
  // Initialize enemies on server start
  initializeEnemies();

  // Update enemies every 16ms (~60fps)
  setInterval(updateEnemies, 16);

  // Broadcast enemy updates every 100ms
  setInterval(() => {
    if (enemies.size > 0) {
      const enemyArray = Array.from(enemies.values()).map(enemy => ({
        id: enemy.id,
        x: enemy.x,
        y: enemy.y,
        spriteType: enemy.spriteType,
        maxHp: enemy.maxHp,
        currentHp: enemy.currentHp,
        isMoving: enemy.isMoving,
        moveDirectionX: enemy.moveDirectionX,
        moveDirectionY: enemy.moveDirectionY,
        lastRotationAngle: enemy.lastRotationAngle,
      }));
      io.emit('enemies:update', enemyArray);
    }
  }, 100);
  io.on('connection', (socket: Socket) => {
    console.log(`Client connected: ${socket.id}`);

    socket.emit('game:players', Array.from(players.values()));
    
    // Send current enemy state to newly connected client
    console.log(`Client ${socket.id} connected. Current enemies count: ${enemies.size}`);
    if (enemies.size > 0) {
      const enemyArray = Array.from(enemies.values()).map(enemy => ({
        id: enemy.id,
        x: enemy.x,
        y: enemy.y,
        spriteType: enemy.spriteType,
        maxHp: enemy.maxHp,
        currentHp: enemy.currentHp,
        isMoving: enemy.isMoving,
        moveDirectionX: enemy.moveDirectionX,
        moveDirectionY: enemy.moveDirectionY,
        lastRotationAngle: enemy.lastRotationAngle,
      }));
      socket.emit('enemies:update', enemyArray);
      console.log(`Sent ${enemyArray.length} enemies to client ${socket.id}`);
    } else {
      console.log(`WARNING: No enemies to send to client ${socket.id}!`);
    }

    socket.on('game:requestPlayers', () => {
      socket.emit('game:players', Array.from(players.values()));
    });

    socket.on('game:requestEnemies', () => {
      console.log(`Client ${socket.id} requested enemies. Current count: ${enemies.size}`);
      if (enemies.size > 0) {
        const enemyArray = Array.from(enemies.values()).map(enemy => ({
          id: enemy.id,
          x: enemy.x,
          y: enemy.y,
          spriteType: enemy.spriteType,
          maxHp: enemy.maxHp,
          currentHp: enemy.currentHp,
          isMoving: enemy.isMoving,
          moveDirectionX: enemy.moveDirectionX,
          moveDirectionY: enemy.moveDirectionY,
          lastRotationAngle: enemy.lastRotationAngle,
        }));
        socket.emit('enemies:update', enemyArray);
        console.log(`Sent ${enemyArray.length} enemies to client ${socket.id} (requested)`);
      } else {
        console.log(`WARNING: No enemies to send to client ${socket.id} (requested)!`);
      }
    });

    socket.on(
      'player:join',
      (data: { characterId: string; name: string; spriteType?: string; x?: number; y?: number }) => {
        const characterId = data.characterId;
        const existingPlayer = players.get(characterId);

        if (existingPlayer) {
          socketToCharacter.delete(existingPlayer.socketId);
          existingPlayer.socketId = socket.id;
          if (data.x != null) existingPlayer.x = data.x;
          if (data.y != null) existingPlayer.y = data.y;
          if (data.spriteType != null) existingPlayer.spriteType = data.spriteType;
          socketToCharacter.set(socket.id, characterId);
        } else {
          const player: Player = {
            id: characterId,
            socketId: socket.id,
            name: data.name,
            spriteType: data.spriteType,
            x: data.x ?? 0,
            y: data.y ?? 0,
          };

          players.set(characterId, player);
          socketToCharacter.set(socket.id, characterId);
          socket.broadcast.emit('player:joined', player);
        }

        socket.emit(
          'game:players',
          Array.from(players.values()).filter((p) => p.id !== characterId)
        );
      }
    );

    socket.on('player:move', (data: { x: number; y: number }) => {
      const characterId = socketToCharacter.get(socket.id);
      if (!characterId) return;
      const player = players.get(characterId);
      if (!player) return;

      player.x = data.x;
      player.y = data.y;
      io.emit('player:moved', { id: player.id, x: player.x, y: player.y });
    });

    socket.on('chat:message', (data: { message: string }) => {
      const characterId = socketToCharacter.get(socket.id);
      if (!characterId) return;
      const player = players.get(characterId);
      if (!player) return;

      io.emit('chat:broadcast', {
        playerId: player.id,
        playerName: player.name,
        message: data.message,
        timestamp: new Date().toISOString(),
      });
    });

    // Handle projectile damage
    socket.on('projectile:damage', (data: { enemyId: string; damage: number; playerId: string }) => {
      const enemy = enemies.get(data.enemyId);
      if (!enemy) {
        console.log(`Enemy ${data.enemyId} not found for damage`);
        return;
      }

      const wasAlive = enemy.currentHp > 0;
      enemy.currentHp = Math.max(0, enemy.currentHp - data.damage);

      // Broadcast enemy HP update to all clients
      io.emit('enemy:damaged', {
        enemyId: enemy.id,
        currentHp: enemy.currentHp,
        maxHp: enemy.maxHp,
      });

      // If enemy dies, remove it and broadcast
      if (wasAlive && enemy.currentHp <= 0) {
        enemies.delete(enemy.id);
        io.emit('enemy:death', {
          enemyId: enemy.id,
          x: enemy.x,
          y: enemy.y,
          playerId: data.playerId,
        });
        console.log(`Enemy ${enemy.id} killed by player ${data.playerId}`);
      }
    });

    socket.on('disconnect', () => {
      const characterId = socketToCharacter.get(socket.id);
      if (!characterId) return;

      const player = players.get(characterId);
      if (player && player.socketId === socket.id) {
        players.delete(characterId);
        socket.broadcast.emit('player:left', { id: player.id });
      }
      socketToCharacter.delete(socket.id);
    });
  });
}



