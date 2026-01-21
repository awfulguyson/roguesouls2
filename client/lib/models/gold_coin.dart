class GoldCoin {
  final String id;
  final double x;
  final double y;
  final int amount;
  DateTime createdAt;
  
  GoldCoin({
    required this.id,
    required this.x,
    required this.y,
    required this.amount,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  
  bool get isExpired {
    final now = DateTime.now();
    return now.difference(createdAt).inSeconds > 300; // Expire after 5 minutes
  }
}

