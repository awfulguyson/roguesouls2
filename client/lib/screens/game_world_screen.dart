import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/game_service.dart';
import '../services/api_service.dart';
import '../models/player.dart';
import '../models/enemy.dart';
import '../models/projectile.dart';
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
  int _repaintCounter = 0;
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
  ui.Image? _enemy1Sprite;
  ui.Image? _enemy2Sprite;
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
  
  // Loading screen state
  bool _isLoading = true;
  String _loadingStatus = 'Loading assets...';
  double _loadingProgress = 0.0;
  bool _assetsLoaded = false;
  bool _serverConnected = false;
  bool _accountInitialized = false;
  DateTime? _loadingStartTime;
  
  // Enemy and combat system
  final Map<String, Enemy> _enemies = {};
  final Map<String, Projectile> _projectiles = {};
  String? _targetedEnemyId;
  Timer? _projectileUpdateTimer;
  int _projectileIdCounter = 0;
  double _playerHp = 100.0;
  double _playerMaxHp = 100.0;
  DateTime? _lastPlayerDamageTime;

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
    
    // Timeout: if server doesn't connect within 10 seconds, proceed anyway
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && !_serverConnected) {
        setState(() {
          _serverConnected = true; // Allow game to proceed
          _loadingStatus = 'Server connection timeout - continuing offline';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _checkLoadingComplete());
      }
    });
    
    _gameService.socket?.on('connect', (_) {
      print('Socket connected, requesting player list...');
      _gameService.socket?.emit('game:requestPlayers');
      _gameService.requestEnemies();
      
      if (!mounted) return;
      try {
        void updateConnection() {
          if (!mounted) return;
          setState(() {
            _serverConnected = true;
            _loadingProgress = 0.8;
            if (!_accountInitialized) {
              _loadingStatus = 'Initializing account...';
            } else {
              _loadingStatus = 'Ready!';
              _loadingProgress = 1.0;
            }
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _checkLoadingComplete());
        }
        
        if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
          WidgetsBinding.instance.addPostFrameCallback((_) => updateConnection());
        } else {
          updateConnection();
        }
        
        if (_currentCharacterId != null) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _joinGameWithCharacter();
            }
          });
        }
      } catch (e) {
        print('Error in socket connect callback: $e');
      }
    });
    
    _gameService.socket?.on('reconnect', (_) {
      print('Socket reconnected, rejoining game...');
      _gameService.socket?.emit('game:requestPlayers');
      _gameService.requestEnemies();
      
      if (!mounted) return;
      try {
        void updateConnection() {
          if (!mounted) return;
          setState(() {
            _serverConnected = true;
            _loadingProgress = 0.8;
            if (!_accountInitialized) {
              _loadingStatus = 'Initializing account...';
            } else {
              _loadingStatus = 'Ready!';
              _loadingProgress = 1.0;
            }
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _checkLoadingComplete());
        }
        
        if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
          WidgetsBinding.instance.addPostFrameCallback((_) => updateConnection());
        } else {
          updateConnection();
        }
        
        if (_currentCharacterId != null) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _joinGameWithCharacter();
            }
          });
        }
      } catch (e) {
        print('Error in socket reconnect callback: $e');
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
    
    // Request enemies from server
    _gameService.requestEnemies();
    
    // Projectile update timer
    _projectileUpdateTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      _updateProjectiles();
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
        if (!mounted) return;
        
        void updateAccount() {
          if (!mounted) return;
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
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _checkLoadingComplete());
        }
        
        if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
          WidgetsBinding.instance.addPostFrameCallback((_) => updateAccount());
        } else {
          updateAccount();
        }
      } else {
        final account = await _apiService.createTemporaryAccount();
        final accountId = account['id'] as String;
        final characters = await _apiService.getCharacters(accountId);
        
        if (!mounted) return;
        
        void updateAccount() {
          if (!mounted) return;
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
          });
          _checkLoadingComplete();
        }
        
        if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
          WidgetsBinding.instance.addPostFrameCallback((_) => updateAccount());
        } else {
          updateAccount();
        }
      }
    } catch (e) {
      if (!mounted) return;
      
      void updateAccountError() {
        if (!mounted) return;
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
        });
        // Defer check after setState completes
        WidgetsBinding.instance.addPostFrameCallback((_) => _checkLoadingComplete());
      }
      
      if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) => updateAccountError());
      } else {
        updateAccountError();
      }
    }
  }

  void _checkLoadingComplete() {
    // Always defer this check to avoid calling setState during a build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      if (_assetsLoaded && _serverConnected && _accountInitialized) {
        // Ensure "Ready!" status is set
        if (_loadingStatus != 'Ready!') {
          try {
            if (mounted) {
              setState(() {
                _loadingStatus = 'Ready!';
                _loadingProgress = 1.0;
              });
            }
          } catch (e) {
            print('Error updating loading status: $e');
          }
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
          if (!mounted) return;
          try {
            if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                  });
                }
              });
            } else {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            }
          } catch (e, stackTrace) {
            print('Error hiding loading screen: $e');
            print('Stack trace: $stackTrace');
          }
        });
      }
    });
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

    final enemy1Bytes = await rootBundle.load('assets/enemy-1.png');
    final enemy1Codec = await ui.instantiateImageCodec(enemy1Bytes.buffer.asUint8List());
    final enemy1Frame = await enemy1Codec.getNextFrame();
    _enemy1Sprite = enemy1Frame.image;
    
    if (mounted) {
      setState(() {
        _loadingProgress = 0.55;
      });
    }

    final enemy2Bytes = await rootBundle.load('assets/enemy-2.png');
    final enemy2Codec = await ui.instantiateImageCodec(enemy2Bytes.buffer.asUint8List());
    final enemy2Frame = await enemy2Codec.getNextFrame();
    _enemy2Sprite = enemy2Frame.image;
    
    if (mounted) {
      setState(() {
        _loadingProgress = 0.6;
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
        _assetsLoaded = true;
        _loadingProgress = 0.6;
        _loadingStatus = 'Connecting to server...';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkLoadingComplete());
    }
  }

  void _setupGameService() {
    _playersListCallback = (players) {
      if (!mounted) {
        return;
      }
      try {
        void updatePlayers() {
          if (!mounted) return;
          setState(() {
            _players.clear();
            for (var playerData in players) {
              try {
                final data = playerData as Map<String, dynamic>?;
                if (data == null) continue;
                
                final player = Player.fromJson(data);
                if (_currentCharacterId == null || player.id != _currentCharacterId) {
                  _players[player.id] = player;
                }
              } catch (e, stackTrace) {
                print('Error parsing player from JSON in players list: $e');
                print('Stack trace: $stackTrace');
              }
            }
          });
        }
        
        if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
          // Defer setState if we're in a build phase
          WidgetsBinding.instance.addPostFrameCallback((_) => updatePlayers());
        } else {
          updatePlayers();
        }
      } catch (e, stackTrace) {
        print('Error in players list callback: $e');
        print('Stack trace: $stackTrace');
      }
    };
    _gameService.addPlayersListListener(_playersListCallback);

    _playerJoinedCallback = (data) {
      if (!mounted) {
        return;
      }
      try {
        void updatePlayer() {
          if (!mounted) return;
          setState(() {
            try {
              final player = Player.fromJson(data);
              if (_currentCharacterId == null || player.id != _currentCharacterId) {
                _players[player.id] = player;
              }
            } catch (e) {
              print('Error parsing player from JSON: $e');
            }
          });
        }
        
        if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
          WidgetsBinding.instance.addPostFrameCallback((_) => updatePlayer());
        } else {
          updatePlayer();
        }
      } catch (e) {
        print('Error in player joined callback: $e');
      }
    };
    _gameService.addPlayerJoinedListener(_playerJoinedCallback);

    _playerMovedCallback = (data) {
      if (!mounted) return;
      try {
        final playerId = data['id'] as String?;
        if (playerId == null || playerId.isEmpty) return;
        if (_currentCharacterId != null && playerId == _currentCharacterId) {
          return;
        }
        
        final newX = ((data['x'] as num?) ?? 0).toDouble();
        final newY = ((data['y'] as num?) ?? 0).toDouble();
        
        if (newX.isNaN || newY.isNaN) return;
        
        void updatePlayer() {
          if (!mounted) return;
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
              try {
                final player = Player.fromJson(data);
                player.x = newX;
                player.y = newY;
                _players[playerId] = player;
                _playerTargetPositions[playerId] = Offset(newX, newY);
                _playerLastUpdateTime[playerId] = DateTime.now();
              } catch (e) {
                print('Error parsing player from JSON in move callback: $e');
              }
            });
          }
        }
        
        if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
          WidgetsBinding.instance.addPostFrameCallback((_) => updatePlayer());
        } else {
          updatePlayer();
        }
      } catch (e, stackTrace) {
        print('Error in player moved callback: $e');
        print('Stack trace: $stackTrace');
      }
    };
    _gameService.addPlayerMovedListener(_playerMovedCallback);

    _playerLeftCallback = (data) {
      if (!mounted) return;
      try {
        final playerId = data['id'] as String?;
        if (playerId == null || playerId.isEmpty) return;
        
        void removePlayer() {
          if (!mounted) return;
          setState(() {
            _players.remove(playerId);
          });
        }
        
        if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
          WidgetsBinding.instance.addPostFrameCallback((_) => removePlayer());
        } else {
          removePlayer();
        }
      } catch (e) {
        print('Error in player left callback: $e');
      }
    };
    _gameService.addPlayerLeftListener(_playerLeftCallback);

    _enemiesListCallback = (enemiesList) {
      if (!mounted) return;
      try {
        void updateEnemies() {
          if (!mounted) return;
          setState(() {
            _enemies.clear();
            for (var enemyData in enemiesList) {
              try {
                final data = enemyData as Map<String, dynamic>?;
                if (data == null) continue;
                
                final enemy = Enemy(
                  id: data['id'] as String? ?? 'unknown',
                  x: ((data['x'] as num?) ?? 0).toDouble(),
                  y: ((data['y'] as num?) ?? 0).toDouble(),
                  maxHp: ((data['maxHp'] as num?) ?? 100).toDouble(),
                  currentHp: ((data['currentHp'] as num?) ?? 100).toDouble(),
                  isAggroed: data['isAggroed'] as bool? ?? false,
                  spriteType: data['spriteType'] as String?,
                  direction: _directionFromString(data['direction'] as String? ?? 'down'),
                );
                if (enemy.id != 'unknown') {
                  _enemies[enemy.id] = enemy;
                }
              } catch (e, stackTrace) {
                print('Error creating enemy from data: $e');
                print('Stack trace: $stackTrace');
              }
            }
            _repaintCounter++;
          });
        }
        
        if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
          // Defer setState if we're in a build phase
          WidgetsBinding.instance.addPostFrameCallback((_) => updateEnemies());
        } else {
          updateEnemies();
        }
      } catch (e, stackTrace) {
        print('Error in enemies list callback: $e');
        print('Stack trace: $stackTrace');
      }
    };
    _gameService.addEnemiesListListener(_enemiesListCallback);

    _enemyUpdatedCallback = (data) {
      if (!mounted) return;
      try {
        final enemyId = data['id'] as String?;
        if (enemyId == null || enemyId.isEmpty) return;
        
        void updateEnemy() {
          if (!mounted) return;
          if (_enemies.containsKey(enemyId)) {
            setState(() {
              final enemy = _enemies[enemyId]!;
              final oldY = enemy.y;
              enemy.x = ((data['x'] as num?) ?? enemy.x).toDouble();
              enemy.y = ((data['y'] as num?) ?? enemy.y).toDouble();
              enemy.currentHp = ((data['currentHp'] as num?) ?? enemy.currentHp).toDouble();
              enemy.maxHp = ((data['maxHp'] as num?) ?? enemy.maxHp).toDouble();
              enemy.isAggroed = data['isAggroed'] as bool? ?? enemy.isAggroed;
              if (data['spriteType'] != null) {
                enemy.spriteType = data['spriteType'] as String;
              }
              if (data['direction'] != null) {
                try {
                  enemy.direction = _directionFromString(data['direction'] as String);
                } catch (e) {
                  // Fallback to direction based on movement if direction string is invalid
                  final dy = enemy.y - oldY;
                  if (dy != 0) {
                    enemy.direction = dy < 0 ? PlayerDirection.up : PlayerDirection.down;
                  }
                }
              } else {
                // Update direction based on Y movement
                final dy = enemy.y - oldY;
                if (dy != 0) {
                  enemy.direction = dy < 0 ? PlayerDirection.up : PlayerDirection.down;
                }
              }
              _repaintCounter++;
            });
          } else {
            // New enemy
            setState(() {
              final enemy = Enemy(
                id: enemyId,
                x: ((data['x'] as num?) ?? 0).toDouble(),
                y: ((data['y'] as num?) ?? 0).toDouble(),
                maxHp: ((data['maxHp'] as num?) ?? 100).toDouble(),
                currentHp: ((data['currentHp'] as num?) ?? 100).toDouble(),
                isAggroed: data['isAggroed'] as bool? ?? false,
                spriteType: data['spriteType'] as String?,
                direction: _directionFromString(data['direction'] as String? ?? 'down'),
              );
              _enemies[enemyId] = enemy;
              _repaintCounter++;
            });
          }
        }
        
        if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
          // Defer setState if we're in a build phase
          WidgetsBinding.instance.addPostFrameCallback((_) => updateEnemy());
        } else {
          updateEnemy();
        }
      } catch (e, stackTrace) {
        print('Error updating enemy: $e');
        print('Stack trace: $stackTrace');
      }
    };
    _gameService.addEnemyUpdatedListener(_enemyUpdatedCallback);

    _enemyRemovedCallback = (data) {
      if (!mounted) return;
      try {
        final enemyId = data['id'] as String?;
        if (enemyId == null || enemyId.isEmpty) return;
        
        if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
          // Defer setState if we're in a build phase
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _enemies.remove(enemyId);
                if (_targetedEnemyId == enemyId) {
                  _targetedEnemyId = null;
                }
                _repaintCounter++;
              });
            }
          });
        } else {
          setState(() {
            _enemies.remove(enemyId);
            if (_targetedEnemyId == enemyId) {
              _targetedEnemyId = null;
            }
            _repaintCounter++;
          });
        }
      } catch (e, stackTrace) {
        print('Error removing enemy: $e');
        print('Stack trace: $stackTrace');
      }
    };
    _gameService.addEnemyRemovedListener(_enemyRemovedCallback);
  }

  PlayerDirection _directionFromString(String? dir) {
    if (dir == null || dir.isEmpty) {
      return PlayerDirection.down;
    }
    try {
      switch (dir.toLowerCase().trim()) {
        case 'up':
          return PlayerDirection.up;
        case 'left':
          return PlayerDirection.left;
        case 'right':
          return PlayerDirection.right;
        case 'down':
          return PlayerDirection.down;
        default:
          return PlayerDirection.down;
      }
    } catch (e) {
      return PlayerDirection.down;
    }
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
      setState(() {
        _repaintCounter++;
      });
    }
  }

  // Enemies are now server-managed, no client-side AI needed

  void _updateProjectiles() {
    if (!mounted) return;
    
    bool needsUpdate = false;
    final projectilesToRemove = <String>[];
    
    for (var projectile in _projectiles.values) {
      if (!projectile.isActive) {
        projectilesToRemove.add(projectile.id);
        continue;
      }
      
      final oldX = projectile.x;
      final oldY = projectile.y;
      projectile.update();
      
      if (projectile.x != oldX || projectile.y != oldY) {
        needsUpdate = true;
      }
      
      // Check collision with target enemy
      if (projectile.targetEnemyId != null && 
          _enemies.containsKey(projectile.targetEnemyId)) {
        final enemy = _enemies[projectile.targetEnemyId]!;
        final dx = projectile.x - enemy.x;
        final dy = projectile.y - enemy.y;
        final distance = sqrt(dx * dx + dy * dy);
        
        if (distance < enemy.size / 2) {
          // Hit! Send damage to server
          _gameService.damageEnemy(projectile.targetEnemyId!, projectile.damage);
          projectilesToRemove.add(projectile.id);
          needsUpdate = true;
        }
      }
      
      // Remove if reached target
      if (projectile.hasReachedTarget()) {
        projectilesToRemove.add(projectile.id);
        needsUpdate = true;
      }
    }
    
    // Remove inactive projectiles
    for (var id in projectilesToRemove) {
      _projectiles.remove(id);
    }
    
    if (needsUpdate && mounted) {
      setState(() {
        _repaintCounter++;
      });
    }
  }

  void _targetNextEnemy() {
    if (_enemies.isEmpty) return;
    
    final enemyList = _enemies.values.where((e) => e.isAlive).toList();
    if (enemyList.isEmpty) {
      _targetedEnemyId = null;
      return;
    }
    
    if (_targetedEnemyId == null) {
      // Target first enemy
      _targetedEnemyId = enemyList.first.id;
    } else {
      // Find current index and target next
      final currentIndex = enemyList.indexWhere((e) => e.id == _targetedEnemyId);
      if (currentIndex == -1 || currentIndex == enemyList.length - 1) {
        _targetedEnemyId = enemyList.first.id;
      } else {
        _targetedEnemyId = enemyList[currentIndex + 1].id;
      }
    }
    
    if (mounted) {
      setState(() {});
    }
  }

  void _targetEnemyAtPosition(Offset screenPosition) {
    final worldX = _screenToWorldX(screenPosition.dx);
    final worldY = _screenToWorldY(screenPosition.dy);
    
    Enemy? closestEnemy;
    double closestDistance = double.infinity;
    
    for (var enemy in _enemies.values) {
      if (!enemy.isAlive) continue;
      
      final dx = worldX - enemy.x;
      final dy = worldY - enemy.y;
      final distance = sqrt(dx * dx + dy * dy);
      
      if (distance < enemy.size && distance < closestDistance) {
        closestEnemy = enemy;
        closestDistance = distance;
      }
    }
    
    if (closestEnemy != null) {
      _targetedEnemyId = closestEnemy.id;
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _shootProjectile({int attackType = 1}) {
    if (_targetedEnemyId == null || !_enemies.containsKey(_targetedEnemyId)) {
      return;
    }
    
    final enemy = _enemies[_targetedEnemyId]!;
    if (!enemy.isAlive) return;
    
    // Set damage based on attack type: 1 = 10hp, 2 = 20hp, others default to 10hp
    final damage = attackType == 2 ? 20.0 : 10.0;
    
    final projectile = Projectile(
      id: 'projectile_${_projectileIdCounter++}',
      x: _playerX,
      y: _playerY,
      targetX: enemy.x,
      targetY: enemy.y,
      speed: 5.0,
      damage: damage,
      targetEnemyId: enemy.id,
    );
    
    _projectiles[projectile.id] = projectile;
    
    if (mounted) {
      setState(() {
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
                  _enemy1Sprite,
                  _enemy2Sprite,
                  _worldBackground,
                  _worldToScreenX,
                  _worldToScreenY,
                  _playerSize,
                  _repaintCounter,
                  _enemies,
                  _projectiles,
                  _targetedEnemyId,
                  _playerHp,
                  _playerMaxHp,
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
    
    return Stack(
      children: [
        KeyboardListener(
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
              } else if (key == LogicalKeyboardKey.tab) {
                _targetNextEnemy();
              } else if (key == LogicalKeyboardKey.digit1) {
                _shootProjectile(attackType: 1);
              } else if (key == LogicalKeyboardKey.digit2) {
                _shootProjectile(attackType: 2);
              } else if (key == LogicalKeyboardKey.digit3) {
                _shootProjectile(attackType: 3);
              } else if (key == LogicalKeyboardKey.digit4) {
                _shootProjectile(attackType: 4);
              } else if (key == LogicalKeyboardKey.digit5) {
                _shootProjectile(attackType: 5);
              } else if (key == LogicalKeyboardKey.digit6) {
                _shootProjectile(attackType: 6);
              } else if (key == LogicalKeyboardKey.digit7) {
                _shootProjectile(attackType: 7);
              } else if (key == LogicalKeyboardKey.digit8) {
                _shootProjectile(attackType: 8);
              } else if (key == LogicalKeyboardKey.digit9) {
                _shootProjectile(attackType: 9);
              }
            } else if (event is KeyUpEvent) {
              _pressedKeys.remove(key);
            }
          },
          child: gameContent,
        ),
        if (_isLoading)
          _buildLoadingScreen(),
      ],
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
  Function(List<dynamic>) _enemiesListCallback = (_) {};
  Function(Map<String, dynamic>) _enemyUpdatedCallback = (_) {};
  Function(Map<String, dynamic>) _enemyRemovedCallback = (_) {};

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    _characterNameController?.dispose();
    _characterNameFocusNode?.dispose();
    _movementTimer?.cancel();
    _positionUpdateTimer?.cancel();
    _projectileUpdateTimer?.cancel();
    _gameService.removeCallback(
      onPlayerJoined: _playerJoinedCallback,
      onPlayerMoved: _playerMovedCallback,
      onPlayerLeft: _playerLeftCallback,
      onPlayersList: _playersListCallback,
      onEnemiesList: _enemiesListCallback,
      onEnemyUpdated: _enemyUpdatedCallback,
      onEnemyRemoved: _enemyRemovedCallback,
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
  final ui.Image? enemy1Sprite;
  final ui.Image? enemy2Sprite;
  final ui.Image? worldBackground;
  final double Function(double) worldToScreenX;
  final double Function(double) worldToScreenY;
  final double playerSize;
  final int repaintCounter;
  final Map<String, Enemy> enemies;
  final Map<String, Projectile> projectiles;
  final String? targetedEnemyId;
  final double playerHp;
  final double playerMaxHp;
  
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
    this.enemy1Sprite,
    this.enemy2Sprite,
    this.worldBackground,
    this.worldToScreenX,
    this.worldToScreenY,
    this.playerSize,
    this.repaintCounter,
    this.enemies,
    this.projectiles,
    this.targetedEnemyId,
    this.playerHp,
    this.playerMaxHp,
  );

  void _drawSprite(
    Canvas canvas,
    ui.Image? sprite,
    double worldX,
    double worldY,
    double size,
    PlayerDirection direction,
  ) {
    if (sprite == null) return;
    
    // Validate sprite dimensions
    if (sprite.width <= 0 || sprite.height <= 0) return;
    
    // Ensure sprite is at least 1024x512 for up/down directions
    final spriteWidth = sprite.width.toDouble();
    final spriteHeight = sprite.height.toDouble();
    
    Rect sourceRect;
    if (direction == PlayerDirection.down) {
      sourceRect = Rect.fromLTWH(0, 0, spriteWidth >= 512 ? 512 : spriteWidth, spriteHeight >= 512 ? 512 : spriteHeight);
    } else if (direction == PlayerDirection.up) {
      // For up direction, use the right half if sprite is wide enough, otherwise use the left half
      if (spriteWidth >= 1024) {
        sourceRect = Rect.fromLTWH(512, 0, 512, spriteHeight >= 512 ? 512 : spriteHeight);
      } else {
        // Fallback to left half if sprite is not wide enough
        sourceRect = Rect.fromLTWH(0, 0, spriteWidth >= 512 ? 512 : spriteWidth, spriteHeight >= 512 ? 512 : spriteHeight);
      }
    } else {
      sourceRect = Rect.fromLTWH(0, 0, spriteWidth >= 512 ? 512 : spriteWidth, spriteHeight >= 512 ? 512 : spriteHeight);
    }
    
    // Clamp sourceRect to sprite bounds
    sourceRect = Rect.fromLTWH(
      sourceRect.left.clamp(0.0, spriteWidth),
      sourceRect.top.clamp(0.0, spriteHeight),
      sourceRect.width.clamp(0.0, spriteWidth - sourceRect.left),
      sourceRect.height.clamp(0.0, spriteHeight - sourceRect.top),
    );

    final screenX = worldToScreenX(worldX);
    final screenY = worldToScreenY(worldY);
    
    // Validate screen coordinates
    if (screenX.isNaN || screenY.isNaN || size.isNaN || size <= 0) return;
    
    final destRect = Rect.fromCenter(
      center: Offset(screenX, screenY),
      width: size,
      height: size,
    );
    
    try {
      canvas.drawImageRect(sprite, sourceRect, destRect, Paint());
    } catch (e) {
      // Silently fail if drawing fails
      print('Error drawing sprite: $e');
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

  ui.Image? _getEnemySpriteForType(String? spriteType) {
    if (spriteType == 'enemy-1' && enemy1Sprite != null) {
      return enemy1Sprite;
    } else if (spriteType == 'enemy-2' && enemy2Sprite != null) {
      return enemy2Sprite;
    }
    // Return first available sprite, or null if neither is loaded
    return enemy1Sprite ?? enemy2Sprite;
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
      
      // Calculate what world coordinates we want to see (centered on player)
      final worldViewStartX = playerX - size.width / 2;
      final worldViewStartY = playerY - size.height / 2;
      final worldViewEndX = playerX + size.width / 2;
      final worldViewEndY = playerY + size.height / 2;
      
      // Clamp to actual world bounds
      final clampedStartX = worldViewStartX.clamp(_worldMinX, _worldMaxX);
      final clampedStartY = worldViewStartY.clamp(_worldMinY, _worldMaxY);
      final clampedEndX = worldViewEndX.clamp(_worldMinX, _worldMaxX);
      final clampedEndY = worldViewEndY.clamp(_worldMinY, _worldMaxY);
      
      // Normalize to [0, 1] range within world bounds
      final normStartX = (clampedStartX - _worldMinX) / worldWidth;
      final normStartY = (clampedStartY - _worldMinY) / worldHeight;
      final normEndX = (clampedEndX - _worldMinX) / worldWidth;
      final normEndY = (clampedEndY - _worldMinY) / worldHeight;
      
      // Map to background image coordinates
      final sourceX = normStartX * bgWidth;
      final sourceY = normStartY * bgHeight;
      final sourceW = (normEndX - normStartX) * bgWidth;
      final sourceH = (normEndY - normStartY) * bgHeight;
      
      // Source rectangle (clamped to image bounds)
      final sourceRect = Rect.fromLTWH(
        sourceX.clamp(0.0, bgWidth),
        sourceY.clamp(0.0, bgHeight),
        sourceW.clamp(0.0, bgWidth - sourceX.clamp(0.0, bgWidth)),
        sourceH.clamp(0.0, bgHeight - sourceY.clamp(0.0, bgHeight)),
      );
      
      // Destination always fills entire screen
      final destRect = Rect.fromLTWH(0, 0, size.width, size.height);
      
      canvas.drawImageRect(worldBackground!, sourceRect, destRect, Paint());
    }
    
    for (var player in players.values) {
      if (player.id != currentPlayerId) {
        try {
          // Validate player properties
          if (player.x.isNaN || player.y.isNaN) continue;
          
          final playerSpriteType = player.spriteType ?? 'char-2';
          final sprite = _getSpriteForType(playerSpriteType);
          
          if (sprite != null) {
            final playerDirection = player.direction ?? PlayerDirection.down;
            _drawSprite(canvas, sprite, player.x, player.y, playerSize, playerDirection);
          } else {
            final screenX = worldToScreenX(player.x);
            final screenY = worldToScreenY(player.y);
            
            if (screenX.isNaN || screenY.isNaN) continue;
            
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
          
          if (screenX.isNaN || screenY.isNaN) continue;
          
          final fontSize = playerSize * 0.1;
          final textPainter = TextPainter(
            text: TextSpan(
              text: player.name ?? '',
              style: TextStyle(color: Colors.black, fontSize: fontSize),
            ),
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();
          final textX = screenX - textPainter.width / 2;
          textPainter.paint(canvas, Offset(textX, screenY - playerSize / 2 - fontSize * 1.2));
        } catch (e) {
          // Skip rendering this player if there's an error
          print('Error rendering player ${player.id}: $e');
        }
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
    
    // Draw enemies
    for (var enemy in enemies.values) {
      if (enemy == null) continue;
      if (!enemy.isAlive || enemy.size <= 0) continue;
      
      try {
        // Validate enemy properties
        if (enemy.x.isNaN || enemy.y.isNaN || enemy.size.isNaN) continue;
        if (enemy.maxHp.isNaN || enemy.currentHp.isNaN) continue;
        
        final screenX = worldToScreenX(enemy.x);
        final screenY = worldToScreenY(enemy.y);
        final enemySize = enemy.size;
        
        if (screenX.isNaN || screenY.isNaN || enemySize.isNaN) continue;
        
        // Draw enemy sprite
        final enemySprite = _getEnemySpriteForType(enemy.spriteType);
        if (enemySprite != null) {
          final enemyDirection = enemy.direction ?? PlayerDirection.down;
          _drawSprite(canvas, enemySprite, enemy.x, enemy.y, enemySize, enemyDirection);
        } else {
          // Fallback to red rectangle if sprite not loaded
          final enemyPaint = Paint()..color = Colors.red;
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(screenX, screenY),
              width: enemySize,
              height: enemySize,
            ),
            enemyPaint,
          );
        }
        
        // Draw HP bar
        final hpBarWidth = enemySize;
        final hpBarHeight = 6.0;
        final hpBarY = screenY - enemySize / 2 - 15;
        final hpPercent = enemy.maxHp > 0 ? (enemy.currentHp.clamp(0.0, enemy.maxHp) / enemy.maxHp) : 0.0;
      
        // Background
        canvas.drawRect(
          Rect.fromLTWH(screenX - hpBarWidth / 2, hpBarY, hpBarWidth, hpBarHeight),
          Paint()..color = Colors.black54,
        );
        
        // HP bar
        canvas.drawRect(
          Rect.fromLTWH(screenX - hpBarWidth / 2, hpBarY, hpBarWidth * hpPercent, hpBarHeight),
          Paint()..color = hpPercent > 0.5 ? Colors.green : (hpPercent > 0.25 ? Colors.orange : Colors.red),
        );
        
        // Draw targeting indicator if targeted
        if (targetedEnemyId == enemy.id) {
          final indicatorPaint = Paint()
            ..color = Colors.yellow
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0;
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(screenX, screenY),
              width: enemySize + 10,
              height: enemySize + 10,
            ),
            indicatorPaint,
          );
        }
      } catch (e, stackTrace) {
        // Skip rendering this enemy if there's an error
        print('Error rendering enemy ${enemy.id}: $e');
        print('Stack trace: $stackTrace');
      }
    }
    
    // Draw projectiles
    for (var projectile in projectiles.values) {
      if (!projectile.isActive) continue;
      
      try {
        if (projectile.x.isNaN || projectile.y.isNaN) continue;
        
        final screenX = worldToScreenX(projectile.x);
        final screenY = worldToScreenY(projectile.y);
        
        if (screenX.isNaN || screenY.isNaN) continue;
        
        final projectilePaint = Paint()..color = Colors.yellow;
        canvas.drawCircle(
          Offset(screenX, screenY),
          5.0,
          projectilePaint,
        );
      } catch (e) {
        // Skip rendering this projectile if there's an error
        print('Error rendering projectile ${projectile.id}: $e');
      }
    }
    
    // Draw player HP bar
    if (currentPlayerId.isNotEmpty) {
      final hpBarWidth = 200.0;
      final hpBarHeight = 20.0;
      final hpBarX = 20.0;
      final hpBarY = size.height - 40.0;
      final hpPercent = playerMaxHp > 0 ? (playerHp.clamp(0.0, playerMaxHp) / playerMaxHp) : 0.0;
      
      // Background
      canvas.drawRect(
        Rect.fromLTWH(hpBarX, hpBarY, hpBarWidth, hpBarHeight),
        Paint()..color = Colors.black54,
      );
      
      // HP bar
      canvas.drawRect(
        Rect.fromLTWH(hpBarX, hpBarY, hpBarWidth * hpPercent, hpBarHeight),
        Paint()..color = hpPercent > 0.5 ? Colors.green : (hpPercent > 0.25 ? Colors.orange : Colors.red),
      );
      
      // HP text
      final hpText = 'HP: ${playerHp.toInt()}/${playerMaxHp.toInt()}';
      final textPainter = TextPainter(
        text: TextSpan(
          text: hpText,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(hpBarX + 5, hpBarY + 2));
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
    
    if (oldDelegate.enemies.length != enemies.length ||
        oldDelegate.projectiles.length != projectiles.length ||
        oldDelegate.targetedEnemyId != targetedEnemyId ||
        (oldDelegate.playerHp - playerHp).abs() > 0.1) {
      return true;
    }
    
    for (var enemyId in enemies.keys) {
      final oldEnemy = oldDelegate.enemies[enemyId];
      final newEnemy = enemies[enemyId];
      if (oldEnemy == null || newEnemy == null) {
        return true;
      }
      if ((oldEnemy.x - newEnemy.x).abs() > 0.01 ||
          (oldEnemy.y - newEnemy.y).abs() > 0.01 ||
          (oldEnemy.currentHp - newEnemy.currentHp).abs() > 0.1 ||
          oldEnemy.direction != newEnemy.direction ||
          oldEnemy.spriteType != newEnemy.spriteType) {
        return true;
      }
    }
    
    for (var projectileId in projectiles.keys) {
      final oldProjectile = oldDelegate.projectiles[projectileId];
      final newProjectile = projectiles[projectileId];
      if (oldProjectile == null || newProjectile == null) {
        return true;
      }
      if ((oldProjectile.x - newProjectile.x).abs() > 0.01 ||
          (oldProjectile.y - newProjectile.y).abs() > 0.01 ||
          oldProjectile.isActive != newProjectile.isActive) {
        return true;
      }
    }
    
    return oldDelegate.currentPlayerName != currentPlayerName ||
        oldDelegate.currentPlayerDirection != currentPlayerDirection ||
        oldDelegate.currentPlayerSpriteType != currentPlayerSpriteType ||
        oldDelegate.char1Sprite != char1Sprite ||
        oldDelegate.char2Sprite != char2Sprite ||
        oldDelegate.enemy1Sprite != enemy1Sprite ||
        oldDelegate.enemy2Sprite != enemy2Sprite;
  }
}

