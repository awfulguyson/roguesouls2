import { Server, Socket } from 'socket.io';

interface Player {
  id: string;
  socketId: string;
  name: string;
  spriteType?: string;
  x: number;
  y: number;
  hp: number;
  maxHp: number;
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
  // Attack tracking
  damageDealtBy: Map<string, number>; // playerId -> total damage dealt
  targetPlayerId: string | null; // Player to attack
  lastAttackTime: number; // Last time enemy attacked
  isAttacking: boolean; // Whether enemy is currently attacking
}

const players: Map<string, Player> = new Map();
const socketToCharacter: Map<string, string> = new Map();
const enemies: Map<string, Enemy> = new Map();

let io: Server;

let enemyIdCounter = 1;
const maxEnemies = 50;

// Initialize enemies on server startup - start with 20, spawn more over time
function initializeEnemies() {
  enemies.clear();
  enemyIdCounter = 1;
  
  // Spawn initial 20 enemies within 1000 units of origin
  const enemyTypes = ['enemy-1', 'enemy-2', 'enemy-3', 'enemy-4', 'enemy-5'];
  
  for (let i = 1; i <= 20; i++) {
    spawnEnemy(enemyTypes);
  }
  
  // Spawn one enemy every 10 seconds until we reach maxEnemies
  setInterval(() => {
    if (enemies.size < maxEnemies) {
      spawnEnemy(enemyTypes);
    }
  }, 10000); // 10 seconds
}

function spawnEnemy(enemyTypes: string[]) {
  // Random position within -1000 to 1000 for both X and Y
  const x = (Math.random() * 2000) - 1000; // -1000 to 1000
  const y = (Math.random() * 2000) - 1000; // -1000 to 1000
  // Cycle through enemy types
  const spriteType = enemyTypes[(enemyIdCounter - 1) % enemyTypes.length];
  
  const enemyId = `enemy_${enemyIdCounter++}`;

  const maxHp = getHpForSpriteType(spriteType);
  // Randomize initial state - some start moving, some start paused
  const startMoving = Math.random() > 0.5;
  let moveDirectionX = 0;
  let moveDirectionY = 0;
  let lastStateChangeTime = Date.now();
  
  if (startMoving) {
    // Start moving in random direction
    const angle = Math.random() * 2 * Math.PI;
    moveDirectionX = Math.cos(angle);
    moveDirectionY = Math.sin(angle);
    // Randomize when they started (0 to 2000ms ago)
    lastStateChangeTime = Date.now() - (Math.random() * 2000);
  } else {
    // Start paused, randomize when they paused (0 to 3000ms ago)
    lastStateChangeTime = Date.now() - (Math.random() * 3000);
  }
  
  enemies.set(enemyId, {
    id: enemyId,
    x: x,
    y: y,
    spriteType: spriteType,
    maxHp: maxHp,
    currentHp: maxHp,
    moveDirectionX: moveDirectionX,
    moveDirectionY: moveDirectionY,
    isMoving: startMoving,
    lastStateChangeTime: lastStateChangeTime,
    lastRotationAngle: spriteType === 'enemy-5' ? Math.atan2(moveDirectionY, moveDirectionX) : 0,
    damageDealtBy: new Map(),
    targetPlayerId: null,
    lastAttackTime: 0,
    isAttacking: false,
  });
  
  // Broadcast new enemy to all clients
  if (io) {
    const enemy = enemies.get(enemyId);
    if (enemy) {
      io.emit('enemy:spawn', {
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
        isAttacking: enemy.isAttacking,
      });
    }
  }
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

// Update enemies periodically
function updateEnemies() {
  const now = Date.now();
  const moveSpeed = 1.0;
  const moveDuration = 2000; // 2 seconds moving
  const pauseDuration = 3000; // 3 seconds paused
  const attackRange = 64.0; // Attack range (half of player size)
  const attackCooldown = 500; // 0.5 seconds between attacks
  const attackDamage = 10.0;

  enemies.forEach((enemy, enemyId) => {
    if (!enemy.lastStateChangeTime) {
      enemy.lastStateChangeTime = now;
      return;
    }

    // Update target player based on damage dealt
    if (enemy.damageDealtBy.size > 0) {
      let maxDamage = 0;
      let topDamager: string | null = null;
      enemy.damageDealtBy.forEach((damage, playerId) => {
        if (damage > maxDamage) {
          maxDamage = damage;
          topDamager = playerId;
        }
      });
      enemy.targetPlayerId = topDamager;
    }

    // If enemy has a target, move towards them
    if (enemy.targetPlayerId) {
      const targetPlayer = players.get(enemy.targetPlayerId);
      if (targetPlayer && targetPlayer.hp > 0) {
        const dx = targetPlayer.x - enemy.x;
        const dy = targetPlayer.y - enemy.y;
        const distance = Math.sqrt(dx * dx + dy * dy);

        // Check if in attack range
        if (distance <= attackRange) {
          // Attack the player
          enemy.isMoving = false;
          enemy.moveDirectionX = 0;
          enemy.moveDirectionY = 0;
          enemy.isAttacking = true;

          // Deal damage every 0.5 seconds
          if (now - enemy.lastAttackTime >= attackCooldown) {
            targetPlayer.hp = Math.max(0, targetPlayer.hp - attackDamage);
            enemy.lastAttackTime = now;

            // Broadcast player HP update
            if (io) {
              io.emit('player:damaged', {
                playerId: targetPlayer.id,
                currentHp: targetPlayer.hp,
                maxHp: targetPlayer.maxHp,
                damage: attackDamage,
              });

              // Check if player died
              if (targetPlayer.hp <= 0) {
                io.emit('player:death', {
                  playerId: targetPlayer.id,
                });
              }
            }
          }
        } else {
          // Move towards target
          enemy.isAttacking = false;
          const normalizedDx = dx / distance;
          const normalizedDy = dy / distance;
          enemy.moveDirectionX = normalizedDx;
          enemy.moveDirectionY = normalizedDy;
          enemy.isMoving = true;
          
          // Move towards target
          enemy.x += enemy.moveDirectionX * moveSpeed;
          enemy.y += enemy.moveDirectionY * moveSpeed;

          // Update rotation angle for zombie enemies
          if (enemy.spriteType === 'enemy-5') {
            enemy.lastRotationAngle = Math.atan2(enemy.moveDirectionY, enemy.moveDirectionX);
          }
        }
      } else {
        // Target player is dead or doesn't exist, clear target
        enemy.targetPlayerId = null;
        enemy.isAttacking = false;
      }
    }

    // If no target, use random movement
    if (!enemy.targetPlayerId) {
      enemy.isAttacking = false;
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
        isAttacking: enemy.isAttacking,
      }));
      io.emit('enemies:update', enemyArray);
    }
  }, 100);
  io.on('connection', (socket: Socket) => {
    console.log(`Client connected: ${socket.id}`);

    socket.emit('game:players', Array.from(players.values()));
    
    // Send current enemy state to newly connected client
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
        isAttacking: enemy.isAttacking,
      }));
      socket.emit('enemies:update', enemyArray);
    }

    socket.on('game:requestPlayers', () => {
      socket.emit('game:players', Array.from(players.values()));
    });

    socket.on('game:requestEnemies', () => {
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
          isAttacking: enemy.isAttacking,
        }));
        socket.emit('enemies:update', enemyArray);
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
          // Ensure HP is initialized (for backwards compatibility with existing players)
          if (!existingPlayer.hp || existingPlayer.hp <= 0) {
            existingPlayer.hp = 100.0;
            existingPlayer.maxHp = 100.0;
          }
          socketToCharacter.set(socket.id, characterId);
        } else {
          const player: Player = {
            id: characterId,
            socketId: socket.id,
            name: data.name,
            spriteType: data.spriteType,
            x: data.x ?? 0,
            y: data.y ?? 0,
            hp: 100.0,
            maxHp: 100.0,
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

    // Handle projectile creation
    socket.on('projectile:create', (data: { id: string; x: number; y: number; targetX: number; targetY: number; speed: number; playerId: string }) => {
      // Broadcast projectile to all other clients
      socket.broadcast.emit('projectile:spawn', {
        id: data.id,
        x: data.x,
        y: data.y,
        targetX: data.targetX,
        targetY: data.targetY,
        speed: data.speed,
        playerId: data.playerId,
      });
    });

    // Handle projectile damage
    socket.on('projectile:damage', (data: { enemyId: string; damage: number; playerId: string }) => {
      const enemy = enemies.get(data.enemyId);
      if (!enemy) {
        return;
      }

      // Track damage dealt by this player
      const currentDamage = enemy.damageDealtBy.get(data.playerId) || 0;
      enemy.damageDealtBy.set(data.playerId, currentDamage + data.damage);

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



