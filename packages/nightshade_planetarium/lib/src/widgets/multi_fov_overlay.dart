import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../coordinate_system.dart';
import 'fov_presets.dart';

/// Interactive, multi-rig FOV framing overlay for the planetarium sky view.
///
/// Draws every *visible* preset from [fovPresetsProvider] as a schematic sensor
/// rectangle, sized from each preset's computed angular field of view and
/// rotated to its position angle. The **active** preset is interactive:
///
///  * dragging its body pins it to a fixed RA/Dec and moves it across the sky;
///  * dragging the small handle above it rotates its position angle;
///  * a host-level "snap to target" sets the active preset's center directly.
///
/// The degrees→pixels mapping is identical to the sky painter
/// (`scale = min(w, h) / fieldOfView`) and the legacy single-FOV overlay, so the
/// rectangles stay angularly correct and aligned with the stars as the user
/// zooms, pans and rotates the view.
///
/// Non-active presets are non-interactive; wrap the whole widget in an
/// [IgnorePointer] at the call site if FOV editing should be globally disabled.
class MultiFovOverlay extends ConsumerStatefulWidget {
  /// Current view center right ascension in hours.
  final double centerRaHours;

  /// Current view center declination in degrees.
  final double centerDecDeg;

  /// Current field of view (short screen axis) in degrees.
  final double fieldOfViewDeg;

  /// View rotation in degrees (the sky's roll).
  final double viewRotationDeg;

  const MultiFovOverlay({
    super.key,
    required this.centerRaHours,
    required this.centerDecDeg,
    required this.fieldOfViewDeg,
    required this.viewRotationDeg,
  });

  @override
  ConsumerState<MultiFovOverlay> createState() => _MultiFovOverlayState();
}

class _MultiFovOverlayState extends ConsumerState<MultiFovOverlay> {
  /// Hit-test radius (px) around the rotation handle.
  static const double _handleHitRadius = 16;

  bool _rotating = false;

  double _scale(Size size) =>
      math.min(size.width, size.height) / 2 / (widget.fieldOfViewDeg / 2);

  /// Screen position of a preset's center. Pinned presets project from their
  /// fixed RA/Dec; unpinned presets sit at the view center.
  Offset _centerOffset(FovPreset preset, Size size) {
    final viewCenter = Offset(size.width / 2, size.height / 2);
    final center = preset.center;
    if (center == null) return viewCenter;
    final scale = _scale(size);
    final viewDecRad = widget.centerDecDeg * math.pi / 180;
    final deltaRaDeg =
        (center.ra - widget.centerRaHours) * 15 * math.cos(viewDecRad);
    final deltaDecDeg = center.dec - widget.centerDecDeg;
    return viewCenter + Offset(deltaRaDeg * scale, -deltaDecDeg * scale);
  }

  /// Inverse of [_centerOffset]: convert a screen point to a sky coordinate.
  CelestialCoordinate _coordAt(Offset point, Size size) {
    final viewCenter = Offset(size.width / 2, size.height / 2);
    final scale = _scale(size);
    final viewDecRad = widget.centerDecDeg * math.pi / 180;
    final dx = point.dx - viewCenter.dx;
    final dy = point.dy - viewCenter.dy;
    final deltaDecDeg = -dy / scale;
    // Guard the cos(dec) term so a near-pole view center can't divide by ~0.
    final cosDec = math.cos(viewDecRad).abs();
    final deltaRaDeg = (cosDec < 1e-6) ? 0.0 : (dx / scale) / cosDec;
    var ra = widget.centerRaHours + deltaRaDeg / 15;
    ra %= 24;
    if (ra < 0) ra += 24;
    final dec = (widget.centerDecDeg + deltaDecDeg).clamp(-90.0, 90.0);
    return CelestialCoordinate(ra: ra, dec: dec);
  }

  /// Screen position of the active preset's rotation handle.
  Offset? _handleOffset(FovPreset active, Size size) {
    final fov = active.fovDegrees;
    if (fov == null) return null;
    final scale = _scale(size);
    final halfHeightPx = fov.$2 * scale / 2;
    final angle = (active.positionAngleDeg + widget.viewRotationDeg) *
        math.pi /
        180;
    final center = _centerOffset(active, size);
    // Handle sits "up" along the rotated rectangle's short axis.
    final up = Offset(math.sin(angle), -math.cos(angle));
    return center + up * (halfHeightPx + 18);
  }

  void _onPanStart(DragStartDetails details, Size size) {
    final active = ref.read(fovPresetsProvider).active;
    if (active == null || !active.visible) return;
    final handle = _handleOffset(active, size);
    if (handle != null &&
        (details.localPosition - handle).distance <= _handleHitRadius) {
      _rotating = true;
    } else {
      _rotating = false;
      // Begin a drag: pin the preset to where it currently sits so subsequent
      // deltas move a concrete coordinate rather than the floating view center.
      if (active.center == null) {
        ref
            .read(fovPresetsProvider.notifier)
            .setActiveCenter(_coordAt(_centerOffset(active, size), size));
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final notifier = ref.read(fovPresetsProvider.notifier);
    final active = ref.read(fovPresetsProvider).active;
    if (active == null) return;

    if (_rotating) {
      final center = _centerOffset(active, size);
      final v = details.localPosition - center;
      // Angle of the pointer measured from screen "up", minus the view roll so
      // the stored PA is relative to the sky, not the rotated canvas.
      final screenAngle = math.atan2(v.dx, -v.dy) * 180 / math.pi;
      notifier.setActivePositionAngle(screenAngle - widget.viewRotationDeg);
    } else {
      notifier.setActiveCenter(_coordAt(details.localPosition, size));
    }
  }

  void _onPanEnd(DragEndDetails details) {
    _rotating = false;
  }

  /// Axis-aligned screen bounds of the active preset's rotated rectangle,
  /// expanded to enclose its rotation handle and a small touch margin. This is
  /// the only region that captures gestures, so panning empty sky always falls
  /// through to the sky-pan handler beneath.
  Rect? _activeHitRect(FovPreset active, Size size) {
    final fov = active.fovDegrees;
    if (fov == null) return null;
    final scale = _scale(size);
    final halfW = fov.$1 * scale / 2;
    final halfH = fov.$2 * scale / 2;
    final center = _centerOffset(active, size);
    final angle = (active.positionAngleDeg + widget.viewRotationDeg) *
        math.pi /
        180;
    final cos = math.cos(angle).abs();
    final sin = math.sin(angle).abs();
    // Half-extents of the rotated rectangle's enclosing AABB.
    final aabbHalfW = halfW * cos + halfH * sin;
    final aabbHalfH = halfW * sin + halfH * cos;
    var rect = Rect.fromCenter(
      center: center,
      width: aabbHalfW * 2,
      height: aabbHalfH * 2,
    );
    final handle = _handleOffset(active, size);
    if (handle != null) {
      rect = rect.expandToInclude(
        Rect.fromCircle(center: handle, radius: _handleHitRadius),
      );
    }
    // Touch margin so thin rigs remain grabbable.
    return rect.inflate(8);
  }

  @override
  Widget build(BuildContext context) {
    final presetsState = ref.watch(fovPresetsProvider);
    final visible = presetsState.presets.where((p) => p.visible).toList();
    if (visible.isEmpty) return const SizedBox.expand();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final active = presetsState.active;
        final hitRect = (active != null && active.visible)
            ? _activeHitRect(active, size)
            : null;

        return Stack(
          children: [
            // Non-interactive drawing layer: never intercepts gestures, so
            // sky pan/zoom keeps working over the whole canvas.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  size: size,
                  painter: _MultiFovPainter(
                    presets: visible,
                    activeId: presetsState.activeId,
                    centerRaHours: widget.centerRaHours,
                    centerDecDeg: widget.centerDecDeg,
                    fieldOfViewDeg: widget.fieldOfViewDeg,
                    viewRotationDeg: widget.viewRotationDeg,
                  ),
                ),
              ),
            ),
            // Interactive hit region scoped to the active preset only. Gestures
            // are reported in the full overlay's coordinate space (the region
            // is a sub-rect of it), so the existing projection math is reused
            // unchanged.
            if (hitRect != null)
              Positioned.fromRect(
                rect: hitRect,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => _onPanStart(
                      _shift(d, hitRect.topLeft), size),
                  onPanUpdate: (d) =>
                      _onPanUpdate(_shiftUpdate(d, hitRect.topLeft), size),
                  onPanEnd: _onPanEnd,
                ),
              ),
          ],
        );
      },
    );
  }

  // The hit region is offset from the overlay origin, so translate gesture
  // local positions back into overlay space before projecting.
  DragStartDetails _shift(DragStartDetails d, Offset origin) => DragStartDetails(
        sourceTimeStamp: d.sourceTimeStamp,
        globalPosition: d.globalPosition,
        localPosition: d.localPosition + origin,
        kind: d.kind,
      );

  DragUpdateDetails _shiftUpdate(DragUpdateDetails d, Offset origin) =>
      DragUpdateDetails(
        sourceTimeStamp: d.sourceTimeStamp,
        delta: d.delta,
        primaryDelta: d.primaryDelta,
        globalPosition: d.globalPosition,
        localPosition: d.localPosition + origin,
      );
}

class _MultiFovPainter extends CustomPainter {
  final List<FovPreset> presets;
  final String? activeId;
  final double centerRaHours;
  final double centerDecDeg;
  final double fieldOfViewDeg;
  final double viewRotationDeg;

  _MultiFovPainter({
    required this.presets,
    required this.activeId,
    required this.centerRaHours,
    required this.centerDecDeg,
    required this.fieldOfViewDeg,
    required this.viewRotationDeg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fieldOfViewDeg <= 0) return;
    final scale = math.min(size.width, size.height) / 2 / (fieldOfViewDeg / 2);
    final viewCenter = Offset(size.width / 2, size.height / 2);
    final viewDecRad = centerDecDeg * math.pi / 180;

    for (final preset in presets) {
      final fov = preset.fovDegrees;
      if (fov == null) continue;

      // Project the preset center.
      Offset center = viewCenter;
      final pc = preset.center;
      if (pc != null) {
        final deltaRaDeg =
            (pc.ra - centerRaHours) * 15 * math.cos(viewDecRad);
        final deltaDecDeg = pc.dec - centerDecDeg;
        center = viewCenter + Offset(deltaRaDeg * scale, -deltaDecDeg * scale);
      }

      final isActive = preset.id == activeId;
      _drawPreset(canvas, center, scale, fov, preset, isActive);
    }
  }

  void _drawPreset(
    Canvas canvas,
    Offset center,
    double scale,
    (double, double) fov,
    FovPreset preset,
    bool isActive,
  ) {
    final widthPx = fov.$1 * scale;
    final heightPx = fov.$2 * scale;
    final angle =
        (preset.positionAngleDeg + viewRotationDeg) * math.pi / 180;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: widthPx,
      height: heightPx,
    );

    final color = preset.color;

    // Faint fill so overlapping rigs read as distinct framing footprints.
    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withValues(alpha: isActive ? 0.10 : 0.05)
        ..style = PaintingStyle.fill,
    );

    // Schematic border: dimmer for inactive presets so the active one reads.
    final border = Paint()
      ..color = color.withValues(alpha: isActive ? 0.95 : 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isActive ? 1.6 : 1.1;
    canvas.drawRect(rect, border);

    // Corner brackets emphasise the sensor framing.
    _drawCornerBrackets(canvas, rect, border);

    // Center tick.
    final tick = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(-6, 0), const Offset(6, 0), tick);
    canvas.drawLine(const Offset(0, -6), const Offset(0, 6), tick);

    // Rotation handle (active only): a stem + dot at the top short edge.
    if (isActive) {
      final handlePaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final stem = Paint()
        ..color = color.withValues(alpha: 0.8)
        ..strokeWidth = 1.2;
      final handleY = -heightPx / 2 - 18;
      canvas.drawLine(Offset(0, -heightPx / 2), Offset(0, handleY + 5), stem);
      canvas.drawCircle(Offset(0, handleY), 5, handlePaint);
    }

    canvas.restore();

    // Labels are drawn un-rotated, below the (unrotated) center, so they stay
    // legible regardless of position angle.
    final label = preset.name;
    final fovText =
        '${fov.$1.toStringAsFixed(2)}° × ${fov.$2.toStringAsFixed(2)}°';
    final scaleText = preset.imageScaleArcsecPerPx != null
        ? '${preset.imageScaleArcsecPerPx!.toStringAsFixed(2)}"/px'
        : null;

    final maxHalf = math.max(widthPx, heightPx) / 2;
    _drawLabel(
      canvas,
      center + Offset(0, maxHalf + 14),
      label,
      preset.color,
      bold: isActive,
    );
    _drawLabel(
      canvas,
      center + Offset(0, maxHalf + 28),
      scaleText == null ? fovText : '$fovText  ·  $scaleText',
      preset.color.withValues(alpha: 0.75),
      fontSize: 9,
    );
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, Paint paint) {
    final len = math.min(rect.width, rect.height) * 0.14;
    if (len <= 0) return;
    // Top-left
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(len, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, len), paint);
    // Top-right
    canvas.drawLine(rect.topRight, rect.topRight + Offset(-len, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight + Offset(0, len), paint);
    // Bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(-len, 0), paint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(0, -len), paint);
    // Bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(len, 0), paint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(0, -len), paint);
  }

  void _drawLabel(
    Canvas canvas,
    Offset position,
    String text,
    Color color, {
    double fontSize = 10,
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(
      canvas,
      position - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _MultiFovPainter old) {
    return old.presets != presets ||
        old.activeId != activeId ||
        old.centerRaHours != centerRaHours ||
        old.centerDecDeg != centerDecDeg ||
        old.fieldOfViewDeg != fieldOfViewDeg ||
        old.viewRotationDeg != viewRotationDeg;
  }
}
