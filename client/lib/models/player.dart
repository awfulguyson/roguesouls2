enum PlayerDirection {
  up,
  down,
  left,
  right,
}

class Player {
  final String id;
  final String name;
  double x;
  double y;
  PlayerDirection direction;
  String? spriteType;
  double hp;
  double maxHp;
  int level;

  Player({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    this.direction = PlayerDirection.down,
    this.spriteType,
    this.hp = 100.0,
    this.maxHp = 100.0,
    this.level = 1,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      direction: _directionFromString(json['direction'] as String? ?? 'down'),
      spriteType: json['spriteType'] as String?,
      hp: (json['hp'] as num?)?.toDouble() ?? 100.0,
      maxHp: (json['maxHp'] as num?)?.toDouble() ?? 100.0,
      level: (json['level'] as int?) ?? 1,
    );
  }

  static PlayerDirection _directionFromString(String dir) {
    switch (dir.toLowerCase()) {
      case 'up':
        return PlayerDirection.up;
      case 'left':
        return PlayerDirection.left;
      case 'right':
        return PlayerDirection.right;
      default:
        return PlayerDirection.down;
    }
  }
}

