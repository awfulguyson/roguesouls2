import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/app_config.dart';

class GameService {
  // Singleton pattern - only one connection across all screens
  static final GameService _instance = GameService._internal();
  factory GameService() => _instance;
  GameService._internal();

  IO.Socket? socket;
  // Support multiple listeners for each event
  final List<Function(Map<String, dynamic>)> _onPlayerJoinedListeners = [];
  final List<Function(Map<String, dynamic>)> _onPlayerMovedListeners = [];
  final List<Function(Map<String, dynamic>)> _onPlayerLeftListeners = [];
  final List<Function(Map<String, dynamic>)> _onChatMessageListeners = [];
  final List<Function(List<dynamic>)> _onPlayersListListeners = [];
  
  // Add callback methods (for multiple listeners)
  void addPlayerJoinedListener(Function(Map<String, dynamic>) callback) {
    if (!_onPlayerJoinedListeners.contains(callback)) {
      _onPlayerJoinedListeners.add(callback);
    }
  }
  
  void addPlayerMovedListener(Function(Map<String, dynamic>) callback) {
    if (!_onPlayerMovedListeners.contains(callback)) {
      _onPlayerMovedListeners.add(callback);
    }
  }
  
  void addPlayerLeftListener(Function(Map<String, dynamic>) callback) {
    if (!_onPlayerLeftListeners.contains(callback)) {
      _onPlayerLeftListeners.add(callback);
    }
  }
  
  void addChatMessageListener(Function(Map<String, dynamic>) callback) {
    if (!_onChatMessageListeners.contains(callback)) {
      _onChatMessageListeners.add(callback);
    }
  }
  
  void addPlayersListListener(Function(List<dynamic>) callback) {
    if (!_onPlayersListListeners.contains(callback)) {
      _onPlayersListListeners.add(callback);
    }
  }
  
  // Legacy single-callback support (for backward compatibility - clears and sets)
  Function(Map<String, dynamic>)? get onPlayerJoined => _onPlayerJoinedListeners.isNotEmpty ? _onPlayerJoinedListeners.first : null;
  set onPlayerJoined(Function(Map<String, dynamic>)? callback) {
    _onPlayerJoinedListeners.clear();
    if (callback != null) _onPlayerJoinedListeners.add(callback);
  }
  
  Function(Map<String, dynamic>)? get onPlayerMoved => _onPlayerMovedListeners.isNotEmpty ? _onPlayerMovedListeners.first : null;
  set onPlayerMoved(Function(Map<String, dynamic>)? callback) {
    _onPlayerMovedListeners.clear();
    if (callback != null) _onPlayerMovedListeners.add(callback);
  }
  
  Function(Map<String, dynamic>)? get onPlayerLeft => _onPlayerLeftListeners.isNotEmpty ? _onPlayerLeftListeners.first : null;
  set onPlayerLeft(Function(Map<String, dynamic>)? callback) {
    _onPlayerLeftListeners.clear();
    if (callback != null) _onPlayerLeftListeners.add(callback);
  }
  
  Function(Map<String, dynamic>)? get onChatMessage => _onChatMessageListeners.isNotEmpty ? _onChatMessageListeners.first : null;
  set onChatMessage(Function(Map<String, dynamic>)? callback) {
    _onChatMessageListeners.clear();
    if (callback != null) _onChatMessageListeners.add(callback);
  }
  
  Function(List<dynamic>)? get onPlayersList => _onPlayersListListeners.isNotEmpty ? _onPlayersListListeners.first : null;
  set onPlayersList(Function(List<dynamic>)? callback) {
    _onPlayersListListeners.clear();
    if (callback != null) _onPlayersListListeners.add(callback);
  }
  
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
      for (var listener in _onPlayersListListeners) {
        listener(data as List<dynamic>);
      }
    });

    socket!.on('player:joined', (data) {
      print('Received player:joined: ${data['name']} (${data['id']})');
      for (var listener in _onPlayerJoinedListeners) {
        listener(data as Map<String, dynamic>);
      }
    });

    socket!.on('player:moved', (data) {
      // Player movement event received
      for (var listener in _onPlayerMovedListeners) {
        listener(data as Map<String, dynamic>);
      }
    });

    socket!.on('player:left', (data) {
      for (var listener in _onPlayerLeftListeners) {
        listener(data as Map<String, dynamic>);
      }
    });

    socket!.on('chat:broadcast', (data) {
      for (var listener in _onChatMessageListeners) {
        listener(data as Map<String, dynamic>);
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
  
  // Method to remove a specific callback (for cleanup when screen disposes)
  void removeCallback({
    Function(Map<String, dynamic>)? onPlayerJoined,
    Function(Map<String, dynamic>)? onPlayerMoved,
    Function(Map<String, dynamic>)? onPlayerLeft,
    Function(Map<String, dynamic>)? onChatMessage,
    Function(List<dynamic>)? onPlayersList,
  }) {
    if (onPlayerJoined != null) _onPlayerJoinedListeners.remove(onPlayerJoined);
    if (onPlayerMoved != null) _onPlayerMovedListeners.remove(onPlayerMoved);
    if (onPlayerLeft != null) _onPlayerLeftListeners.remove(onPlayerLeft);
    if (onChatMessage != null) _onChatMessageListeners.remove(onChatMessage);
    if (onPlayersList != null) _onPlayersListListeners.remove(onPlayersList);
  }
  
  // Method to clean up all callbacks without disconnecting
  void clearCallbacks() {
    _onPlayerJoinedListeners.clear();
    _onPlayerMovedListeners.clear();
    _onPlayerLeftListeners.clear();
    _onChatMessageListeners.clear();
    _onPlayersListListeners.clear();
  }
}

