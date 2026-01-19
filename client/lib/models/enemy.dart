import 'dart:math';
import 'package:flutter/material.dart';
import 'player.dart';

class Enemy {
  final String id;
  double x;
  double y;
  double maxHp;
  double currentHp;
  double size;
  bool isAggroed;
  DateTime? lastMoveTime;
  DateTime? lastAttackTime;
  double moveDirectionX;
  double moveDirectionY;
  bool isPaused;
  String? spriteType;
  PlayerDirection direction;
  
  Enemy({
    required this.id,
    required this.x,
    required this.y,
    this.maxHp = 100.0,
    this.currentHp = 100.0,
    this.size = 128.0,
    this.isAggroed = false,
    this.lastMoveTime,
    this.lastAttackTime,
    this.moveDirectionX = 0.0,
    this.moveDirectionY = 0.0,
    this.isPaused = false,
    this.spriteType,
    this.direction = PlayerDirection.down,
  });
  
  bool get isAlive => currentHp > 0;
  
  void takeDamage(double damage) {
    currentHp = (currentHp - damage).clamp(0.0, maxHp);
    if (damage > 0 && !isAggroed) {
      isAggroed = true;
    }
  }
  
  void setRandomDirection() {
    final random = Random();
    final angle = random.nextDouble() * 2 * pi;
    moveDirectionX = cos(angle);
    moveDirectionY = sin(angle);
  }
  
  Rect get hitbox => Rect.fromCenter(
    center: Offset(x, y),
    width: size,
    height: size,
  );
}

