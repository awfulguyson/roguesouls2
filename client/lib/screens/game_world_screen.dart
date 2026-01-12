import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/game_service.dart';
import '../models/player.dart';

class GameWorldScreen extends StatefulWidget {
  final String characterId;
  final String characterName;

  const GameWorldScreen({
    super.key,
    required this.characterId,
    required this.characterName,
  });

  @override
  State<GameWorldScreen> createState() => _GameWorldScreenState();
}

class _GameWorldScreenState extends State<GameWorldScreen> {
  final GameService _gameService = GameService();
  final Map<String, Player> _players = {};
  double _playerX = 400;
  double _playerY = 300;
  final double _playerSpeed = 5.0;
  final double _playerSize = 40.0;
  Timer? _positionUpdateTimer;
  Timer? _movementTimer;
  double _lastSentX = 400;
  double _lastSentY = 300;
  final Set<LogicalKeyboardKey> _pressedKeys = {};

  @override
  void initState() {
    super.initState();
    _setupGameService();
    _gameService.connect();
    
    // Join game after a short delay to ensure connection
    Future.delayed(const Duration(milliseconds: 500), () {
      _gameService.joinGame(widget.characterId, widget.characterName);
      // Send initial position immediately
      _gameService.movePlayer(_playerX, _playerY);
      _lastSentX = _playerX;
      _lastSentY = _playerY;
    });
    
    // Game loop: check pressed keys and move player continuously (60 FPS)
    _movementTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      _updateMovement();
    });
    
    // Send position updates periodically (every 100ms) to keep other players synced
    _positionUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      // Only send if position changed significantly (reduces network traffic)
      final dx = (_playerX - _lastSentX).abs();
      final dy = (_playerY - _lastSentY).abs();
      
      if (dx > 1 || dy > 1) {
        _gameService.movePlayer(_playerX, _playerY);
        _lastSentX = _playerX;
        _lastSentY = _playerY;
      }
    });
  }

  void _setupGameService() {
    _gameService.onPlayersList = (players) {
      setState(() {
        _players.clear();
        for (var playerData in players) {
          final player = Player.fromJson(playerData as Map<String, dynamic>);
          // Don't add yourself to the other players list
          if (player.id != widget.characterId) {
            _players[player.id] = player;
          }
        }
      });
    };

    _gameService.onPlayerJoined = (data) {
      setState(() {
        final player = Player.fromJson(data);
        // Don't add yourself to the other players list
        if (player.id != widget.characterId) {
          _players[player.id] = player;
        }
      });
    };

    _gameService.onPlayerMoved = (data) {
      setState(() {
        final playerId = data['id'] as String;
        if (_players.containsKey(playerId)) {
          _players[playerId]!.x = (data['x'] as num).toDouble();
          _players[playerId]!.y = (data['y'] as num).toDouble();
        }
      });
    };

    _gameService.onPlayerLeft = (data) {
      setState(() {
        _players.remove(data['id'] as String);
      });
    };
  }

  void _updateMovement() {
    if (_pressedKeys.isEmpty) return;
    
    double deltaX = 0;
    double deltaY = 0;
    
    // Check which keys are pressed and calculate movement
    if (_pressedKeys.contains(LogicalKeyboardKey.arrowLeft) ||
        _pressedKeys.contains(LogicalKeyboardKey.keyA)) {
      deltaX -= _playerSpeed;
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.arrowRight) ||
        _pressedKeys.contains(LogicalKeyboardKey.keyD)) {
      deltaX += _playerSpeed;
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.arrowUp) ||
        _pressedKeys.contains(LogicalKeyboardKey.keyW)) {
      deltaY -= _playerSpeed;
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.arrowDown) ||
        _pressedKeys.contains(LogicalKeyboardKey.keyS)) {
      deltaY += _playerSpeed;
    }
    
    // Normalize diagonal movement (so diagonal speed equals horizontal/vertical speed)
    if (deltaX != 0 && deltaY != 0) {
      final length = sqrt(deltaX * deltaX + deltaY * deltaY);
      deltaX = (deltaX / length) * _playerSpeed;
      deltaY = (deltaY / length) * _playerSpeed;
    }
    
    if (deltaX != 0 || deltaY != 0) {
      setState(() {
        _playerX += deltaX;
        _playerY += deltaY;
        
        // Keep player in bounds (adjust based on your world size)
        _playerX = _playerX.clamp(0.0, 800.0 - _playerSize);
        _playerY = _playerY.clamp(0.0, 600.0 - _playerSize);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        final key = event.logicalKey;
        
        // Track key presses/releases for continuous movement
        if (event is KeyDownEvent) {
          if (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.keyA ||
              key == LogicalKeyboardKey.arrowRight ||
              key == LogicalKeyboardKey.keyD ||
              key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.keyW ||
              key == LogicalKeyboardKey.arrowDown ||
              key == LogicalKeyboardKey.keyS) {
            _pressedKeys.add(key);
          }
        } else if (event is KeyUpEvent) {
          _pressedKeys.remove(key);
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Game world background
            Container(
              color: Colors.green[100],
              child: CustomPaint(
                painter: GameWorldPainter(_players, _playerX, _playerY, widget.characterId),
                size: Size.infinite,
              ),
            ),
            // UI overlay
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black54,
                child: Text(
                  'Players: ${_players.length + 1}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black54,
                child: const Text(
                  'Use WASD or Arrow Keys to move',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _movementTimer?.cancel();
    _positionUpdateTimer?.cancel();
    _gameService.disconnect();
    super.dispose();
  }
}

class GameWorldPainter extends CustomPainter {
  final Map<String, Player> players;
  final double playerX;
  final double playerY;
  final String currentPlayerId;

  GameWorldPainter(this.players, this.playerX, this.playerY, this.currentPlayerId);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw other players
    for (var player in players.values) {
      if (player.id != currentPlayerId) {
        final paint = Paint()..color = Colors.blue;
        canvas.drawRect(
          Rect.fromLTWH(player.x, player.y, 40, 40),
          paint,
        );
        
        // Draw player name
        final textPainter = TextPainter(
          text: TextSpan(
            text: player.name,
            style: const TextStyle(color: Colors.black, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(player.x, player.y - 16));
      }
    }

    // Draw current player (on top)
    final currentPlayerPaint = Paint()..color = Colors.red;
    canvas.drawRect(
      Rect.fromLTWH(playerX, playerY, 40, 40),
      currentPlayerPaint,
    );
    
    // Draw current player name
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'You',
        style: const TextStyle(color: Colors.black, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(playerX, playerY - 16));
  }

  @override
  bool shouldRepaint(GameWorldPainter oldDelegate) {
    return oldDelegate.playerX != playerX ||
        oldDelegate.playerY != playerY ||
        oldDelegate.players.length != players.length;
  }
}

