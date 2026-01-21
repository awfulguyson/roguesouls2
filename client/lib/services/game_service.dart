import 'dart:async';
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
  final List<Function(List<dynamic>)> _onEnemiesUpdateListeners = [];
  final List<Function(Map<String, dynamic>)> _onEnemyDamagedListeners = [];
  final List<Function(Map<String, dynamic>)> _onEnemyDeathListeners = [];
  final List<Function(Map<String, dynamic>)> _onProjectileSpawnListeners = [];
  final List<Function(Map<String, dynamic>)> _onPlayerDamagedListeners = [];
  final List<Function(Map<String, dynamic>)> _onPlayerDeathListeners = [];
  
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
  
  void addEnemiesUpdateListener(Function(List<dynamic>) callback) {
    if (!_onEnemiesUpdateListeners.contains(callback)) {
      _onEnemiesUpdateListeners.add(callback);
    }
  }
  
  void addEnemyDamagedListener(Function(Map<String, dynamic>) callback) {
    if (!_onEnemyDamagedListeners.contains(callback)) {
      _onEnemyDamagedListeners.add(callback);
    }
  }
  
  void addEnemyDeathListener(Function(Map<String, dynamic>) callback) {
    if (!_onEnemyDeathListeners.contains(callback)) {
      _onEnemyDeathListeners.add(callback);
    }
  }
  
  void addProjectileSpawnListener(Function(Map<String, dynamic>) callback) {
    if (!_onProjectileSpawnListeners.contains(callback)) {
      _onProjectileSpawnListeners.add(callback);
    }
  }
  
  void addPlayerDamagedListener(Function(Map<String, dynamic>) callback) {
    if (!_onPlayerDamagedListeners.contains(callback)) {
      _onPlayerDamagedListeners.add(callback);
    }
  }
  
  void addPlayerDeathListener(Function(Map<String, dynamic>) callback) {
    if (!_onPlayerDeathListeners.contains(callback)) {
      _onPlayerDeathListeners.add(callback);
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
  Timer? _reconnectTimer;
  Timer? _keepaliveTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 3);
  static const Duration _keepaliveInterval = Duration(seconds: 30);

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
      'reconnection': true,
      'reconnectionAttempts': _maxReconnectAttempts,
      'reconnectionDelay': _reconnectDelay.inMilliseconds,
      'reconnectionDelayMax': _reconnectDelay.inMilliseconds * 2,
    });

    socket!.connect();
    print('Socket connect() called, waiting for connection...');

    socket!.on('connect', (_) {
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      print('✅ Connected to game server: ${socket!.id}');
      // Request current players list
      socket!.emit('game:requestPlayers');
      
      // Start keepalive timer
      _startKeepalive();
      
      // Cancel any pending reconnection attempts
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    });

    socket!.on('disconnect', (reason) {
      _isConnected = false;
      _isConnecting = false;
      print('❌ Disconnected from game server: $reason');
      _stopKeepalive();
      
      // Attempt to reconnect if not explicitly disconnected
      if (reason != 'io client disconnect') {
        _scheduleReconnect();
      }
    });

    socket!.on('error', (error) {
      print('❌ Socket error: $error');
      _isConnected = false;
      _isConnecting = false;
      _stopKeepalive();
      
      // Attempt to reconnect on error
      if (socket != null && !socket!.connected) {
        _scheduleReconnect();
      }
    });
    
    // Handle reconnection events
    socket!.on('reconnect', (attemptNumber) {
      print('🔄 Reconnected after $attemptNumber attempts');
      _reconnectAttempts = 0;
    });
    
    socket!.on('reconnect_attempt', (attemptNumber) {
      print('🔄 Reconnection attempt $attemptNumber');
      _reconnectAttempts = attemptNumber;
    });
    
    socket!.on('reconnect_failed', (_) {
      print('❌ Reconnection failed after $_maxReconnectAttempts attempts');
      _reconnectAttempts = 0;
    });

    socket!.on('game:players', (data) {
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

    socket!.on('enemies:update', (data) {
      for (var listener in _onEnemiesUpdateListeners) {
        listener(data as List<dynamic>);
      }
    });

    socket!.on('enemy:damaged', (data) {
      for (var listener in _onEnemyDamagedListeners) {
        listener(data as Map<String, dynamic>);
      }
    });

    socket!.on('enemy:death', (data) {
      for (var listener in _onEnemyDeathListeners) {
        listener(data as Map<String, dynamic>);
      }
    });

    socket!.on('projectile:spawn', (data) {
      for (var listener in _onProjectileSpawnListeners) {
        listener(data as Map<String, dynamic>);
      }
    });

    socket!.on('player:damaged', (data) {
      // Broadcast to all listeners (handled in game_world_screen)
      for (var listener in _onPlayerDamagedListeners) {
        listener(data as Map<String, dynamic>);
      }
    });

    socket!.on('player:death', (data) {
      // Broadcast to all listeners (handled in game_world_screen)
      for (var listener in _onPlayerDeathListeners) {
        listener(data as Map<String, dynamic>);
      }
    });
  }

  void joinGame(String characterId, String name, {String? spriteType, double? x, double? y, String? accountId}) {
    print('Joining game: characterId=$characterId, name=$name, x=$x, y=$y');
    socket?.emit('player:join', {
      'characterId': characterId,
      'name': name,
      'spriteType': spriteType,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (accountId != null) 'accountId': accountId,
    });
    print('player:join event emitted');
  }

  void movePlayer(double x, double y) {
    socket?.emit('player:move', {'x': x, 'y': y});
  }

  void sendChatMessage(String message) {
    socket?.emit('chat:message', {'message': message});
  }

  void sendProjectileDamage(String enemyId, double damage, String playerId) {
    socket?.emit('projectile:damage', {
      'enemyId': enemyId,
      'damage': damage,
      'playerId': playerId,
    });
  }

  void sendProjectileCreate(String projectileId, double x, double y, double targetX, double targetY, double speed, String playerId) {
    socket?.emit('projectile:create', {
      'id': projectileId,
      'x': x,
      'y': y,
      'targetX': targetX,
      'targetY': targetY,
      'speed': speed,
      'playerId': playerId,
    });
  }

  void _startKeepalive() {
    _stopKeepalive(); // Stop any existing keepalive
    _keepaliveTimer = Timer.periodic(_keepaliveInterval, (timer) {
      if (socket != null && socket!.connected) {
        // Send a ping/keepalive by requesting player list (lightweight operation)
        socket!.emit('game:requestPlayers');
      } else {
        // Connection lost, stop keepalive and attempt reconnect
        _stopKeepalive();
        if (socket != null) {
          _scheduleReconnect();
        }
      }
    });
  }
  
  void _stopKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
  }
  
  void _scheduleReconnect() {
    // Don't schedule if already scheduled or connecting
    if (_reconnectTimer != null || _isConnecting) {
      return;
    }
    
    // Don't reconnect if we've exceeded max attempts
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('Max reconnection attempts reached, stopping reconnection');
      return;
    }
    
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (socket != null && !socket!.connected && !_isConnecting) {
        print('🔄 Attempting to reconnect...');
        _reconnectAttempts++;
        socket!.connect();
      }
      _reconnectTimer = null;
    });
  }

  void disconnect() {
    // Only disconnect if explicitly requested (e.g., logging out)
    // Don't disconnect on screen navigation
    _stopKeepalive();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    socket?.disconnect();
    socket = null;
    _isConnected = false;
    _isConnecting = false;
    _reconnectAttempts = 0;
  }
  
  // Method to remove a specific callback (for cleanup when screen disposes)
  void removeCallback({
    Function(Map<String, dynamic>)? onPlayerJoined,
    Function(Map<String, dynamic>)? onPlayerMoved,
    Function(Map<String, dynamic>)? onPlayerLeft,
    Function(Map<String, dynamic>)? onChatMessage,
    Function(List<dynamic>)? onPlayersList,
    Function(List<dynamic>)? onEnemiesUpdate,
    Function(Map<String, dynamic>)? onEnemyDamaged,
    Function(Map<String, dynamic>)? onEnemyDeath,
  }) {
    if (onPlayerJoined != null) _onPlayerJoinedListeners.remove(onPlayerJoined);
    if (onPlayerMoved != null) _onPlayerMovedListeners.remove(onPlayerMoved);
    if (onPlayerLeft != null) _onPlayerLeftListeners.remove(onPlayerLeft);
    if (onChatMessage != null) _onChatMessageListeners.remove(onChatMessage);
    if (onPlayersList != null) _onPlayersListListeners.remove(onPlayersList);
    if (onEnemiesUpdate != null) _onEnemiesUpdateListeners.remove(onEnemiesUpdate);
    if (onEnemyDamaged != null) _onEnemyDamagedListeners.remove(onEnemyDamaged);
    if (onEnemyDeath != null) _onEnemyDeathListeners.remove(onEnemyDeath);
    // Note: projectile spawn, player damaged, and player death listeners cleanup would go here if needed
  }
  
  // Method to clean up all callbacks without disconnecting
  void clearCallbacks() {
    _onPlayerJoinedListeners.clear();
    _onPlayerMovedListeners.clear();
    _onPlayerLeftListeners.clear();
    _onChatMessageListeners.clear();
    _onPlayersListListeners.clear();
    _onEnemiesUpdateListeners.clear();
    _onEnemyDamagedListeners.clear();
    _onEnemyDeathListeners.clear();
    _onProjectileSpawnListeners.clear();
    _onPlayerDamagedListeners.clear();
    _onPlayerDeathListeners.clear();
  }
}

