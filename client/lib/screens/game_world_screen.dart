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
  final String? accountId; // Pass accountId to preserve it

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
  // Interpolation targets for smooth movement
  final Map<String, Offset> _playerTargetPositions = {};
  final Map<String, DateTime> _playerLastUpdateTime = {};
  // Game world coordinates: world is 10000x10000, origin at (0, 0) in top-left
  // Player position in world coordinates
  double _playerX = 5000.0; // Start at center of world
  double _playerY = 5000.0; // Start at center of world
  double _playerSpeed = 2.5; // Base speed (can be modified by dev tools)
  double _playerSize = 128.0; // Player sprite size (will scale with screen)
  Timer? _positionUpdateTimer;
  Timer? _movementTimer;
  double _lastSentX = 0.0;
  double _lastSentY = 0.0;
  
  // World dimensions
  static const double _worldWidth = 10000.0;
  static const double _worldHeight = 10000.0;
  
  // Screen dimensions (playable area) - will be set from MediaQuery
  double _screenWidth = 800.0;
  double _screenHeight = 600.0;
  
  // Joystick state for mobile
  double _joystickDeltaX = 0.0;
  double _joystickDeltaY = 0.0;
  
  // Check if mobile device (using screen size and aspect ratio)
  bool _isMobileDevice(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    
    // Mobile devices typically have:
    // 1. Smaller screens (width OR height < 768px)
    // 2. Higher pixel density (devicePixelRatio > 1.5 for most mobile)
    // 3. Aspect ratio closer to phone/tablet (not ultra-wide desktop)
    
    // Very lenient: consider mobile if screen is small OR has high pixel density
    // This will show joystick on most mobile devices
    final isSmallScreen = size.width < 768 || size.height < 768;
    final hasHighDensity = mediaQuery.devicePixelRatio > 1.5;
    final aspectRatio = size.width / size.height;
    final isPhoneAspectRatio = aspectRatio > 0.4 && aspectRatio < 3.0; // Very wide range
    
    // Consider it mobile if:
    // - Small screen with reasonable aspect ratio (most mobile devices)
    // - OR high pixel density with reasonable aspect ratio (mobile devices)
    // - OR very small screen (definitely mobile)
    // Only exclude if it's a large screen with low pixel density (desktop)
    if (size.width < 400 || size.height < 400) return true; // Very small = mobile
    if (size.width >= 1200 && size.height >= 800 && !hasHighDensity) return false; // Large desktop
    return (isSmallScreen && isPhoneAspectRatio) || (hasHighDensity && isPhoneAspectRatio);
  }
  
  // Convert world coordinates to screen coordinates (camera system - player always centered)
  // Camera follows player, so player position is the camera position
  // When player moves up (Y increases), objects should appear to move down on screen
  double _worldToScreenX(double worldX) => worldX - _playerX + _screenWidth / 2;
  double _worldToScreenY(double worldY) => _playerY - worldY + _screenHeight / 2;
  
  // Convert screen coordinates to world coordinates
  double _screenToWorldX(double screenX) => screenX - _screenWidth / 2 + _playerX;
  double _screenToWorldY(double screenY) => screenY - _screenHeight / 2 + _playerY;
  final Set<LogicalKeyboardKey> _pressedKeys = {};
  PlayerDirection _playerDirection = PlayerDirection.down;
  PlayerDirection _lastVerticalDirection = PlayerDirection.down; // Track last up/down for left/right movement
  ui.Image? _char1Sprite;
  ui.Image? _char2Sprite;
  ui.Image? _worldBackground;
  bool _showSettingsModal = false;
  bool _showCharacterCreateModal = false;
  String? _settingsView; // null = main menu, 'characterSelect' = character select, 'settings' = settings view, 'howToPlay' = how to play, 'devTools' = dev tools
  String _joystickMode = 'fixed-right'; // 'fixed-left', 'fixed-right', 'floating-left', 'floating-right'
  Offset? _floatingJoystickPosition; // Position for floating joystick
  bool _showFloatingJoystick = false; // Whether floating joystick is visible
  bool _showDevTools = false; // Whether dev tools panel is visible
  Map<String, dynamic>? _selectedCharacter; // Selected character in character select screen
  String? _accountId;
  List<dynamic> _characters = [];
  bool _isInitialized = false;
  final FocusNode _keyboardFocusNode = FocusNode(); // Persistent focus node for keyboard input
  String? _currentCharacterId; // Track current character ID (can be different from widget.characterId)
  String? _currentCharacterName;
  String? _currentSpriteType;
  // Character creation modal state (persistent across rebuilds)
  TextEditingController? _characterNameController;
  FocusNode? _characterNameFocusNode;
  String _selectedSpriteTypeForCreation = 'char-1';

  @override
  void initState() {
    super.initState();
    // Initialize current character from widget
    _currentCharacterId = widget.characterId;
    _currentCharacterName = widget.characterName;
    _currentSpriteType = widget.spriteType;
    
    _loadSprites();
    // Set up callbacks BEFORE connecting to ensure we receive all events
    _setupGameService();
    _gameService.connect();
    _initializeAccount();
    
    // Connect to server to see other players (even without character)
    // Request player list when connected (callbacks are already set up)
    _gameService.socket?.on('connect', (_) {
      print('Socket connected, requesting player list...');
      // Request current players list
      _gameService.socket?.emit('game:requestPlayers');
      
      // Join game if character is loaded
      if (_currentCharacterId != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _joinGameWithCharacter();
        });
      }
    });
    
    // Handle reconnection - rejoin game if we have a character
    _gameService.socket?.on('reconnect', (_) {
      print('Socket reconnected, rejoining game...');
      // Request fresh player list
      _gameService.socket?.emit('game:requestPlayers');
      
      // Rejoin game if character is loaded
      if (_currentCharacterId != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _joinGameWithCharacter();
        });
      }
    });
    
    // Also try after a delay in case already connected
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (_currentCharacterId != null && _gameService.socket?.connected == true) {
        _joinGameWithCharacter();
      }
    });
    
    // Always start game loop: check pressed keys and move player continuously (60 FPS)
    // This allows interpolation of other players even without a character
    _movementTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      _updateMovement();
      _interpolateOtherPlayers();
    });
    
    // Always start position update timer (only sends if we have a character)
    _positionUpdateTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (_currentCharacterId == null) return;
      final dx = (_playerX - _lastSentX).abs();
      final dy = (_playerY - _lastSentY).abs();
      
      // Send if moved more than 0.5 pixels (more frequent updates)
      if (dx > 0.5 || dy > 0.5) {
        // Send game world coordinates directly (not screen coordinates)
        _gameService.movePlayer(_playerX, _playerY);
        _lastSentX = _playerX;
        _lastSentY = _playerY;
      }
    });
    
    // Show settings modal if no character loaded
    if (_currentCharacterId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _showSettingsModal = true;
          _settingsView = null; // Show main settings menu
        });
        _refreshCharacters();
      });
    }
  }

  void _joinGameWithCharacter() {
    if (_currentCharacterId == null || _currentCharacterName == null) return;
    print('Joining game with character: $_currentCharacterId');
    // Send game world coordinates directly (not screen coordinates)
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
      // If accountId is provided from widget, use it instead of creating new one
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
        // Create new temporary account only if none provided
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

    // Load world background image
    // Note: When you update world-img.jpg:
    // 1. Save the new image file
    // 2. Run: flutter clean && flutter build web
    // 3. Deploy: firebase deploy --only hosting
    // 4. Users should hard refresh (Ctrl+Shift+R) to see the new image
    // Flutter automatically generates hash-based filenames, so the new image will have a different URL
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
          // Positions from server are already in game world coordinates
          // Only skip if this is our own character (when we have one)
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
        // Positions from server are already in game world coordinates
        // Only skip if this is our own character (when we have one)
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
      // Skip our own movement updates (we handle our own position locally)
      if (_currentCharacterId != null && playerId == _currentCharacterId) {
        return;
      }
      
      // Positions from server are already in game world coordinates
      final newX = (data['x'] as num).toDouble();
      final newY = (data['y'] as num).toDouble();
      
      // Always update state to trigger repaint, even if player already exists
      if (_players.containsKey(playerId)) {
        final oldX = _players[playerId]!.x;
        final oldY = _players[playerId]!.y;
        
        // Store target position for interpolation (don't update immediately)
        _playerTargetPositions[playerId] = Offset(newX, newY);
        _playerLastUpdateTime[playerId] = DateTime.now();
        
        // Infer direction from movement
        final dx = newX - oldX;
        final dy = newY - oldY;
        if (dy != 0) {
          // Vertical movement - update direction (in game coords, +y is up)
          _players[playerId]!.direction = dy > 0 ? PlayerDirection.up : PlayerDirection.down;
        }
      } else {
        // Player moved but not in our list - add them (might be a late join)
        setState(() {
          final player = Player.fromJson(data);
          player.x = newX;
          player.y = newY;
          _players[playerId] = player;
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
    if (_currentCharacterId == null) return; // Don't allow movement without character
    
    double deltaX = 0;
    double deltaY = 0;
    PlayerDirection? newVerticalDirection;
    
    // Check if joystick is being used (has input)
    final isUsingJoystick = _joystickDeltaX.abs() > 0.1 || _joystickDeltaY.abs() > 0.1;
    
    if (isUsingJoystick) {
      // Mobile: use joystick input
      deltaX = _joystickDeltaX * _playerSpeed;
      // Invert Y: joystick negative Y (up on screen) should increase world Y (move up)
      deltaY = -_joystickDeltaY * _playerSpeed;
      
      // Determine direction based on joystick input
      // Joystick: negative Y is up (toward top of screen), positive Y is down
      // World: up increases Y, down decreases Y
      if (_joystickDeltaY.abs() > _joystickDeltaX.abs()) {
        // Vertical movement dominates
        newVerticalDirection = _joystickDeltaY < 0 ? PlayerDirection.up : PlayerDirection.down;
      } else if (_joystickDeltaX != 0) {
        // Horizontal movement - use last vertical direction
        // Direction already set to last vertical direction
      }
    } else {
      // Desktop: use keyboard input (always check keyboard, even if no keys pressed yet)
      if (_pressedKeys.isEmpty) return;
      
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
        deltaY += _playerSpeed; // Up increases Y (player moves up in world, Y increases)
        newVerticalDirection = PlayerDirection.up;
      }
      if (_pressedKeys.contains(LogicalKeyboardKey.arrowDown) ||
          _pressedKeys.contains(LogicalKeyboardKey.keyS)) {
        deltaY -= _playerSpeed; // Down decreases Y (player moves down in world, Y decreases)
        newVerticalDirection = PlayerDirection.down;
      }
    }
    
    // Normalize diagonal movement (so diagonal speed equals horizontal/vertical speed)
    if (deltaX != 0 && deltaY != 0) {
      final length = sqrt(deltaX * deltaX + deltaY * deltaY);
      deltaX = (deltaX / length) * _playerSpeed;
      deltaY = (deltaY / length) * _playerSpeed;
      // For diagonal, use the vertical direction for sprite
      if (newVerticalDirection == null) {
        newVerticalDirection = deltaY > 0 ? PlayerDirection.down : PlayerDirection.up;
      }
    }
    
    if (deltaX != 0 || deltaY != 0) {
      setState(() {
        _playerX += deltaX;
        _playerY += deltaY;
        
        // Update direction: use new vertical direction if provided, otherwise keep last vertical direction
        if (newVerticalDirection != null) {
          _lastVerticalDirection = newVerticalDirection;
          _playerDirection = newVerticalDirection;
        } else if (deltaX != 0 && deltaY == 0) {
          // Pure horizontal movement - use last vertical direction
          _playerDirection = _lastVerticalDirection;
        }
        
        // Keep player in world bounds (world is 10000x10000)
        // Allow player to go to exact edges (0 and 10000)
        _playerX = _playerX.clamp(0.0, _worldWidth);
        _playerY = _playerY.clamp(0.0, _worldHeight);
      });
    }
  }

  // Interpolate other players' positions smoothly
  void _interpolateOtherPlayers() {
    final now = DateTime.now();
    bool needsUpdate = false;
    
    for (var entry in _playerTargetPositions.entries) {
      final playerId = entry.key;
      final targetPos = entry.value;
      
      if (!_players.containsKey(playerId)) continue;
      
      final player = _players[playerId]!;
      final currentPos = Offset(player.x, player.y);
      final distance = (targetPos - currentPos).distance;
      
      // If very close, snap to target
      if (distance < 0.5) {
        if ((player.x - targetPos.dx).abs() > 0.1 || (player.y - targetPos.dy).abs() > 0.1) {
          player.x = targetPos.dx;
          player.y = targetPos.dy;
          needsUpdate = true;
        }
      } else {
        // Interpolate towards target (lerp factor based on distance and time)
        final lastUpdate = _playerLastUpdateTime[playerId];
        final timeSinceUpdate = lastUpdate != null 
            ? now.difference(lastUpdate).inMilliseconds 
            : 50;
        
        // Use a lerp factor that adapts to update frequency
        // Faster interpolation for larger distances, slower for small
        final lerpFactor = (distance > 10) ? 0.3 : 0.15;
        
        player.x = currentPos.dx + (targetPos.dx - currentPos.dx) * lerpFactor;
        player.y = currentPos.dy + (targetPos.dy - currentPos.dy) * lerpFactor;
        needsUpdate = true;
      }
    }
    
    if (needsUpdate && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions and update game world size
    final mediaQuery = MediaQuery.of(context);
    _screenWidth = mediaQuery.size.width;
    _screenHeight = mediaQuery.size.height;
    
    // Keep player size constant (not scaled with screen)
    _playerSize = 128.0; // Fixed size regardless of screen dimensions
    
    final isMobile = _isMobileDevice(context);
    
    Widget gameContent = Scaffold(
        body: Stack(
          children: [
            // Gesture detector for closing modals when tapping outside
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
            // Game world background
            Container(
              color: const Color(0xFF222222), // Dark grey background
              child: CustomPaint(
                key: ValueKey('game_${_players.length}_${_worldBackground != null ? "bg" : "nobg"}'), // Force repaint on player changes or background load
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
                  _playerSize, // Pass player size to painter
                ),
                size: Size.infinite,
              ),
            ),
            // Menu button (top left)
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
            // Settings modal (centered)
            if (_showSettingsModal)
              _buildSettingsModal(),
            // Players count and debug info (moved to top right)
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
                          'Pos: (${_playerX.toInt()}, ${_playerY.toInt()})',
                          style: const TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Virtual joystick (always visible for debugging)
            if (_currentCharacterId != null)
              _joystickMode.startsWith('floating')
                  ? _buildFloatingJoystick()
                  : Positioned(
                      bottom: max(20.0, _screenHeight * 0.05), // At least 20px or 5% of screen height
                      left: _joystickMode == 'fixed-left' ? max(20.0, _screenWidth * 0.05) : null, // Left side
                      right: _joystickMode == 'fixed-right' ? max(20.0, _screenWidth * 0.05) : null, // Right side
                      child: VirtualJoystick(
                        size: min(min(_screenWidth, _screenHeight) * 0.2, 150.0).toDouble(), // 20% of smaller dimension, max 150px
                        onMove: (deltaX, deltaY) {
                          setState(() {
                            _joystickDeltaX = deltaX;
                            _joystickDeltaY = deltaY;
                          });
                        },
                      ),
                    ),
            // Character creation modal (standalone, only when not in settings)
            if (_showCharacterCreateModal && !_showSettingsModal)
              _buildCharacterCreateModal(),
            ],
          ),
        );
    
    // Always wrap with KeyboardListener for desktop input
    // On mobile, joystick input takes precedence in _updateMovement
    // Request focus after build to ensure keyboard input works
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_keyboardFocusNode.hasFocus) {
        _keyboardFocusNode.requestFocus();
      }
    });
    
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
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
      child: gameContent,
    );
  }

  Widget _buildFloatingJoystick() {
    final joystickSize = min(min(_screenWidth, _screenHeight) * 0.2, 150.0).toDouble();
    
    // Only show touch detector when modals are NOT open (menus take priority)
    final modalsOpen = _showSettingsModal || _showCharacterCreateModal;
    
    // Determine which quadrant to use (bottom-left or bottom-right)
    final isFloatingLeft = _joystickMode == 'floating-left';
    final isFloatingRight = _joystickMode == 'floating-right';
    
    // Calculate quadrant boundaries (bottom half of screen, left or right half)
    final quadrantWidth = _screenWidth / 2;
    final quadrantHeight = _screenHeight / 2;
    final quadrantTop = _screenHeight / 2; // Start at middle of screen (bottom half)
    final quadrantLeft = isFloatingLeft ? 0.0 : (_screenWidth / 2);
    final quadrantRight = isFloatingRight ? _screenWidth : (_screenWidth / 2);
    
    // Helper to check if a position is in the active quadrant
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
        // Touch detector only for the active quadrant (only active when modals are closed)
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
                
                // Only activate if touch is in the active quadrant
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
                  
                  // Only process if still in active quadrant
                  if (isInActiveQuadrant(globalPosition)) {
                    // Calculate movement relative to joystick center
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
        // Visible joystick at touch position (only when active and modals are closed)
        if (_showFloatingJoystick && _floatingJoystickPosition != null && !modalsOpen)
          Positioned(
            left: _floatingJoystickPosition!.dx - joystickSize / 2,
            top: _floatingJoystickPosition!.dy - joystickSize / 2,
            child: _buildFloatingJoystickVisual(joystickSize),
          ),
      ],
    );
  }

  // Build the visual representation of the floating joystick with stick position
  Widget _buildFloatingJoystickVisual(double size) {
    final baseRadius = 60.0;
    final stickRadius = 30.0;
    final maxDistance = baseRadius - stickRadius;
    
    // Calculate stick position from current joystick deltas
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
          // Base circle
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
          // Stick (positioned based on joystick deltas)
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
        onTap: () {}, // Prevent closing when tapping inside
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
                                  setState(() {}); // Trigger rebuild for hover effect
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
    final teleportYController = TextEditingController(text: _playerY.toInt().toString());
    
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
              // Movement Speed Control
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
                              _playerSpeed = 2.5; // Reset to default
                            });
                          },
                          child: const Text('Reset'),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _playerSpeed = 5.0; // Fast
                            });
                          },
                          child: const Text('Fast'),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _playerSpeed = 10.0; // Very Fast
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
              // Teleport Section
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
                                _playerX = x.clamp(0.0, _worldWidth);
                                _playerY = y.clamp(0.0, _worldHeight);
                                // Update last sent position to prevent unnecessary network updates
                                _lastSentX = _playerX;
                                _lastSentY = _playerY;
                                // Send teleport to server
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
                              teleportYController.text = _playerY.toInt().toString();
                            });
                          },
                          child: const Text('Current'),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              teleportXController.text = '5000';
                              teleportYController.text = '5000';
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
              // Joystick mode selection
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
                        // Reset floating joystick state when switching modes
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
    // Initialize controllers only once when modal is first shown
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
                      // Ensure focus on tap for mobile
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
                          // Auto-load the newly created character
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
    // Close modals when loading a character
    // Clear the text field when loading a character
    _characterNameController?.clear();
    setState(() {
      _showSettingsModal = false;
      _showCharacterCreateModal = false;
      _settingsView = null;
      _selectedCharacter = null;
      
      // Update current character state
      _currentCharacterId = character['id'] as String;
      _currentCharacterName = character['name'] as String;
      _currentSpriteType = character['spriteType'] as String? ?? 'char-1';
    });

    // Join game with the new character
    if (_gameService.socket?.connected == true) {
      _joinGameWithCharacter();
    } else {
      // Wait for connection
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
      // Silently fail - preserve existing characters
      print('Failed to refresh characters: $e');
    }
  }

  // Store callback references so we can remove them on dispose
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
    // Remove only this screen's callbacks, don't clear all
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
  final double playerX; // Game X coordinate
  final double playerY; // Game Y coordinate
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
    // Determine source rect based on direction
    // Down = top left 512x512 (0, 0, 512, 512)
    // Up = top right 512x512 (512, 0, 512, 512)
    // Left/right keep the last vertical direction (direction parameter already has this)
    Rect sourceRect;
    if (direction == PlayerDirection.down) {
      sourceRect = const Rect.fromLTWH(0, 0, 512, 512);
    } else if (direction == PlayerDirection.up) {
      sourceRect = const Rect.fromLTWH(512, 0, 512, 512);
    } else {
      // For left/right, direction should already be set to last vertical direction
      // Default to down (top left) if somehow it's not up or down
      sourceRect = const Rect.fromLTWH(0, 0, 512, 512);
    }

    // Convert world coordinates to screen coordinates
    final screenX = worldToScreenX(worldX);
    final screenY = worldToScreenY(worldY);
    
    // Center the sprite (x, y is the center of the sprite)
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
    return char1Sprite; // Default fallback
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Always draw black background first (for areas outside world bounds)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black,
    );
    
    // Draw world background image
    if (worldBackground != null) {
      // Calculate the visible world area (camera view)
      final worldStartX = playerX - size.width / 2;
      final worldStartY = playerY - size.height / 2;
      final worldEndX = playerX + size.width / 2;
      final worldEndY = playerY + size.height / 2;
      
      // Calculate source rect from background image (scale to world size)
      final bgWidth = worldBackground!.width.toDouble();
      final bgHeight = worldBackground!.height.toDouble();
      const worldWidth = 10000.0;
      const worldHeight = 10000.0;
      
      // Clamp world coordinates to valid range
      final clampedWorldStartX = worldStartX.clamp(0.0, worldWidth);
      final clampedWorldStartY = worldStartY.clamp(0.0, worldHeight);
      final clampedWorldEndX = worldEndX.clamp(0.0, worldWidth);
      final clampedWorldEndY = worldEndY.clamp(0.0, worldHeight);
      
      // Calculate which part of the background image to show
      // X is straightforward: left to right
      final sourceX = (clampedWorldStartX / worldWidth) * bgWidth;
      // Y needs to be inverted: when player Y increases (moves up), show lower part of image
      final sourceY = ((worldHeight - clampedWorldEndY) / worldHeight) * bgHeight;
      final sourceWidth = ((clampedWorldEndX - clampedWorldStartX) / worldWidth) * bgWidth;
      final sourceHeight = ((clampedWorldEndY - clampedWorldStartY) / worldHeight) * bgHeight;
      
      // Calculate screen position for the background (offset if camera is outside world)
      final screenOffsetX = (clampedWorldStartX - worldStartX);
      final screenOffsetY = (clampedWorldStartY - worldStartY);
      
      final sourceRect = Rect.fromLTWH(
        sourceX.clamp(0.0, bgWidth),
        sourceY.clamp(0.0, bgHeight),
        sourceWidth.clamp(0.0, bgWidth - sourceX.clamp(0.0, bgWidth)),
        sourceHeight.clamp(0.0, bgHeight - sourceY.clamp(0.0, bgHeight)),
      );
      
      final destRect = Rect.fromLTWH(
        screenOffsetX,
        screenOffsetY,
        sourceWidth,
        sourceHeight,
      );
      
      canvas.drawImageRect(worldBackground!, sourceRect, destRect, Paint());
    }
    
    // Draw other players (world coordinates)
    for (var player in players.values) {
      if (player.id != currentPlayerId) {
        final playerSpriteType = player.spriteType ?? 'char-2';
        final sprite = _getSpriteForType(playerSpriteType);
        
        if (sprite != null) {
          _drawSprite(canvas, sprite, player.x, player.y, playerSize, player.direction);
        } else {
          // Fallback to rectangle if sprite not loaded
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
        
        // Draw player name (centered above sprite)
        final screenX = worldToScreenX(player.x);
        final screenY = worldToScreenY(player.y);
        final fontSize = playerSize * 0.1; // Scale font with player size
        final textPainter = TextPainter(
          text: TextSpan(
            text: player.name,
            style: TextStyle(color: Colors.black, fontSize: fontSize),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        // Center the text above the sprite (sprite is centered, so text is centered above)
        final textX = screenX - textPainter.width / 2;
        textPainter.paint(canvas, Offset(textX, screenY - playerSize / 2 - fontSize * 1.2));
      }
    }

    // Draw current player (on top) - always at screen center
    // Only draw if character is loaded
    if (currentPlayerId.isNotEmpty && currentPlayerName.isNotEmpty) {
      final currentSprite = _getSpriteForType(currentPlayerSpriteType);
      if (currentSprite != null) {
        // Current player is always at screen center (world position is playerX, playerY)
        _drawSprite(canvas, currentSprite, playerX, playerY, playerSize, currentPlayerDirection);
      } else {
        // Fallback to rectangle if sprite not loaded
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
      
      // Draw current player name (centered above sprite)
      final screenX = worldToScreenX(playerX);
      final screenY = worldToScreenY(playerY);
      final fontSize = playerSize * 0.1; // Scale font with player size
      final textPainter = TextPainter(
        text: TextSpan(
          text: currentPlayerName,
          style: TextStyle(color: Colors.black, fontSize: fontSize),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      // Center the text above the sprite (sprite is centered, so text is centered above)
      final textX = screenX - textPainter.width / 2;
      textPainter.paint(canvas, Offset(textX, screenY - playerSize / 2 - fontSize * 1.2));
    }
  }

  @override
  bool shouldRepaint(GameWorldPainter oldDelegate) {
    // Always repaint if player positions changed
    if (oldDelegate.players.length != players.length) {
      return true;
    }
    
    // Check if any player position changed
    for (var playerId in players.keys) {
      final oldPlayer = oldDelegate.players[playerId];
      final newPlayer = players[playerId];
      if (oldPlayer == null || newPlayer == null) {
        return true;
      }
      // Use a small threshold to account for floating point precision
      if ((oldPlayer.x - newPlayer.x).abs() > 0.01 || 
          (oldPlayer.y - newPlayer.y).abs() > 0.01 ||
          oldPlayer.direction != newPlayer.direction) {
        return true;
      }
    }
    
    // Check current player position
    if ((oldDelegate.playerX - playerX).abs() > 0.01 ||
        (oldDelegate.playerY - playerY).abs() > 0.01) {
      return true;
    }
    
    // Check other properties
    return oldDelegate.currentPlayerName != currentPlayerName ||
        oldDelegate.currentPlayerDirection != currentPlayerDirection ||
        oldDelegate.currentPlayerSpriteType != currentPlayerSpriteType ||
        oldDelegate.char1Sprite != char1Sprite ||
        oldDelegate.char2Sprite != char2Sprite;
  }
}

