import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/game_service.dart';
import '../services/api_service.dart';
import '../models/player.dart';
import '../models/enemy.dart';
import '../models/projectile.dart';
import '../models/gold_coin.dart' show CurrencyCoin, CurrencyType;
import '../models/floating_text.dart';
import '../widgets/virtual_joystick.dart';
import 'initial_screen.dart';
import 'character_select_screen.dart';
import 'dart:html' as html show window;

class _TargetEnemyIntent extends Intent {
  const _TargetEnemyIntent();
}

// Helper painter for character image
class _CharacterImagePainter extends CustomPainter {
  final ui.Image image;
  
  _CharacterImagePainter(this.image);
  
  @override
  void paint(Canvas canvas, Size size) {
    final sourceRect = const Rect.fromLTWH(0, 0, 800, 800);
    final destRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;
    canvas.drawImageRect(image, sourceRect, destRect, paint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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
  int _repaintCounter = 0;
  double _playerX = 0.0;
  double _playerY = 0.0;
  double _playerSpeed = 7.5;
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
  // Track last movement direction for rotation (default facing down/south)
  double _playerLastMoveX = 0.0;
  double _playerLastMoveY = 1.0; // Default facing down
  double _playerLastRotationAngle = 0.0; // Default rotation (facing down)
  ui.Image? _char1Sprite;
  ui.Image? _char2Sprite;
  ui.Image? _worldBackground;
  ui.Image? _enemy1Sprite;
  ui.Image? _enemy2Sprite;
  ui.Image? _enemy3Sprite;
  ui.Image? _enemy4Sprite;
  ui.Image? _zombie1Sprite; // Sprite sheet for enemy-5
  
  // Enemies with fixed positions
  final List<Enemy> _enemies = [];
  final Random _random = Random();
  String? _targetedEnemyId;
  Timer? _enemyUpdateTimer;
  
  // Player health
  double _playerHp = 100.0;
  double _playerMaxHp = 100.0;
  bool _isDead = false;
  DateTime? _deathTime;
  Set<String> _aggroEnemyIds = {}; // Enemies targeting the current player
  
  // Player experience
  int _playerExp = 0;
  int _playerLevel = 1;
  static const int _expPerLevel = 100; // Base exp needed per level
  
  // Player currency (stored in base units: copper)
  int _playerCopper = 0;
  int _playerSilver = 0;
  int _playerGold = 0;
  int _playerPlatinum = 0;
  
  // Currency coins and floating text
  final List<CurrencyCoin> _currencyCoins = [];
  final List<FloatingText> _floatingTexts = [];
  int _currencyCoinIdCounter = 0;
  int _floatingTextIdCounter = 0;
  
  // Projectiles
  final List<Projectile> _projectiles = [];
  DateTime? _lastAbility1Use;
  static const Duration _ability1Cooldown = Duration(milliseconds: 500);
  int _projectileIdCounter = 0;
  bool _showSettingsModal = false;
  bool _showCharacterCreateModal = false;
  bool _showCharacterSelectModal = false;
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
  
  // Loading screen state
  bool _isLoading = true;
  String _loadingStatus = 'Loading assets...';
  double _loadingProgress = 0.0;
  bool _assetsLoaded = false;
  bool _serverConnected = false;
  bool _accountInitialized = false;
  DateTime? _loadingStartTime;

  @override
  void initState() {
    super.initState();
    _loadingStartTime = DateTime.now();
    _currentCharacterId = widget.characterId;
    _currentCharacterName = widget.characterName;
    _currentSpriteType = widget.spriteType;
    
    _loadSprites();
    _setupGameService();
    _gameService.connect();
    _initializeAccount();
    _checkLoadingComplete();
    
    // Prevent Tab key from triggering browser focus navigation on web
    // Only when the game screen has focus
    if (kIsWeb) {
      html.window.document.addEventListener('keydown', (event) {
        final keyEvent = event as dynamic;
        if (keyEvent.keyCode == 9 && _keyboardFocusNode.hasFocus) { // Tab key
          event.preventDefault();
          event.stopPropagation();
        }
      }, true);
    }
    
    // Timeout: if server doesn't connect within 10 seconds, proceed anyway
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && !_serverConnected) {
        setState(() {
          _serverConnected = true; // Allow game to proceed
          _loadingStatus = 'Server connection timeout - continuing offline';
          _checkLoadingComplete();
        });
      }
    });
    
    _gameService.socket?.on('connect', (_) {
      print('Socket connected, requesting player list...');
      _gameService.socket?.emit('game:requestPlayers');
      
      // Request enemies update (server should send on connect, but request just in case)
      print('Requesting enemies from server...');
      _gameService.socket?.emit('game:requestEnemies');
      
      if (mounted) {
        setState(() {
          _serverConnected = true;
          _loadingProgress = 0.8;
          if (!_accountInitialized) {
            _loadingStatus = 'Initializing account...';
          } else {
            _loadingStatus = 'Ready!';
            _loadingProgress = 1.0;
          }
          _checkLoadingComplete();
        });
      }
      
      if (_currentCharacterId != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _joinGameWithCharacter();
        });
      }
    });
    
    _gameService.socket?.on('reconnect', (_) {
      print('Socket reconnected, rejoining game...');
      _gameService.socket?.emit('game:requestPlayers');
      
      if (mounted) {
        setState(() {
          _serverConnected = true;
          _loadingProgress = 0.8;
          if (!_accountInitialized) {
            _loadingStatus = 'Initializing account...';
          } else {
            _loadingStatus = 'Ready!';
            _loadingProgress = 1.0;
          }
          _checkLoadingComplete();
        });
      }
      
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
      _updateProjectiles(16 / 1000.0); // Convert milliseconds to seconds
      _checkCurrencyCollection(); // Check for currency collection
      _updateFloatingTexts(); // Update floating text animations
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
    
    // Enemy updates are now received from server, no local timer needed
    
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
      accountId: _accountId,
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
            _accountInitialized = true;
            _loadingProgress = 0.9;
            if (_serverConnected) {
              _loadingStatus = 'Ready!';
              _loadingProgress = 1.0;
            } else {
              _loadingStatus = 'Connecting to server...';
            }
            _checkLoadingComplete();
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
            _accountInitialized = true;
            _loadingProgress = 0.9;
            if (_serverConnected) {
              _loadingStatus = 'Ready!';
              _loadingProgress = 1.0;
            } else {
              _loadingStatus = 'Connecting to server...';
            }
            _checkLoadingComplete();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _accountInitialized = true;
          _loadingProgress = 0.9;
          if (_serverConnected) {
            _loadingStatus = 'Ready!';
            _loadingProgress = 1.0;
          } else {
            _loadingStatus = 'Connecting to server...';
          }
          _checkLoadingComplete();
        });
      }
    }
  }

  void _checkLoadingComplete() {
    if (_assetsLoaded && _serverConnected && _accountInitialized) {
      // Ensure "Ready!" status is set
      if (mounted && _loadingStatus != 'Ready!') {
        setState(() {
          _loadingStatus = 'Ready!';
          _loadingProgress = 1.0;
        });
      }
      
      if (_loadingStartTime == null) return;
      
      final elapsed = DateTime.now().difference(_loadingStartTime!);
      final minimumDisplayTime = const Duration(seconds: 1);
      final remainingTime = minimumDisplayTime - elapsed;
      
      // Wait for minimum 1 second, or show "Ready!" for at least 500ms
      final delay = remainingTime.isNegative 
          ? const Duration(milliseconds: 500)
          : remainingTime + const Duration(milliseconds: 500);
      
      Future.delayed(delay, () {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      });
    }
  }

  Future<void> _loadSprites() async {
    if (mounted) {
      setState(() {
        _loadingStatus = 'Loading assets...';
        _loadingProgress = 0.1;
      });
    }
    
    final char1Bytes = await rootBundle.load('assets/char-1.png');
    final char1Codec = await ui.instantiateImageCodec(char1Bytes.buffer.asUint8List());
    final char1Frame = await char1Codec.getNextFrame();
    _char1Sprite = char1Frame.image;
    
    if (mounted) {
      setState(() {
        _loadingProgress = 0.3;
      });
    }

    final char2Bytes = await rootBundle.load('assets/char-2.png');
    final char2Codec = await ui.instantiateImageCodec(char2Bytes.buffer.asUint8List());
    final char2Frame = await char2Codec.getNextFrame();
    _char2Sprite = char2Frame.image;
    
    if (mounted) {
      setState(() {
        _loadingProgress = 0.5;
      });
    }

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
      setState(() {
        _loadingProgress = 0.55;
      });
    }
    
    // Load enemy sprites
    try {
      final enemy1Bytes = await rootBundle.load('assets/enemy-1.png');
      final enemy1Codec = await ui.instantiateImageCodec(enemy1Bytes.buffer.asUint8List());
      final enemy1Frame = await enemy1Codec.getNextFrame();
      _enemy1Sprite = enemy1Frame.image;
    } catch (e) {
      print('❌ Failed to load enemy-1: $e');
    }
    
    try {
      final enemy2Bytes = await rootBundle.load('assets/enemy-2.png');
      final enemy2Codec = await ui.instantiateImageCodec(enemy2Bytes.buffer.asUint8List());
      final enemy2Frame = await enemy2Codec.getNextFrame();
      _enemy2Sprite = enemy2Frame.image;
    } catch (e) {
      print('❌ Failed to load enemy-2: $e');
    }
    
    try {
      final enemy3Bytes = await rootBundle.load('assets/enemy-3.png');
      final enemy3Codec = await ui.instantiateImageCodec(enemy3Bytes.buffer.asUint8List());
      final enemy3Frame = await enemy3Codec.getNextFrame();
      _enemy3Sprite = enemy3Frame.image;
    } catch (e) {
      print('❌ Failed to load enemy-3: $e');
    }
    
    try {
      final enemy4Bytes = await rootBundle.load('assets/enemy-4.png');
      final enemy4Codec = await ui.instantiateImageCodec(enemy4Bytes.buffer.asUint8List());
      final enemy4Frame = await enemy4Codec.getNextFrame();
      _enemy4Sprite = enemy4Frame.image;
    } catch (e) {
      print('❌ Failed to load enemy-4: $e');
    }
    
    try {
      final zombie1Bytes = await rootBundle.load('assets/zombie-1-sprite.png');
      final zombie1Codec = await ui.instantiateImageCodec(zombie1Bytes.buffer.asUint8List());
      final zombie1Frame = await zombie1Codec.getNextFrame();
      _zombie1Sprite = zombie1Frame.image;
      print('✅ Zombie sprite sheet loaded: ${_zombie1Sprite!.width}x${_zombie1Sprite!.height}');
    } catch (e) {
      print('❌ Failed to load zombie-1-sprite: $e');
    }
    
    // Enemies are now managed server-side, will be received via socket

    if (mounted) {
      setState(() {
        _assetsLoaded = true;
        _loadingProgress = 0.6;
        _loadingStatus = 'Connecting to server...';
        _checkLoadingComplete();
      });
    }
  }
  
  void _initializeEnemies() {
    _enemies.clear();
    // Add enemies at fixed positions around the world
    _enemies.addAll([
      Enemy(id: 'enemy_1', x: -1000.0, y: -1000.0, spriteType: 'enemy-1'),
      Enemy(id: 'enemy_2', x: 1000.0, y: -1000.0, spriteType: 'enemy-2'),
      Enemy(id: 'enemy_3', x: -1000.0, y: 1000.0, spriteType: 'enemy-3'),
      Enemy(id: 'enemy_4', x: 1000.0, y: 1000.0, spriteType: 'enemy-4'),
      Enemy(id: 'enemy_5', x: 0.0, y: -1500.0, spriteType: 'enemy-5'), // Zombie with sprite sheet
      Enemy(id: 'enemy_6', x: 1500.0, y: 0.0, spriteType: 'enemy-2'),
      Enemy(id: 'enemy_7', x: -1500.0, y: 0.0, spriteType: 'enemy-3'),
      Enemy(id: 'enemy_8', x: 0.0, y: 1500.0, spriteType: 'enemy-4'),
    ]);
  }

  void _setupGameService() {
    _playersListCallback = (players) {
      if (!mounted) {
        return;
      }
      setState(() {
        _players.clear();
        for (var playerData in players) {
          final player = Player.fromJson(playerData as Map<String, dynamic>);
          if (_currentCharacterId == null || player.id != _currentCharacterId) {
            _players[player.id] = player;
          }
        }
      });
    };
    _gameService.addPlayersListListener(_playersListCallback);

    _playerJoinedCallback = (data) {
      if (!mounted) {
        return;
      }
      setState(() {
        final player = Player.fromJson(data);
        if (_currentCharacterId == null || player.id != _currentCharacterId) {
          _players[player.id] = player;
        }
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
      
      // Update player HP if provided
      if (data['hp'] != null && data['maxHp'] != null) {
        if (_players.containsKey(playerId)) {
          _players[playerId]!.hp = (data['hp'] as num).toDouble();
          _players[playerId]!.maxHp = (data['maxHp'] as num).toDouble();
        }
      }
      
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
          _repaintCounter++;
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

    _enemiesUpdateCallback = (data) {
      if (!mounted) return;
      final enemyList = data as List<dynamic>;
      setState(() {
        // Update enemies from server
        for (var enemyData in enemyList) {
          final enemyJson = enemyData as Map<String, dynamic>;
          final enemyId = enemyJson['id'] as String;
          
          // Find existing enemy or create new one
          Enemy? existingEnemy;
          try {
            existingEnemy = _enemies.firstWhere((e) => e.id == enemyId);
          } catch (e) {
            // Enemy doesn't exist, create it
            existingEnemy = Enemy(
              id: enemyId,
              x: (enemyJson['x'] as num).toDouble(),
              y: (enemyJson['y'] as num).toDouble(),
              spriteType: enemyJson['spriteType'] as String,
            );
            _enemies.add(existingEnemy);
          }
          
          // Update enemy state from server
          existingEnemy.x = (enemyJson['x'] as num).toDouble();
          existingEnemy.y = (enemyJson['y'] as num).toDouble();
          existingEnemy.currentHp = (enemyJson['currentHp'] as num).toDouble();
          existingEnemy.maxHp = (enemyJson['maxHp'] as num).toDouble();
          existingEnemy.isMoving = enemyJson['isMoving'] as bool? ?? false;
          existingEnemy.moveDirectionX = (enemyJson['moveDirectionX'] as num?)?.toDouble() ?? 0.0;
          existingEnemy.moveDirectionY = (enemyJson['moveDirectionY'] as num?)?.toDouble() ?? 0.0;
          
          // Update attack state (if available)
          if (enemyJson['isAttacking'] != null) {
            // Store attack state if needed for visual feedback
          }
          
          // Update last rotation angle for zombie enemies
          if (existingEnemy.spriteType == 'enemy-5' && enemyJson['lastRotationAngle'] != null) {
            final lastRotationAngle = (enemyJson['lastRotationAngle'] as num).toDouble();
            existingEnemy.setLastRotationAngle(lastRotationAngle);
          }
        }
        
        // Remove enemies that are no longer in server state
        final serverEnemyIds = enemyList.map((e) => (e as Map<String, dynamic>)['id'] as String).toSet();
        _enemies.removeWhere((e) => !serverEnemyIds.contains(e.id));
        
        _repaintCounter++;
      });
    };
    _gameService.addEnemiesUpdateListener(_enemiesUpdateCallback);

    _enemyDamagedCallback = (data) {
      if (!mounted) return;
      final enemyId = data['enemyId'] as String;
      final currentHp = (data['currentHp'] as num).toDouble();
      
      try {
        final enemy = _enemies.firstWhere((e) => e.id == enemyId);
        setState(() {
          enemy.currentHp = currentHp;
          // Remove target if enemy died
          if (enemy.currentHp <= 0 && _targetedEnemyId == enemyId) {
            _targetedEnemyId = null;
          }
          _repaintCounter++;
        });
      } catch (e) {
        // Enemy not found, ignore
      }
    };
    _gameService.addEnemyDamagedListener(_enemyDamagedCallback);

    _enemyDeathCallback = (data) {
      if (!mounted) return;
      final enemyId = data['enemyId'] as String;
      final playerId = data['playerId'] as String;
      final x = (data['x'] as num).toDouble();
      final y = (data['y'] as num).toDouble();
      
      setState(() {
        // Remove enemy
        _enemies.removeWhere((e) => e.id == enemyId);
        
        // Remove target if it was targeted
        if (_targetedEnemyId == enemyId) {
          _targetedEnemyId = null;
        }
        
        // Give exp to last hitter
        if (playerId == _currentCharacterId) {
          _playerExp += 10;
          _updatePlayerLevel();
          
          // Show floating text for exp at player position
          _floatingTexts.add(FloatingText(
            id: 'floating_text_${_floatingTextIdCounter++}',
            x: _playerX,
            y: _playerY,
            text: '10 xp',
          ));
        }
        
        // Spawn currency coins for all players who dealt damage
        final lootDrops = data['lootDrops'] as List<dynamic>?;
        if (lootDrops != null) {
          for (var loot in lootDrops) {
            final lootData = loot as Map<String, dynamic>;
            final lootPlayerId = lootData['playerId'] as String;
            final copper = lootData['copper'] as int;
            final lootX = (lootData['x'] as num).toDouble();
            final lootY = (lootData['y'] as num).toDouble();
            
            // Convert copper to appropriate currency type
            CurrencyType currencyType;
            int currencyAmount;
            if (copper >= 1000000) {
              // Platinum (100 gold = 1 platinum)
              currencyType = CurrencyType.platinum;
              currencyAmount = copper ~/ 1000000;
            } else if (copper >= 10000) {
              // Gold (100 silver = 1 gold)
              currencyType = CurrencyType.gold;
              currencyAmount = copper ~/ 10000;
            } else if (copper >= 100) {
              // Silver (100 copper = 1 silver)
              currencyType = CurrencyType.silver;
              currencyAmount = copper ~/ 100;
            } else {
              // Copper
              currencyType = CurrencyType.copper;
              currencyAmount = copper;
            }
            
            _currencyCoins.add(CurrencyCoin(
              id: 'currency_coin_${_currencyCoinIdCounter++}',
              x: lootX,
              y: lootY,
              type: currencyType,
              amount: currencyAmount,
            ));
          }
        }
        
        _repaintCounter++;
      });
    };
    _gameService.addEnemyDeathListener(_enemyDeathCallback);

    // Listen for new enemy spawns
    _gameService.socket?.on('enemy:spawn', (data) {
      if (!mounted) return;
      final enemyJson = data as Map<String, dynamic>;
      final enemyId = enemyJson['id'] as String;
      
      // Check if enemy already exists
      if (_enemies.any((e) => e.id == enemyId)) {
        return;
      }
      
      final newEnemy = Enemy(
        id: enemyId,
        x: (enemyJson['x'] as num).toDouble(),
        y: (enemyJson['y'] as num).toDouble(),
        spriteType: enemyJson['spriteType'] as String,
      );
      
      // Update enemy state from server
      newEnemy.currentHp = (enemyJson['currentHp'] as num).toDouble();
      newEnemy.maxHp = (enemyJson['maxHp'] as num).toDouble();
      newEnemy.isMoving = enemyJson['isMoving'] as bool? ?? false;
      newEnemy.moveDirectionX = (enemyJson['moveDirectionX'] as num?)?.toDouble() ?? 0.0;
      newEnemy.moveDirectionY = (enemyJson['moveDirectionY'] as num?)?.toDouble() ?? 0.0;
      
      if (newEnemy.spriteType == 'enemy-5' && enemyJson['lastRotationAngle'] != null) {
        final lastRotationAngle = (enemyJson['lastRotationAngle'] as num).toDouble();
        newEnemy.setLastRotationAngle(lastRotationAngle);
      }
      
      setState(() {
        _enemies.add(newEnemy);
        _repaintCounter++;
      });
    });

    _projectileSpawnCallback = (data) {
      if (!mounted) return;
      // Only add projectiles from other players (not our own)
      final playerId = data['playerId'] as String;
      if (playerId == _currentCharacterId) {
        return; // We already created this projectile locally
      }
      
      final projectile = Projectile(
        id: data['id'] as String,
        x: (data['x'] as num).toDouble(),
        y: (data['y'] as num).toDouble(),
        targetX: (data['targetX'] as num).toDouble(),
        targetY: (data['targetY'] as num).toDouble(),
        speed: (data['speed'] as num).toDouble(),
        damage: 10.0, // Default damage
      );
      
      setState(() {
        _projectiles.add(projectile);
        _repaintCounter++;
      });
    };
    _gameService.addProjectileSpawnListener(_projectileSpawnCallback);

    _playerDamagedCallback = (data) {
      if (!mounted) return;
      final playerId = data['playerId'] as String;
      final currentHp = (data['currentHp'] as num).toDouble();
      final maxHp = (data['maxHp'] as num).toDouble();
      
      setState(() {
        // Update current player HP if it's us
        if (playerId == _currentCharacterId) {
          _playerHp = currentHp;
          _playerMaxHp = maxHp;
          
          // Check if player died
          if (currentHp <= 0 && !_isDead) {
            _isDead = true;
            _deathTime = DateTime.now();
            // Mark character as dead and navigate after 3 seconds
            Future.delayed(const Duration(seconds: 3), () async {
              if (mounted && _isDead && _currentCharacterId != null) {
                // Mark character as dead via API
                try {
                  await _apiService.markCharacterDead(_currentCharacterId!);
                } catch (e) {
                  print('Failed to mark character as dead: $e');
                }
                
                // Show character select modal
                if (mounted) {
                  _refreshCharacters().then((_) {
                    if (mounted) {
                      setState(() {
                        _showCharacterSelectModal = true;
                      });
                    }
                  });
                }
              }
            });
          }
        }
        
        // Update other player HP
        if (_players.containsKey(playerId)) {
          _players[playerId]!.hp = currentHp;
          _players[playerId]!.maxHp = maxHp;
        }
        
        _repaintCounter++;
      });
    };
    _gameService.addPlayerDamagedListener(_playerDamagedCallback);

    _playerDeathCallback = (data) {
      if (!mounted) return;
      final playerId = data['playerId'] as String;
      
      setState(() {
        // If current player died
        if (playerId == _currentCharacterId) {
          _isDead = true;
          _playerHp = 0;
          _deathTime = DateTime.now();
          // Mark character as dead and navigate after 3 seconds
          Future.delayed(const Duration(seconds: 3), () async {
            if (mounted && _isDead && _currentCharacterId != null) {
              // Mark character as dead via API
              try {
                await _apiService.markCharacterDead(_currentCharacterId!);
              } catch (e) {
                print('Failed to mark character as dead: $e');
              }
              
              // Navigate to character select
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => CharacterSelectScreen(
                      accountId: _accountId ?? '',
                      characters: [],
                      isTemporary: true,
                    ),
                  ),
                );
              }
            }
          });
        }
        
        // Update other player HP to 0
        if (_players.containsKey(playerId)) {
          _players[playerId]!.hp = 0;
        }
        
        _repaintCounter++;
      });
    };
    _gameService.addPlayerDeathListener(_playerDeathCallback);
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
        
        // Update movement direction for rotation
        _playerLastMoveX = deltaX;
        _playerLastMoveY = deltaY;
        // Calculate rotation angle (default facing down/south, so subtract pi/2)
        // atan2(y, x): 0 = right, π/2 = down, π = left, -π/2 = up
        // Since default is down, we subtract π/2 to account for that
        _playerLastRotationAngle = atan2(deltaY, deltaX) - (pi / 2);
        
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
      setState(() {
        _repaintCounter++;
      });
    }
  }
  
  // Enemies are now updated from server, no local update needed
  
  bool _isEnemyVisible(Enemy enemy) {
    final screenX = _worldToScreenX(enemy.x);
    final screenY = _worldToScreenY(enemy.y);
    
    // Check if enemy is within screen bounds (with some padding for enemy size)
    final padding = _playerSize / 2;
    return screenX >= -padding &&
           screenX <= _screenWidth + padding &&
           screenY >= -padding &&
           screenY <= _screenHeight + padding;
  }
  
  void _useAbility1() {
    // Check cooldown
    final now = DateTime.now();
    if (_lastAbility1Use != null) {
      final timeSinceLastUse = now.difference(_lastAbility1Use!);
      if (timeSinceLastUse < _ability1Cooldown) {
        return; // Still on cooldown
      }
    }
    
    // Need a targeted enemy to fire at
    if (_targetedEnemyId == null) {
      return;
    }
    
    // Find the targeted enemy
    final targetEnemy = _enemies.firstWhere(
      (e) => e.id == _targetedEnemyId,
      orElse: () => throw StateError('Targeted enemy not found'),
    );
    
    // Only fire if enemy is visible
    if (!_isEnemyVisible(targetEnemy)) {
      return;
    }
    
    // Create projectile from player position to enemy position
    final projectile = Projectile(
      id: 'projectile_${_projectileIdCounter++}',
      x: _playerX,
      y: _playerY,
      targetX: targetEnemy.x,
      targetY: targetEnemy.y,
      speed: 500.0,
      damage: 10.0,
    );
    
    // Send projectile to server so other players can see it
    if (_currentCharacterId != null) {
      _gameService.sendProjectileCreate(
        projectile.id,
        projectile.x,
        projectile.y,
        projectile.targetX,
        projectile.targetY,
        projectile.speed,
        _currentCharacterId!,
      );
    }
    
    _lastAbility1Use = now;
    
    if (mounted) {
      setState(() {
        _projectiles.add(projectile);
        _repaintCounter++;
      });
    }
  }
  
  void _updateProjectiles(double deltaTime) {
    bool needsUpdate = false;
    final projectilesToRemove = <Projectile>[];
    final enemiesToDamage = <String, double>{}; // enemyId -> damage
    
    for (var projectile in _projectiles) {
      // Update projectile position
      final hit = projectile.update(deltaTime);
      
      if (hit) {
        // Projectile reached target, check collision with enemies
        for (var enemy in _enemies) {
          final dx = projectile.x - enemy.x;
          final dy = projectile.y - enemy.y;
          final distance = sqrt(dx * dx + dy * dy);
          
          // If within enemy hitbox (using player size as reference)
          if (distance < _playerSize) {
            // Send damage to server instead of applying locally
            if (_currentCharacterId != null) {
              _gameService.sendProjectileDamage(enemy.id, projectile.damage, _currentCharacterId!);
            }
            projectilesToRemove.add(projectile);
            needsUpdate = true;
            break;
          }
        }
        
        // If projectile didn't hit an enemy but reached target, remove it
        if (!projectilesToRemove.contains(projectile)) {
          projectilesToRemove.add(projectile);
          needsUpdate = true;
        }
      } else {
        // Check if projectile is off-screen (beyond reasonable bounds)
        final screenX = _worldToScreenX(projectile.x);
        final screenY = _worldToScreenY(projectile.y);
        final padding = 200.0; // Remove projectiles that are far off-screen
        
        if (screenX < -padding ||
            screenX > _screenWidth + padding ||
            screenY < -padding ||
            screenY > _screenHeight + padding) {
          projectilesToRemove.add(projectile);
          needsUpdate = true;
        } else {
          needsUpdate = true; // Projectile is still moving
        }
      }
    }
    
    // Damage is now handled server-side, no local damage application needed
    
    // Remove projectiles that hit or went off-screen
    _projectiles.removeWhere((p) => projectilesToRemove.contains(p));
    
    if (needsUpdate && mounted) {
      setState(() {
        _repaintCounter++;
      });
    }
  }
  
  int _getExpForCurrentLevel() {
    int totalExpNeeded = 0;
    for (int level = 1; level < _playerLevel; level++) {
      totalExpNeeded += (_expPerLevel * level).toInt();
    }
    return totalExpNeeded;
  }
  
  int _getExpForNextLevel() {
    return _getExpForCurrentLevel() + (_expPerLevel * _playerLevel).toInt();
  }
  
  void _addCurrency(int copper) {
    _playerCopper += copper;
    // Auto-convert currency
    while (_playerCopper >= 100) {
      _playerCopper -= 100;
      _playerSilver += 1;
    }
    while (_playerSilver >= 100) {
      _playerSilver -= 100;
      _playerGold += 1;
    }
    while (_playerGold >= 100) {
      _playerGold -= 100;
      _playerPlatinum += 1;
    }
  }
  
  String _getCurrencyDisplay() {
    final parts = <String>[];
    if (_playerPlatinum > 0) parts.add('${_playerPlatinum}P');
    if (_playerGold > 0) parts.add('${_playerGold}G');
    if (_playerSilver > 0) parts.add('${_playerSilver}S');
    if (_playerCopper > 0) parts.add('${_playerCopper}C');
    return parts.isEmpty ? '0C' : parts.join(' ');
  }
  
  void _checkCurrencyCollection() {
    final double collectionRange = _playerSize * 1.5; // Slightly larger than player size
    final coinsToRemove = <CurrencyCoin>[];
    bool needsUpdate = false;
    
    for (var coin in _currencyCoins) {
      // Remove expired coins
      if (coin.isExpired) {
        coinsToRemove.add(coin);
        needsUpdate = true;
        continue;
      }
      
      final dx = _playerX - coin.x;
      final dy = _playerY - coin.y;
      final distance = sqrt(dx * dx + dy * dy);
      
      if (distance < collectionRange) {
        // Collect currency based on type
        int copperToAdd = 0;
        switch (coin.type) {
          case CurrencyType.copper:
            copperToAdd = coin.amount;
            break;
          case CurrencyType.silver:
            copperToAdd = coin.amount * 100;
            break;
          case CurrencyType.gold:
            copperToAdd = coin.amount * 10000; // 100 * 100
            break;
          case CurrencyType.platinum:
            copperToAdd = coin.amount * 1000000; // 100 * 100 * 100
            break;
        }
        _addCurrency(copperToAdd);
        coinsToRemove.add(coin);
        needsUpdate = true;
      }
    }
    
    // Remove collected/expired coins
    _currencyCoins.removeWhere((c) => coinsToRemove.contains(c));
    
    if (needsUpdate && mounted) {
      setState(() {
        _repaintCounter++;
      });
    }
  }
  
  void _updateFloatingTexts() {
    final textsToRemove = _floatingTexts.where((t) => t.isExpired).toList();
    if (textsToRemove.isNotEmpty) {
      _floatingTexts.removeWhere((t) => textsToRemove.contains(t));
      if (mounted) {
        setState(() {
          _repaintCounter++;
        });
      }
    }
  }
  
  void _updatePlayerLevel() {
    // Calculate required exp for current level
    int requiredExp = 0;
    for (int level = 1; level <= _playerLevel; level++) {
      requiredExp += (_expPerLevel * level).toInt(); // Each level needs more exp
    }
    
    // Level up if player has enough exp
    while (_playerExp >= requiredExp) {
      _playerLevel++;
      requiredExp += (_expPerLevel * _playerLevel).toInt();
    }
  }
  
  Widget _buildCharacterInfo() {
    final expForCurrent = _getExpForCurrentLevel();
    final expForNext = _getExpForNextLevel();
    final expInCurrentLevel = _playerExp - expForCurrent;
    final expNeededForNext = expForNext - expForCurrent;
    final expPercent = expNeededForNext > 0 
        ? (expInCurrentLevel / expNeededForNext).clamp(0.0, 1.0)
        : 1.0;
    
    final hpPercent = (_playerHp / _playerMaxHp).clamp(0.0, 1.0);
    
    // Get character sprite
    ui.Image? characterSprite;
    if (_currentSpriteType == 'char-1') {
      characterSprite = _char1Sprite;
    } else if (_currentSpriteType == 'char-2') {
      characterSprite = _char2Sprite;
    }
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade700, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Character image
          if (characterSprite != null)
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(4),
              ),
              child: CustomPaint(
                painter: _CharacterImagePainter(characterSprite),
                size: const Size(48, 48),
              ),
            ),
          const SizedBox(width: 8),
          // Character info
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Character name
              Text(
                _currentCharacterName ?? 'Unknown',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              // HP bar
              SizedBox(
                width: 200,
                child: Stack(
                  children: [
                    // Background
                    Container(
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    // Filled HP
                    FractionallySizedBox(
                      widthFactor: hpPercent,
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              hpPercent > 0.6 
                                  ? Colors.green 
                                  : hpPercent > 0.3 
                                      ? Colors.orange 
                                      : Colors.red,
                              hpPercent > 0.6 
                                  ? Colors.green.shade400 
                                  : hpPercent > 0.3 
                                      ? Colors.orange.shade400 
                                      : Colors.red.shade400,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    // Text overlay
                    Container(
                      height: 16,
                      alignment: Alignment.center,
                      child: Text(
                        '${_playerHp.toInt()} / ${_playerMaxHp.toInt()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              blurRadius: 2.0,
                              offset: Offset(1, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              // Currency display
              Text(
                _getCurrencyDisplay(),
                style: TextStyle(
                  color: Colors.amber.shade300,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              // Exp bar
              SizedBox(
                width: 200,
                child: Stack(
                  children: [
                    // Background
                    Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    // Filled exp
                    FractionallySizedBox(
                      widthFactor: expPercent,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue.shade400,
                              Colors.cyan.shade400,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                    // Text overlay
                    Container(
                      height: 14,
                      alignment: Alignment.center,
                      child: Text(
                        'Lv.$_playerLevel  $expInCurrentLevel/$expNeededForNext',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              blurRadius: 2.0,
                              offset: Offset(1, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  void _targetNextEnemy() {
    // Filter to only visible enemies
    final visibleEnemies = _enemies.where((e) => _isEnemyVisible(e)).toList();
    
    if (visibleEnemies.isEmpty) {
      _targetedEnemyId = null;
      if (mounted) {
        setState(() {
          _repaintCounter++;
        });
      }
      return;
    }
    
    if (_targetedEnemyId == null) {
      // Target first visible enemy
      _targetedEnemyId = visibleEnemies.first.id;
    } else {
      // Check if current target is still visible
      final currentTarget = _enemies.firstWhere(
        (e) => e.id == _targetedEnemyId,
        orElse: () => visibleEnemies.first,
      );
      
      if (!_isEnemyVisible(currentTarget)) {
        // Current target is no longer visible, target first visible enemy
        _targetedEnemyId = visibleEnemies.first.id;
      } else {
        // Find current index in visible enemies and target next
        final currentIndex = visibleEnemies.indexWhere((e) => e.id == _targetedEnemyId);
        if (currentIndex == -1 || currentIndex == visibleEnemies.length - 1) {
          _targetedEnemyId = visibleEnemies.first.id;
        } else {
          _targetedEnemyId = visibleEnemies[currentIndex + 1].id;
        }
      }
    }
    
    if (mounted) {
      setState(() {
        _repaintCounter++;
      });
    }
  }
  
  void _targetEnemyAtPosition(Offset screenPosition) {
    final worldX = _screenToWorldX(screenPosition.dx);
    final worldY = _screenToWorldY(screenPosition.dy);
    
    Enemy? closestEnemy;
    double closestDistance = double.infinity;
    const double targetRange = 100.0; // Range to target enemy
    
    // Only consider visible enemies
    for (var enemy in _enemies) {
      if (!_isEnemyVisible(enemy)) {
        continue; // Skip enemies that are off-screen
      }
      
      final dx = worldX - enemy.x;
      final dy = worldY - enemy.y;
      final distance = sqrt(dx * dx + dy * dy);
      
      if (distance < targetRange && distance < closestDistance) {
        closestEnemy = enemy;
        closestDistance = distance;
      }
    }
    
    if (mounted) {
      setState(() {
        // If clicked on an enemy, target it; otherwise clear target
        if (closestEnemy != null) {
          _targetedEnemyId = closestEnemy.id;
        } else {
          _targetedEnemyId = null;
        }
        _repaintCounter++;
      });
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
            // Apply death filters to entire game content
            ColorFiltered(
              colorFilter: _isDead 
                ? ColorFilter.mode(
                    Colors.black.withOpacity(0.1),
                    BlendMode.darken,
                  )
                : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
              child: ColorFiltered(
                colorFilter: _isDead
                  ? const ColorFilter.matrix([
                      0.2126, 0.7152, 0.0722, 0, 0, // Red channel
                      0.2126, 0.7152, 0.0722, 0, 0, // Green channel
                      0.2126, 0.7152, 0.0722, 0, 0, // Blue channel
                      0, 0, 0, 1, 0, // Alpha channel
                    ])
                  : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                child: Container(
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
                  _repaintCounter,
                  _enemies,
                  _enemy1Sprite,
                  _enemy2Sprite,
                  _enemy3Sprite,
                  _enemy4Sprite,
                  _zombie1Sprite,
                  _targetedEnemyId,
                  _aggroEnemyIds,
                  _playerHp,
                  _playerMaxHp,
                  _playerLevel,
                  _projectiles,
                  _currencyCoins,
                  _floatingTexts,
                  _playerLastRotationAngle,
                ),
                size: Size.infinite,
              ),
                ),
              ),
            ),
            // Character info at top left (only show when character is loaded)
            if (_currentCharacterId != null)
              Positioned(
                top: 16,
                left: 16,
                child: _buildCharacterInfo(),
              ),
            // Menu button at top right, above player info
            Positioned(
              top: 16,
              right: 16,
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
            if (_showCharacterSelectModal)
              _buildCharacterSelectModal(),
            // Death overlay - apply filters to entire screen
            if (_isDead)
              Positioned.fill(
                child: Stack(
                  children: [
                    // Apply filters to entire background
                    ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.black.withOpacity(0.1),
                        BlendMode.darken,
                      ),
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.matrix([
                          0.2126, 0.7152, 0.0722, 0, 0, // Red channel
                          0.2126, 0.7152, 0.0722, 0, 0, // Green channel
                          0.2126, 0.7152, 0.0722, 0, 0, // Blue channel
                          0, 0, 0, 1, 0, // Alpha channel
                        ]),
                        child: Container(
                          color: Colors.transparent,
                        ),
                      ),
                    ),
                    // Text on top
                    Center(
                      child: Text(
                        'YOU DIED',
                        style: TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                          shadows: [
                            Shadow(
                              offset: const Offset(0, 0),
                              blurRadius: 20,
                              color: Colors.white,
                            ),
                            Shadow(
                              offset: const Offset(0, 0),
                              blurRadius: 40,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Positioned(
              top: 80, // Moved down to make room for character info and menu
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
            if (_showCharacterCreateModal)
              _buildCharacterCreateModal(),
            ],
          ),
        );
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_keyboardFocusNode.hasFocus) {
        _keyboardFocusNode.requestFocus();
      }
    });
    
    return FocusScope(
      canRequestFocus: true,
      child: Stack(
        children: [
          Shortcuts(
            shortcuts: {
              const SingleActivator(LogicalKeyboardKey.tab): _TargetEnemyIntent(),
            },
            child: Actions(
              actions: {
                _TargetEnemyIntent: CallbackAction<_TargetEnemyIntent>(
                  onInvoke: (_) {
                    _targetNextEnemy();
                    return null;
                  },
                ),
              },
                child: KeyboardListener(
                focusNode: _keyboardFocusNode,
                autofocus: true,
                onKeyEvent: (event) {
                  final key = event.logicalKey;
                  
                  if (event is KeyDownEvent) {
                    if (key == LogicalKeyboardKey.tab) {
                      // Tab is handled by Shortcuts/Actions above
                      // Prevent default browser behavior
                      return;
                    } else if (key == LogicalKeyboardKey.arrowLeft ||
                        key == LogicalKeyboardKey.keyA ||
                        key == LogicalKeyboardKey.arrowRight ||
                        key == LogicalKeyboardKey.keyD ||
                        key == LogicalKeyboardKey.arrowUp ||
                        key == LogicalKeyboardKey.keyW ||
                        key == LogicalKeyboardKey.arrowDown ||
                        key == LogicalKeyboardKey.keyS) {
                      _pressedKeys.add(key);
                    } else if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
                      _useAbility1();
                    } else if (key == LogicalKeyboardKey.escape) {
                      // ESC clears target if one is selected, otherwise opens menu
                      if (_targetedEnemyId != null) {
                        setState(() {
                          _targetedEnemyId = null;
                          _repaintCounter++;
                        });
                      } else {
                        setState(() {
                          _showSettingsModal = !_showSettingsModal;
                          _settingsView = null;
                        });
                        if (_showSettingsModal) {
                          _refreshCharacters();
                        }
                      }
                    }
                  } else if (event is KeyUpEvent) {
                    if (key == LogicalKeyboardKey.tab) {
                      // Prevent default browser behavior
                      return;
                    }
                    _pressedKeys.remove(key);
                  }
                },
                child: GestureDetector(
                  onTapDown: (details) {
                    _targetEnemyAtPosition(details.localPosition);
                  },
                  child: gameContent,
                ),
              ),
            ),
          ),
          if (_isLoading)
            _buildLoadingScreen(),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          color: Colors.black.withOpacity(0.5), // Semi-transparent black
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Game Title
                const Text(
                  'RogueSouls',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFb8860b), // Dark yellow/gold
                    letterSpacing: 2,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 60),
                // Loading Bar Container
                Container(
                  width: min(_screenWidth * 0.7, 400),
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        // Animated progress bar
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: _loadingProgress),
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                          builder: (context, value, child) {
                            return FractionallySizedBox(
                              widthFactor: value,
                              alignment: Alignment.centerLeft,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFFb8860b), // Dark yellow
                                      const Color(0xFFdaa520), // Goldenrod
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Loading Status Text
                Text(
                  _loadingStatus,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                    letterSpacing: 0.5,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
                            title: const Text(
                              'Select Character',
                              style: TextStyle(fontSize: 14),
                            ),
                            onTap: () {
                              setState(() {
                                _settingsView = 'characterSelect';
                              });
                              _refreshCharacters();
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

  Widget _buildCharacterSelectModal() {
    return Center(
      child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 300,
          height: 500,
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
                      'Select Character',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        setState(() {
                          _showCharacterSelectModal = false;
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
              Expanded(
                child: _buildCharacterSelectContent(),
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
                                onTap: char['isDead'] == true ? null : () {
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
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          char['name'] as String,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            color: char['isDead'] == true ? Colors.grey : null,
                                          ),
                                        ),
                                      ),
                                      if (char['isDead'] == true)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 8),
                                          child: Text(
                                            'dead',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.red.shade700,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
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
              onPressed: _selectedCharacter == null || (_selectedCharacter!['isDead'] == true)
                  ? null
                  : () {
                      if (_selectedCharacter != null) {
                        _loadCharacter(_selectedCharacter!);
                        setState(() {
                          _showCharacterSelectModal = false;
                        });
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
                            // Close create modal and return to character select
                            setState(() {
                              _showCharacterCreateModal = false;
                              _characterNameController?.clear();
                              // Stay in character select view to select the new character
                              if (_settingsView != 'characterSelect') {
                                _settingsView = 'characterSelect';
                              }
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
      _showCharacterSelectModal = false;
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
  Function(List<dynamic>) _enemiesUpdateCallback = (_) {};
  Function(Map<String, dynamic>) _enemyDamagedCallback = (_) {};
  Function(Map<String, dynamic>) _enemyDeathCallback = (_) {};
  Function(Map<String, dynamic>) _projectileSpawnCallback = (_) {};
  Function(Map<String, dynamic>) _playerDamagedCallback = (_) {};
  Function(Map<String, dynamic>) _playerDeathCallback = (_) {};

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
      onEnemiesUpdate: _enemiesUpdateCallback,
      onEnemyDamaged: _enemyDamagedCallback,
      onEnemyDeath: _enemyDeathCallback,
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
  final int repaintCounter;
  final List<Enemy> enemies;
  final ui.Image? enemy1Sprite;
  final ui.Image? enemy2Sprite;
  final ui.Image? enemy3Sprite;
  final ui.Image? enemy4Sprite;
  final ui.Image? zombie1Sprite; // Sprite sheet for enemy-5
  final String? targetedEnemyId;
  final Set<String> aggroEnemyIds;
  final double playerHp;
  final double playerMaxHp;
  final int playerLevel;
  final List<Projectile> projectiles;
  final List<CurrencyCoin> currencyCoins;
  final List<FloatingText> floatingTexts;
  final double currentPlayerRotationAngle;
  
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
    this.repaintCounter,
    this.enemies,
    this.enemy1Sprite,
    this.enemy2Sprite,
    this.enemy3Sprite,
    this.enemy4Sprite,
    this.zombie1Sprite,
    this.targetedEnemyId,
    this.aggroEnemyIds,
    this.playerHp,
    this.playerMaxHp,
    this.playerLevel,
    this.projectiles,
    this.currencyCoins,
    this.floatingTexts,
    this.currentPlayerRotationAngle,
  );

  void _drawSprite(
    Canvas canvas,
    ui.Image sprite,
    double worldX,
    double worldY,
    double size,
    PlayerDirection direction, {
    double? rotationAngle,
  }) {
    Rect sourceRect;
    // Use full sprite (800x800 image, no direction-based frames)
    sourceRect = const Rect.fromLTWH(0, 0, 800, 800);

    final screenX = worldToScreenX(worldX);
    final screenY = worldToScreenY(worldY);
    
    final destRect = Rect.fromCenter(
      center: Offset(screenX, screenY),
      width: size,
      height: size,
    );
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;
    
    // Apply rotation if provided
    if (rotationAngle != null) {
      canvas.save();
      canvas.translate(screenX, screenY);
      canvas.rotate(rotationAngle);
      canvas.translate(-screenX, -screenY);
      canvas.drawImageRect(sprite, sourceRect, destRect, paint);
      canvas.restore();
    } else {
      canvas.drawImageRect(sprite, sourceRect, destRect, paint);
    }
  }

  ui.Image? _getSpriteForType(String spriteType) {
    if (spriteType == 'char-1') {
      return char1Sprite;
    } else if (spriteType == 'char-2') {
      return char2Sprite;
    }
    return char1Sprite;
  }
  
  ui.Image? _getEnemySpriteForType(String spriteType) {
    if (spriteType == 'enemy-1') {
      return enemy1Sprite;
    } else if (spriteType == 'enemy-2') {
      return enemy2Sprite;
    } else if (spriteType == 'enemy-3') {
      return enemy3Sprite;
    } else if (spriteType == 'enemy-4') {
      return enemy4Sprite;
    } else if (spriteType == 'enemy-5') {
      return zombie1Sprite;
    }
    return enemy1Sprite;
  }
  
  void _drawEnemy(
    Canvas canvas,
    ui.Image sprite,
    double worldX,
    double worldY,
    double size,
    Enemy enemy,
  ) {
    final screenX = worldToScreenX(worldX);
    final screenY = worldToScreenY(worldY);
    
    Rect sourceRect;
    if (enemy.spriteType == 'enemy-5') {
      // Sprite sheet: 100x100 frames with 1px padding
      // Frame index N starts at X = N * 101
      final frameIndex = enemy.getCurrentAnimationFrame();
      final frameX = (frameIndex * 101).toDouble(); // 100px sprite + 1px padding
      sourceRect = Rect.fromLTWH(frameX, 0, 100, 100);
    } else {
      // Regular sprites: 512x512
      sourceRect = const Rect.fromLTWH(0, 0, 512, 512);
    }
    
    final destRect = Rect.fromCenter(
      center: Offset(screenX, screenY),
      width: size,
      height: size,
    );
    
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;
    
    // Apply rotation for zombie enemy to face movement direction (or last direction when idle)
    if (enemy.spriteType == 'enemy-5') {
      final rotationAngle = enemy.getRotationAngle();
      canvas.save();
      canvas.translate(screenX, screenY);
      canvas.rotate(rotationAngle);
      canvas.translate(-screenX, -screenY);
      canvas.drawImageRect(sprite, sourceRect, destRect, paint);
      canvas.restore();
    } else {
      canvas.drawImageRect(sprite, sourceRect, destRect, paint);
    }
  }
  
  void _drawHealthBar(
    Canvas canvas,
    double screenX,
    double screenY,
    double currentHp,
    double maxHp,
    double size,
    bool isTargeted,
  ) {
    final hpBarWidth = size;
    final hpBarHeight = isTargeted ? 8.0 : 6.0;
    final hpBarY = screenY - size / 2 - (isTargeted ? 20.0 : 15.0);
    final hpPercent = (currentHp / maxHp).clamp(0.0, 1.0);
    
    // Background
    final bgPaint = Paint()..color = Colors.black54;
    canvas.drawRect(
      Rect.fromLTWH(screenX - hpBarWidth / 2, hpBarY, hpBarWidth, hpBarHeight),
      bgPaint,
    );
    
    // HP bar
    final hpColor = hpPercent > 0.6 
        ? Colors.green 
        : hpPercent > 0.3 
            ? Colors.orange 
            : Colors.red;
    final hpPaint = Paint()..color = hpColor;
    canvas.drawRect(
      Rect.fromLTWH(screenX - hpBarWidth / 2, hpBarY, hpBarWidth * hpPercent, hpBarHeight),
      hpPaint,
    );
    
    // Border
    final borderPaint = Paint()
      ..color = isTargeted ? Colors.white : Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = isTargeted ? 2.0 : 1.0;
    canvas.drawRect(
      Rect.fromLTWH(screenX - hpBarWidth / 2, hpBarY, hpBarWidth, hpBarHeight),
      borderPaint,
    );
    
    // HP text if targeted
    if (isTargeted) {
      final hpText = '${currentHp.toInt()}/${maxHp.toInt()}';
      final textPainter = TextPainter(
        text: TextSpan(
          text: hpText,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            shadows: [
              const Shadow(
                color: Colors.black,
                blurRadius: 2.0,
                offset: Offset(1, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      final textX = screenX - textPainter.width / 2;
      textPainter.paint(canvas, Offset(textX, hpBarY - 14));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black,
    );
    
    if (worldBackground != null) {
      final bgWidth = worldBackground!.width.toDouble();
      final bgHeight = worldBackground!.height.toDouble();
      const worldWidth = 10000.0;
      const worldHeight = 10000.0;
      
      // Desired world view (centered on player, in world units)
      final worldViewStartX = playerX - size.width / 2;
      final worldViewStartY = playerY - size.height / 2;
      final worldViewEndX = playerX + size.width / 2;
      final worldViewEndY = playerY + size.height / 2;
      
      final worldViewRect = Rect.fromLTWH(
        worldViewStartX,
        worldViewStartY,
        size.width,
        size.height,
      );
      final worldBoundsRect = Rect.fromLTWH(
        _worldMinX,
        _worldMinY,
        worldWidth,
        worldHeight,
      );
      
      // Intersection between view and world bounds (this is what we can actually show)
      final visibleWorldRect = worldViewRect.intersect(worldBoundsRect);
      if (!visibleWorldRect.isEmpty) {
        // Normalize to [0, 1] within world bounds
        final normStartX = (visibleWorldRect.left - _worldMinX) / worldWidth;
        final normStartY = (visibleWorldRect.top - _worldMinY) / worldHeight;
        final normEndX = (visibleWorldRect.right - _worldMinX) / worldWidth;
        final normEndY = (visibleWorldRect.bottom - _worldMinY) / worldHeight;
        
        // Source rectangle in background image
        final sourceX = normStartX * bgWidth;
        final sourceY = normStartY * bgHeight;
        final sourceW = (normEndX - normStartX) * bgWidth;
        final sourceH = (normEndY - normStartY) * bgHeight;
        
        final sourceRect = Rect.fromLTWH(
          sourceX.clamp(0.0, bgWidth),
          sourceY.clamp(0.0, bgHeight),
          sourceW.clamp(0.0, bgWidth - sourceX.clamp(0.0, bgWidth)),
          sourceH.clamp(0.0, bgHeight - sourceY.clamp(0.0, bgHeight)),
        );
        
        // Destination rectangle on screen: where the visible world portion sits
        final offsetX = visibleWorldRect.left - worldViewRect.left;
        final offsetY = visibleWorldRect.top - worldViewRect.top;
        final destRect = Rect.fromLTWH(
          offsetX,
          offsetY,
          visibleWorldRect.width,
          visibleWorldRect.height,
        );
        
        // Draw only the visible part of the world; the rest stays black (letterboxed)
        canvas.drawImageRect(worldBackground!, sourceRect, destRect, Paint());
      }
    }
    
    for (var player in players.values) {
      if (player.id != currentPlayerId) {
        final playerSpriteType = player.spriteType ?? 'char-2';
        final sprite = _getSpriteForType(playerSpriteType);
        
        if (sprite != null) {
          // Calculate rotation angle from direction (default facing down)
          double rotationAngle = 0.0;
          switch (player.direction) {
            case PlayerDirection.down:
              rotationAngle = 0.0; // Default facing down
              break;
            case PlayerDirection.right:
              rotationAngle = -pi / 2; // Rotate 90 degrees clockwise
              break;
            case PlayerDirection.up:
              rotationAngle = pi; // Rotate 180 degrees
              break;
            case PlayerDirection.left:
              rotationAngle = pi / 2; // Rotate 90 degrees counter-clockwise
              break;
          }
          _drawSprite(canvas, sprite, player.x, player.y, playerSize, player.direction,
              rotationAngle: rotationAngle);
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
        
        // Draw player level to the left of HP bar
        final levelText = TextPainter(
          text: TextSpan(
            text: '${player.level}',
            style: TextStyle(
              color: Colors.white,
              fontSize: playerSize * 0.08,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
                Shadow(offset: Offset(-1, -1), blurRadius: 2, color: Colors.black),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        levelText.layout();
        levelText.paint(canvas, Offset(screenX - playerSize / 2 - levelText.width - 4, screenY - playerSize / 2 - 20));
        
        // Draw player health bar
        _drawHealthBar(canvas, screenX, screenY, player.hp, player.maxHp, playerSize, false);
        
        // Draw player name (white with black shadow, above HP bar)
        final fontSize = playerSize * 0.1;
        final textPainter = TextPainter(
          text: TextSpan(
            text: player.name,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              shadows: [
                Shadow(
                  offset: const Offset(1, 1),
                  blurRadius: 2,
                  color: Colors.black,
                ),
                Shadow(
                  offset: const Offset(-1, -1),
                  blurRadius: 2,
                  color: Colors.black,
                ),
                Shadow(
                  offset: const Offset(1, -1),
                  blurRadius: 2,
                  color: Colors.black,
                ),
                Shadow(
                  offset: const Offset(-1, 1),
                  blurRadius: 2,
                  color: Colors.black,
                ),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        final textX = screenX - textPainter.width / 2;
        // Position name above HP bar (HP bar is at screenY - playerSize/2 - 20, name goes above that)
        textPainter.paint(canvas, Offset(textX, screenY - playerSize / 2 - 40));
      }
    }

    if (currentPlayerId.isNotEmpty && currentPlayerName.isNotEmpty) {
      final currentSprite = _getSpriteForType(currentPlayerSpriteType);
      if (currentSprite != null) {
        _drawSprite(canvas, currentSprite, playerX, playerY, playerSize, currentPlayerDirection,
            rotationAngle: currentPlayerRotationAngle);
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
      
      // Draw player level to the left of HP bar
      final levelText = TextPainter(
        text: TextSpan(
          text: '$playerLevel',
          style: TextStyle(
            color: Colors.white,
            fontSize: playerSize * 0.08,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
              Shadow(offset: Offset(-1, -1), blurRadius: 2, color: Colors.black),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      levelText.layout();
      levelText.paint(canvas, Offset(screenX - playerSize / 2 - levelText.width - 4, screenY - playerSize / 2 - 20));
      
      // Draw player health bar
      _drawHealthBar(canvas, screenX, screenY, playerHp, playerMaxHp, playerSize, false);
      
      // Draw player name (white with black shadow, above HP bar)
      final fontSize = playerSize * 0.1;
      final textPainter = TextPainter(
        text: TextSpan(
          text: currentPlayerName,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            shadows: [
              Shadow(
                offset: const Offset(1, 1),
                blurRadius: 2,
                color: Colors.black,
              ),
              Shadow(
                offset: const Offset(-1, -1),
                blurRadius: 2,
                color: Colors.black,
              ),
              Shadow(
                offset: const Offset(1, -1),
                blurRadius: 2,
                color: Colors.black,
              ),
              Shadow(
                offset: const Offset(-1, 1),
                blurRadius: 2,
                color: Colors.black,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      final textX = screenX - textPainter.width / 2;
      // Position name above HP bar
      textPainter.paint(canvas, Offset(textX, screenY - playerSize / 2 - 40));
    }
    
    // Draw enemies
    for (var enemy in enemies) {
      final isTargeted = targetedEnemyId == enemy.id;
      final hasAggro = aggroEnemyIds.contains(enemy.id);
      final enemySprite = _getEnemySpriteForType(enemy.spriteType);
      final screenX = worldToScreenX(enemy.x);
      final screenY = worldToScreenY(enemy.y);
      
      // Draw aggro highlight (red) if enemy is targeting player, but white takes priority
      if (hasAggro && !isTargeted && enemySprite != null) {
        Rect sourceRect;
        if (enemy.spriteType == 'enemy-5') {
          final frameIndex = enemy.getCurrentAnimationFrame();
          final frameX = (frameIndex * 101).toDouble();
          sourceRect = Rect.fromLTWH(frameX, 0, 100, 100);
        } else {
          sourceRect = const Rect.fromLTWH(0, 0, 512, 512);
        }
        
        final destRect = Rect.fromCenter(
          center: Offset(screenX, screenY),
          width: playerSize,
          height: playerSize,
        );
        
        final aggroPaint = Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.high
          ..colorFilter = const ColorFilter.mode(Colors.red, BlendMode.srcATop)
          ..imageFilter = ui.ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0);
        
        final aggroRect = destRect.inflate(4);
        
        if (enemy.spriteType == 'enemy-5') {
          final rotationAngle = enemy.getRotationAngle();
          canvas.save();
          canvas.translate(screenX, screenY);
          canvas.rotate(rotationAngle);
          canvas.translate(-screenX, -screenY);
          canvas.drawImageRect(enemySprite, sourceRect, aggroRect, aggroPaint);
          canvas.restore();
        } else {
          canvas.drawImageRect(enemySprite, sourceRect, aggroRect, aggroPaint);
        }
      }
      
      // Draw targeting highlight (white dropshadow with blur) before the enemy sprite
      if (isTargeted && enemySprite != null) {
        Rect sourceRect;
        if (enemy.spriteType == 'enemy-5') {
          // Sprite sheet: 100x100 frames with 1px padding
          final frameIndex = enemy.getCurrentAnimationFrame();
          final frameX = (frameIndex * 101).toDouble(); // 100px sprite + 1px padding
          sourceRect = Rect.fromLTWH(frameX, 0, 100, 100);
        } else {
          // Regular sprites: 512x512
          sourceRect = const Rect.fromLTWH(0, 0, 512, 512);
        }
        
        final destRect = Rect.fromCenter(
          center: Offset(screenX, screenY),
          width: playerSize,
          height: playerSize,
        );
        
        // Draw white glow by drawing the sprite with white tint and blur
        final glowPaint = Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.high
          ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcATop)
          ..imageFilter = ui.ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0);
        
        // Draw the sprite with white glow effect (draw it slightly larger for outline effect)
        final glowRect = destRect.inflate(4);
        
        // Apply rotation for zombie enemy to face movement direction (or last direction when idle)
        if (enemy.spriteType == 'enemy-5') {
          final rotationAngle = enemy.getRotationAngle();
          canvas.save();
          canvas.translate(screenX, screenY);
          canvas.rotate(rotationAngle);
          canvas.translate(-screenX, -screenY);
          canvas.drawImageRect(enemySprite, sourceRect, glowRect, glowPaint);
          canvas.restore();
        } else {
          canvas.drawImageRect(enemySprite, sourceRect, glowRect, glowPaint);
        }
      }
      
      // Draw the enemy sprite
      if (enemySprite != null) {
        _drawEnemy(canvas, enemySprite, enemy.x, enemy.y, playerSize, enemy);
      } else {
        // Fallback: draw a red rectangle if sprite not loaded
        final enemyPaint = Paint()..color = Colors.red;
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(screenX, screenY),
            width: playerSize,
            height: playerSize,
          ),
          enemyPaint,
        );
      }
      
      // Draw enemy health bar
      _drawHealthBar(canvas, screenX, screenY, enemy.currentHp, enemy.maxHp, playerSize, isTargeted);
      
      // Draw enemy name
      final fontSize = isTargeted ? playerSize * 0.12 : playerSize * 0.1;
      final textColor = isTargeted ? Colors.white : Colors.black;
      final textPainter = TextPainter(
        text: TextSpan(
          text: enemy.name,
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            fontWeight: isTargeted ? FontWeight.bold : FontWeight.normal,
            shadows: isTargeted ? [
              const Shadow(
                color: Colors.black,
                blurRadius: 3.0,
                offset: Offset(1, 1),
              ),
            ] : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      final textX = screenX - textPainter.width / 2;
      final nameY = screenY - playerSize / 2 - (isTargeted ? fontSize * 1.5 : fontSize * 1.2);
      textPainter.paint(canvas, Offset(textX, nameY));
    }
    
    // Draw projectiles
    for (var projectile in projectiles) {
      final screenX = worldToScreenX(projectile.x);
      final screenY = worldToScreenY(projectile.y);
      
      // Draw projectile as a small circle
      final projectilePaint = Paint()
        ..color = Colors.orange
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(screenX, screenY),
        4.0, // Projectile radius
        projectilePaint,
      );
      
      // Draw a trail/glow effect
      final glowPaint = Paint()
        ..color = Colors.orange.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(screenX, screenY),
        8.0,
        glowPaint,
      );
    }
    
    // Draw currency coins
    for (var coin in currencyCoins) {
      final screenX = worldToScreenX(coin.x);
      final screenY = worldToScreenY(coin.y);
      
      // Draw currency coin with color based on type
      final coinPaint = Paint()
        ..color = Color(coin.color)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(screenX, screenY),
        8.0, // Coin radius
        coinPaint,
      );
      
      // Draw coin border
      final borderPaint = Paint()
        ..color = Color(coin.color).withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(
        Offset(screenX, screenY),
        8.0,
        borderPaint,
      );
      
      // Draw coin shine/glow
      final shinePaint = Paint()
        ..color = Color(coin.color).withOpacity(0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(screenX - 2, screenY - 2),
        3.0,
        shinePaint,
      );
    }
    
    // Draw floating texts
    for (var text in floatingTexts) {
      final screenX = worldToScreenX(text.x);
      // Position text above player (subtract playerSize/2 to get top of player)
      final screenY = worldToScreenY(text.y) - playerSize / 2 + text.offsetY;
      
      final textPainter = TextPainter(
        text: TextSpan(
          text: text.text,
          style: TextStyle(
            color: Colors.purple.withOpacity(text.opacity),
            fontSize: 16,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(text.opacity),
                blurRadius: 3.0,
                offset: const Offset(1, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      final textX = screenX - textPainter.width / 2;
      textPainter.paint(canvas, Offset(textX, screenY));
    }
  }

  @override
  bool shouldRepaint(GameWorldPainter oldDelegate) {
    // Always repaint if repaint counter changed (indicates player movement updates)
    if (oldDelegate.repaintCounter != repaintCounter) {
      return true;
    }
    
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
    
    if (oldDelegate.enemies.length != enemies.length) {
      return true;
    }
    
    if (oldDelegate.targetedEnemyId != targetedEnemyId) {
      return true;
    }
    
    // Check if any enemy moved
    for (var i = 0; i < enemies.length; i++) {
      if (i >= oldDelegate.enemies.length) return true;
      final oldEnemy = oldDelegate.enemies[i];
      final newEnemy = enemies[i];
      if ((oldEnemy.x - newEnemy.x).abs() > 0.01 || 
          (oldEnemy.y - newEnemy.y).abs() > 0.01) {
        return true;
      }
    }
    
    return oldDelegate.currentPlayerName != currentPlayerName ||
        oldDelegate.currentPlayerDirection != currentPlayerDirection ||
        oldDelegate.currentPlayerSpriteType != currentPlayerSpriteType ||
        oldDelegate.char1Sprite != char1Sprite ||
        oldDelegate.char2Sprite != char2Sprite ||
        oldDelegate.enemy1Sprite != enemy1Sprite ||
        oldDelegate.enemy2Sprite != enemy2Sprite ||
        oldDelegate.enemy3Sprite != enemy3Sprite ||
        oldDelegate.enemy4Sprite != enemy4Sprite ||
        oldDelegate.zombie1Sprite != zombie1Sprite ||
        oldDelegate.currencyCoins.length != currencyCoins.length ||
        oldDelegate.floatingTexts.length != floatingTexts.length;
  }
}

