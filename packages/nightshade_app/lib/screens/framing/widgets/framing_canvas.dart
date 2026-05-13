import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart'
    hide TargetSearchState, targetSearchProvider;

import '../../../widgets/tutorial_keys/framing_keys.dart';
import '../painters/framing_background_painters.dart';
import '../painters/framing_painters.dart';
import 'framing_overlays.dart';

/// The main framing canvas: handles pan / rotate gestures, stacks the survey
/// image (or starfield fallback), optional grid, equipment FOV overlays, the
/// mosaic grid, and the on-canvas controls (top chips, zoom, scale, target
/// info, error banner).
class FramingCanvas extends StatefulWidget {
  final NightshadeColors colors;
  final FramingState framingState;
  final FramingEquipmentResult? equipmentResult;
  final void Function(double dx, double dy) onPan;
  final void Function(double angle) onRotate;

  const FramingCanvas({
    super.key,
    required this.colors,
    required this.framingState,
    required this.equipmentResult,
    required this.onPan,
    required this.onRotate,
  });

  @override
  State<FramingCanvas> createState() => _FramingCanvasState();
}

class _FramingCanvasState extends State<FramingCanvas> {
  bool _isDragging = false;
  bool _isRotating = false;
  Offset _lastPosition = Offset.zero;

  FramingEquipment? get _equipment => widget.equipmentResult?.equipment;
  bool get _hasEquipment => widget.equipmentResult?.isReady ?? false;

  /// Whether to show the equipment FOV overlay (preview FOV > equipment FOV)
  bool get _showEquipmentOverlay {
    if (!_hasEquipment || _equipment == null) return false;
    return widget.framingState.previewFovDegrees > _equipment!.fovWidthDeg &&
        widget.framingState.showEquipmentFovOverlay;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        _lastPosition = details.localPosition;
        final center = Offset(
          MediaQuery.of(context).size.width / 2,
          MediaQuery.of(context).size.height / 2,
        );
        final distance = (details.localPosition - center).distance;

        // If clicking near the rotation handle, rotate instead of pan
        if (_hasEquipment && _equipment != null) {
          final fovHeight =
              _equipment!.fovHeightDeg * 60 * widget.framingState.zoom;
          if (distance > fovHeight / 2 + 10 && distance < fovHeight / 2 + 40) {
            _isRotating = true;
          } else {
            _isDragging = true;
          }
        } else {
          _isDragging = true;
        }
      },
      onPanUpdate: (details) {
        if (_isRotating) {
          final center = Offset(
            MediaQuery.of(context).size.width / 2,
            MediaQuery.of(context).size.height / 2,
          );
          final angle = math.atan2(
            details.localPosition.dx - center.dx,
            -(details.localPosition.dy - center.dy),
          );
          widget.onRotate(angle * 180 / math.pi);
        } else if (_isDragging) {
          final delta = details.localPosition - _lastPosition;
          widget.onPan(delta.dx, delta.dy);
          _lastPosition = details.localPosition;
        }
      },
      onPanEnd: (_) {
        _isDragging = false;
        _isRotating = false;
      },
      child: Container(
        color: const Color(0xFF0A0A12),
        child: Stack(
          children: [
            // Survey image background
            if (widget.framingState.surveyImage != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: FramingSurveyImagePainter(
                    image: widget.framingState.surveyImage!,
                    zoom: widget.framingState.zoom,
                    panX: widget.framingState.panX,
                    panY: widget.framingState.panY,
                  ),
                ),
              )
            else if (widget.framingState.isLoadingImage)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: widget.colors.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Loading sky survey...',
                      style: TextStyle(color: widget.colors.textMuted),
                    ),
                  ],
                ),
              )
            else
              // Static star field backdrop
              CustomPaint(
                painter: FramingStarBackgroundPainter(colors: widget.colors),
                size: Size.infinite,
              ),

            // Grid overlay
            if (widget.framingState.showGrid)
              CustomPaint(
                painter: FramingGridPainter(
                  zoom: widget.framingState.zoom,
                  panX: widget.framingState.panX,
                  panY: widget.framingState.panY,
                  color: widget.colors.primary.withValues(alpha: 0.2),
                ),
                size: Size.infinite,
              ),

            // Equipment FOV overlay - Show when preview FOV > equipment FOV
            if (_showEquipmentOverlay && _equipment != null)
              Center(
                child: Transform.translate(
                  offset: Offset(
                      widget.framingState.panX, widget.framingState.panY),
                  child: Transform.rotate(
                    angle: widget.framingState.rotation * math.pi / 180,
                    child: CustomPaint(
                      painter: FramingEquipmentFOVOverlayPainter(
                        fovWidth: _equipment!.fovWidthDeg,
                        fovHeight: _equipment!.fovHeightDeg,
                        previewFov: widget.framingState.previewFovDegrees,
                        zoom: widget.framingState.zoom,
                        colors: widget.colors,
                        opacity: widget.framingState.equipmentFovOverlayOpacity,
                        showDirections:
                            widget.framingState.showCardinalDirections,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),

            // FOV overlay - Show when equipment is configured and preview FOV <= equipment FOV
            if (_hasEquipment && _equipment != null && !_showEquipmentOverlay)
              Center(
                child: Transform.translate(
                  offset: Offset(
                      widget.framingState.panX, widget.framingState.panY),
                  child: Transform.rotate(
                    angle: widget.framingState.rotation * math.pi / 180,
                    child: CustomPaint(
                      key: FramingTutorialKeys.fovRect,
                      painter: FramingFOVPainter(
                        fovWidth: _equipment!.fovWidthDeg,
                        fovHeight: _equipment!.fovHeightDeg,
                        zoom: widget.framingState.zoom,
                        colors: widget.colors,
                        showDirections:
                            widget.framingState.showCardinalDirections,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),

            // Mosaic grid overlay
            if (widget.framingState.mosaicEnabled &&
                _hasEquipment &&
                _equipment != null)
              Center(
                child: Transform.translate(
                  offset: Offset(
                      widget.framingState.panX, widget.framingState.panY),
                  child: Transform.rotate(
                    angle: widget.framingState.rotation * math.pi / 180,
                    child: CustomPaint(
                      painter: FramingMosaicGridPainter(
                        config: widget.framingState.mosaicConfig,
                        panels: widget.framingState.mosaicPanels,
                        fovWidth: _equipment!.fovWidthDeg,
                        fovHeight: _equipment!.fovHeightDeg,
                        zoom: widget.framingState.zoom,
                        colors: widget.colors,
                        showPanelNumbers: widget.framingState.showPanelNumbers,
                        showSequencePath: widget.framingState.showSequencePath,
                        selectedPanelIndex:
                            widget.framingState.selectedPanelIndex,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),

            // Crosshairs
            Center(
              child: CustomPaint(
                painter: FramingCrosshairPainter(colors: widget.colors),
                size: const Size(100, 100),
              ),
            ),

            // Top controls
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _CanvasControls(
                colors: widget.colors,
                framingState: widget.framingState,
              ),
            ),

            // Equipment status overlay (when not configured)
            if (!_hasEquipment && widget.framingState.target != null)
              Positioned(
                top: 60,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.colors.info.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: widget.colors.info.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.eye,
                          size: 14, color: widget.colors.info),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Preview: ${widget.framingState.previewFovDegrees.toStringAsFixed(1)}° FOV',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: widget.colors.info,
                            ),
                          ),
                          Text(
                            'Configure equipment for accurate framing',
                            style: TextStyle(
                              fontSize: 9,
                              color: widget.colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            // Zoom controls
            Positioned(
              bottom: 16,
              right: 16,
              child: Consumer(
                builder: (context, ref, child) => _ZoomControls(
                  colors: widget.colors,
                  zoom: widget.framingState.zoom,
                  onZoomIn: () => ref.read(framingProvider.notifier).zoomIn(),
                  onZoomOut: () => ref.read(framingProvider.notifier).zoomOut(),
                  onReset: () => ref.read(framingProvider.notifier).resetView(),
                ),
              ),
            ),

            // Scale indicator
            Positioned(
              bottom: 16,
              left: 16,
              child: _ScaleIndicator(
                colors: widget.colors,
                zoom: widget.framingState.zoom,
              ),
            ),

            // Target info overlay
            if (widget.framingState.target != null &&
                widget.framingState.showLabels)
              Positioned(
                top: 60,
                left: 16,
                child: FramingTargetInfoOverlay(
                  colors: widget.colors,
                  target: widget.framingState.target!,
                ),
              ),

            // Error overlay
            if (widget.framingState.imageError != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: widget.colors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: widget.colors.error),
                  ),
                  child: Text(
                    widget.framingState.imageError!,
                    style: TextStyle(color: widget.colors.error),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CanvasControls extends StatelessWidget {
  final NightshadeColors colors;
  final FramingState framingState;

  const _CanvasControls({
    required this.colors,
    required this.framingState,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        return Row(
          children: [
            // Survey source chip
            _ControlChip(
              icon: LucideIcons.layers,
              label: framingState.surveySource.displayName,
              colors: colors,
              onTap: () {
                // Show survey source picker
              },
            ),
            const SizedBox(width: 8),
            _ControlChip(
              icon: LucideIcons.grid,
              label: 'Grid',
              isActive: framingState.showGrid,
              colors: colors,
              onTap: () => ref.read(framingProvider.notifier).toggleGrid(),
            ),
            const SizedBox(width: 8),
            _ControlChip(
              icon: LucideIcons.tag,
              label: 'Labels',
              isActive: framingState.showLabels,
              colors: colors,
              onTap: () => ref.read(framingProvider.notifier).toggleLabels(),
            ),
            const Spacer(),
            if (framingState.isLoadingImage)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ControlChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final NightshadeColors colors;
  final VoidCallback? onTap;

  const _ControlChip({
    required this.icon,
    required this.label,
    this.isActive = false,
    required this.colors,
    this.onTap,
  });

  @override
  State<_ControlChip> createState() => _ControlChipState();
}

class _ControlChipState extends State<_ControlChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive
                ? widget.colors.primary.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: _isHovered ? 0.7 : 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isActive
                  ? widget.colors.primary.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.isActive ? widget.colors.primary : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  color:
                      widget.isActive ? widget.colors.primary : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  final NightshadeColors colors;
  final double zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _ZoomControls({
    required this.colors,
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(icon: LucideIcons.plus, colors: colors, onTap: onZoomIn),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '${(zoom * 100).round()}%',
              style: TextStyle(
                fontSize: 10,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          _ZoomButton(
              icon: LucideIcons.minus, colors: colors, onTap: onZoomOut),
          const SizedBox(height: 4),
          Container(height: 1, width: 20, color: colors.border),
          const SizedBox(height: 4),
          _ZoomButton(
              icon: LucideIcons.maximize2, colors: colors, onTap: onReset),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatefulWidget {
  final IconData icon;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _ZoomButton({
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_ZoomButton> createState() => _ZoomButtonState();
}

class _ZoomButtonState extends State<_ZoomButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _isHovered ? widget.colors.surfaceAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            widget.icon,
            size: 14,
            color: widget.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ScaleIndicator extends StatelessWidget {
  final NightshadeColors colors;
  final double zoom;

  const _ScaleIndicator({required this.colors, required this.zoom});

  @override
  Widget build(BuildContext context) {
    // Scale bar represents ~10 arcminutes at zoom level
    final barLength = (10.0 / 60.0) * 60 * zoom;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scale',
            style: TextStyle(
              fontSize: 9,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: barLength.clamp(30.0, 100.0),
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                "10'",
                style: TextStyle(
                  fontSize: 10,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
