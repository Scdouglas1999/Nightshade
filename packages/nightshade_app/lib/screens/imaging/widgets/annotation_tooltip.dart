import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../../../utils/preview_transform.dart';
import '../../../widgets/annotation_overlay.dart';
import '../imaging_science_state.dart';
import 'annotation_panel.dart';

/// Wrapper widget for annotation overlay with object info popup
class AnnotationOverlayWrapper extends ConsumerStatefulWidget {
  final double zoomLevel;
  final Offset imageOffset;
  final Size imageSize;
  final NightshadeColors colors;

  /// Called when the user selects an object from the sidebar panel that is
  /// off-screen. The callback receives the image-space coordinate so the parent
  /// can pan to center it.
  final void Function(Offset imagePoint)? onPanToObject;

  const AnnotationOverlayWrapper({
    super.key,
    required this.zoomLevel,
    required this.imageOffset,
    required this.imageSize,
    required this.colors,
    this.onPanToObject,
  });

  @override
  ConsumerState<AnnotationOverlayWrapper> createState() =>
      _AnnotationOverlayWrapperState();
}

class _AnnotationOverlayWrapperState
    extends ConsumerState<AnnotationOverlayWrapper> {
  CelestialObjectAnnotation? _selectedObject;
  Offset? _tooltipPosition;
  bool _isHoverTooltip = false; // Tracks if tooltip is from hover
  static const double _tooltipWidth = 300;
  static const double _tooltipHeight = 220;
  static const double _tooltipMargin = 12;
  static const double _objectsPanelWidth = 280;

  Offset _computeTooltipPosition(Offset anchor, {bool preferRight = true}) {
    final screenSize = MediaQuery.of(context).size;
    final isPanelVisible = ref.read(annotationPanelVisibleProvider);
    final reservedRight = isPanelVisible ? _objectsPanelWidth : 0.0;
    final availableRight =
        (screenSize.width - reservedRight).clamp(0.0, screenSize.width);

    final preferX =
        preferRight ? anchor.dx + 20 : anchor.dx - _tooltipWidth - 20;
    final fallbackX =
        preferRight ? anchor.dx - _tooltipWidth - 20 : anchor.dx + 20;
    final x = (preferX + _tooltipWidth + _tooltipMargin <= availableRight)
        ? preferX
        : fallbackX;

    final preferredY = anchor.dy - (_tooltipHeight / 2);
    final y = preferredY.clamp(
      _tooltipMargin,
      screenSize.height - _tooltipHeight - _tooltipMargin,
    );
    final maxX = math.max(
      _tooltipMargin,
      availableRight - _tooltipWidth - _tooltipMargin,
    );

    return Offset(
      x.clamp(_tooltipMargin, maxX),
      y,
    );
  }

  void _onObjectTapped(CelestialObjectAnnotation object) {
    ref.read(selectedAnnotationObjectProvider.notifier).state = object;
    final screenPosition = imageToViewport(
      imagePoint: Offset(object.x, object.y),
      imageOffset: widget.imageOffset,
      zoomLevel: widget.zoomLevel,
    );

    setState(() {
      _selectedObject = object;
      _isHoverTooltip = false; // This is a click, not hover
      _tooltipPosition =
          _computeTooltipPosition(screenPosition, preferRight: true);
    });
  }

  void _onObjectHovered(
      CelestialObjectAnnotation object, Offset screenPosition) {
    ref.read(selectedAnnotationObjectProvider.notifier).state = object;
    // Don't override a click-selected tooltip with hover
    if (_selectedObject != null && !_isHoverTooltip) return;

    setState(() {
      _selectedObject = object;
      _isHoverTooltip = true;
      _tooltipPosition =
          _computeTooltipPosition(screenPosition, preferRight: true);
    });
  }

  void _onObjectUnhovered() {
    // Only clear if this was a hover tooltip, not a click
    if (!_isHoverTooltip) return;

    ref.read(selectedAnnotationObjectProvider.notifier).state = null;
    setState(() {
      _selectedObject = null;
      _tooltipPosition = null;
      _isHoverTooltip = false;
    });
  }

  void _onIdentifyAt(double x, double y) async {
    // Use annotation service to identify object at position
    final annotationService = ref.read(annotationServiceProvider);
    final annotation = ref.read(currentAnnotationProvider);
    final settings = ref.read(annotationSettingsProvider).valueOrNull ??
        const AnnotationSettings();

    if (annotation?.plateSolve == null) return;

    final result = await annotationService.identifyAtPixel(
      plateSolve: annotation!.plateSolve,
      x: x,
      y: y,
      searchRadiusArcsec: settings.clickSearchRadiusArcsec,
    );

    if (result != null && mounted) {
      final screenPosition = imageToViewport(
        imagePoint: Offset(x, y),
        imageOffset: widget.imageOffset,
        zoomLevel: widget.zoomLevel,
      );

      setState(() {
        _selectedObject = result;
        _isHoverTooltip = false;
        _tooltipPosition =
            _computeTooltipPosition(screenPosition, preferRight: true);
      });
    }
  }

  void _closeTooltip() {
    ref.read(selectedAnnotationObjectProvider.notifier).state = null;
    setState(() {
      _selectedObject = null;
      _tooltipPosition = null;
      _isHoverTooltip = false;
    });
  }

  void _showMoreInfo() {
    if (_selectedObject == null) return;
    final obj = _selectedObject!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(obj.commonName ?? obj.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (obj.commonName != null) ...[
                Text('Common Name: ${obj.commonName}',
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
              ],
              Text('Type: ${obj.type.toString().split('.').last}',
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Text('RA: ${obj.ra.toStringAsFixed(6)}°',
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Text('Dec: ${obj.dec.toStringAsFixed(6)}°',
                  style: const TextStyle(fontSize: 14)),
              if (obj.magnitude != null) ...[
                const SizedBox(height: 8),
                Text('Magnitude: ${obj.magnitude!.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 14)),
              ],
              if (obj.size != null) ...[
                const SizedBox(height: 8),
                Text('Size: ${obj.size!.toStringAsFixed(2)}\'',
                    style: const TextStyle(fontSize: 14)),
              ],
            ],
          ),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Close',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
        ],
      ),
    );

    _closeTooltip();
  }

  void _onObjectSelectedFromPanel(CelestialObjectAnnotation object) {
    ref.read(selectedAnnotationObjectProvider.notifier).state = object;

    // Trigger pulse animation on the marker
    ref.read(annotationPulseObjectProvider.notifier).state = object.id;

    final imagePoint = Offset(object.x, object.y);
    final screenPosition = imageToViewport(
      imagePoint: imagePoint,
      imageOffset: widget.imageOffset,
      zoomLevel: widget.zoomLevel,
    );

    // If the marker is off-screen, auto-pan to center it first
    final screenSize = MediaQuery.of(context).size;
    final isOffScreen = screenPosition.dx < 0 ||
        screenPosition.dy < 0 ||
        screenPosition.dx > screenSize.width ||
        screenPosition.dy > screenSize.height;

    if (isOffScreen && widget.onPanToObject != null) {
      widget.onPanToObject!(imagePoint);
      // After panning, recalculate the screen position. The next frame will
      // have the updated offset so the tooltip will appear at the right place.
      // We still set the tooltip at the computed position — it will be corrected
      // on the next build when the pan settles.
    }

    setState(() {
      _selectedObject = object;
      _isHoverTooltip = false;
      _tooltipPosition =
          _computeTooltipPosition(screenPosition, preferRight: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final annotation = ref.watch(currentAnnotationProvider);
    final isPanelVisible = ref.watch(annotationPanelVisibleProvider);

    return Stack(
      children: [
        AnnotationOverlay(
          annotation: annotation,
          zoomLevel: widget.zoomLevel,
          imageOffset: widget.imageOffset,
          imageSize: widget.imageSize,
          onObjectTapped: _onObjectTapped,
          onIdentifyAt: _onIdentifyAt,
          onObjectHovered: _onObjectHovered,
          onObjectUnhovered: _onObjectUnhovered,
        ),
        // Object info tooltip
        if (_selectedObject != null && _tooltipPosition != null)
          Positioned(
            left: _tooltipPosition!.dx,
            top: _tooltipPosition!.dy,
            child: ObjectInfoTooltip(
              object: _selectedObject!,
              onClose: _closeTooltip,
              onMoreInfo: _isHoverTooltip ? null : _showMoreInfo,
            ),
          ),
        // Objects sidebar panel
        if (isPanelVisible)
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            child: AnnotationObjectsPanel(
              colors: widget.colors,
              onObjectSelected: _onObjectSelectedFromPanel,
              selectedObjectId: _selectedObject?.id,
            ),
          ),
      ],
    );
  }
}
