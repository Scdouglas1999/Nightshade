import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Marker showing user's observation location on the weather radar map.
///
/// Displays as a pulsing dot with an outer ring to indicate the current
/// observing location. The pulsing animation helps draw attention to the
/// user's position on the map.
class LocationMarker extends StatefulWidget {
  /// Theme colors for styling the marker
  final NightshadeColors colors;

  const LocationMarker({
    super.key,
    required this.colors,
  });

  @override
  State<LocationMarker> createState() => _LocationMarkerState();
}

class _LocationMarkerState extends State<LocationMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    // Start the pulsing animation
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highlightColor = Theme.of(context).colorScheme.onPrimary;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return CustomPaint(
          painter: _LocationMarkerPainter(
            colors: widget.colors,
            highlightColor: highlightColor,
            pulseScale: _pulseAnimation.value,
          ),
          size: const Size(40, 40),
        );
      },
    );
  }
}

/// Custom painter for the location marker
class _LocationMarkerPainter extends CustomPainter {
  final NightshadeColors colors;
  final Color highlightColor;
  final double pulseScale;

  _LocationMarkerPainter({
    required this.colors,
    required this.highlightColor,
    required this.pulseScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 6;

    // Outer pulsing ring
    final outerRingPaint = Paint()
      ..color = colors.primary.withValues(alpha: 0.3 * (2.0 - pulseScale))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      center,
      baseRadius * 2.5 * pulseScale,
      outerRingPaint,
    );

    // Middle ring (static)
    final middleRingPaint = Paint()
      ..color = colors.primary.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(
      center,
      baseRadius * 2.0,
      middleRingPaint,
    );

    // Inner dot (solid)
    final innerDotPaint = Paint()
      ..color = colors.primary
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      center,
      baseRadius,
      innerDotPaint,
    );

    // Center highlight (white dot)
    final highlightPaint = Paint()
      ..color = highlightColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      center,
      baseRadius * 0.4,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(_LocationMarkerPainter oldDelegate) {
    return oldDelegate.pulseScale != pulseScale ||
        oldDelegate.highlightColor != highlightColor ||
        oldDelegate.colors != colors;
  }
}
