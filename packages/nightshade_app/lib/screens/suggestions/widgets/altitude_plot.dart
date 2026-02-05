import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../framing/framing_altaz.dart';

/// A compact altitude plot showing target altitude over the night.
///
/// Displays a line chart with twilight zones, current time marker,
/// and transit indicator. Designed to be responsive and fit within
/// suggestion cards.
class AltitudePlot extends StatelessWidget {
  /// Right ascension in hours (0-24)
  final double raHours;

  /// Declination in degrees (-90 to +90)
  final double decDegrees;

  /// Observer latitude in degrees
  final double latitude;

  /// Observer longitude in degrees
  final double longitude;

  /// Height of the plot (width is flexible)
  final double height;

  /// Visibility info containing rise/set/transit times
  final TargetVisibilityInfo? visibility;

  const AltitudePlot({
    super.key,
    required this.raHours,
    required this.decDegrees,
    required this.latitude,
    required this.longitude,
    this.height = 60,
    this.visibility,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _AltitudePlotPainter(
          raHours: raHours,
          decDegrees: decDegrees,
          latitude: latitude,
          longitude: longitude,
          visibility: visibility,
          lineColor: colors.primary,
          gridColor: colors.border,
          textColor: colors.textMuted,
          twilightColor: colors.warning.withValues(alpha: 0.15),
          currentTimeColor: colors.success,
          transitColor: colors.info,
          horizonColor: colors.error.withValues(alpha: 0.3),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _AltitudePlotPainter extends CustomPainter {
  final double raHours;
  final double decDegrees;
  final double latitude;
  final double longitude;
  final TargetVisibilityInfo? visibility;
  final Color lineColor;
  final Color gridColor;
  final Color textColor;
  final Color twilightColor;
  final Color currentTimeColor;
  final Color transitColor;
  final Color horizonColor;

  _AltitudePlotPainter({
    required this.raHours,
    required this.decDegrees,
    required this.latitude,
    required this.longitude,
    this.visibility,
    required this.lineColor,
    required this.gridColor,
    required this.textColor,
    required this.twilightColor,
    required this.currentTimeColor,
    required this.transitColor,
    required this.horizonColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    final plotPadding = EdgeInsets.only(left: 20, right: 8, top: 4, bottom: 14);
    final plotRect = Rect.fromLTWH(
      plotPadding.left,
      plotPadding.top,
      size.width - plotPadding.left - plotPadding.right,
      size.height - plotPadding.top - plotPadding.bottom,
    );

    // Time range: 6 PM to 6 AM (12 hours centered on midnight)
    final today = DateTime(now.year, now.month, now.day);
    final startTime = today.add(const Duration(hours: 18)); // 6 PM
    final endTime = today.add(const Duration(hours: 30)); // 6 AM next day

    // Calculate twilight times
    final twilight = AstronomyCalculations.calculateTwilightTimes(
      date: now,
      latitudeDeg: latitude,
      longitudeDeg: longitude,
    );

    // Draw twilight zones (civil twilight as lighter background)
    _drawTwilightZones(canvas, plotRect, startTime, endTime, twilight);

    // Draw horizon line at 0 degrees
    _drawHorizonLine(canvas, plotRect);

    // Draw grid lines
    _drawGrid(canvas, plotRect, startTime, endTime);

    // Calculate and draw altitude curve
    _drawAltitudeCurve(canvas, plotRect, startTime, endTime);

    // Draw current time marker
    _drawCurrentTimeMarker(canvas, plotRect, startTime, endTime, now);

    // Draw transit marker if available
    if (visibility?.transitTime != null) {
      _drawTransitMarker(canvas, plotRect, startTime, endTime, visibility!.transitTime!);
    }

    // Draw axis labels
    _drawAxisLabels(canvas, size, plotRect, startTime, endTime);
  }

  void _drawTwilightZones(
    Canvas canvas,
    Rect plotRect,
    DateTime startTime,
    DateTime endTime,
    TwilightTimes twilight,
  ) {
    final paint = Paint()..color = twilightColor;

    // Civil twilight zones (before astronomical dusk, after astronomical dawn)
    if (twilight.astronomicalDusk != null) {
      final duskX = _timeToX(twilight.astronomicalDusk!, startTime, endTime, plotRect);
      if (duskX > plotRect.left) {
        canvas.drawRect(
          Rect.fromLTRB(plotRect.left, plotRect.top, duskX, plotRect.bottom),
          paint,
        );
      }
    }

    if (twilight.astronomicalDawn != null) {
      final dawnX = _timeToX(twilight.astronomicalDawn!, startTime, endTime, plotRect);
      if (dawnX < plotRect.right) {
        canvas.drawRect(
          Rect.fromLTRB(dawnX, plotRect.top, plotRect.right, plotRect.bottom),
          paint,
        );
      }
    }
  }

  void _drawHorizonLine(Canvas canvas, Rect plotRect) {
    final paint = Paint()
      ..color = horizonColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final horizonY = _altitudeToY(0, plotRect);
    canvas.drawLine(
      Offset(plotRect.left, horizonY),
      Offset(plotRect.right, horizonY),
      paint,
    );
  }

  void _drawGrid(Canvas canvas, Rect plotRect, DateTime startTime, DateTime endTime) {
    final paint = Paint()
      ..color = gridColor.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Horizontal grid lines at 30 and 60 degrees
    for (final alt in [30.0, 60.0]) {
      final y = _altitudeToY(alt, plotRect);
      canvas.drawLine(
        Offset(plotRect.left, y),
        Offset(plotRect.right, y),
        paint,
      );
    }

    // Vertical grid lines every 2 hours
    for (var hours = 0; hours <= 12; hours += 2) {
      final time = startTime.add(Duration(hours: hours));
      final x = _timeToX(time, startTime, endTime, plotRect);
      canvas.drawLine(
        Offset(x, plotRect.top),
        Offset(x, plotRect.bottom),
        paint,
      );
    }
  }

  void _drawAltitudeCurve(
    Canvas canvas,
    Rect plotRect,
    DateTime startTime,
    DateTime endTime,
  ) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();
    var first = true;

    // Sample altitude every 10 minutes
    final samples = 72; // 12 hours * 6 samples per hour
    final interval = const Duration(minutes: 10);

    for (var i = 0; i <= samples; i++) {
      final time = startTime.add(interval * i);
      final (alt, _) = calculateCurrentAltAz(
        raHours: raHours,
        decDegrees: decDegrees,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
        time: time,
      );

      final x = _timeToX(time, startTime, endTime, plotRect);
      final y = _altitudeToY(alt, plotRect);

      if (first) {
        path.moveTo(x, y);
        fillPath.moveTo(x, plotRect.bottom);
        fillPath.lineTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Complete fill path
    fillPath.lineTo(plotRect.right, plotRect.bottom);
    fillPath.close();

    // Draw fill first, then line
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  void _drawCurrentTimeMarker(
    Canvas canvas,
    Rect plotRect,
    DateTime startTime,
    DateTime endTime,
    DateTime now,
  ) {
    if (now.isBefore(startTime) || now.isAfter(endTime)) return;

    final x = _timeToX(now, startTime, endTime, plotRect);
    final paint = Paint()
      ..color = currentTimeColor
      ..strokeWidth = 1.5;

    // Dashed vertical line
    const dashHeight = 4.0;
    const gapHeight = 3.0;
    var y = plotRect.top;
    while (y < plotRect.bottom) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + dashHeight, plotRect.bottom)),
        paint,
      );
      y += dashHeight + gapHeight;
    }

    // Small triangle at current altitude
    final (alt, _) = calculateCurrentAltAz(
      raHours: raHours,
      decDegrees: decDegrees,
      latitudeDeg: latitude,
      longitudeDeg: longitude,
      time: now,
    );
    final altY = _altitudeToY(alt, plotRect);

    final trianglePath = Path()
      ..moveTo(x - 4, altY)
      ..lineTo(x + 4, altY)
      ..lineTo(x, altY - 5)
      ..close();
    canvas.drawPath(trianglePath, Paint()..color = currentTimeColor);
  }

  void _drawTransitMarker(
    Canvas canvas,
    Rect plotRect,
    DateTime startTime,
    DateTime endTime,
    DateTime transitTime,
  ) {
    if (transitTime.isBefore(startTime) || transitTime.isAfter(endTime)) return;

    final x = _timeToX(transitTime, startTime, endTime, plotRect);
    final paint = Paint()
      ..color = transitColor
      ..strokeWidth = 1;

    // Small diamond at transit
    final (alt, _) = calculateCurrentAltAz(
      raHours: raHours,
      decDegrees: decDegrees,
      latitudeDeg: latitude,
      longitudeDeg: longitude,
      time: transitTime,
    );
    final altY = _altitudeToY(alt, plotRect);

    final diamondPath = Path()
      ..moveTo(x, altY - 4)
      ..lineTo(x + 3, altY)
      ..lineTo(x, altY + 4)
      ..lineTo(x - 3, altY)
      ..close();
    canvas.drawPath(diamondPath, paint..style = PaintingStyle.fill);
  }

  void _drawAxisLabels(
    Canvas canvas,
    Size size,
    Rect plotRect,
    DateTime startTime,
    DateTime endTime,
  ) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    // Y-axis labels (altitude)
    for (final alt in [0, 30, 60, 90]) {
      textPainter.text = TextSpan(
        text: '$alt°',
        style: TextStyle(
          color: textColor,
          fontSize: 8,
        ),
      );
      textPainter.layout();
      final y = _altitudeToY(alt.toDouble(), plotRect);
      textPainter.paint(
        canvas,
        Offset(0, y - textPainter.height / 2),
      );
    }

    // X-axis labels (time)
    for (var hours = 0; hours <= 12; hours += 4) {
      final time = startTime.add(Duration(hours: hours));
      final label = hours == 0 ? '6PM' : hours == 6 ? '12AM' : '6AM';

      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          color: textColor,
          fontSize: 8,
        ),
      );
      textPainter.layout();
      final x = _timeToX(time, startTime, endTime, plotRect);
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, plotRect.bottom + 2),
      );
    }
  }

  double _timeToX(DateTime time, DateTime start, DateTime end, Rect plotRect) {
    final totalDuration = end.difference(start).inMinutes;
    final elapsed = time.difference(start).inMinutes;
    final fraction = elapsed / totalDuration;
    return plotRect.left + fraction * plotRect.width;
  }

  double _altitudeToY(double altitude, Rect plotRect) {
    // Clamp altitude to -10 to 90 range for display
    final clampedAlt = altitude.clamp(-10.0, 90.0);
    // Map -10 to bottom, 90 to top
    final fraction = (clampedAlt + 10) / 100;
    return plotRect.bottom - fraction * plotRect.height;
  }

  @override
  bool shouldRepaint(covariant _AltitudePlotPainter oldDelegate) {
    return raHours != oldDelegate.raHours ||
        decDegrees != oldDelegate.decDegrees ||
        latitude != oldDelegate.latitude ||
        longitude != oldDelegate.longitude;
  }
}
