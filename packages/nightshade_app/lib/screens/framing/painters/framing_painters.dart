import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Equipment FOV rectangle drawn at the canvas center when the preview FOV is
/// at or below the equipment FOV. Includes corner markers, a rotation handle
/// stub, FOV dimensions, and optional cardinal directions.
class FramingFOVPainter extends CustomPainter {
  final double fovWidth;
  final double fovHeight;
  final double zoom;
  final NightshadeColors colors;
  final bool showDirections;

  FramingFOVPainter({
    required this.fovWidth,
    required this.fovHeight,
    required this.zoom,
    required this.colors,
    required this.showDirections,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Scale: roughly 60 pixels per degree at zoom 1.0
    final pixelsPerDegree = 60.0 * zoom;
    final rectWidth = fovWidth * pixelsPerDegree;
    final rectHeight = fovHeight * pixelsPerDegree;

    final center = Offset(size.width / 2, size.height / 2);

    // Semi-transparent fill
    final fillPaint = Paint()
      ..color = colors.primary.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    // Border
    final borderPaint = Paint()
      ..color = colors.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromCenter(
      center: center,
      width: rectWidth,
      height: rectHeight,
    );

    // Draw frame
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(rrect, borderPaint);

    // Draw corner markers
    _drawCorners(canvas, rect, borderPaint);

    // Draw rotation handle
    final handlePaint = Paint()
      ..color = colors.primary
      ..style = PaintingStyle.fill;
    final handleY = center.dy - rectHeight / 2 - 18;
    canvas.drawCircle(Offset(center.dx, handleY), 10, handlePaint);
    canvas.drawLine(
      Offset(center.dx, center.dy - rectHeight / 2),
      Offset(center.dx, handleY + 10),
      borderPaint,
    );

    // Draw rotation icon
    final iconPainter = TextPainter(
      text: const TextSpan(
        text: '↻',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();
    iconPainter.paint(canvas, Offset(center.dx - 6, handleY - 7));

    // Draw cardinal directions
    if (showDirections) {
      _drawCardinalDirections(canvas, center, rectWidth, rectHeight);
    }

    // Draw FOV dimensions
    final fovText =
        '${fovWidth.toStringAsFixed(2)}° × ${fovHeight.toStringAsFixed(2)}°';
    final textPainter = TextPainter(
      text: TextSpan(
        text: fovText,
        style: TextStyle(
          color: colors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Draw text background
    final textBg = Rect.fromCenter(
      center: Offset(center.dx, center.dy + rectHeight / 2 + 18),
      width: textPainter.width + 12,
      height: textPainter.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(textBg, const Radius.circular(4)),
      Paint()..color = Colors.black.withValues(alpha: 0.7),
    );
    textPainter.paint(
      canvas,
      Offset(
          center.dx - textPainter.width / 2, center.dy + rectHeight / 2 + 15),
    );
  }

  void _drawCorners(Canvas canvas, Rect rect, Paint paint) {
    final cornerLength = math.min(rect.width, rect.height) * 0.1;
    paint.strokeWidth = 3;

    // Top-left
    canvas.drawLine(
        Offset(rect.left, rect.top + cornerLength), rect.topLeft, paint);
    canvas.drawLine(
        rect.topLeft, Offset(rect.left + cornerLength, rect.top), paint);

    // Top-right
    canvas.drawLine(
        Offset(rect.right - cornerLength, rect.top), rect.topRight, paint);
    canvas.drawLine(
        rect.topRight, Offset(rect.right, rect.top + cornerLength), paint);

    // Bottom-right
    canvas.drawLine(Offset(rect.right, rect.bottom - cornerLength),
        rect.bottomRight, paint);
    canvas.drawLine(rect.bottomRight,
        Offset(rect.right - cornerLength, rect.bottom), paint);

    // Bottom-left
    canvas.drawLine(
        Offset(rect.left + cornerLength, rect.bottom), rect.bottomLeft, paint);
    canvas.drawLine(
        rect.bottomLeft, Offset(rect.left, rect.bottom - cornerLength), paint);
  }

  void _drawCardinalDirections(
      Canvas canvas, Offset center, double width, double height) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.6),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    final directions = ['N', 'E', 'S', 'W'];
    final positions = [
      Offset(center.dx, center.dy - height / 2 + 12),
      Offset(center.dx + width / 2 - 12, center.dy),
      Offset(center.dx, center.dy + height / 2 - 12),
      Offset(center.dx - width / 2 + 8, center.dy),
    ];

    for (var i = 0; i < 4; i++) {
      final textPainter = TextPainter(
        text: TextSpan(text: directions[i], style: style),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        positions[i] - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant FramingFOVPainter oldDelegate) {
    return fovWidth != oldDelegate.fovWidth ||
        fovHeight != oldDelegate.fovHeight ||
        zoom != oldDelegate.zoom ||
        showDirections != oldDelegate.showDirections;
  }
}

/// Draws the equipment FOV overlay when preview FOV is larger than equipment FOV
/// This shows the user what their actual capture area will be
class FramingEquipmentFOVOverlayPainter extends CustomPainter {
  final double fovWidth;
  final double fovHeight;
  final double previewFov;
  final double zoom;
  final NightshadeColors colors;
  final double opacity;
  final bool showDirections;

  FramingEquipmentFOVOverlayPainter({
    required this.fovWidth,
    required this.fovHeight,
    required this.previewFov,
    required this.zoom,
    required this.colors,
    required this.opacity,
    required this.showDirections,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Scale: the preview FOV fills the canvas
    final pixelsPerDegree = size.width / previewFov * zoom;
    final rectWidth = fovWidth * pixelsPerDegree;
    final rectHeight = fovHeight * pixelsPerDegree;

    final center = Offset(size.width / 2, size.height / 2);

    // Semi-transparent fill for the equipment FOV area
    final fillPaint = Paint()
      ..color = colors.info.withValues(alpha: opacity * 0.3)
      ..style = PaintingStyle.fill;

    // Border for the equipment FOV
    final borderPaint = Paint()
      ..color = colors.info.withValues(alpha: 0.8)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromCenter(
      center: center,
      width: rectWidth,
      height: rectHeight,
    );

    // Draw dark overlay outside the equipment FOV
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: opacity),
    );

    // Draw equipment FOV frame
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(rrect, borderPaint);

    // Draw corner brackets
    _drawCornerBrackets(canvas, rect, borderPaint);

    // Draw equipment FOV label
    final fovText =
        'Equipment FOV: ${fovWidth.toStringAsFixed(2)}° × ${fovHeight.toStringAsFixed(2)}°';
    final textPainter = TextPainter(
      text: TextSpan(
        text: fovText,
        style: TextStyle(
          color: colors.info,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Draw text background
    final textBg = Rect.fromCenter(
      center: Offset(center.dx, rect.top - 16),
      width: textPainter.width + 16,
      height: textPainter.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(textBg, const Radius.circular(4)),
      Paint()..color = colors.info.withValues(alpha: 0.15),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(textBg, const Radius.circular(4)),
      Paint()
        ..color = colors.info.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2,
          rect.top - textPainter.height / 2 - 16),
    );

    // Draw cardinal directions inside the equipment FOV
    if (showDirections) {
      _drawCardinalDirections(canvas, center, rectWidth, rectHeight);
    }
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, Paint paint) {
    final bracketLength = math.min(rect.width, rect.height) * 0.12;
    paint.strokeWidth = 3;

    // Top-left bracket
    canvas.drawLine(Offset(rect.left - 2, rect.top + bracketLength),
        Offset(rect.left - 2, rect.top - 2), paint);
    canvas.drawLine(Offset(rect.left - 2, rect.top - 2),
        Offset(rect.left + bracketLength, rect.top - 2), paint);

    // Top-right bracket
    canvas.drawLine(Offset(rect.right - bracketLength, rect.top - 2),
        Offset(rect.right + 2, rect.top - 2), paint);
    canvas.drawLine(Offset(rect.right + 2, rect.top - 2),
        Offset(rect.right + 2, rect.top + bracketLength), paint);

    // Bottom-right bracket
    canvas.drawLine(Offset(rect.right + 2, rect.bottom - bracketLength),
        Offset(rect.right + 2, rect.bottom + 2), paint);
    canvas.drawLine(Offset(rect.right + 2, rect.bottom + 2),
        Offset(rect.right - bracketLength, rect.bottom + 2), paint);

    // Bottom-left bracket
    canvas.drawLine(Offset(rect.left + bracketLength, rect.bottom + 2),
        Offset(rect.left - 2, rect.bottom + 2), paint);
    canvas.drawLine(Offset(rect.left - 2, rect.bottom + 2),
        Offset(rect.left - 2, rect.bottom - bracketLength), paint);
  }

  void _drawCardinalDirections(
      Canvas canvas, Offset center, double width, double height) {
    final style = TextStyle(
      color: colors.info.withValues(alpha: 0.7),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    final directions = ['N', 'E', 'S', 'W'];
    final positions = [
      Offset(center.dx, center.dy - height / 2 + 14),
      Offset(center.dx + width / 2 - 14, center.dy),
      Offset(center.dx, center.dy + height / 2 - 14),
      Offset(center.dx - width / 2 + 10, center.dy),
    ];

    for (var i = 0; i < 4; i++) {
      final textPainter = TextPainter(
        text: TextSpan(text: directions[i], style: style),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        positions[i] - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant FramingEquipmentFOVOverlayPainter oldDelegate) {
    return fovWidth != oldDelegate.fovWidth ||
        fovHeight != oldDelegate.fovHeight ||
        previewFov != oldDelegate.previewFov ||
        zoom != oldDelegate.zoom ||
        opacity != oldDelegate.opacity ||
        showDirections != oldDelegate.showDirections;
  }
}

/// Draws the mosaic panel grid: panel outlines, optional numbering, optional
/// sequence path, selection highlight, and a START marker on panel 1.
class FramingMosaicGridPainter extends CustomPainter {
  final FramingMosaicConfig config;
  final List<FramingMosaicPanel> panels;
  final double fovWidth;
  final double fovHeight;
  final double zoom;
  final NightshadeColors colors;
  final bool showPanelNumbers;
  final bool showSequencePath;
  final int selectedPanelIndex;

  FramingMosaicGridPainter({
    required this.config,
    required this.panels,
    required this.fovWidth,
    required this.fovHeight,
    required this.zoom,
    required this.colors,
    required this.showPanelNumbers,
    required this.showSequencePath,
    required this.selectedPanelIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Scale: convert degrees to pixels (60 pixels per degree at zoom 1)
    final scale = 60 * zoom;
    final panelWidth = fovWidth * scale;
    final panelHeight = fovHeight * scale;

    // Calculate step size accounting for overlap
    final overlapFactor = 1 - (config.overlapPercent / 100);
    final stepX = panelWidth * overlapFactor;
    final stepY = panelHeight * overlapFactor;

    // Calculate total mosaic extent
    final totalWidth = panelWidth + (config.columns - 1) * stepX;
    final totalHeight = panelHeight + (config.rows - 1) * stepY;

    // Starting offset (top-left corner of mosaic relative to center)
    final startX = center.dx - totalWidth / 2 + panelWidth / 2;
    final startY = center.dy - totalHeight / 2 + panelHeight / 2;

    // Draw mosaic outline
    final outlinePaint = Paint()
      ..color = colors.warning.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(
      Rect.fromCenter(
        center: center,
        width: totalWidth,
        height: totalHeight,
      ),
      outlinePaint,
    );

    // Draw sequence path if enabled
    if (showSequencePath && panels.length > 1) {
      final pathPaint = Paint()
        ..color = colors.warning.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      final path = Path();
      bool first = true;

      for (final panel in panels) {
        final panelX = startX + panel.column * stepX;
        final panelY = startY + panel.row * stepY;

        if (first) {
          path.moveTo(panelX, panelY);
          first = false;
        } else {
          path.lineTo(panelX, panelY);
        }
      }

      canvas.drawPath(path, pathPaint);
    }

    // Draw individual panels
    for (int i = 0; i < panels.length; i++) {
      final panel = panels[i];
      final panelX = startX + panel.column * stepX;
      final panelY = startY + panel.row * stepY;
      final isSelected = i == selectedPanelIndex;

      // Panel rect
      final panelRect = Rect.fromCenter(
        center: Offset(panelX, panelY),
        width: panelWidth,
        height: panelHeight,
      );

      // Draw panel fill
      final fillPaint = Paint()
        ..color = isSelected
            ? colors.primary.withValues(alpha: 0.2)
            : colors.warning.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill;
      canvas.drawRect(panelRect, fillPaint);

      // Draw panel border
      final borderPaint = Paint()
        ..color = isSelected
            ? colors.primary.withValues(alpha: 0.8)
            : colors.warning.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2 : 1;
      canvas.drawRect(panelRect, borderPaint);

      // Draw panel number
      if (showPanelNumbers) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${panel.index + 1}',
            style: TextStyle(
              color: isSelected ? colors.primary : colors.warning,
              fontSize: 14 * zoom.clamp(0.5, 2.0),
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        textPainter.paint(
          canvas,
          Offset(
            panelX - textPainter.width / 2,
            panelY - textPainter.height / 2,
          ),
        );
      }

      // Draw crosshair on selected panel
      if (isSelected) {
        final crosshairPaint = Paint()
          ..color = colors.primary.withValues(alpha: 0.6)
          ..strokeWidth = 1;

        canvas.drawLine(
          Offset(panelX - 10, panelY),
          Offset(panelX + 10, panelY),
          crosshairPaint,
        );
        canvas.drawLine(
          Offset(panelX, panelY - 10),
          Offset(panelX, panelY + 10),
          crosshairPaint,
        );
      }
    }

    // Draw start indicator
    if (panels.isNotEmpty) {
      final firstPanel = panels.first;
      final startX2 = startX + firstPanel.column * stepX;
      final startY2 = startY + firstPanel.row * stepY;

      final startPaint = Paint()
        ..color = colors.success.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(startX2, startY2),
        6 * zoom.clamp(0.5, 1.5),
        startPaint,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: 'START',
          style: TextStyle(
            color: colors.success,
            fontSize: 8 * zoom.clamp(0.7, 1.3),
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(
          startX2 - textPainter.width / 2,
          startY2 + 10 * zoom.clamp(0.5, 1.5),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant FramingMosaicGridPainter oldDelegate) {
    return config.columns != oldDelegate.config.columns ||
        config.rows != oldDelegate.config.rows ||
        config.overlapPercent != oldDelegate.config.overlapPercent ||
        fovWidth != oldDelegate.fovWidth ||
        fovHeight != oldDelegate.fovHeight ||
        zoom != oldDelegate.zoom ||
        showPanelNumbers != oldDelegate.showPanelNumbers ||
        showSequencePath != oldDelegate.showSequencePath ||
        selectedPanelIndex != oldDelegate.selectedPanelIndex ||
        panels.length != oldDelegate.panels.length;
  }
}
