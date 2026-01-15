import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/app_config.dart';

class GameService {
  // Singleton pattern - only one connection across all screens
  static final GameService _instance = GameService._internal();
  factory GameService() => _instance;
  GameService._internal();

  IO.Socket? socket;
  Function(Map<String, dynamic>)? onPlayerJoined;
  Function(Map<String, dynamic>)? onPlayerMoved;
  Function(Map<String, dynamic>)? onPlayerLeft;
  Function(Map<String, dynamic>)? onChatMessage;
  Function(List<dynamic>)? onPlayersList;
  bool _isConnected = false;
  bool _isConnecting = false;

  void connect() {
    // Don't create a new connection if already connected or connecting
    if (socket != null && (socket!.connected || _isConnecting)) {
      print('WebSocket already connected or connecting, reusing existing connection');
      return;
    }
    
    _isConnecting = true;
    print('Connecting to WebSocket: ${AppConfig.websocketUrl}');
    socket = IO.io(AppConfig.websocketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket!.connect();
    print('Socket connect() called, waiting for connection...');

    socket!.on('connect', (_) {
      _isConnected = true;
      _isConnecting = false;
      print('✅ Connected to game server: ${socket!.id}');
      // Request current players list
      socket!.emit('game:requestPlayers');
    });

    socket!.on('disconnect', (_) {
      _isConnected = false;
      _isConnecting = false;
      print('❌ Disconnected from game server');
    });

    socket!.on('error', (error) {
      print('❌ Socket error: $error');
    });

    socket!.on('game:players', (data) {
      print('Received game:players: ${data.length} players');
      if (onPlayersList != null) {
        onPlayersList!(data as List<dynamic>);
      }
    });

    socket!.on('player:joined', (data) {
      print('Received player:joined: ${data['name']} (${data['id']})');
      if (onPlayerJoined != null) {
        onPlayerJoined!(data as Map<String, dynamic>);
      }
    });

    socket!.on('player:moved', (data) {
      if (onPlayerMoved != null) {
        onPlayerMoved!(data as Map<String, dynamic>);
      }
    });

    socket!.on('player:left', (data) {
      if (onPlayerLeft != null) {
        onPlayerLeft!(data as Map<String, dynamic>);
      }
    });

    socket!.on('chat:broadcast', (data) {
      if (onChatMessage != null) {
        onChatMessage!(data as Map<String, dynamic>);
      }
    });
  }

  void joinGame(String characterId, String name, {String? spriteType, double? x, double? y}) {
    print('Joining game: characterId=$characterId, name=$name, x=$x, y=$y');
    socket?.emit('player:join', {
      'characterId': characterId,
      'name': name,
      'spriteType': spriteType,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
    });
    print('player:join event emitted');
  }

  void movePlayer(double x, double y) {
    socket?.emit('player:move', {'x': x, 'y': y});
  }

  void sendChatMessage(String message) {
    socket?.emit('chat:message', {'message': message});
  }

  void disconnect() {
    // Only disconnect if explicitly requested (e.g., logging out)
    // Don't disconnect on screen navigation
    socket?.disconnect();
    socket = null;
    _isConnected = false;
    _isConnecting = false;
  }
  
  // Method to clean up callbacks without disconnecting
  void clearCallbacks() {
    onPlayerJoined = null;
    onPlayerMoved = null;
    onPlayerLeft = null;
    onChatMessage = null;
    onPlayersList = null;
  }
}

