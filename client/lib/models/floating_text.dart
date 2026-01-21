class FloatingText {
  final String id;
  final double x;
  final double y;
  final String text;
  final DateTime createdAt;
  final Duration duration;
  
  FloatingText({
    required this.id,
    required this.x,
    required this.y,
    required this.text,
    DateTime? createdAt,
    Duration? duration,
  }) : createdAt = createdAt ?? DateTime.now(),
       duration = duration ?? const Duration(milliseconds: 1500);
  
  bool get isExpired {
    final now = DateTime.now();
    return now.difference(createdAt) >= duration;
  }
  
  double get progress {
    final elapsed = DateTime.now().difference(createdAt);
    return (elapsed.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }
  
  double get offsetY {
    // Move upward as time progresses
    return -progress * 50.0; // Move up 50 pixels over duration
  }
  
  double get opacity {
    // Fade out in the last 30% of duration
    final fadeStart = 0.7;
    if (progress < fadeStart) {
      return 1.0;
    }
    final fadeProgress = (progress - fadeStart) / (1.0 - fadeStart);
    return 1.0 - fadeProgress;
  }
}

