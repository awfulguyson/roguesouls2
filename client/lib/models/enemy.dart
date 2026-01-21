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
      default:
        return 100.0;
    }
  }
  
  void startMoving(Random random) {
    // Choose random direction
    final angle = random.nextDouble() * 2 * pi;
    moveDirectionX = cos(angle);
    moveDirectionY = sin(angle);
    isMoving = true;
    lastStateChangeTime = DateTime.now();
  }
  
  void stopMoving() {
    isMoving = false;
    moveDirectionX = 0.0;
    moveDirectionY = 0.0;
    lastStateChangeTime = DateTime.now();
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

