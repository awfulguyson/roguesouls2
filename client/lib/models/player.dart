class Player {
  final String id;
  final String name;
  double x;
  double y;

  Player({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }
}

