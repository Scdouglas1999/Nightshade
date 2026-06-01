// Part of ../targets_tab.dart -- extracted for maintainability.
//
// Night timeline widget and painter.
part of '../targets_tab.dart';

class _NightTimeline extends ConsumerWidget {
  const _NightTimeline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final sequence = ref.watch(currentSequenceProvider);
    final location = ref.watch(observerLocationProvider);

    // Calculate timeline range (Sunset to Sunrise, centered on midnight)
    // For simplicity in this view, we'll show 6pm to 6am local time
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 18);
    final end = start.add(const Duration(hours: 12));

    final targetGroups = sequence?.targetHeaders ?? [];

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _TimelinePainter(
            colors: colors,
            startTime: start,
            endTime: end,
            targets: targetGroups,
            latitude: location.latitude,
            longitude: location.longitude,
          ),
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final NightshadeColors colors;
  final DateTime startTime;
  final DateTime endTime;
  final List<TargetHeaderNode> targets;
  final double latitude;
  final double longitude;

  _TimelinePainter({
    required this.colors,
    required this.startTime,
    required this.endTime,
    required this.targets,
    required this.latitude,
    required this.longitude,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = colors.surfaceAlt;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw Optimal Window (Alt > 30)
    _drawOptimalWindow(canvas, size);

    // Draw Grid lines
    _drawGrid(canvas, size);

    // Draw Moon Altitude Curve
    _drawMoonCurve(canvas, size);

    // Draw Target Altitude Curves
    for (int i = 0; i < targets.length; i++) {
      final target = targets[i];
      // Assign a color based on index
      final color = [
        colors.primary,
        colors.accent,
        colors.success,
        colors.warning,
        colors.info
      ][i % 5];

      _drawAltitudeCurve(canvas, size, target, color);
    }

    // Draw Current Time Indicator
    _drawCurrentTime(canvas, size);
  }

  void _drawOptimalWindow(Canvas canvas, Size size) {
    // Highlight area above 30 degrees
    final y30 = size.height - (30 / 90.0 * size.height);
    final paint = Paint()
      ..color = colors.success.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, y30), paint);

    // Draw clear 30 degree line
    final linePaint = Paint()
      ..color = colors.success.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    // ..pathEffect = const DashPathEffect(5, 5); // Requires ui import or helper

    canvas.drawLine(Offset(0, y30), Offset(size.width, y30), linePaint);
  }

  void _drawMoonCurve(Canvas canvas, Size size) {
    final path = Path();
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // ..pathEffect = DashPathEffect(5, 5);

    final totalMinutes = endTime.difference(startTime).inMinutes;
    bool first = true;

    for (int i = 0; i <= totalMinutes; i += 10) {
      final time = startTime.add(Duration(minutes: i));
      final pos = AstronomyCalculations.moonPosition(time);
      final altAz = AstronomyCalculations.objectAltAz(
        raDeg: pos.$1 * 15.0,
        decDeg: pos.$2,
        dt: time,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
      );

      final x = (i / totalMinutes) * size.width;
      final y = size.height - (altAz.$1 / 90.0 * size.height);
      final clampedY = y.clamp(0.0, size.height);

      if (first) {
        path.moveTo(x, clampedY);
        first = false;
      } else {
        path.lineTo(x, clampedY);
      }
    }

    canvas.drawPath(path, paint);

    // Label for Moon
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Moon',
        style: TextStyle(color: Colors.white54, fontSize: 10),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - 40, 10));
  }

  void _drawGrid(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = colors.border.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    final textStyle = TextStyle(
      color: colors.textMuted,
      fontSize: 10,
    );
    final textPainter = TextPainter(
      text: const TextSpan(text: ''),
      textDirection: ui.TextDirection.ltr,
    );

    // Horizontal lines (Altitude: 0, 30, 60, 90)
    for (int alt = 0; alt <= 90; alt += 30) {
      final y = size.height - (alt / 90.0 * size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);

      textPainter.text = TextSpan(text: '$alt°', style: textStyle);
      textPainter.layout();
      textPainter.paint(canvas, Offset(4, y - 12));
    }

    // Vertical lines (Time)
    final totalDuration = endTime.difference(startTime).inMinutes;
    for (int i = 0; i <= totalDuration; i += 60) {
      // Every hour
      final x = (i / totalDuration) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

      final time = startTime.add(Duration(minutes: i));
      textPainter.text = TextSpan(
        text: DateFormat('HH:mm').format(time),
        style: textStyle,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 4, size.height - 16));
    }
  }

  void _drawAltitudeCurve(
      Canvas canvas, Size size, TargetHeaderNode target, Color color) {
    final path = Path();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final shadowPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final totalMinutes = endTime.difference(startTime).inMinutes;

    // Calculate points every 10 minutes
    bool first = true;
    final shadowPath = Path();

    for (int i = 0; i <= totalMinutes; i += 10) {
      final time = startTime.add(Duration(minutes: i));
      final altAz = AstronomyCalculations.objectAltAz(
        raDeg: target.raHours * 15.0,
        decDeg: target.decDegrees,
        dt: time,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
      );

      final x = (i / totalMinutes) * size.width;
      final y = size.height - (altAz.$1 / 90.0 * size.height); // $1 is altitude

      // Clamp Y to not go below chart
      final clampedY = y.clamp(0.0, size.height);

      if (first) {
        path.moveTo(x, clampedY);
        shadowPath.moveTo(x, size.height);
        shadowPath.lineTo(x, clampedY);
        first = false;
      } else {
        path.lineTo(x, clampedY);
        shadowPath.lineTo(x, clampedY);
      }
    }

    shadowPath.lineTo(size.width, size.height);
    shadowPath.close();

    canvas.drawPath(shadowPath, shadowPaint);
    canvas.drawPath(path, paint);

    // Draw label near the highest altitude point (approximate transit).
    final textPainter = TextPainter(
      text: TextSpan(
        text: target.targetName,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(blurRadius: 2, color: Colors.black.withValues(alpha: 0.5)),
          ],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );

    // Find highest point on curve to place label
    // Re-calculate just the peak approx
    double peakAlt = -90;
    double peakX = 0;

    for (int i = 0; i <= totalMinutes; i += 30) {
      final time = startTime.add(Duration(minutes: i));
      final altAz = AstronomyCalculations.objectAltAz(
        raDeg: target.raHours * 15.0,
        decDeg: target.decDegrees,
        dt: time,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
      );
      if (altAz.$1 > peakAlt) {
        peakAlt = altAz.$1;
        peakX = (i / totalMinutes) * size.width;
      }
    }

    if (peakAlt > 0) {
      final peakY = size.height - (peakAlt / 90.0 * size.height);
      textPainter.layout();
      textPainter.paint(
          canvas, Offset(peakX - textPainter.width / 2, peakY - 20));
    }
  }

  void _drawCurrentTime(Canvas canvas, Size size) {
    final now = DateTime.now();
    if (now.isBefore(startTime) || now.isAfter(endTime)) return;

    final totalDuration = endTime.difference(startTime).inMinutes;
    final elapsed = now.difference(startTime).inMinutes;
    final x = (elapsed / totalDuration) * size.width;

    final paint = Paint()
      ..color = colors.error
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Now',
        style: TextStyle(color: colors.error, fontSize: 10),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x + 4, 4));
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.startTime != startTime || oldDelegate.targets != targets;
  }
}
