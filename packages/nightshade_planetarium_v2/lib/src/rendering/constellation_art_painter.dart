import 'package:flutter/material.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

import '../catalogs/constellation_art.dart';
import 'sky_projection.dart';

/// Paints procedural constellation art figures for visible placements.
class ConstellationArtPainter extends CustomPainter {
  ConstellationArtPainter({
    required this.viewPose,
    required this.placements,
  });

  final ViewPoseDto viewPose;
  final List<ConstellationArtPlacementDto> placements;

  static const Color _fillColor = Color(0x33DAA520);
  static const Color _strokeColor = Color(0x28DAA520);

  @override
  void paint(Canvas canvas, Size size) {
    if (placements.isEmpty) {
      return;
    }

    final center = Offset(size.width / 2, size.height / 2);
    final scale = skyProjectionScale(size, viewPose);

    for (final placement in placements) {
      final figure =
          ConstellationArt.findByAbbreviation(placement.abbreviation);
      if (figure == null) {
        continue;
      }

      if (!isOffsetNearCanvas(
        Offset(placement.screenX, placement.screenY),
        size,
      )) {
        continue;
      }

      final path = _buildFigurePath(
        figure: figure,
        viewPose: viewPose,
        center: center,
        scale: scale * placement.scale,
        size: size,
      );
      if (path == null) {
        continue;
      }

      final alpha = placement.opacity.clamp(0, 1);
      final fillPaint = Paint()
        ..color = _fillColor.withValues(alpha: _fillColor.a * alpha)
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = _strokeColor.withValues(alpha: _strokeColor.a * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }
  }

  Path? _buildFigurePath({
    required ConstellationArtData figure,
    required ViewPoseDto viewPose,
    required Offset center,
    required double scale,
    required Size size,
  }) {
    final path = Path();
    var hasVisiblePoint = false;

    for (final segment in figure.segments) {
      switch (segment) {
        case ArtMoveTo(:final point):
          final screenPt = celestialToScreen(
            coord: point,
            viewPose: viewPose,
            center: center,
            scale: scale,
          );
          if (screenPt != null) {
            path.moveTo(screenPt.dx, screenPt.dy);
            if (isOffsetNearCanvas(screenPt, size)) {
              hasVisiblePoint = true;
            }
          }
        case ArtLineTo(:final point):
          final screenPt = celestialToScreen(
            coord: point,
            viewPose: viewPose,
            center: center,
            scale: scale,
          );
          if (screenPt != null) {
            path.lineTo(screenPt.dx, screenPt.dy);
            if (isOffsetNearCanvas(screenPt, size)) {
              hasVisiblePoint = true;
            }
          }
        case ArtQuadTo(:final control, :final point):
          final ctrlPt = celestialToScreen(
            coord: control,
            viewPose: viewPose,
            center: center,
            scale: scale,
          );
          final endPt = celestialToScreen(
            coord: point,
            viewPose: viewPose,
            center: center,
            scale: scale,
          );
          if (ctrlPt != null && endPt != null) {
            path.quadraticBezierTo(
              ctrlPt.dx,
              ctrlPt.dy,
              endPt.dx,
              endPt.dy,
            );
            if (isOffsetNearCanvas(endPt, size)) {
              hasVisiblePoint = true;
            }
          } else if (endPt != null) {
            path.lineTo(endPt.dx, endPt.dy);
            if (isOffsetNearCanvas(endPt, size)) {
              hasVisiblePoint = true;
            }
          }
        case ArtClose():
          path.close();
      }
    }

    return hasVisiblePoint ? path : null;
  }

  @override
  bool shouldRepaint(covariant ConstellationArtPainter oldDelegate) {
    return oldDelegate.viewPose != viewPose ||
        oldDelegate.placements != placements;
  }
}
