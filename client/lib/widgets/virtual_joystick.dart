import 'dart:math';
import 'package:flutter/material.dart';

class VirtualJoystick extends StatefulWidget {
  final Function(double deltaX, double deltaY) onMove;
  final double size;

  const VirtualJoystick({
    super.key,
    required this.onMove,
    this.size = 150.0,
  });

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _stickPosition = Offset.zero;
  bool _isActive = false;
  final double _baseRadius = 60.0;
  final double _stickRadius = 30.0;
  double _maxDistance = 0.0;

  @override
  void initState() {
    super.initState();
    _maxDistance = _baseRadius - _stickRadius;
  }

  void _updateStickPosition(Offset localPosition) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final delta = localPosition - center;
    final distance = delta.distance;

    if (distance <= _maxDistance) {
      _stickPosition = delta;
    } else {
      // Clamp to max distance
      final angle = atan2(delta.dy, delta.dx);
      _stickPosition = Offset(
        cos(angle) * _maxDistance,
        sin(angle) * _maxDistance,
      );
    }

    // Normalize to -1 to 1 range
    final normalizedX = _stickPosition.dx / _maxDistance;
    final normalizedY = _stickPosition.dy / _maxDistance;

    widget.onMove(normalizedX, normalizedY);
    setState(() {});
  }

  void _resetStick() {
    _stickPosition = Offset.zero;
    widget.onMove(0, 0);
    setState(() {
      _isActive = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        setState(() {
          _isActive = true;
        });
        final localPosition = details.localPosition;
        _updateStickPosition(localPosition);
      },
      onPanUpdate: (details) {
        final localPosition = details.localPosition;
        _updateStickPosition(localPosition);
      },
      onPanEnd: (_) => _resetStick(),
      onPanCancel: () => _resetStick(),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withOpacity(0.3),
          border: Border.all(
            color: Colors.white.withOpacity(0.5),
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            // Base circle
            Center(
              child: Container(
                width: _baseRadius * 2,
                height: _baseRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.2),
                ),
              ),
            ),
            // Stick
            Center(
              child: Transform.translate(
                offset: _stickPosition,
                child: Container(
                  width: _stickRadius * 2,
                  height: _stickRadius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isActive
                        ? Colors.white.withOpacity(0.9)
                        : Colors.white.withOpacity(0.6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

