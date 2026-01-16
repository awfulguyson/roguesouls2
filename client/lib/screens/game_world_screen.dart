import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/game_service.dart';
import '../services/api_service.dart';
import '../models/player.dart';
import '../widgets/virtual_joystick.dart';
import 'initial_screen.dart';

class GameWorldScreen extends StatefulWidget {
  final String? characterId;
  final String? characterName;
  final String? spriteType;
  final bool isTemporary;
  final String? accountId;

  const GameWorldScreen({
    super.key,
    this.characterId,
    this.characterName,
    this.spriteType,
    this.isTemporary = true,
    this.accountId,
  });

  @override
  State<GameWorldScreen> createState() => _GameWorldScreenState();
}

class _GameWorldScreenState extends State<GameWorldScreen> {
  final GameService _gameService = GameService();
  final ApiService _apiService = ApiService();
  final Map<String, Player> _players = {};
  final Map<String, Offset> _playerTargetPositions = {};
  final Map<String, DateTime> _playerLastUpdateTime = {};
  double _playerX = 0.0;
  double _playerY = 0.0;
  double _playerSpeed = 2.5;
  double _playerSize = 128.0;
  Timer? _positionUpdateTimer;
  Timer? _movementTimer;
  double _lastSentX = 0.0;
  double _lastSentY = 0.0;
  
  static const double _worldWidth = 10000.0;
  static const double _worldHeight = 10000.0;
  static const double _worldMinX = -5000.0;
  static const double _worldMaxX = 5000.0;
  static const double _worldMinY = -5000.0;
  static const double _worldMaxY = 5000.0;
  
  double _screenWidth = 800.0;
  double _screenHeight = 600.0;
  
  double _joystickDeltaX = 0.0;
  double _joystickDeltaY = 0.0;
  
  bool _isMobileDevice(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    
    final isSmallScreen = size.width < 768 || size.height < 768;
    final hasHighDensity = mediaQuery.devicePixelRatio > 1.5;
    final aspectRatio = size.width / size.height;
    final isPhoneAspectRatio = aspectRatio > 0.4 && aspectRatio < 3.0;
    
    if (size.width < 400 || size.height < 400) return true;
    if (size.width >= 1200 && size.height >= 800 && !hasHighDensity) return false;
    return (isSmallScreen && isPhoneAspectRatio) || (hasHighDensity && isPhoneAspectRatio);
  }
  
  double _worldToScreenX(double worldX) => worldX - _playerX + _screenWidth / 2;
  double _worldToScreenY(double worldY) => worldY - _playerY + _screenHeight / 2;
  
  double _screenToWorldX(double screenX) => screenX - _screenWidth / 2 + _playerX;
  double _screenToWorldY(double screenY) => screenY - _screenHeight / 2 + _playerY;
  final Set<LogicalKeyboardKey> _pressedKeys = {};
  PlayerDirection _playerDirection = PlayerDirection.down;
  PlayerDirection _lastVerticalDirection = PlayerDirection.down;
  ui.Image? _char1Sprite;
  ui.Image? _char2Sprite;
  ui.Image? _worldBackground;
  bool _showSettingsModal = false;
  bool _showCharacterCreateModal = false;
  String? _settingsView;
  String _joystickMode = 'fixed-right';
  Offset? _floatingJoystickPosition;
  bool _showFloatingJoystick = false;
  bool _showDevTools = false;
  Map<String, dynamic>? _selectedCharacter;
  String? _accountId;
  List<dynamic> _characters = [];
  bool _isInitialized = false;
  final FocusNode _keyboardFocusNode = FocusNode();
  String? _currentCharacterId;
  String? _currentCharacterName;
  String? _currentSpriteType;
  TextEditingController? _characterNameController;
  FocusNode? _characterNameFocusNode;
  String _selectedSpriteTypeForCreation = 'char-1';

  @override
  void initState() {
    super.initState();
    _currentCharacterId = widget.characterId;
    _currentCharacterName = widget.characterName;
    _currentSpriteType = widget.spriteType;
    
    _loadSprites();
    _setupGameService();
    _gameService.connect();
    _initializeAccount();
    
    _gameService.socket?.on('connect', (_) {
      print('Socket connected, requesting player list...');
      _gameService.socket?.emit('game:requestPlayers');
      
      if (_currentCharacterId != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _joinGameWithCharacter();
        });
      }
    });
    
    _gameService.socket?.on('reconnect', (_) {
      print('Socket reconnected, rejoining game...');
      _gameService.socket?.emit('game:requestPlayers');
      
      if (_currentCharacterId != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _joinGameWithCharacter();
        });
      }
    });
    
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (_currentCharacterId != null && _gameService.socket?.connected == true) {
        _joinGameWithCharacter();
      }
    });
    
    _movementTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      _updateMovement();
      _interpolateOtherPlayers();
    });
    
    _positionUpdateTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (_currentCharacterId == null) return;
      final dx = (_playerX - _lastSentX).abs();
      final dy = (_playerY - _lastSentY).abs();
      
      if (dx > 0.5 || dy > 0.5) {
        _gameService.movePlayer(_playerX, _playerY);
        _lastSentX = _playerX;
        _lastSentY = _playerY;
      }
    });
    
    if (_currentCharacterId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _showSettingsModal = true;
          _settingsView = null;
        });
        _refreshCharacters();
      });
    }
  }

  void _joinGameWithCharacter() {
    if (_currentCharacterId == null || _currentCharacterName == null) return;
    print('Joining game with character: $_currentCharacterId');
    _gameService.joinGame(
      _currentCharacterId!,
      _currentCharacterName!,
      spriteType: _currentSpriteType ?? 'char-1',
      x: _playerX,
      y: _playerY,
    );
    _lastSentX = _playerX;
    _lastSentY = _playerY;
  }

  Future<void> _initializeAccount() async {
    try {
      if (widget.accountId != null) {
        final accountId = widget.accountId!;
        final characters = await _apiService.getCharacters(accountId);
        if (mounted) {
          setState(() {
            _accountId = accountId;
            _characters = characters;
            _isInitialized = true;
          });
        }
      } else {
        final account = await _apiService.createTemporaryAccount();
        final accountId = account['id'] as String;
        final characters = await _apiService.getCharacters(accountId);
        
        if (mounted) {
          setState(() {
            _accountId = accountId;
            _characters = characters;
            _isInitialized = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    }
  }

  Future<void> _loadSprites() async {
    final char1Bytes = await rootBundle.load('assets/char-1.png');
    final char1Codec = await ui.instantiateImageCodec(char1Bytes.buffer.asUint8List());
    final char1Frame = await char1Codec.getNextFrame();
    _char1Sprite = char1Frame.image;

    final char2Bytes = await rootBundle.load('assets/char-2.png');
    final char2Codec = await ui.instantiateImageCodec(char2Bytes.buffer.asUint8List());
    final char2Frame = await char2Codec.getNextFrame();
    _char2Sprite = char2Frame.image;

    try {
      final worldBytes = await rootBundle.load('assets/world-img.jpg');
      final worldCodec = await ui.instantiateImageCodec(worldBytes.buffer.asUint8List());
      final worldFrame = await worldCodec.getNextFrame();
      _worldBackground = worldFrame.image;
      print('✅ World background loaded: ${_worldBackground!.width}x${_worldBackground!.height}');
    } catch (e) {
      print('❌ Failed to load world background: $e');
      _worldBackground = null;
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _setupGameService() {
    _playersListCallback = (players) {
      print('onPlayersList called with ${players.length} players, characterId: $_currentCharacterId');
      if (!mounted) {
        print('Skipping: not mounted');
        return;
      }
      setState(() {
        _players.clear();
        for (var playerData in players) {
          print('Processing player: $playerData');
          final player = Player.fromJson(playerData as Map<String, dynamic>);
          print('Parsed player: id=${player.id}, name=${player.name}, x=${player.x}, y=${player.y}');
          if (_currentCharacterId == null || player.id != _currentCharacterId) {
            print('Adding player to map: ${player.id}');
            _players[player.id] = player;
          } else {
            print('Skipping self: ${player.id}');
          }
        }
        print('Total players in map: ${_players.length}');
      });
    };
    _gameService.addPlayersListListener(_playersListCallback);

    _playerJoinedCallback = (data) {
      print('onPlayerJoined called: $data, characterId: $_currentCharacterId');
      if (!mounted) {
        print('Skipping: not mounted');
        return;
      }
      setState(() {
        final player = Player.fromJson(data);
        print('Parsed joined player: id=${player.id}, name=${player.name}');
        if (_currentCharacterId == null || player.id != _currentCharacterId) {
          print('Adding joined player to map: ${player.id}');
          _players[player.id] = player;
        } else {
          print('Skipping self (joined): ${player.id}');
        }
        print('Total players in map after join: ${_players.length}');
      });
    };
    _gameService.addPlayerJoinedListener(_playerJoinedCallback);

    _playerMovedCallback = (data) {
      if (!mounted) return;
      final playerId = data['id'] as String;
      if (_currentCharacterId != null && playerId == _currentCharacterId) {
        return;
      }
      
      final newX = (data['x'] as num).toDouble();
      final newY = (data['y'] as num).toDouble();
      print('Received player:moved event: $playerId at ($newX, $newY)');
      
      if (_players.containsKey(playerId)) {
        setState(() {
          final player = _players[playerId]!;
          final oldX = player.x;
          final oldY = player.y;
          
          final dx = newX - oldX;
          final dy = newY - oldY;
          
          // Update direction based on movement
          if (dy != 0) {
            player.direction = dy < 0 ? PlayerDirection.up : PlayerDirection.down;
          }
          
          // Set target for interpolation
          _playerTargetPositions[playerId] = Offset(newX, newY);
          _playerLastUpdateTime[playerId] = DateTime.now();
          
          // Always update position immediately to make movement visible
          // For large movements, jump closer immediately; for small movements, update fully
          final distance = sqrt(dx * dx + dy * dy);
          if (distance > 5.0) {
            // For large movements, jump closer immediately
            player.x = oldX + (dx * 0.5);
            player.y = oldY + (dy * 0.5);
          } else {
            // For small movements, update to target immediately to ensure visibility
            player.x = newX;
            player.y = newY;
            // Remove from interpolation since we're already at target
            _playerTargetPositions.remove(playerId);
          }
        });
      } else {
        setState(() {
          final player = Player.fromJson(data);
          player.x = newX;
          player.y = newY;
          _players[playerId] = player;
          _playerTargetPositions[playerId] = Offset(newX, newY);
          _playerLastUpdateTime[playerId] = DateTime.now();
        });
      }
    };
    _gameService.addPlayerMovedListener(_playerMovedCallback);

    _playerLeftCallback = (data) {
      if (!mounted) return;
      setState(() {
        _players.remove(data['id'] as String);
      });
    };
    _gameService.addPlayerLeftListener(_playerLeftCallback);
  }

  void _updateMovement() {
    if (_currentCharacterId == null) return;
    
    double deltaX = 0;
    double deltaY = 0;
    PlayerDirection? newVerticalDirection;
    
    final isUsingJoystick = _joystickDeltaX.abs() > 0.1 || _joystickDeltaY.abs() > 0.1;
    
    if (isUsingJoystick) {
      deltaX = _joystickDeltaX * _playerSpeed;
      deltaY = _joystickDeltaY * _playerSpeed;
      
      if (_joystickDeltaY.abs() > _joystickDeltaX.abs()) {
        newVerticalDirection = _joystickDeltaY < 0 ? PlayerDirection.up : PlayerDirection.down;
      } else if (_joystickDeltaX != 0) {
      }
    } else {
      if (_pressedKeys.isEmpty) return;
      
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
        newVerticalDirection = PlayerDirection.up;
      }
      if (_pressedKeys.contains(LogicalKeyboardKey.arrowDown) ||
          _pressedKeys.contains(LogicalKeyboardKey.keyS)) {
        deltaY += _playerSpeed;
        newVerticalDirection = PlayerDirection.down;
      }
    }
    
    if (deltaX != 0 && deltaY != 0) {
      final length = sqrt(deltaX * deltaX + deltaY * deltaY);
      deltaX = (deltaX / length) * _playerSpeed;
      deltaY = (deltaY / length) * _playerSpeed;
      if (newVerticalDirection == null) {
        newVerticalDirection = deltaY < 0 ? PlayerDirection.up : PlayerDirection.down;
      }
    }
    
    if (deltaX != 0 || deltaY != 0) {
      setState(() {
        _playerX += deltaX;
        _playerY += deltaY;
        
        if (newVerticalDirection != null) {
          _lastVerticalDirection = newVerticalDirection;
          _playerDirection = newVerticalDirection;
        } else if (deltaX != 0 && deltaY == 0) {
          _playerDirection = _lastVerticalDirection;
        }
        
        _playerX = _playerX.clamp(_worldMinX, _worldMaxX);
        _playerY = _playerY.clamp(_worldMinY, _worldMaxY);
      });
    }
  }

  void _interpolateOtherPlayers() {
    if (!mounted || _playerTargetPositions.isEmpty) return;
    
    final now = DateTime.now();
    bool needsUpdate = false;
    final targetsToRemove = <String>[];
    
    for (var entry in _playerTargetPositions.entries) {
      final playerId = entry.key;
      final targetPos = entry.value;
      
      if (!_players.containsKey(playerId)) continue;
      
      final player = _players[playerId]!;
      final currentPos = Offset(player.x, player.y);
      final distance = (targetPos - currentPos).distance;
      
      if (distance < 0.5) {
        if ((player.x - targetPos.dx).abs() > 0.1 || (player.y - targetPos.dy).abs() > 0.1) {
          player.x = targetPos.dx;
          player.y = targetPos.dy;
          needsUpdate = true;
        } else {
          // Mark for removal if we're close enough
          targetsToRemove.add(playerId);
        }
      } else {
        final lerpFactor = (distance > 10) ? 0.3 : 0.15;
        
        final newX = currentPos.dx + (targetPos.dx - currentPos.dx) * lerpFactor;
        final newY = currentPos.dy + (targetPos.dy - currentPos.dy) * lerpFactor;
        
        // Always update to ensure smooth movement and visibility
        player.x = newX;
        player.y = newY;
        needsUpdate = true;
      }
    }
    
    // Remove completed targets
    for (var playerId in targetsToRemove) {
      _playerTargetPositions.remove(playerId);
    }
    
    // Always call setState if there are active targets to ensure repaints
    if (needsUpdate && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    _screenWidth = mediaQuery.size.width;
    _screenHeight = mediaQuery.size.height;
    
    _playerSize = 128.0;
    
    final isMobile = _isMobileDevice(context);
    
    Widget gameContent = Scaffold(
        body: Stack(
          children: [
            if (_showSettingsModal || _showCharacterCreateModal)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _showSettingsModal = false;
                      _showCharacterCreateModal = false;
                      _settingsView = null;
                    });
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),
            Container(
              color: const Color(0xFF222222),
              child: CustomPaint(
                painter: GameWorldPainter(
                  _players,
                  _playerX,
                  _playerY,
                  _currentCharacterId ?? '',
                  _currentCharacterName ?? '',
                  _playerDirection,
                  _currentSpriteType ?? 'char-1',
                  _char1Sprite,
                  _char2Sprite,
                  _worldBackground,
                  _worldToScreenX,
                  _worldToScreenY,
                  _playerSize,
                ),
                size: Size.infinite,
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: IconButton(
                onPressed: () {
                  setState(() {
                    _showSettingsModal = !_showSettingsModal;
                    _settingsView = null;
                  });
                  if (_showSettingsModal) {
                    _refreshCharacters();
                  }
                },
                icon: const Icon(Icons.menu, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  padding: const EdgeInsets.all(8),
                ),
                tooltip: 'Menu',
              ),
            ),
            if (_showSettingsModal)
              _buildSettingsModal(),
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _currentCharacterId == null 
                          ? 'No Character'
                          : 'Players: ${_players.length + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    if (_currentCharacterId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Pos: (${_playerX.toInt()}, ${(-_playerY).toInt()})',
                          style: const TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_currentCharacterId != null)
              _joystickMode.startsWith('floating')
                  ? _buildFloatingJoystick()
                  : Positioned(
                      bottom: max(20.0, _screenHeight * 0.05),
                      left: _joystickMode == 'fixed-left' ? max(20.0, _screenWidth * 0.05) : null,
                      right: _joystickMode == 'fixed-right' ? max(20.0, _screenWidth * 0.05) : null,
                      child: VirtualJoystick(
                        size: min(min(_screenWidth, _screenHeight) * 0.2, 150.0).toDouble(),
                        onMove: (deltaX, deltaY) {
                          setState(() {
                            _joystickDeltaX = deltaX;
                            _joystickDeltaY = deltaY;
                          });
                        },
                      ),
                    ),
            if (_showCharacterCreateModal && !_showSettingsModal)
              _buildCharacterCreateModal(),
            ],
          ),
        );
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_keyboardFocusNode.hasFocus) {
        _keyboardFocusNode.requestFocus();
      }
    });
    
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      onKeyEvent: (event) {
        final key = event.logicalKey;
        
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
      child: gameContent,
    );
  }

  Widget _buildFloatingJoystick() {
    final joystickSize = min(min(_screenWidth, _screenHeight) * 0.2, 150.0).toDouble();
    
    final modalsOpen = _showSettingsModal || _showCharacterCreateModal;
    
    final isFloatingLeft = _joystickMode == 'floating-left';
    final isFloatingRight = _joystickMode == 'floating-right';
    
    final quadrantWidth = _screenWidth / 2;
    final quadrantHeight = _screenHeight / 2;
    final quadrantTop = _screenHeight / 2;
    final quadrantLeft = isFloatingLeft ? 0.0 : (_screenWidth / 2);
    final quadrantRight = isFloatingRight ? _screenWidth : (_screenWidth / 2);
    
    bool isInActiveQuadrant(Offset position) {
      if (modalsOpen) return false;
      final x = position.dx;
      final y = position.dy;
      return y >= quadrantTop && 
             x >= quadrantLeft && 
             x < quadrantRight;
    }
    
    return Stack(
      children: [
        if (!modalsOpen)
          Positioned(
            left: quadrantLeft,
            top: quadrantTop,
            width: quadrantWidth,
            height: quadrantHeight,
            child: GestureDetector(
              onPanStart: (details) {
                final localPosition = details.localPosition;
                final globalPosition = Offset(quadrantLeft + localPosition.dx, quadrantTop + localPosition.dy);
                
                if (isInActiveQuadrant(globalPosition)) {
                  setState(() {
                    _floatingJoystickPosition = globalPosition;
                    _showFloatingJoystick = true;
                  });
                }
              },
              onPanUpdate: (details) {
                if (_showFloatingJoystick && _floatingJoystickPosition != null) {
                  final localPosition = details.localPosition;
                  final globalPosition = Offset(quadrantLeft + localPosition.dx, quadrantTop + localPosition.dy);
                  
                  if (isInActiveQuadrant(globalPosition)) {
                    final center = _floatingJoystickPosition!;
                    final delta = globalPosition - center;
                    final maxDistance = (joystickSize / 2) - 30;
                    final distance = delta.distance;
                    
                    double deltaX, deltaY;
                    if (distance <= maxDistance) {
                      deltaX = delta.dx / maxDistance;
                      deltaY = delta.dy / maxDistance;
                    } else {
                      final angle = atan2(delta.dy, delta.dx);
                      deltaX = cos(angle);
                      deltaY = sin(angle);
                    }
                    
                    setState(() {
                      _joystickDeltaX = deltaX;
                      _joystickDeltaY = deltaY;
                    });
                  }
                }
              },
              onPanEnd: (_) {
                setState(() {
                  _joystickDeltaX = 0;
                  _joystickDeltaY = 0;
                  _showFloatingJoystick = false;
                  _floatingJoystickPosition = null;
                });
              },
              onPanCancel: () {
                setState(() {
                  _joystickDeltaX = 0;
                  _joystickDeltaY = 0;
                  _showFloatingJoystick = false;
                  _floatingJoystickPosition = null;
                });
              },
              child: Container(color: Colors.transparent),
            ),
          ),
        if (_showFloatingJoystick && _floatingJoystickPosition != null && !modalsOpen)
          Positioned(
            left: _floatingJoystickPosition!.dx - joystickSize / 2,
            top: _floatingJoystickPosition!.dy - joystickSize / 2,
            child: _buildFloatingJoystickVisual(joystickSize),
          ),
      ],
    );
  }

  Widget _buildFloatingJoystickVisual(double size) {
    final baseRadius = 60.0;
    final stickRadius = 30.0;
    final maxDistance = baseRadius - stickRadius;
    
    final stickOffset = Offset(
      _joystickDeltaX * maxDistance,
      _joystickDeltaY * maxDistance,
    );
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(0.3),
        border: Border.all(
          color: Colors.white.withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Container(
              width: baseRadius * 2,
              height: baseRadius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.2),
              ),
            ),
          ),
          Center(
            child: Transform.translate(
              offset: stickOffset,
              child: Container(
                width: stickRadius * 2,
                height: stickRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.9),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsModal() {
    return Center(
      child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 300,
          height: 400,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: _settingsView == 'characterSelect'
              ? _buildCharacterSelectContent()
              : _settingsView == 'settings'
              ? _buildSettingsContent()
              : _settingsView == 'howToPlay'
              ? _buildHowToPlayContent()
              : _settingsView == 'devTools'
              ? _buildDevToolsContent()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Menu',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () {
                              setState(() {
                                _showSettingsModal = false;
                                _settingsView = null;
                              });
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView(
                        children: [
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.help_outline, size: 20),
                            title: const Text(
                              'How to Play',
                              style: TextStyle(fontSize: 14),
                            ),
                            onTap: () {
                              setState(() {
                                _settingsView = 'howToPlay';
                              });
                            },
                          ),
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.settings, size: 20),
                            title: const Text(
                              'Settings',
                              style: TextStyle(fontSize: 14),
                            ),
                            onTap: () {
                              setState(() {
                                _settingsView = 'settings';
                              });
                            },
                          ),
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.build, size: 20),
                            title: const Text(
                              'Dev Tools',
                              style: TextStyle(fontSize: 14),
                            ),
                            onTap: () {
                              setState(() {
                                _settingsView = 'devTools';
                              });
                            },
                          ),
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.person, size: 20),
                            title: Text(
                              'Select Character',
                              style: TextStyle(
                                fontSize: 14,
                                color: _characters.isEmpty ? Colors.grey : null,
                              ),
                            ),
                            enabled: _characters.isNotEmpty,
                            onTap: _characters.isEmpty
                                ? null
                                : () {
                                    setState(() {
                                      _settingsView = 'characterSelect';
                                    });
                                    _refreshCharacters();
                                  },
                          ),
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.add, size: 20),
                            title: const Text(
                              'Create Character',
                              style: TextStyle(fontSize: 14),
                            ),
                            onTap: () {
                              setState(() {
                                _showSettingsModal = false;
                                _showCharacterCreateModal = true;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildCharacterSelectContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () {
                  setState(() {
                    _settingsView = null;
                    _selectedCharacter = null;
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const Text(
                'Character Select',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() {
                    _showSettingsModal = false;
                    _settingsView = null;
                    _selectedCharacter = null;
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const Divider(),
        Flexible(
          child: !_isInitialized
              ? const Center(child: CircularProgressIndicator())
              : _characters.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          'No characters',
                          style: TextStyle(fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _characters.length,
                      itemBuilder: (context, index) {
                        final char = _characters[index];
                        final isSelected = _selectedCharacter != null && 
                            _selectedCharacter!['id'] == char['id'];
                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.blue.shade50 : null,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: Colors.blue.withOpacity(0.3),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedCharacter = char;
                                  });
                                },
                                onHover: (hovering) {
                                  setState(() {});
                                },
                                borderRadius: BorderRadius.circular(8),
                                hoverColor: Colors.grey.shade200,
                                child: ListTile(
                                  dense: true,
                                  selected: isSelected,
                                  leading: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: ClipRect(
                                        child: FittedBox(
                                          fit: BoxFit.cover,
                                          alignment: Alignment.topLeft,
                                          child: SizedBox(
                                            width: 1024,
                                            height: 512,
                                            child: Image.asset(
                                              'assets/${char['spriteType'] ?? 'char-1'}.png',
                                              fit: BoxFit.none,
                                              alignment: Alignment.topLeft,
                                              errorBuilder: (context, error, stackTrace) {
                                                return const Center(child: Icon(Icons.person, size: 20));
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    char['name'] as String,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedCharacter == null
                  ? null
                  : () {
                      if (_selectedCharacter != null) {
                        _loadCharacter(_selectedCharacter!);
                      }
                    },
              child: const Text('Play', style: TextStyle(fontSize: 12)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _settingsView = null;
                  _showCharacterCreateModal = true;
                  _selectedCharacter = null;
                });
              },
              child: const Text('Create Character', style: TextStyle(fontSize: 12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHowToPlayContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'How to Play',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () {
                  setState(() {
                    _settingsView = null;
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Getting Started',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. Create or select a character to enter the game world',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Movement',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Desktop:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  '• Use WASD keys or Arrow keys to move your character',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Mobile:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  '• Use the virtual joystick to move your character',
                  style: TextStyle(fontSize: 14),
                ),
                const Text(
                  '• You can change the joystick position in Settings',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Multiplayer',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• You can see other players in real-time as they move around the world',
                  style: TextStyle(fontSize: 14),
                ),
                const Text(
                  '• All players share the same game world',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Tips',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• Use the Menu button (top left) to access settings and character selection',
                  style: TextStyle(fontSize: 14),
                ),
                const Text(
                  '• Your character position is saved automatically',
                  style: TextStyle(fontSize: 14),
                ),
                const Text(
                  '• You can create multiple characters and switch between them',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDevToolsContent() {
    final teleportXController = TextEditingController(text: _playerX.toInt().toString());
    final teleportYController = TextEditingController(text: (-_playerY).toInt().toString());
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Dev Tools',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () {
                  setState(() {
                    _settingsView = null;
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Movement Speed: ${_playerSpeed.toStringAsFixed(1)}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: _playerSpeed,
                      min: 0.5,
                      max: 20.0,
                      divisions: 39,
                      label: _playerSpeed.toStringAsFixed(1),
                      onChanged: (value) {
                        setState(() {
                          _playerSpeed = value;
                        });
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _playerSpeed = 2.5;
                            });
                          },
                          child: const Text('Reset'),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _playerSpeed = 5.0;
                            });
                          },
                          child: const Text('Fast'),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _playerSpeed = 10.0;
                            });
                          },
                          child: const Text('Very Fast'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Teleport',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: teleportXController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'X',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: teleportYController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Y',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            final x = double.tryParse(teleportXController.text);
                            final y = double.tryParse(teleportYController.text);
                            if (x != null && y != null) {
                              setState(() {
                                _playerX = x.clamp(_worldMinX, _worldMaxX);
                                _playerY = (-y).clamp(_worldMinY, _worldMaxY);
                                _lastSentX = _playerX;
                                _lastSentY = _playerY;
                                if (_currentCharacterId != null) {
                                  _gameService.movePlayer(_playerX, _playerY);
                                }
                              });
                            }
                          },
                          child: const Text('Teleport'),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              teleportXController.text = _playerX.toInt().toString();
                              teleportYController.text = (-_playerY).toInt().toString();
                            });
                          },
                          child: const Text('Current'),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              teleportXController.text = '0';
                              teleportYController.text = '0';
                            });
                          },
                          child: const Text('Center'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Settings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () {
                  setState(() {
                    _settingsView = null;
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView(
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.gamepad, size: 20),
                title: const Text(
                  'Joystick Mode',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  _joystickMode == 'fixed-left'
                      ? 'Fixed Left'
                      : _joystickMode == 'fixed-right'
                          ? 'Fixed Right'
                          : _joystickMode == 'floating-left'
                              ? 'Floating Left'
                              : 'Floating Right',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: DropdownButton<String>(
                  value: _joystickMode,
                  items: const [
                    DropdownMenuItem(value: 'fixed-left', child: Text('Fixed Left')),
                    DropdownMenuItem(value: 'fixed-right', child: Text('Fixed Right')),
                    DropdownMenuItem(value: 'floating-left', child: Text('Floating Left')),
                    DropdownMenuItem(value: 'floating-right', child: Text('Floating Right')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _joystickMode = value;
                        _showFloatingJoystick = false;
                        _floatingJoystickPosition = null;
                        _joystickDeltaX = 0;
                        _joystickDeltaY = 0;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCharacterCreateModal() {
    _characterNameController ??= TextEditingController();
    _characterNameFocusNode ??= FocusNode();

    return Center(
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            width: 300,
            height: 400,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Create Character',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          setState(() {
                            _showCharacterCreateModal = false;
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    focusNode: _characterNameFocusNode,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.done,
                    autofocus: false,
                    controller: _characterNameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onTap: () {
                      _characterNameFocusNode?.requestFocus();
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          setModalState(() {
                            _selectedSpriteTypeForCreation = 'char-1';
                          });
                        },
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _selectedSpriteTypeForCreation == 'char-1' ? Colors.blue : Colors.grey,
                              width: _selectedSpriteTypeForCreation == 'char-1' ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: ClipRect(
                              child: FittedBox(
                                fit: BoxFit.cover,
                                alignment: Alignment.topLeft,
                                child: SizedBox(
                                  width: 1024,
                                  height: 512,
                                  child: Image.asset(
                                    'assets/char-1.png',
                                    fit: BoxFit.none,
                                    alignment: Alignment.topLeft,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Center(child: Icon(Icons.person, size: 20));
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          setModalState(() {
                            _selectedSpriteTypeForCreation = 'char-2';
                          });
                        },
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _selectedSpriteTypeForCreation == 'char-2' ? Colors.blue : Colors.grey,
                              width: _selectedSpriteTypeForCreation == 'char-2' ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: ClipRect(
                              child: FittedBox(
                                fit: BoxFit.cover,
                                alignment: Alignment.topLeft,
                                child: SizedBox(
                                  width: 1024,
                                  height: 512,
                                  child: Image.asset(
                                    'assets/char-2.png',
                                    fit: BoxFit.none,
                                    alignment: Alignment.topLeft,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Center(child: Icon(Icons.person, size: 20));
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (_characterNameController == null || _characterNameController!.text.isEmpty || _accountId == null) return;
                        
                        try {
                          final newCharacter = await _apiService.createCharacter(
                            _accountId!,
                            _characterNameController!.text,
                            _selectedSpriteTypeForCreation,
                          );
                          await _refreshCharacters();
                          if (mounted) {
                            await _loadCharacter({
                              'id': newCharacter['id'],
                              'name': newCharacter['name'],
                              'spriteType': newCharacter['spriteType'],
                            });
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed: $e')),
                            );
                          }
                        }
                      },
                      child: const Text('Create', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadCharacter(Map<String, dynamic> character) async {
    _characterNameController?.clear();
    setState(() {
      _showSettingsModal = false;
      _showCharacterCreateModal = false;
      _settingsView = null;
      _selectedCharacter = null;
      
      _currentCharacterId = character['id'] as String;
      _currentCharacterName = character['name'] as String;
      _currentSpriteType = character['spriteType'] as String? ?? 'char-1';
    });

    if (_gameService.socket?.connected == true) {
      _joinGameWithCharacter();
    } else {
      _gameService.socket?.on('connect', (_) {
        _joinGameWithCharacter();
      });
    }
  }

  Future<void> _refreshCharacters() async {
    if (_accountId == null) return;
    try {
      final characters = await _apiService.getCharacters(_accountId!);
      if (mounted) {
        setState(() {
          _characters = characters;
        });
      }
    } catch (e) {
      print('Failed to refresh characters: $e');
    }
  }

  Function(Map<String, dynamic>) _playerJoinedCallback = (_) {};
  Function(Map<String, dynamic>) _playerMovedCallback = (_) {};
  Function(Map<String, dynamic>) _playerLeftCallback = (_) {};
  Function(List<dynamic>) _playersListCallback = (_) {};

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    _characterNameController?.dispose();
    _characterNameFocusNode?.dispose();
    _movementTimer?.cancel();
    _positionUpdateTimer?.cancel();
    _gameService.removeCallback(
      onPlayerJoined: _playerJoinedCallback,
      onPlayerMoved: _playerMovedCallback,
      onPlayerLeft: _playerLeftCallback,
      onPlayersList: _playersListCallback,
    );
    super.dispose();
  }
}

class GameWorldPainter extends CustomPainter {
  final Map<String, Player> players;
  final double playerX;
  final double playerY;
  final String currentPlayerId;
  final String currentPlayerName;
  final PlayerDirection currentPlayerDirection;
  final String currentPlayerSpriteType;
  final ui.Image? char1Sprite;
  final ui.Image? char2Sprite;
  final ui.Image? worldBackground;
  final double Function(double) worldToScreenX;
  final double Function(double) worldToScreenY;
  final double playerSize;
  
  static const double _worldMinX = -5000.0;
  static const double _worldMaxX = 5000.0;
  static const double _worldMinY = -5000.0;
  static const double _worldMaxY = 5000.0;

  GameWorldPainter(
    this.players,
    this.playerX,
    this.playerY,
    this.currentPlayerId,
    this.currentPlayerName,
    this.currentPlayerDirection,
    this.currentPlayerSpriteType,
    this.char1Sprite,
    this.char2Sprite,
    this.worldBackground,
    this.worldToScreenX,
    this.worldToScreenY,
    this.playerSize,
  );

  void _drawSprite(
    Canvas canvas,
    ui.Image sprite,
    double worldX,
    double worldY,
    double size,
    PlayerDirection direction,
  ) {
    Rect sourceRect;
    if (direction == PlayerDirection.down) {
      sourceRect = const Rect.fromLTWH(0, 0, 512, 512);
    } else if (direction == PlayerDirection.up) {
      sourceRect = const Rect.fromLTWH(512, 0, 512, 512);
    } else {
      sourceRect = const Rect.fromLTWH(0, 0, 512, 512);
    }

    final screenX = worldToScreenX(worldX);
    final screenY = worldToScreenY(worldY);
    
    final destRect = Rect.fromCenter(
      center: Offset(screenX, screenY),
      width: size,
      height: size,
    );
    canvas.drawImageRect(sprite, sourceRect, destRect, Paint());
  }

  ui.Image? _getSpriteForType(String spriteType) {
    if (spriteType == 'char-1') {
      return char1Sprite;
    } else if (spriteType == 'char-2') {
      return char2Sprite;
    }
    return char1Sprite;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black,
    );
    
    if (worldBackground != null) {
      final worldStartX = playerX - size.width / 2;
      final worldStartY = playerY - size.height / 2;
      final worldEndX = playerX + size.width / 2;
      final worldEndY = playerY + size.height / 2;
      
      final bgWidth = worldBackground!.width.toDouble();
      final bgHeight = worldBackground!.height.toDouble();
      const worldWidth = 10000.0;
      const worldHeight = 10000.0;
      
      final clampedWorldStartX = worldStartX.clamp(_worldMinX, _worldMaxX);
      final clampedWorldStartY = worldStartY.clamp(_worldMinY, _worldMaxY);
      final clampedWorldEndX = worldEndX.clamp(_worldMinX, _worldMaxX);
      final clampedWorldEndY = worldEndY.clamp(_worldMinY, _worldMaxY);
      
      final normalizedStartX = (clampedWorldStartX - _worldMinX) / worldWidth;
      final normalizedStartY = (clampedWorldStartY - _worldMinY) / worldHeight;
      final normalizedEndX = (clampedWorldEndX - _worldMinX) / worldWidth;
      final normalizedEndY = (clampedWorldEndY - _worldMinY) / worldHeight;
      
      final sourceX = normalizedStartX * bgWidth;
      final sourceY = normalizedStartY * bgHeight;
      final sourceWidth = (normalizedEndX - normalizedStartX) * bgWidth;
      final sourceHeight = (normalizedEndY - normalizedStartY) * bgHeight;
      
      final screenOffsetX = clampedWorldStartX - worldStartX;
      final screenOffsetY = clampedWorldStartY - worldStartY;
      
      final clampedSourceX = sourceX.clamp(0.0, bgWidth);
      final clampedSourceY = sourceY.clamp(0.0, bgHeight);
      final clampedSourceWidth = (sourceWidth).clamp(0.0, bgWidth - clampedSourceX);
      final clampedSourceHeight = (sourceHeight).clamp(0.0, bgHeight - clampedSourceY);
      
      final sourceRect = Rect.fromLTWH(
        clampedSourceX,
        clampedSourceY,
        clampedSourceWidth,
        clampedSourceHeight,
      );
      
      final destX = screenOffsetX > 0 ? screenOffsetX : 0.0;
      final destY = screenOffsetY > 0 ? screenOffsetY : 0.0;
      final destWidth = screenOffsetX > 0 ? clampedSourceWidth : (clampedSourceWidth + screenOffsetX);
      final destHeight = screenOffsetY > 0 ? clampedSourceHeight : (clampedSourceHeight + screenOffsetY);
      
      final destRect = Rect.fromLTWH(
        destX,
        destY,
        destWidth.clamp(0.0, size.width - destX),
        destHeight.clamp(0.0, size.height - destY),
      );
      
      canvas.drawImageRect(worldBackground!, sourceRect, destRect, Paint());
    }
    
    for (var player in players.values) {
      if (player.id != currentPlayerId) {
        final playerSpriteType = player.spriteType ?? 'char-2';
        final sprite = _getSpriteForType(playerSpriteType);
        
        if (sprite != null) {
          _drawSprite(canvas, sprite, player.x, player.y, playerSize, player.direction);
        } else {
          final screenX = worldToScreenX(player.x);
          final screenY = worldToScreenY(player.y);
          final paint = Paint()..color = Colors.blue;
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(screenX, screenY),
              width: playerSize,
              height: playerSize,
            ),
            paint,
          );
        }
        
        final screenX = worldToScreenX(player.x);
        final screenY = worldToScreenY(player.y);
        final fontSize = playerSize * 0.1;
        final textPainter = TextPainter(
          text: TextSpan(
            text: player.name,
            style: TextStyle(color: Colors.black, fontSize: fontSize),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        final textX = screenX - textPainter.width / 2;
        textPainter.paint(canvas, Offset(textX, screenY - playerSize / 2 - fontSize * 1.2));
      }
    }

    if (currentPlayerId.isNotEmpty && currentPlayerName.isNotEmpty) {
      final currentSprite = _getSpriteForType(currentPlayerSpriteType);
      if (currentSprite != null) {
        _drawSprite(canvas, currentSprite, playerX, playerY, playerSize, currentPlayerDirection);
      } else {
        final screenX = worldToScreenX(playerX);
        final screenY = worldToScreenY(playerY);
        final currentPlayerPaint = Paint()..color = Colors.red;
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(screenX, screenY),
            width: playerSize,
            height: playerSize,
          ),
          currentPlayerPaint,
        );
      }
      
      final screenX = worldToScreenX(playerX);
      final screenY = worldToScreenY(playerY);
      final fontSize = playerSize * 0.1;
      final textPainter = TextPainter(
        text: TextSpan(
          text: currentPlayerName,
          style: TextStyle(color: Colors.black, fontSize: fontSize),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      final textX = screenX - textPainter.width / 2;
      textPainter.paint(canvas, Offset(textX, screenY - playerSize / 2 - fontSize * 1.2));
    }
  }

  @override
  bool shouldRepaint(GameWorldPainter oldDelegate) {
    if (oldDelegate.players.length != players.length) {
      return true;
    }
    
    for (var playerId in players.keys) {
      final oldPlayer = oldDelegate.players[playerId];
      final newPlayer = players[playerId];
      if (oldPlayer == null || newPlayer == null) {
        return true;
      }
      if ((oldPlayer.x - newPlayer.x).abs() > 0.01 || 
          (oldPlayer.y - newPlayer.y).abs() > 0.01 ||
          oldPlayer.direction != newPlayer.direction) {
        return true;
      }
    }
    
    if ((oldDelegate.playerX - playerX).abs() > 0.01 ||
        (oldDelegate.playerY - playerY).abs() > 0.01) {
      return true;
    }
    
    return oldDelegate.currentPlayerName != currentPlayerName ||
        oldDelegate.currentPlayerDirection != currentPlayerDirection ||
        oldDelegate.currentPlayerSpriteType != currentPlayerSpriteType ||
        oldDelegate.char1Sprite != char1Sprite ||
        oldDelegate.char2Sprite != char2Sprite;
  }
}

