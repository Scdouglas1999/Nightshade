import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
// FramingPlateScale is the C1 single-source-of-truth astrometric scale shared by
// the framing painters and the gesture hit-tester. It lives in nightshade_core's
// models layer and is not surfaced through the public barrel, matching the
// app->core src-model convention used by the framing painters themselves.
// ignore: implementation_imports
import 'package:nightshade_core/src/models/framing_plate_scale.dart';

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
  /// Reports a pan delta together with the real, sidebar-excluded [canvasSize]
  /// the delta was measured against. The size is required so the framing
  /// provider can convert drawn-canvas-pixel pans to sky degrees through the
  /// shared plate scale (the pan-refetch threshold depends on it).
  final void Function(double dx, double dy, Size canvasSize) onPan;
  final void Function(double angle) onRotate;

  /// Fired whenever the measured canvas size changes (the LayoutBuilder reports
  /// a new bounded box, e.g. when the user drags the sidebar splitter or the
  /// window resizes). Drives C9's plate-scale-aware survey re-fetch so the
  /// imagery resolution tracks the canvas.
  final void Function(Size canvasSize) onCanvasResized;

  const FramingCanvas({
    super.key,
    required this.colors,
    required this.framingState,
    required this.equipmentResult,
    required this.onPan,
    required this.onRotate,
    required this.onCanvasResized,
  });

  @override
  State<FramingCanvas> createState() => _FramingCanvasState();
}

class _FramingCanvasState extends State<FramingCanvas> {
  bool _isDragging = false;
  bool _isRotating = false;
  Offset _lastPosition = Offset.zero;

  /// The real canvas size, captured from the [LayoutBuilder] in [build].
  ///
  /// Gesture handlers ([GestureDetector] callbacks) need the canvas center and
  /// the plate scale's pixels-per-degree, both of which depend on the *actual*
  /// painted size of the canvas — not [MediaQuery.sizeOf], which returns the
  /// whole window (including the framing sidebar) and so put the rotation ring
  /// and rotation pivot in the wrong place. The size is written from the
  /// LayoutBuilder's constraints on every layout pass and read back in the
  /// gesture math.
  Size _canvasSize = Size.zero;

  FramingEquipment? get _equipment => widget.equipmentResult?.equipment;
  bool get _hasEquipment => widget.equipmentResult?.isReady ?? false;

  /// The astrometric plate scale every overlay painter shares, for the given
  /// real [canvasSize].
  ///
  /// When a survey image is loaded its real [FramingPlateScale] (published by
  /// [FramingNotifier]) is used, so the FOV reticle, equipment overlay and
  /// mosaic grid are co-registered with the imagery to the pixel. When no image
  /// is loaded there is nothing to register against, so a synthetic scale is
  /// derived inline from the current preview FOV and the real canvas geometry:
  /// the field is treated as a cutout whose pixel aspect matches the canvas and
  /// whose *width* spans [FramingState.previewFovDegrees] of sky. With that the
  /// fit-to-canvas math in [FramingPlateScale] makes the preview FOV fill the
  /// canvas width at zoom 1.0 — the long-standing behavior of the no-image
  /// fallback, now expressed through the one shared scale instead of three
  /// divergent ad-hoc constants, so the overlays still render correctly before
  /// any survey imagery is fetched.
  FramingPlateScale _resolvePlateScale(Size canvasSize) {
    final loaded = widget.framingState.plateScale;
    if (loaded != null) return loaded;

    final previewFov = widget.framingState.previewFovDegrees;

    // Match the synthetic cutout's pixel aspect to the canvas so the preview
    // FOV maps onto the full canvas width (mirroring the fit-to-canvas rule the
    // real survey path uses). Before first layout the canvas is empty; fall back
    // to a unit-aspect square, which still yields a valid, finite scale.
    final aspect = canvasSize.isEmpty || canvasSize.height <= 0
        ? 1.0
        : canvasSize.width / canvasSize.height;
    const pixelHeight = 1000;
    final pixelWidth = (pixelHeight * aspect).round().clamp(1, 1 << 20);

    return FramingPlateScale(
      surveyFovWidthDeg: previewFov,
      surveyFovHeightDeg: previewFov / aspect,
      imagePixelWidth: pixelWidth,
      imagePixelHeight: pixelHeight,
    );
  }

  /// Whether to show the equipment FOV overlay (preview FOV > equipment FOV)
  bool get _showEquipmentOverlay {
    if (!_hasEquipment || _equipment == null) return false;
    return widget.framingState.previewFovDegrees > _equipment!.fovWidthDeg &&
        widget.framingState.showEquipmentFovOverlay;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Capture the real canvas size so both the shared plate scale and the
        // gesture handlers below use the canvas geometry rather than the
        // whole-window MediaQuery size (which includes the framing sidebar).
        final newSize = constraints.biggest;
        if (newSize != _canvasSize) {
          _canvasSize = newSize;
          // Notify after the frame: the LayoutBuilder runs during build, and the
          // resize handler may trigger a provider state change (survey re-fetch)
          // which must not mutate state mid-build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onCanvasResized(newSize);
          });
        }
        final plateScale = _resolvePlateScale(_canvasSize);
        return _buildCanvas(context, plateScale);
      },
    );
  }

  Widget _buildCanvas(BuildContext context, FramingPlateScale plateScale) {
    return GestureDetector(
      onPanStart: (details) {
        _lastPosition = details.localPosition;
        final canvasSize = _canvasSize;
        final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
        final distance = (details.localPosition - center).distance;

        // If clicking near the rotation handle, rotate instead of pan. The
        // handle is painted [FramingFOVPainter.rotationHandleGap] above the FOV
        // rectangle's top edge with radius
        // [FramingFOVPainter.rotationHandleRadius]; the hit ring spans that
        // handle center +/- [FramingFOVPainter.rotationHitTolerance] so the
        // touch target matches exactly where the handle is drawn. The FOV
        // rectangle's half-height is derived from the *same* shared plate scale
        // the painter uses, so the ring tracks the rendered reticle under any
        // zoom or survey registration.
        if (_hasEquipment && _equipment != null) {
          final pixelsPerDegree =
              plateScale.pixelsPerDegree(canvasSize, widget.framingState.zoom);
          final fovHalfHeight = _equipment!.fovHeightDeg * pixelsPerDegree / 2;
          final handleCenterDistance =
              fovHalfHeight + FramingFOVPainter.rotationHandleGap;
          final innerRadius = handleCenterDistance -
              FramingFOVPainter.rotationHandleRadius -
              FramingFOVPainter.rotationHitTolerance;
          final outerRadius = handleCenterDistance +
              FramingFOVPainter.rotationHandleRadius +
              FramingFOVPainter.rotationHitTolerance;
          if (distance > innerRadius && distance < outerRadius) {
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
            _canvasSize.width / 2,
            _canvasSize.height / 2,
          );
          final angle = math.atan2(
            details.localPosition.dx - center.dx,
            -(details.localPosition.dy - center.dy),
          );
          widget.onRotate(angle * 180 / math.pi);
        } else if (_isDragging) {
          final delta = details.localPosition - _lastPosition;
          widget.onPan(delta.dx, delta.dy, _canvasSize);
          _lastPosition = details.localPosition;
        }
      },
      onPanEnd: (_) {
        _isDragging = false;
        _isRotating = false;
      },
      child: Container(
        color: widget.colors.background,
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
                    rotation: widget.framingState.rotation,
                    plateScale: plateScale,
                  ),
                ),
              )
            else if (widget.framingState.isLoadingImage)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: widget.colors.primary),
                    const SizedBox(height: NightshadeTokens.spaceLg),
                    Text(
                      'Loading sky survey...',
                      style: NightshadeTypography.body
                          .copyWith(color: widget.colors.textMuted),
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
                  color: widget.colors.primary
                      .withValues(alpha: NightshadeTokens.opacityMedium),
                  plateScale: plateScale,
                ),
                size: Size.infinite,
              ),

            // Equipment FOV overlay - Show when preview FOV > equipment FOV
            //
            // Transform order MUST match FramingSurveyImagePainter: the survey
            // background is drawn into a pan-displaced rect and THEN rotated
            // about the canvas center (rotate ∘ translate), so the image center
            // lands at canvasCenter + rotate(pan). To keep the reticle pixel-co-
            // registered with the imagery under simultaneous pan AND rotation,
            // the overlay must compose the same way: rotate about the canvas
            // center OUTERMOST, translate by pan INNERMOST. (Reversing these —
            // translate outer, rotate inner — drifts the reticle off the
            // imagery by rotate(pan) - pan whenever rotation != 0 and pan != 0.)
            if (_showEquipmentOverlay && _equipment != null)
              Center(
                child: Transform.rotate(
                  angle: widget.framingState.rotation * math.pi / 180,
                  child: Transform.translate(
                    offset: Offset(
                        widget.framingState.panX, widget.framingState.panY),
                    child: CustomPaint(
                      painter: FramingEquipmentFOVOverlayPainter(
                        fovWidth: _equipment!.fovWidthDeg,
                        fovHeight: _equipment!.fovHeightDeg,
                        zoom: widget.framingState.zoom,
                        plateScale: plateScale,
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
            // Same rotate-outer / translate-inner order as the background and
            // the larger-than-equipment overlay above, so the reticle stays
            // co-registered with the survey imagery under pan + rotation.
            if (_hasEquipment && _equipment != null && !_showEquipmentOverlay)
              Center(
                child: Transform.rotate(
                  angle: widget.framingState.rotation * math.pi / 180,
                  child: Transform.translate(
                    offset: Offset(
                        widget.framingState.panX, widget.framingState.panY),
                    child: CustomPaint(
                      key: FramingTutorialKeys.fovRect,
                      painter: FramingFOVPainter(
                        fovWidth: _equipment!.fovWidthDeg,
                        fovHeight: _equipment!.fovHeightDeg,
                        zoom: widget.framingState.zoom,
                        plateScale: plateScale,
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
            // Same rotate-outer / translate-inner order as the background and
            // FOV overlays so the mosaic panels stay co-registered with the
            // survey imagery under pan + rotation.
            if (widget.framingState.mosaicEnabled &&
                _hasEquipment &&
                _equipment != null)
              Center(
                child: Transform.rotate(
                  angle: widget.framingState.rotation * math.pi / 180,
                  child: Transform.translate(
                    offset: Offset(
                        widget.framingState.panX, widget.framingState.panY),
                    child: CustomPaint(
                      painter: FramingMosaicGridPainter(
                        config: widget.framingState.mosaicConfig,
                        panels: widget.framingState.mosaicPanels,
                        fovWidth: _equipment!.fovWidthDeg,
                        fovHeight: _equipment!.fovHeightDeg,
                        zoom: widget.framingState.zoom,
                        plateScale: plateScale,
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
                  padding: NightshadeTokens.paddingMd,
                  decoration: BoxDecoration(
                    color: widget.colors.info
                        .withValues(alpha: NightshadeTokens.opacityStatusFill),
                    borderRadius: NightshadeTokens.borderRadiusMd,
                    border: Border.all(
                        color: widget.colors.info
                            .withValues(alpha: NightshadeTokens.opacityHalf)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.eye,
                          size: NightshadeTokens.iconXs, color: widget.colors.info),
                      const SizedBox(width: NightshadeTokens.spaceSm),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Preview: ${widget.framingState.previewFovDegrees.toStringAsFixed(1)}° FOV',
                            style: NightshadeTypography.labelQuiet
                                .copyWith(color: widget.colors.info),
                          ),
                          Text(
                            'Configure equipment for accurate framing',
                            style: NightshadeTypography.overline
                                .copyWith(color: widget.colors.textMuted),
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
                plateScale: plateScale,
                canvasSize: _canvasSize,
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
                  padding: NightshadeTokens.paddingLg,
                  margin: const EdgeInsets.all(NightshadeTokens.space3xl),
                  decoration: BoxDecoration(
                    color: widget.colors.error
                        .withValues(alpha: NightshadeTokens.opacitySubtle),
                    borderRadius: NightshadeTokens.borderRadiusMd,
                    border: Border.all(color: widget.colors.error),
                  ),
                  child: Text(
                    widget.framingState.imageError!,
                    style: NightshadeTypography.body
                        .copyWith(color: widget.colors.error),
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
            // Survey-source selector: a real NightshadeDropdown wired to the
            // framing notifier so changing the source refetches the imagery for
            // the new survey. No dead handler — selection drives setSurveySource.
            _SurveySourceSelector(
              colors: colors,
              source: framingState.surveySource,
              onChanged: (source) =>
                  ref.read(framingProvider.notifier).setSurveySource(source),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            _ControlChip(
              icon: LucideIcons.grid,
              label: 'Grid',
              isActive: framingState.showGrid,
              colors: colors,
              onTap: () => ref.read(framingProvider.notifier).toggleGrid(),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
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
                padding: const EdgeInsets.symmetric(
                    horizontal: NightshadeTokens.spaceMd,
                    vertical: NightshadeTokens.spaceSm),
                decoration: BoxDecoration(
                  color: colors.surfaceOverlay
                      .withValues(alpha: NightshadeTokens.opacityMuted),
                  borderRadius: NightshadeTokens.borderRadiusMd,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: NightshadeTokens.iconXs,
                      height: NightshadeTokens.iconXs,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: NightshadeTokens.spaceSm),
                    Text(
                      'Loading...',
                      style: NightshadeTypography.labelQuiet
                          .copyWith(color: colors.textSecondary),
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

/// On-canvas survey-source picker.
///
/// A [NightshadeDropdown] (the canonical design-system selector) fronted by the
/// `layers` glyph so it reads as part of the chip strip, wired straight to
/// [FramingNotifier.setSurveySource]. Selecting a source refetches the survey
/// imagery for that band (the refetch lives in the notifier), replacing the old
/// no-op chip that did nothing on tap.
class _SurveySourceSelector extends StatelessWidget {
  final NightshadeColors colors;
  final SurveySource source;
  final ValueChanged<SurveySource> onChanged;

  const _SurveySourceSelector({
    required this.colors,
    required this.source,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // The dropdown keys on the enum name and maps back to the enum on change so
    // SurveySource stays the single source of truth (no string parsing of
    // display names).
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceOverlay
            .withValues(alpha: NightshadeTokens.opacityHalf),
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(
          color: colors.border.withValues(alpha: NightshadeTokens.opacitySubtle),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: NightshadeTokens.spaceMd),
          Icon(
            LucideIcons.layers,
            size: NightshadeTokens.iconXs,
            color: colors.textSecondary,
          ),
          const SizedBox(width: NightshadeTokens.spaceXs),
          NightshadeDropdown(
            value: source.name,
            isDense: true,
            items: SurveySource.values.map((s) => s.name).toList(),
            itemLabels:
                SurveySource.values.map((s) => s.displayName).toList(),
            onChanged: (name) {
              if (name == null) return;
              onChanged(SurveySource.values.byName(name));
            },
          ),
        ],
      ),
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
          duration: NightshadeTokens.durationQuick,
          padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceMd,
              vertical: NightshadeTokens.spaceSm),
          decoration: BoxDecoration(
            color: widget.isActive
                ? widget.colors.primary
                    .withValues(alpha: NightshadeTokens.opacityMedium)
                : widget.colors.surfaceOverlay.withValues(
                    alpha: _isHovered
                        ? NightshadeTokens.opacityHoverBorder
                        : NightshadeTokens.opacityHalf),
            borderRadius: NightshadeTokens.borderRadiusMd,
            border: Border.all(
              color: widget.isActive
                  ? widget.colors.primary
                      .withValues(alpha: NightshadeTokens.opacityHalf)
                  : widget.colors.border
                      .withValues(alpha: NightshadeTokens.opacitySubtle),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: NightshadeTokens.iconXs,
                color: widget.isActive
                    ? widget.colors.primary
                    : widget.colors.textSecondary,
              ),
              const SizedBox(width: NightshadeTokens.spaceXs),
              Text(
                widget.label,
                style: NightshadeTypography.labelQuiet.copyWith(
                  color: widget.isActive
                      ? widget.colors.primary
                      : widget.colors.textSecondary,
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
      padding: NightshadeTokens.paddingXs,
      decoration: BoxDecoration(
        color: colors.surfaceOverlay
            .withValues(alpha: NightshadeTokens.opacityHoverBorder),
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(icon: LucideIcons.plus, colors: colors, onTap: onZoomIn),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Padding(
            padding: const EdgeInsets.symmetric(
                vertical: NightshadeTokens.spaceXs),
            child: Text(
              '${(zoom * 100).round()}%',
              style: NightshadeTypography.withTabular(
                NightshadeTypography.overline
                    .copyWith(color: colors.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          _ZoomButton(
              icon: LucideIcons.minus, colors: colors, onTap: onZoomOut),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Container(height: 1, width: 20, color: colors.border),
          const SizedBox(height: NightshadeTokens.spaceXs),
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
          duration: NightshadeTokens.durationQuick,
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _isHovered ? widget.colors.surfaceAlt : Colors.transparent,
            borderRadius: NightshadeTokens.borderRadiusXs,
          ),
          child: Icon(
            widget.icon,
            size: NightshadeTokens.iconXs,
            color: widget.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// On-canvas scale bar showing a real angular distance derived from the shared
/// [FramingPlateScale].
///
/// The old bar was a fixed `(10/60)*60*zoom` expression that always read "10'"
/// regardless of the actual sky scale — meaningless once the survey image,
/// equipment FOV and zoom are all in play. This version targets a ~60px bar,
/// converts that to degrees through [FramingPlateScale.pixelsPerDegree] (the
/// same scale the imagery and overlays use), snaps it to a "nice" arcminute /
/// degree increment, and then sizes the bar to the *exact* on-screen length of
/// that snapped value so the rule and its label always agree.
class _ScaleIndicator extends StatelessWidget {
  final NightshadeColors colors;
  final double zoom;
  final FramingPlateScale plateScale;
  final Size canvasSize;

  const _ScaleIndicator({
    required this.colors,
    required this.zoom,
    required this.plateScale,
    required this.canvasSize,
  });

  /// Candidate scale-bar lengths, in arcminutes, from 1' up to 5°. The renderer
  /// picks the largest entry whose on-screen length does not exceed the target
  /// bar width, so the bar grows and shrinks through familiar astronomical
  /// increments as the user zooms.
  static const List<double> _niceArcminSteps = [
    1, 2, 5, 10, 15, 30, 60, 120, 300,
  ];

  /// Target on-screen length of the scale bar, in logical pixels, before
  /// snapping to the nearest nice value.
  static const double _targetBarPx = 60;

  @override
  Widget build(BuildContext context) {
    final pixelsPerDegree = canvasSize.isEmpty
        ? 0.0
        : plateScale.pixelsPerDegree(canvasSize, zoom);
    final pixelsPerArcmin = pixelsPerDegree / 60.0;

    // Choose the largest nice step that still fits within the target width;
    // fall back to the smallest step when even 1' is wider than the target
    // (extreme zoom-in) so the bar always represents a real, labelled distance.
    double stepArcmin = _niceArcminSteps.first;
    if (pixelsPerArcmin.isFinite && pixelsPerArcmin > 0) {
      for (final candidate in _niceArcminSteps) {
        if (candidate * pixelsPerArcmin <= _targetBarPx) {
          stepArcmin = candidate;
        } else {
          break;
        }
      }
    }

    final barLength = (stepArcmin * pixelsPerArcmin)
        .clamp(NightshadeTokens.space3xl, _targetBarPx * 1.5);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceMd,
          vertical: NightshadeTokens.spaceSm),
      decoration: BoxDecoration(
        color: colors.surfaceOverlay
            .withValues(alpha: NightshadeTokens.opacityHoverBorder),
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scale',
            style: NightshadeTypography.overline
                .copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Row(
            children: [
              Container(
                width: barLength,
                height: 3,
                decoration: BoxDecoration(
                  color: colors.textSecondary,
                  borderRadius: NightshadeTokens.borderRadiusXs,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceXs),
              Text(
                _formatScaleLabel(stepArcmin),
                style: NightshadeTypography.withTabular(
                  NightshadeTypography.labelQuiet
                      .copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Formats an arcminute span as a compact astronomical label: values that are
  /// a whole number of degrees read as e.g. `2°`, otherwise as arcminutes
  /// (`15'`).
  String _formatScaleLabel(double arcmin) {
    if (arcmin >= 60 && arcmin % 60 == 0) {
      return '${(arcmin / 60).toStringAsFixed(0)}°';
    }
    return "${arcmin.toStringAsFixed(0)}'";
  }
}
