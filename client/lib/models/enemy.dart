import 'dart:math';

class Enemy {
  final String id;
  double x;
  double y;
  final String spriteType;
  double maxHp;
  double currentHp;
  
  // Movement state
  DateTime? lastStateChangeTime;
  bool isMoving = false;
  double moveDirectionX = 0.0;
  double moveDirectionY = 0.0;
  static const double moveSpeed = 1.0; // Speed per frame
  static const Duration moveDuration = Duration(seconds: 1);
  static const Duration pauseDuration = Duration(seconds: 2);
  
  String get name {
    switch (spriteType) {
      case 'enemy-1':
        return 'Fire Zombie';
      case 'enemy-2':
        return 'Water Zombie';
      case 'enemy-3':
        return 'Earth Zombie';
      case 'enemy-4':
        return 'Air Zombie';
      case 'enemy-5':
        return 'Zombie';
      default:
        return 'Zombie';
    }
  }
  
  Enemy({
    required this.id,
    required this.x,
    required this.y,
    required this.spriteType,
    double? maxHp,
    double? currentHp,
  }) : maxHp = maxHp ?? _getHpForSpriteType(spriteType),
       currentHp = currentHp ?? _getHpForSpriteType(spriteType);
  
  static double _getHpForSpriteType(String spriteType) {
    switch (spriteType) {
      case 'enemy-1':
        return 100.0;
      case 'enemy-2':
        return 101.0;
      case 'enemy-3':
        return 102.0;
      case 'enemy-4':
        return 103.0;
      case 'enemy-5':
        return 104.0;
      default:
        return 100.0;
    }
  }
  
  // Animation frame tracking for sprite sheets
  DateTime? _animationStartTime;
  bool _wasMoving = false; // Track previous state to detect changes
  double _lastRotationAngle = 0.0; // Store last rotation angle for idle zombies
  static const Duration _frameDuration = Duration(milliseconds: 150); // ~6.67 fps
  
  // Setter for rotation angle (used when syncing from server)
  void setLastRotationAngle(double angle) {
    _lastRotationAngle = angle;
  }
  
  int getCurrentAnimationFrame() {
    if (spriteType != 'enemy-5') {
      return 0; // Non-sprite-sheet enemies use frame 0
    }
    
    final now = DateTime.now();
    
    // Reset animation if state changed
    if (_wasMoving != isMoving) {
      _animationStartTime = now;
      _wasMoving = isMoving;
    }
    
    if (_animationStartTime == null) {
      _animationStartTime = now;
    }
    
    final elapsed = now.difference(_animationStartTime!);
    final frameIndex = (elapsed.inMilliseconds / _frameDuration.inMilliseconds).floor();
    
    if (isMoving) {
      // Walking animation: frames 5-12 (8 frames, looping)
      // Use a single walking frame for animation, rotation will be applied separately
      return 5 + (frameIndex % 8);
    } else {
      // Idle animation: frame 0
      return 0;
    }
  }
  
  // Get rotation angle in radians for sprite rotation
  // Sprite faces East (right) by default
  // Returns rotation angle needed to face movement direction
  double getRotationAngle() {
    if (spriteType != 'enemy-5') {
      return 0.0; // No rotation for non-zombie enemies
    }
    
    if (isMoving) {
      // Calculate movement angle and store it
      // atan2(y, x): 0 = right, π/2 = down, π = left, -π/2 = up
      // Since sprite faces East (right) by default, rotation = movement angle
      // Only update if direction vectors are non-zero to avoid resetting
      if (moveDirectionX != 0.0 || moveDirectionY != 0.0) {
        _lastRotationAngle = atan2(moveDirectionY, moveDirectionX);
      }
      return _lastRotationAngle;
    } else {
      // When idle, ALWAYS use last rotation angle to maintain facing direction
      // This should never change unless the enemy starts moving again
      return _lastRotationAngle;
    }
  }
  
  void resetAnimation() {
    _animationStartTime = DateTime.now();
    _wasMoving = isMoving;
  }
  
  void startMoving(Random random) {
    // Choose random direction
    final angle = random.nextDouble() * 2 * pi;
    moveDirectionX = cos(angle);
    moveDirectionY = sin(angle);
    isMoving = true;
    lastStateChangeTime = DateTime.now();
    // Update rotation angle when starting to move
    if (spriteType == 'enemy-5') {
      _lastRotationAngle = atan2(moveDirectionY, moveDirectionX);
    }
    resetAnimation();
  }
  
  void stopMoving() {
    // Store rotation angle BEFORE clearing direction vectors
    if (spriteType == 'enemy-5' && (moveDirectionX != 0.0 || moveDirectionY != 0.0)) {
      _lastRotationAngle = atan2(moveDirectionY, moveDirectionX);
    }
    isMoving = false;
    moveDirectionX = 0.0;
    moveDirectionY = 0.0;
    lastStateChangeTime = DateTime.now();
    resetAnimation();
  }
  
  void update(Random random) {
    final now = DateTime.now();
    if (lastStateChangeTime == null) {
      startMoving(random);
      return;
    }
    
    final elapsed = now.difference(lastStateChangeTime!);
    
    if (isMoving) {
      // Move for 1 second
      if (elapsed >= moveDuration) {
        stopMoving();
      } else {
        // Move in the current direction
        x += moveDirectionX * moveSpeed;
        y += moveDirectionY * moveSpeed;
      }
    } else {
      // Pause for 2 seconds, then start moving again
      if (elapsed >= pauseDuration) {
        startMoving(random);
      }
    }
  }
  
  factory Enemy.fromJson(Map<String, dynamic> json) {
    return Enemy(
      id: json['id'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      spriteType: json['spriteType'] as String? ?? 'enemy-1',
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'x': x,
      'y': y,
      'spriteType': spriteType,
    };
  }
}

