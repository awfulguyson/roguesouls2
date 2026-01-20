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
const socketToCharacter: Map<string, string> = new Map();

export function setupSocketIO(io: Server) {
  io.on('connection', (socket: Socket) => {
    console.log(`Client connected: ${socket.id}`);

    socket.emit('game:players', Array.from(players.values()));

    socket.on('game:requestPlayers', () => {
      socket.emit('game:players', Array.from(players.values()));
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
