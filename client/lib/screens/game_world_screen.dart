import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/game_service.dart';
import '../services/api_service.dart';
import '../models/player.dart';
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
  // Game coordinates: center is (0, 0), left is -x, right is +x, up is +y, down is -y
  double _playerX = 0.0; // Game X coordinate (center = 0)
  double _playerY = 0.0; // Game Y coordinate (center = 0, up is +y, down is -y)
  final double _playerSpeed = 5.0;
  final double _playerSize = 128.0; // Player sprite size
  Timer? _positionUpdateTimer;
  Timer? _movementTimer;
  double _lastSentX = 0.0;
  double _lastSentY = 0.0;
  
  // Screen dimensions (playable area)
  static const double _screenWidth = 800.0;
  static const double _screenHeight = 600.0;
  
  // Convert game coordinates to screen coordinates
  double _gameToScreenX(double gameX) => gameX + _screenWidth / 2;
  double _gameToScreenY(double gameY) => _screenHeight / 2 - gameY;
  
  // Convert screen coordinates to game coordinates
  double _screenToGameX(double screenX) => screenX - _screenWidth / 2;
  double _screenToGameY(double screenY) => _screenHeight / 2 - screenY;
  final Set<LogicalKeyboardKey> _pressedKeys = {};
  PlayerDirection _playerDirection = PlayerDirection.down;
  PlayerDirection _lastVerticalDirection = PlayerDirection.down; // Track last up/down for left/right movement
  ui.Image? _char1Sprite;
  ui.Image? _char2Sprite;
  bool _showSettingsModal = false;
  bool _showCharacterCreateModal = false;
  String? _settingsView; // null = main menu, 'characterSelect' = character select inside settings
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
        final dx = (_playerX - _lastSentX).abs();
        final dy = (_playerY - _lastSentY).abs();
        
        // Send if moved more than 0.5 pixels (more frequent updates)
        if (dx > 0.5 || dy > 0.5) {
          // Send screen coordinates (convert game coordinates to screen for server)
          _gameService.movePlayer(_gameToScreenX(_playerX), _gameToScreenY(_playerY));
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
    // Send screen coordinates (convert game coordinates to screen for server)
    final screenX = _gameToScreenX(_playerX);
    final screenY = _gameToScreenY(_playerY);
    _gameService.joinGame(
      widget.characterId!,
      widget.characterName!,
      spriteType: widget.spriteType ?? 'char-1',
      x: screenX,
      y: screenY,
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
          // Convert from screen coordinates (from server) to game coordinates
          player.x = _screenToGameX(player.x);
          player.y = _screenToGameY(player.y);
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
        // Convert from screen coordinates (from server) to game coordinates
        player.x = _screenToGameX(player.x);
        player.y = _screenToGameY(player.y);
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
      setState(() {
        if (_players.containsKey(playerId)) {
          final oldX = _players[playerId]!.x;
          final oldY = _players[playerId]!.y;
          // Convert from screen coordinates (from server) to game coordinates
          final screenX = (data['x'] as num).toDouble();
          final screenY = (data['y'] as num).toDouble();
          final newX = _screenToGameX(screenX);
          final newY = _screenToGameY(screenY);
          
          _players[playerId]!.x = newX;
          _players[playerId]!.y = newY;
          
          // Infer direction from movement
          // Only update if vertical movement (up/down), otherwise keep last vertical direction
          final dx = newX - oldX;
          final dy = newY - oldY;
          if (dy != 0) {
            // Vertical movement - update direction (in game coords, +y is up)
            _players[playerId]!.direction = dy > 0 ? PlayerDirection.up : PlayerDirection.down;
          }
          // Horizontal movement (left/right) doesn't change the sprite direction
        } else {
          // Player moved but not in our list - add them (might be a late join)
          print('Received movement for unknown player: $playerId, adding to map');
          final player = Player.fromJson(data);
          player.x = _screenToGameX((data['x'] as num).toDouble());
          player.y = _screenToGameY((data['y'] as num).toDouble());
          _players[playerId] = player;
        }
      });
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
    if (_pressedKeys.isEmpty) return;
    if (widget.characterId == null) return; // Don't allow movement without character
    
    double deltaX = 0;
    double deltaY = 0;
    PlayerDirection? newVerticalDirection;
    
    // Check which keys are pressed and calculate movement
    if (_pressedKeys.contains(LogicalKeyboardKey.arrowLeft) ||
        _pressedKeys.contains(LogicalKeyboardKey.keyA)) {
      deltaX -= _playerSpeed;
      // Left/right don't change sprite, use last vertical direction
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.arrowRight) ||
        _pressedKeys.contains(LogicalKeyboardKey.keyD)) {
      deltaX += _playerSpeed;
      // Left/right don't change sprite, use last vertical direction
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.arrowUp) ||
        _pressedKeys.contains(LogicalKeyboardKey.keyW)) {
      deltaY += _playerSpeed; // Up is +y in game coordinates
      newVerticalDirection = PlayerDirection.up;
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.arrowDown) ||
        _pressedKeys.contains(LogicalKeyboardKey.keyS)) {
      deltaY -= _playerSpeed; // Down is -y in game coordinates
      newVerticalDirection = PlayerDirection.down;
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
        
        // Keep player in bounds (game coordinates: center is 0,0)
        // X ranges from -400 to +400 (half screen width minus half player size)
        // Y ranges from -300 to +300 (half screen height minus half player size)
        _playerX = _playerX.clamp(-(_screenWidth / 2 - _playerSize / 2), _screenWidth / 2 - _playerSize / 2);
        _playerY = _playerY.clamp(-(_screenHeight / 2 - _playerSize / 2), _screenHeight / 2 - _playerSize / 2);
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
                  _gameToScreenX,
                  _gameToScreenY,
                ),
                size: Size.infinite,
              ),
            ),
            // Settings button (top left)
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
                icon: const Icon(Icons.settings, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  padding: const EdgeInsets.all(8),
                ),
                tooltip: 'Settings',
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
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black54,
                child: Text(
                  widget.characterId == null 
                      ? 'No character loaded - Select a character to play'
                      : 'Use WASD or Arrow Keys to move',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            // Character creation modal (standalone, only when not in settings)
            if (_showCharacterCreateModal && !_showSettingsModal)
              _buildCharacterCreateModal(),
            ],
          ),
        ),
    );
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
              : Column(
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

  Widget _buildCharacterCreateModal() {
    final nameController = TextEditingController();
    String selectedSpriteType = 'char-1';

    return Center(
      child: StatefulBuilder(
        builder: (context, setModalState) {
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
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 12),
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
  final double Function(double) gameToScreenX;
  final double Function(double) gameToScreenY;

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
    this.gameToScreenX,
    this.gameToScreenY,
  );

  void _drawSprite(
    Canvas canvas,
    ui.Image sprite,
    double x,
    double y,
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

    final destRect = Rect.fromLTWH(x, y, size, size);
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
    // Draw playable area with different colors based on position
    const double playableWidth = 800.0;
    const double playableHeight = 600.0;
    const double halfWidth = playableWidth / 2;
    const double halfHeight = playableHeight / 2;
    
    // Top left: #F1FADC
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, halfWidth, halfHeight),
      Paint()..color = const Color(0xFFF1FADC),
    );
    
    // Top right: #FAE9DC
    canvas.drawRect(
      Rect.fromLTWH(halfWidth, 0, halfWidth, halfHeight),
      Paint()..color = const Color(0xFFFAE9DC),
    );
    
    // Bottom left: #DCF6FA
    canvas.drawRect(
      Rect.fromLTWH(0, halfHeight, halfWidth, halfHeight),
      Paint()..color = const Color(0xFFDCF6FA),
    );
    
    // Bottom right: #F1FADC
    canvas.drawRect(
      Rect.fromLTWH(halfWidth, halfHeight, halfWidth, halfHeight),
      Paint()..color = const Color(0xFFF1FADC),
    );
    
    // Draw other players (convert game coordinates to screen coordinates)
    for (var player in players.values) {
      if (player.id != currentPlayerId) {
        // Convert player game coordinates to screen coordinates
        // Note: assuming players come from server in game coordinates
        final screenX = gameToScreenX(player.x);
        final screenY = gameToScreenY(player.y);
        
        final playerSpriteType = player.spriteType ?? 'char-2';
        final sprite = _getSpriteForType(playerSpriteType);
        
        if (sprite != null) {
          _drawSprite(canvas, sprite, screenX, screenY, 128, player.direction);
        } else {
          // Fallback to rectangle if sprite not loaded
          final paint = Paint()..color = Colors.blue;
          canvas.drawRect(
            Rect.fromLTWH(screenX, screenY, 128, 128),
            paint,
          );
        }
        
        // Draw player name (centered above sprite)
        final textPainter = TextPainter(
          text: TextSpan(
            text: player.name,
            style: const TextStyle(color: Colors.black, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        // Center the text above the sprite (sprite size is 128)
        final textX = screenX + (128 - textPainter.width) / 2;
        textPainter.paint(canvas, Offset(textX, screenY - 16));
      }
    }

    // Draw current player (on top) - use character's sprite type
    // Only draw if character is loaded
    if (currentPlayerId.isNotEmpty && currentPlayerName.isNotEmpty) {
      // Convert current player game coordinates to screen coordinates
      final screenX = gameToScreenX(playerX);
      final screenY = gameToScreenY(playerY);
      
      final currentSprite = _getSpriteForType(currentPlayerSpriteType);
      if (currentSprite != null) {
        _drawSprite(canvas, currentSprite, screenX, screenY, 128, currentPlayerDirection);
      } else {
        // Fallback to rectangle if sprite not loaded
        final currentPlayerPaint = Paint()..color = Colors.red;
        canvas.drawRect(
          Rect.fromLTWH(screenX, screenY, 128, 128),
          currentPlayerPaint,
        );
      }
      
      // Draw current player name (centered above sprite)
      final textPainter = TextPainter(
        text: TextSpan(
          text: currentPlayerName,
          style: const TextStyle(color: Colors.black, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      // Center the text above the sprite (sprite size is 128)
      final textX = screenX + (128 - textPainter.width) / 2;
      textPainter.paint(canvas, Offset(textX, screenY - 16));
    }
  }

  @override
  bool shouldRepaint(GameWorldPainter oldDelegate) {
    return oldDelegate.playerX != playerX ||
        oldDelegate.playerY != playerY ||
        oldDelegate.players.length != players.length ||
        oldDelegate.currentPlayerName != currentPlayerName ||
        oldDelegate.currentPlayerDirection != currentPlayerDirection ||
        oldDelegate.currentPlayerSpriteType != currentPlayerSpriteType ||
        oldDelegate.char1Sprite != char1Sprite ||
        oldDelegate.char2Sprite != char2Sprite;
  }
}

