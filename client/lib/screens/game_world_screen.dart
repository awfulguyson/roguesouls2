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
  // Game world coordinates: world is 10000x10000, origin at (0, 0) in top-left
  // Player position in world coordinates
  double _playerX = 5000.0; // Start at center of world
  double _playerY = 5000.0; // Start at center of world
  final double _playerSpeed = 5.0;
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
    // 1. Smaller screens (both width AND height < 768px, or very small in one dimension)
    // 2. Higher pixel density (devicePixelRatio > 1.5 for most mobile)
    // 3. Aspect ratio closer to phone/tablet (not ultra-wide desktop)
    
    // More lenient: only consider mobile if BOTH dimensions are small, or one is very small
    final isSmallScreen = (size.width < 600 && size.height < 600) || 
                          (size.width < 400 || size.height < 400);
    final hasHighDensity = mediaQuery.devicePixelRatio > 1.5;
    final aspectRatio = size.width / size.height;
    final isPhoneAspectRatio = aspectRatio > 0.5 && aspectRatio < 2.5; // Typical phone/tablet range
    
    // Consider it mobile if it's a small screen with high pixel density and phone-like aspect ratio
    // This prevents desktop browsers with resized windows from showing joystick
    return isSmallScreen && hasHighDensity && isPhoneAspectRatio;
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
  String? _settingsView; // null = main menu, 'characterSelect' = character select, 'settings' = settings view, 'howToPlay' = how to play
  bool _joystickOnRight = true; // Default: joystick on right side
  Map<String, dynamic>? _selectedCharacter; // Selected character in character select screen
  String? _accountId;
  List<dynamic> _characters = [];
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
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
    });
    
    // Only join game if character is loaded
    if (widget.characterId != null) {
      // Wait for socket to connect before joining
      _gameService.socket?.on('connect', (_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _joinGameWithCharacter();
        });
      });
      
      // Also try after a delay in case already connected
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (widget.characterId != null && _gameService.socket?.connected == true) {
          _joinGameWithCharacter();
        }
      });
      
      // Game loop: check pressed keys and move player continuously (60 FPS)
      _movementTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        _updateMovement();
      });
      
      // Send position updates periodically (every 50ms) to keep other players synced
      // Send even small movements for smoother synchronization
      _positionUpdateTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (widget.characterId == null) return;
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
    } else {
      // No character loaded - show settings modal
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
    if (widget.characterId == null) return;
    print('Joining game with character: ${widget.characterId}');
    // Send game world coordinates directly (not screen coordinates)
    _gameService.joinGame(
      widget.characterId!,
      widget.characterName!,
      spriteType: widget.spriteType ?? 'char-1',
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
      print('onPlayersList called with ${players.length} players, characterId: ${widget.characterId}');
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
          if (widget.characterId == null || player.id != widget.characterId) {
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
      print('onPlayerJoined called: $data, characterId: ${widget.characterId}');
      if (!mounted) {
        print('Skipping: not mounted');
        return;
      }
      setState(() {
        final player = Player.fromJson(data);
        print('Parsed joined player: id=${player.id}, name=${player.name}');
        // Positions from server are already in game world coordinates
        // Only skip if this is our own character (when we have one)
        if (widget.characterId == null || player.id != widget.characterId) {
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
      if (widget.characterId != null && playerId == widget.characterId) {
        return;
      }
      
      // Positions from server are already in game world coordinates
      final newX = (data['x'] as num).toDouble();
      final newY = (data['y'] as num).toDouble();
      
      // Always update state to trigger repaint, even if player already exists
      if (_players.containsKey(playerId)) {
        final oldX = _players[playerId]!.x;
        final oldY = _players[playerId]!.y;
        
        // Only update if position actually changed (avoid unnecessary repaints)
        if ((oldX - newX).abs() > 0.1 || (oldY - newY).abs() > 0.1) {
          setState(() {
            _players[playerId]!.x = newX;
            _players[playerId]!.y = newY;
            
            // Infer direction from movement
            final dx = newX - oldX;
            final dy = newY - oldY;
            if (dy != 0) {
              // Vertical movement - update direction (in game coords, +y is up)
              _players[playerId]!.direction = dy > 0 ? PlayerDirection.up : PlayerDirection.down;
            }
          });
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
    if (widget.characterId == null) return; // Don't allow movement without character
    
    double deltaX = 0;
    double deltaY = 0;
    PlayerDirection? newVerticalDirection;
    
    // Check if mobile - use joystick if joystick has input, otherwise check screen size
    // If joystick is being used (has input), it's mobile
    final isUsingJoystick = _joystickDeltaX.abs() > 0.1 || _joystickDeltaY.abs() > 0.1;
    final isSmallScreen = _screenWidth < 768 || _screenHeight < 768;
    
    if (isUsingJoystick || isSmallScreen) {
      // Mobile: use joystick input
      if (_joystickDeltaX.abs() > 0.1 || _joystickDeltaY.abs() > 0.1) {
        deltaX = _joystickDeltaX * _playerSpeed;
        deltaY = _joystickDeltaY * _playerSpeed; // Joystick: negative Y is up, world: up increases Y
        
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
      }
    } else {
      // Desktop: use keyboard input
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
        _playerX = _playerX.clamp(_playerSize / 2, _worldWidth - _playerSize / 2);
        _playerY = _playerY.clamp(_playerSize / 2, _worldHeight - _playerSize / 2);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions and update game world size
    final mediaQuery = MediaQuery.of(context);
    _screenWidth = mediaQuery.size.width;
    _screenHeight = mediaQuery.size.height;
    
    // Scale player size based on screen (maintain aspect ratio)
    _playerSize = min(_screenWidth, _screenHeight) * 0.16; // ~16% of smaller dimension
    
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
                key: ValueKey('game_${_players.length}_${_worldBackground != null ? "bg" : "nobg"}_${DateTime.now().millisecondsSinceEpoch ~/ 100}'), // Force repaint on player changes or background load
                painter: GameWorldPainter(
                  _players,
                  _playerX,
                  _playerY,
                  widget.characterId ?? '',
                  widget.characterName ?? '',
                  _playerDirection,
                  widget.spriteType ?? 'char-1',
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
                      widget.characterId == null 
                          ? 'No Character'
                          : 'Players: ${_players.length + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    if (widget.characterId != null)
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
            // Virtual joystick (mobile only)
            if (isMobile && widget.characterId != null)
              Positioned(
                bottom: max(20.0, _screenHeight * 0.05), // At least 20px or 5% of screen height
                left: _joystickOnRight ? null : max(20.0, _screenWidth * 0.05), // Left side
                right: _joystickOnRight ? max(20.0, _screenWidth * 0.05) : null, // Right side (default)
                child: VirtualJoystick(
                  size: min(min(_screenWidth, _screenHeight) * 0.2, 150), // 20% of smaller dimension, max 150px
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
    
    // Wrap with KeyboardListener only on desktop
    if (isMobile) {
      return gameContent;
    } else {
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
        child: gameContent,
      );
    }
  }

  Widget _buildSettingsModal() {
    return Center(
      child: GestureDetector(
        onTap: () {}, // Prevent closing when tapping inside
        child: Container(
          width: 200,
          height: 300,
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

  Widget _buildSettingsContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
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
              // Joystick position toggle
              ListTile(
                dense: true,
                leading: const Icon(Icons.gamepad, size: 20),
                title: const Text(
                  'Joystick Position',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  _joystickOnRight ? 'Right' : 'Left',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Switch(
                  value: _joystickOnRight,
                  onChanged: (value) {
                    setState(() {
                      _joystickOnRight = value;
                    });
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
    final nameController = TextEditingController();
    String selectedSpriteType = 'char-1';

    return Center(
      child: StatefulBuilder(
        builder: (context, setModalState) {
          final focusNode = FocusNode();
          return Container(
            width: 200,
            height: 300,
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
                    focusNode: focusNode,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.done,
                    autofocus: false,
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onTap: () {
                      // Ensure focus on tap for mobile
                      focusNode.requestFocus();
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
                            selectedSpriteType = 'char-1';
                          });
                        },
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: selectedSpriteType == 'char-1' ? Colors.blue : Colors.grey,
                              width: selectedSpriteType == 'char-1' ? 2 : 1,
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
                            selectedSpriteType = 'char-2';
                          });
                        },
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: selectedSpriteType == 'char-2' ? Colors.blue : Colors.grey,
                              width: selectedSpriteType == 'char-2' ? 2 : 1,
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
                        if (nameController.text.isEmpty || _accountId == null) return;
                        
                        try {
                          await _apiService.createCharacter(
                            _accountId!,
                            nameController.text,
                            selectedSpriteType,
                          );
                          await _refreshCharacters();
                          // Close create modal and show character select in settings
                          if (mounted) {
                            setState(() {
                              _showCharacterCreateModal = false;
                              _showSettingsModal = true;
                              _settingsView = 'characterSelect';
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
    setState(() {
      _showSettingsModal = false;
      _showCharacterCreateModal = false;
      _settingsView = null;
      _selectedCharacter = null;
    });

    // Update widget state by replacing the screen, preserving accountId and WebSocket connection
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => GameWorldScreen(
          characterId: character['id'] as String,
          characterName: character['name'] as String,
          spriteType: character['spriteType'] as String? ?? 'char-1',
          isTemporary: widget.isTemporary,
          accountId: _accountId, // Preserve the account ID
        ),
      ),
    );
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
    // Draw world background image
    if (worldBackground != null) {
      // Calculate the visible world area
      // When player moves up (Y increases), we want to show lower parts of the image
      // So we need to invert the Y calculation
      final worldStartX = playerX - size.width / 2;
      final worldStartY = playerY - size.height / 2;
      final worldEndX = playerX + size.width / 2;
      final worldEndY = playerY + size.height / 2;
      
      // Calculate source rect from background image (scale to world size)
      final bgWidth = worldBackground!.width.toDouble();
      final bgHeight = worldBackground!.height.toDouble();
      const worldWidth = 10000.0;
      const worldHeight = 10000.0;
      
      // Calculate which part of the background image to show
      // X is straightforward: left to right
      final sourceX = (worldStartX / worldWidth) * bgWidth;
      // Y needs to be inverted: when player Y increases (moves up), show lower part of image
      // So we calculate from the bottom: worldHeight - worldStartY
      final sourceY = ((worldHeight - worldEndY) / worldHeight) * bgHeight;
      final sourceWidth = ((worldEndX - worldStartX) / worldWidth) * bgWidth;
      final sourceHeight = ((worldEndY - worldStartY) / worldHeight) * bgHeight;
      
      final sourceRect = Rect.fromLTWH(
        sourceX.clamp(0.0, bgWidth).toDouble(),
        sourceY.clamp(0.0, bgHeight).toDouble(),
        sourceWidth.clamp(0.0, bgWidth - sourceX).toDouble(),
        sourceHeight.clamp(0.0, bgHeight - sourceY).toDouble(),
      );
      
      final destRect = Rect.fromLTWH(0, 0, size.width, size.height);
      
      canvas.drawImageRect(worldBackground!, sourceRect, destRect, Paint());
    } else {
      // Fallback: draw black background if image not loaded
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.black,
      );
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

