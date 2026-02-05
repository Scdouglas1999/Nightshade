import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../utils/preview_transform.dart';

/// Enhanced annotation overlay with fade effects, click-to-identify, hover tooltips, and customizable styles
class AnnotationOverlay extends ConsumerStatefulWidget {
  final ImageAnnotation? annotation;
  final double zoomLevel;
  final Offset imageOffset;
  final Size imageSize;
  final void Function(CelestialObjectAnnotation object)? onObjectTapped;
  final void Function(double x, double y)? onIdentifyAt;
  /// Called when the mouse hovers over a celestial object
  final void Function(CelestialObjectAnnotation object, Offset screenPosition)? onObjectHovered;
  /// Called when the mouse moves away from all objects
  final VoidCallback? onObjectUnhovered;

  const AnnotationOverlay({
    super.key,
    required this.annotation,
    this.zoomLevel = 1.0,
    this.imageOffset = Offset.zero,
    required this.imageSize,
    this.onObjectTapped,
    this.onIdentifyAt,
    this.onObjectHovered,
    this.onObjectUnhovered,
  });

  @override
  ConsumerState<AnnotationOverlay> createState() => _AnnotationOverlayState();
}

class _AnnotationOverlayState extends ConsumerState<AnnotationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _isHovering = false;

  // Hover detection state
  CelestialObjectAnnotation? _currentHoveredObject;
  Timer? _hoverDebounceTimer;
  static const _hoverDebounceMs = 75; // Delay before showing tooltip

  Animation<double> _createFadeAnimation(AnnotationSettings settings) {
    return Tween<double>(
      begin: settings.idleOpacity,
      end: settings.hoverOpacity,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void initState() {
    super.initState();
    final settings = ref.read(annotationSettingsProvider).valueOrNull ??
        const AnnotationSettings();
    _fadeController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: settings.fadeAnimationMs),
    );
    _fadeAnimation = _createFadeAnimation(settings);
  }

  @override
  void dispose() {
    _hoverDebounceTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  void _clearHoverState() {
    _hoverDebounceTimer?.cancel();
    if (_currentHoveredObject != null) {
      _currentHoveredObject = null;
      widget.onObjectUnhovered?.call();
    }
  }

  void _onHoverMove(PointerEvent event) {
    final settings = ref.read(annotationSettingsProvider).valueOrNull ??
        const AnnotationSettings();
    if (!settings.enabled || widget.annotation == null) return;

    final localPosition = event.localPosition;

    // Convert screen position to image coordinates
    final imagePoint = viewportToImage(
      viewportPoint: localPosition,
      imageOffset: widget.imageOffset,
      zoomLevel: widget.zoomLevel,
    );

    // Find the object under the cursor (if any)
    CelestialObjectAnnotation? foundObject;
    for (final object in widget.annotation!.objects) {
      // Skip objects that wouldn't be visible based on settings
      if (!object.visible) continue;
      if (object.magnitude != null) {
        if (object.magnitude! > settings.magnitudeCutoff) continue;
        if (object.magnitude! < settings.minMagnitude) continue;
      }
      if (!_isTypeVisibleForHover(object.type, settings.visibleTypes)) continue;

      final dx = object.x - imagePoint.dx;
      final dy = object.y - imagePoint.dy;
      final distance = (dx * dx + dy * dy);
      final hitRadius = (object.size ?? 30) * 1.5;

      if (distance < hitRadius * hitRadius) {
        foundObject = object;
        break;
      }
    }

    // Only update if the hovered object changed
    if (foundObject?.name != _currentHoveredObject?.name) {
      _hoverDebounceTimer?.cancel();

      if (foundObject != null) {
        // Debounce showing the tooltip to avoid flickering
        final objectToShow = foundObject;
        _hoverDebounceTimer = Timer(const Duration(milliseconds: _hoverDebounceMs), () {
          if (!mounted) return;
          _currentHoveredObject = objectToShow;

          // Calculate screen position for the tooltip
          final screenPosition = imageToViewport(
            imagePoint: Offset(objectToShow.x, objectToShow.y),
            imageOffset: widget.imageOffset,
            zoomLevel: widget.zoomLevel,
          );

          widget.onObjectHovered?.call(objectToShow, screenPosition);
        });
      } else {
        // Immediately clear when moving away from objects (no debounce needed)
        _currentHoveredObject = null;
        widget.onObjectUnhovered?.call();
      }
    }
  }

  bool _isTypeVisibleForHover(ObjectType type, Set<AnnotationObjectFilter> filters) {
    switch (type) {
      case ObjectType.galaxy:
        return filters.contains(AnnotationObjectFilter.galaxies);
      case ObjectType.nebula:
        return filters.contains(AnnotationObjectFilter.nebulae);
      case ObjectType.planetaryNebula:
        return filters.contains(AnnotationObjectFilter.planetaryNebulae);
      case ObjectType.starCluster:
        return filters.contains(AnnotationObjectFilter.starClusters);
      case ObjectType.star:
      case ObjectType.doubleStar:
        return filters.contains(AnnotationObjectFilter.stars);
      default:
        return filters.contains(AnnotationObjectFilter.other);
    }
  }

  void _onHoverChanged(bool hovering) {
    if (_isHovering == hovering) return;
    _isHovering = hovering;
    ref.read(annotationHoverStateProvider.notifier).state = hovering;

    final settings = ref.read(annotationSettingsProvider).valueOrNull ??
        const AnnotationSettings();
    if (!settings.fadeWhenNotHovering) return;

    if (hovering) {
      _fadeController.forward();
    } else {
      _fadeController.reverse();
      // When mouse leaves the overlay entirely, clear hover state
      _clearHoverState();
    }
  }

  void _onTapUp(TapUpDetails details) {
    final settings = ref.read(annotationSettingsProvider).valueOrNull ??
        const AnnotationSettings();
    if (!settings.clickToIdentify) return;

    final localPosition = details.localPosition;

    // Convert screen position to image coordinates
    final imagePoint = viewportToImage(
      viewportPoint: localPosition,
      imageOffset: widget.imageOffset,
      zoomLevel: widget.zoomLevel,
    );

    // Check if tapped on an existing object
    if (widget.annotation != null) {
      for (final object in widget.annotation!.objects) {
        final dx = object.x - imagePoint.dx;
        final dy = object.y - imagePoint.dy;
        final distance = (dx * dx + dy * dy);
        final hitRadius = (object.size ?? 30) * 1.5;

        if (distance < hitRadius * hitRadius) {
          widget.onObjectTapped?.call(object);
          return;
        }
      }
    }

    // No object hit, trigger identify at position
    widget.onIdentifyAt?.call(imagePoint.dx, imagePoint.dy);
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(annotationSettingsProvider);
    final markerStyleAsync = ref.watch(annotationMarkerStyleProvider);

    final settings =
        settingsAsync.valueOrNull ?? const AnnotationSettings();
    final markerStyle =
        markerStyleAsync.valueOrNull ?? const AnnotationMarkerStyle();

    _fadeController.duration = Duration(milliseconds: settings.fadeAnimationMs);
    _fadeAnimation = _createFadeAnimation(settings);

    if (!settings.enabled || widget.annotation == null) {
      return const SizedBox.shrink();
    }

    return MouseRegion(
      onEnter: (_) => _onHoverChanged(true),
      onExit: (_) => _onHoverChanged(false),
      onHover: _onHoverMove,
      child: GestureDetector(
        onTapUp: _onTapUp,
        behavior: HitTestBehavior.translucent,
        child: AnimatedBuilder(
          animation: _fadeAnimation,
          builder: (context, child) {
            final opacity = settings.fadeWhenNotHovering
                ? _fadeAnimation.value
                : settings.hoverOpacity;

            return Opacity(
              opacity: opacity,
              child: CustomPaint(
                painter: EnhancedAnnotationPainter(
                  annotation: widget.annotation!,
                  settings: settings,
                  markerStyle: markerStyle,
                  zoomLevel: widget.zoomLevel,
                  imageOffset: widget.imageOffset,
                ),
                size: Size.infinite,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Enhanced painter that uses customizable marker styles
class EnhancedAnnotationPainter extends CustomPainter {
  final ImageAnnotation annotation;
  final AnnotationSettings settings;
  final AnnotationMarkerStyle markerStyle;
  final double zoomLevel;
  final Offset imageOffset;

  EnhancedAnnotationPainter({
    required this.annotation,
    required this.settings,
    required this.markerStyle,
    this.zoomLevel = 1.0,
    this.imageOffset = Offset.zero,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!annotation.visible) return;

    // Filter and sort objects
    final visibleObjects = annotation.objects.where((obj) {
      if (!obj.visible) return false;
      if (obj.magnitude != null) {
        if (obj.magnitude! > settings.magnitudeCutoff) return false;
        if (obj.magnitude! < settings.minMagnitude) return false;
      }
      return _isTypeVisible(obj.type, settings.visibleTypes);
    }).toList();

    // Limit displayed objects
    if (visibleObjects.length > settings.maxObjectsToDisplay) {
      visibleObjects.sort((a, b) => (a.magnitude ?? 20).compareTo(b.magnitude ?? 20));
      visibleObjects.removeRange(settings.maxObjectsToDisplay, visibleObjects.length);
    }

    for (final object in visibleObjects) {
      final screenPosition = imageToViewport(
        imagePoint: Offset(object.x, object.y),
        imageOffset: imageOffset,
        zoomLevel: zoomLevel,
      );

      _drawObjectMarker(canvas, object, screenPosition.dx, screenPosition.dy);

      if (settings.showLabels) {
        _drawObjectLabel(canvas, object, screenPosition.dx, screenPosition.dy);
      }
    }
  }

  bool _isTypeVisible(ObjectType type, Set<AnnotationObjectFilter> filters) {
    switch (type) {
      case ObjectType.galaxy:
        return filters.contains(AnnotationObjectFilter.galaxies);
      case ObjectType.nebula:
        return filters.contains(AnnotationObjectFilter.nebulae);
      case ObjectType.planetaryNebula:
        return filters.contains(AnnotationObjectFilter.planetaryNebulae);
      case ObjectType.starCluster:
        return filters.contains(AnnotationObjectFilter.starClusters);
      case ObjectType.star:
      case ObjectType.doubleStar:
        return filters.contains(AnnotationObjectFilter.stars);
      default:
        return filters.contains(AnnotationObjectFilter.other);
    }
  }

  Color _getColorForType(ObjectType type) {
    switch (type) {
      case ObjectType.galaxy:
        return Color(markerStyle.galaxyColor);
      case ObjectType.nebula:
        return Color(markerStyle.nebulaColor);
      case ObjectType.planetaryNebula:
        return Color(markerStyle.planetaryNebulaColor);
      case ObjectType.starCluster:
        return Color(markerStyle.clusterColor);
      case ObjectType.star:
      case ObjectType.doubleStar:
        return Color(markerStyle.starColor);
      default:
        return Color(markerStyle.otherColor);
    }
  }

  double _getMarkerSize(CelestialObjectAnnotation object) {
    if (!markerStyle.scaleBySize || object.size == null) {
      return markerStyle.minMarkerSize;
    }

    // Scale based on object size (in arcminutes typically)
    final scaled = (object.size! * 2.0).clamp(
      markerStyle.minMarkerSize,
      markerStyle.maxMarkerSize,
    );
    return scaled * zoomLevel;
  }

  void _drawObjectMarker(Canvas canvas, CelestialObjectAnnotation object, double x, double y) {
    final color = _getColorForType(object.type);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = markerStyle.strokeWidth
      ..color = color.withValues(alpha: 0.85);

    final markerSize = _getMarkerSize(object);

    switch (object.type) {
      case ObjectType.galaxy:
        // Draw elegant ellipse for galaxies
        _drawGalaxyMarker(canvas, x, y, markerSize, paint);
        break;

      case ObjectType.nebula:
        // Draw cloud-like shape for nebulae
        _drawNebulaMarker(canvas, x, y, markerSize, paint);
        break;

      case ObjectType.planetaryNebula:
        // Draw double circle for planetary nebulae
        _drawPlanetaryNebulaMarker(canvas, x, y, markerSize, paint);
        break;

      case ObjectType.starCluster:
        // Draw open circle with dots for clusters
        _drawClusterMarker(canvas, x, y, markerSize, paint);
        break;

      case ObjectType.star:
      case ObjectType.doubleStar:
        // Draw crosshair for stars
        _drawStarMarker(canvas, x, y, markerSize, paint);
        break;

      default:
        // Draw simple circle for unknown types
        canvas.drawCircle(Offset(x, y), markerSize / 2, paint);
    }
  }

  void _drawGalaxyMarker(Canvas canvas, double x, double y, double size, Paint paint) {
    // Draw tilted ellipse to represent galaxy shape
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(0.3); // Slight tilt

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: size,
        height: size * 0.5,
      ),
      paint,
    );

    // Draw inner ellipse for spiral arm suggestion
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = markerStyle.strokeWidth * 0.7
      ..color = paint.color.withValues(alpha: 0.4);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: size * 0.6,
        height: size * 0.3,
      ),
      innerPaint,
    );

    canvas.restore();
  }

  void _drawNebulaMarker(Canvas canvas, double x, double y, double size, Paint paint) {
    // Draw rounded rectangle for nebula shape
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, y), width: size, height: size * 0.8),
        Radius.circular(size * 0.25),
      ),
      paint,
    );
  }

  void _drawPlanetaryNebulaMarker(Canvas canvas, double x, double y, double size, Paint paint) {
    // Outer circle
    canvas.drawCircle(Offset(x, y), size / 2, paint);

    // Inner circle (smaller)
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = markerStyle.strokeWidth
      ..color = paint.color.withValues(alpha: 0.6);
    canvas.drawCircle(Offset(x, y), size / 4, innerPaint);

    // Center dot
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = paint.color.withValues(alpha: 0.8);
    canvas.drawCircle(Offset(x, y), markerStyle.strokeWidth, dotPaint);
  }

  void _drawClusterMarker(Canvas canvas, double x, double y, double size, Paint paint) {
    // Dashed circle outline
    canvas.drawCircle(Offset(x, y), size / 2, paint);

    // Small dots to represent stars in cluster
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = paint.color.withValues(alpha: 0.5);

    final dotRadius = markerStyle.strokeWidth * 0.8;
    canvas.drawCircle(Offset(x - size * 0.15, y - size * 0.1), dotRadius, dotPaint);
    canvas.drawCircle(Offset(x + size * 0.1, y - size * 0.15), dotRadius, dotPaint);
    canvas.drawCircle(Offset(x + size * 0.12, y + size * 0.1), dotRadius, dotPaint);
    canvas.drawCircle(Offset(x - size * 0.08, y + size * 0.12), dotRadius, dotPaint);
    canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
  }

  void _drawStarMarker(Canvas canvas, double x, double y, double size, Paint paint) {
    // Draw four-pointed star crosshair
    final halfSize = size / 2;

    canvas.drawLine(
      Offset(x - halfSize, y),
      Offset(x + halfSize, y),
      paint,
    );
    canvas.drawLine(
      Offset(x, y - halfSize),
      Offset(x, y + halfSize),
      paint,
    );
  }

  void _drawObjectLabel(Canvas canvas, CelestialObjectAnnotation object, double x, double y) {
    final label = settings.showMagnitudes && object.magnitude != null
        ? '${object.name} (${object.magnitude!.toStringAsFixed(1)})'
        : object.name;

    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.95),
        fontSize: markerStyle.labelFontSize,
        fontWeight: FontWeight.w500,
        shadows: const [
          Shadow(
            blurRadius: 3,
            color: Colors.black,
            offset: Offset(1, 1),
          ),
          Shadow(
            blurRadius: 6,
            color: Colors.black,
            offset: Offset(0, 0),
          ),
        ],
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Position label below marker
    final markerSize = _getMarkerSize(object);
    final offset = Offset(
      x - textPainter.width / 2,
      y + markerSize / 2 + 4,
    );

    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant EnhancedAnnotationPainter oldDelegate) {
    return oldDelegate.annotation != annotation ||
        oldDelegate.settings != settings ||
        oldDelegate.markerStyle != markerStyle ||
        oldDelegate.zoomLevel != zoomLevel ||
        oldDelegate.imageOffset != imageOffset;
  }
}

/// Compact object info tooltip widget
class ObjectInfoTooltip extends StatelessWidget {
  final CelestialObjectAnnotation object;
  final VoidCallback? onClose;
  final VoidCallback? onMoreInfo;

  const ObjectInfoTooltip({
    super.key,
    required this.object,
    this.onClose,
    this.onMoreInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2D2D44)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ObjectTypeIcon(type: object.type),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  object.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onClose != null)
                GestureDetector(
                  onTap: onClose,
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _InfoRow(label: 'Type', value: _getTypeName(object.type)),
          if (object.magnitude != null)
            _InfoRow(label: 'Magnitude', value: object.magnitude!.toStringAsFixed(2)),
          if (object.size != null)
            _InfoRow(label: 'Size', value: '${object.size!.toStringAsFixed(1)}\''),
          _InfoRow(
            label: 'RA',
            value: _formatRA(object.ra),
          ),
          _InfoRow(
            label: 'Dec',
            value: _formatDec(object.dec),
          ),
          if (onMoreInfo != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                onPressed: onMoreInfo,
                label: 'More Info',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getTypeName(ObjectType type) {
    switch (type) {
      case ObjectType.galaxy:
        return 'Galaxy';
      case ObjectType.nebula:
        return 'Nebula';
      case ObjectType.planetaryNebula:
        return 'Planetary Nebula';
      case ObjectType.starCluster:
        return 'Star Cluster';
      case ObjectType.star:
        return 'Star';
      case ObjectType.doubleStar:
        return 'Double Star';
      default:
        return 'Unknown';
    }
  }

  String _formatRA(double ra) {
    final hours = ra ~/ 15;
    final mins = ((ra / 15 - hours) * 60).toInt();
    final secs = (((ra / 15 - hours) * 60 - mins) * 60);
    return '${hours}h ${mins}m ${secs.toStringAsFixed(1)}s';
  }

  String _formatDec(double dec) {
    final sign = dec >= 0 ? '+' : '-';
    final absDec = dec.abs();
    final degs = absDec.toInt();
    final mins = ((absDec - degs) * 60).toInt();
    final secs = (((absDec - degs) * 60 - mins) * 60);
    return '$sign$degs° $mins\' ${secs.toStringAsFixed(1)}"';
  }
}

class _ObjectTypeIcon extends StatelessWidget {
  final ObjectType type;

  const _ObjectTypeIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (type) {
      case ObjectType.galaxy:
        icon = Icons.blur_circular;
        color = const Color(0xFFFFD700);
        break;
      case ObjectType.nebula:
        icon = Icons.cloud;
        color = const Color(0xFFFF00FF);
        break;
      case ObjectType.planetaryNebula:
        icon = Icons.radio_button_unchecked;
        color = const Color(0xFF9400D3);
        break;
      case ObjectType.starCluster:
        icon = Icons.scatter_plot;
        color = const Color(0xFF00FFFF);
        break;
      case ObjectType.star:
      case ObjectType.doubleStar:
        icon = Icons.star;
        color = const Color(0xFFFFFFFF);
        break;
      default:
        icon = Icons.help_outline;
        color = const Color(0xFF00FF00);
    }

    return Icon(icon, color: color, size: 20);
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
