import 'dart:math';

class Projectile {
  final String id;
  double x;
  double y;
  double targetX;
  double targetY;
  double speed;
  double damage;
  String? targetEnemyId;
  bool isActive;
  
  Projectile({
    required this.id,
    required this.x,
    required this.y,
    required this.targetX,
    required this.targetY,
    this.speed = 5.0,
    this.damage = 10.0,
    this.targetEnemyId,
    this.isActive = true,
  });
  
  void update() {
    if (!isActive) return;
    
    final dx = targetX - x;
    final dy = targetY - y;
    final distance = sqrt(dx * dx + dy * dy);
    
    if (distance < speed) {
      // Reached target
      x = targetX;
      y = targetY;
      isActive = false;
    } else {
      // Move towards target
      x += (dx / distance) * speed;
      y += (dy / distance) * speed;
    }
  }
  
  bool hasReachedTarget() {
    final dx = targetX - x;
    final dy = targetY - y;
    return sqrt(dx * dx + dy * dy) < 5.0;
  }
}

