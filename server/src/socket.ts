import { Server, Socket } from 'socket.io';

interface Player {
  id: string;
  socketId: string;
  name: string;
  spriteType?: string;
  x: number;
  y: number;
}

const players: Map<string, Player> = new Map();

export function setupSocketIO(io: Server) {
  io.on('connection', (socket: Socket) => {
    console.log(`Client connected: ${socket.id}`);

    // Player joins game
    socket.on('player:join', (data: { characterId: string; name: string; spriteType?: string }) => {
      const player: Player = {
        id: data.characterId,
        socketId: socket.id,
        name: data.name,
        spriteType: data.spriteType,
        x: 0,
        y: 0
      };
      
      players.set(socket.id, player);
      
      // Send current players to new player
      socket.emit('game:players', Array.from(players.values()));
      
      // Notify others about new player
      socket.broadcast.emit('player:joined', player);
      
      console.log(`Player joined: ${data.name} (${socket.id})`);
    });

    // Player movement
    socket.on('player:move', (data: { x: number; y: number }) => {
      const player = players.get(socket.id);
      if (player) {
        player.x = data.x;
        player.y = data.y;
        
        // Broadcast movement to all other players
        socket.broadcast.emit('player:moved', {
          id: player.id,
          x: data.x,
          y: data.y
        });
      }
    });

    // Chat message
    socket.on('chat:message', (data: { message: string }) => {
      const player = players.get(socket.id);
      if (player) {
        io.emit('chat:broadcast', {
          playerId: player.id,
          playerName: player.name,
          message: data.message,
          timestamp: new Date().toISOString()
        });
      }
    });

    // Player disconnects
    socket.on('disconnect', () => {
      const player = players.get(socket.id);
      if (player) {
        players.delete(socket.id);
        socket.broadcast.emit('player:left', { id: player.id });
        console.log(`Player left: ${player.name} (${socket.id})`);
      }
    });
  });
}

