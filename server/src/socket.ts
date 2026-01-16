import { Server, Socket } from 'socket.io';

interface Player {
  id: string;
  socketId: string;
  name: string;
  spriteType?: string;
  x: number;
  y: number;
}

// Store players by characterId (not socketId) so reconnections work
const players: Map<string, Player> = new Map();
// Map socketId to characterId for cleanup on disconnect
const socketToCharacter: Map<string, string> = new Map();

export function setupSocketIO(io: Server) {
  io.on('connection', (socket: Socket) => {
    console.log(`Client connected: ${socket.id}`);
    console.log(`Current players in server: ${players.size}`, Array.from(players.values()).map(p => `${p.name} (${p.id})`));
    
    // Send current players list to newly connected client (for viewing before joining)
    socket.emit('game:players', Array.from(players.values()));

    // Request current players list
    socket.on('game:requestPlayers', () => {
      socket.emit('game:players', Array.from(players.values()));
    });

    // Player joins game
    socket.on('player:join', (data: { characterId: string; name: string; spriteType?: string; x?: number; y?: number }) => {
      const characterId = data.characterId;
      
      // Check if this character is already in the game (reconnection)
      const existingPlayer = players.get(characterId);
      
      if (existingPlayer) {
        // Reconnection: update socketId but keep player data
        console.log(`Player reconnected: ${data.name} (${characterId}), old socket: ${existingPlayer.socketId}, new socket: ${socket.id}`);
        
        // Remove old socket mapping
        socketToCharacter.delete(existingPlayer.socketId);
        
        // Update player with new socket
        existingPlayer.socketId = socket.id;
        if (data.x != null) existingPlayer.x = data.x;
        if (data.y != null) existingPlayer.y = data.y;
        
        // Update socket mapping
        socketToCharacter.set(socket.id, characterId);
      } else {
        // New player joining
        const player: Player = {
          id: characterId,
          socketId: socket.id,
          name: data.name,
          spriteType: data.spriteType,
          x: data.x ?? 0,
          y: data.y ?? 0
        };
        
        players.set(characterId, player);
        socketToCharacter.set(socket.id, characterId);
        
        // Notify others about new player
        socket.broadcast.emit('player:joined', player);
        
        console.log(`Player joined: ${data.name} (${characterId}) at (${player.x}, ${player.y})`);
      }
      
      // Send current players to this player (excluding self)
      const otherPlayers = Array.from(players.values()).filter(p => p.id !== characterId);
      console.log(`Sending ${otherPlayers.length} other players to ${data.name}. Total players in server: ${players.size}`);
      console.log(`All players:`, Array.from(players.values()).map(p => `${p.name} (${p.id})`));
      socket.emit('game:players', otherPlayers);
      
      console.log(`Total players: ${players.size}`);
    });

    // Player movement
    socket.on('player:move', (data: { x: number; y: number }) => {
      const characterId = socketToCharacter.get(socket.id);
      if (characterId) {
        const player = players.get(characterId);
        if (player) {
          player.x = data.x;
          player.y = data.y;
          
          // Broadcast movement to ALL players (including sender for consistency)
          io.emit('player:moved', {
            id: player.id,
            x: data.x,
            y: data.y
          });
        } else {
          console.log(`Movement received but player not found: ${characterId}`);
        }
      } else {
        console.log(`Movement received but characterId not found for socket: ${socket.id}`);
      }
    });

    // Chat message
    socket.on('chat:message', (data: { message: string }) => {
      const characterId = socketToCharacter.get(socket.id);
      if (characterId) {
        const player = players.get(characterId);
        if (player) {
          io.emit('chat:broadcast', {
            playerId: player.id,
            playerName: player.name,
            message: data.message,
            timestamp: new Date().toISOString()
          });
        }
      }
    });

    // Player disconnects
    socket.on('disconnect', () => {
      const characterId = socketToCharacter.get(socket.id);
      if (characterId) {
        const player = players.get(characterId);
        if (player) {
          // Only remove player if this is their current socket (not a stale connection)
          if (player.socketId === socket.id) {
            players.delete(characterId);
            socket.broadcast.emit('player:left', { id: player.id });
            console.log(`Player left: ${player.name} (${characterId})`);
          } else {
            // Stale connection, just remove the mapping
            console.log(`Stale connection removed: ${socket.id} for ${characterId}`);
          }
        }
        socketToCharacter.delete(socket.id);
      }
    });
  });
}

