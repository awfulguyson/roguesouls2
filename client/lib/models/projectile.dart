import 'dart:math';

class Projectile {
  final String id;
  double x;
  double y;
  final double targetX;
  final double targetY;
  final double speed;
  final double damage;
  final DateTime createdAt;
  
  Projectile({
    required this.id,
    required this.x,
    required this.y,
    required this.targetX,
    required this.targetY,
    this.speed = 500.0, // pixels per second
    this.damage = 10.0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  
  bool update(double deltaTime) {
    // Calculate direction to target
    final dx = targetX - x;
    final dy = targetY - y;
    final distance = sqrt(dx * dx + dy * dy);
    
    // If we're close enough to the target, consider it hit
    if (distance < 10.0) {
      return true; // Hit target
    }
    
    // Move towards target
    if (distance > 0) {
      final moveDistance = speed * deltaTime;
      final ratio = (moveDistance / distance).clamp(0.0, 1.0);
      x += dx * ratio;
      y += dy * ratio;
    }
    
    return false; // Still traveling
  }
  
  double get angle {
    final dx = targetX - x;
    final dy = targetY - y;
    return atan2(dy, dx);
  }
}

