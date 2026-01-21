enum CurrencyType {
  copper,
  silver,
  gold,
  platinum,
}

class CurrencyCoin {
  final String id;
  final double x;
  final double y;
  final CurrencyType type;
  final int amount; // Amount in the base unit (copper for copper, silver for silver, etc.)
  DateTime createdAt;
  
  CurrencyCoin({
    required this.id,
    required this.x,
    required this.y,
    required this.type,
    required this.amount,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  
  bool get isExpired {
    final now = DateTime.now();
    return now.difference(createdAt).inSeconds > 300; // Expire after 5 minutes
  }
  
  // Convert to display color
  int get color {
    switch (type) {
      case CurrencyType.copper:
        return 0xFFCD7F32; // Bronze/copper color
      case CurrencyType.silver:
        return 0xFFC0C0C0; // Silver color
      case CurrencyType.gold:
        return 0xFFFFD700; // Gold color
      case CurrencyType.platinum:
        return 0xFFB8D4E3; // Platinum/blueish color
    }
  }
}

