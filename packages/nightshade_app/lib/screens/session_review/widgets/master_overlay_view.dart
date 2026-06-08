import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The finished-master hero for the Morning Report: the stretched preview PNG
/// (loaded on-disk exactly like [MasterPreviewView]) under a [Stack] of
/// toggleable overlays — rejection map, coverage map, and a vector catalog
/// annotation layer drawn at each [Annotation]'s pixel position.
///
/// This is the post-session analogue of the live viewer but, like
/// `MasterPreviewView`, reads on-disk artifacts rather than an in-memory buffer
/// (the batch master never lives in the Dart heap). The image-map overlays blend
/// a second PNG at low opacity; the annotation layer is *vector* (labels +
/// ellipses), painted via [CustomPaint] in the un-zoomed image space and kept in
/// lock-step with the [InteractiveViewer]'s zoom/pan because it sits inside the
/// viewer's child subtree — the viewer's single `Transform` moves it. A shared
/// [TransformationController] drives a rebuild on zoom so stroke/label sizes can
/// be damped by 1/zoom (positions are never re-transformed here).
class MasterOverlayView extends StatefulWidget {
  /// Path to the stretched master preview PNG (the hero base layer).
  final String previewPngPath;

  /// Catalog annotation layer (labels at master pixel coords), or null.
  final AnnotationLayer? annotations;

  /// Path to the rejection-map PNG, or null when none was produced.
  final String? rejectionMapPngPath;

  /// Path to the coverage-map PNG, or null when none was produced.
  final String? coverageMapPngPath;

  /// Initial visibility of the annotation layer.
  final bool showAnnotations;

  /// Initial visibility of the rejection-map overlay.
  final bool showRejection;

  /// Initial visibility of the coverage-map overlay.
  final bool showCoverage;

  const MasterOverlayView({
    super.key,
    required this.previewPngPath,
    this.annotations,
    this.rejectionMapPngPath,
    this.coverageMapPngPath,
    this.showAnnotations = true,
    this.showRejection = false,
    this.showCoverage = false,
  });

  @override
  State<MasterOverlayView> createState() => _MasterOverlayViewState();
}

class _MasterOverlayViewState extends State<MasterOverlayView> {
  late bool _showAnnotations = widget.showAnnotations;
  late bool _showRejection = widget.showRejection;
  late bool _showCoverage = widget.showCoverage;

  // Shared with the annotation painter so labels track zoom/pan.
  final TransformationController _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  bool _exists(String? path) {
    if (path == null) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final hasPreview = _exists(widget.previewPngPath);
    final hasRejection = _exists(widget.rejectionMapPngPath);
    final hasCoverage = _exists(widget.coverageMapPngPath);
    final layer = widget.annotations;
    final hasAnnotations = layer != null && layer.items.isNotEmpty;

    if (!hasPreview) {
      return EmptyState(
        icon: NightshadeIcons.imageOff,
        title: 'Preview not available',
        body: 'The master preview file is no longer on disk:\n'
            '${widget.previewPngPath}',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasRejection || hasCoverage || hasAnnotations)
          Padding(
            padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
            child: Wrap(
              spacing: NightshadeTokens.spaceSm,
              runSpacing: NightshadeTokens.spaceXs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (hasAnnotations)
                  _OverlayToggle(
                    icon: NightshadeIcons.target,
                    label: 'Annotations',
                    value: _showAnnotations,
                    onChanged: (v) => setState(() => _showAnnotations = v),
                  ),
                if (hasRejection)
                  _OverlayToggle(
                    icon: NightshadeIcons.layers,
                    label: 'Rejection',
                    value: _showRejection,
                    onChanged: (v) => setState(() => _showRejection = v),
                  ),
                if (hasCoverage)
                  _OverlayToggle(
                    icon: NightshadeIcons.grid,
                    label: 'Coverage',
                    value: _showCoverage,
                    onChanged: (v) => setState(() => _showCoverage = v),
                  ),
              ],
            ),
          ),
        Expanded(
          child: Container(
            color: colors.background,
            padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
            child: InteractiveViewer(
              transformationController: _transform,
              maxScale: 8,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(widget.previewPngPath),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(NightshadeIcons.imageOff,
                              size: NightshadeTokens.icon2xl,
                              color: colors.textMuted),
                        ),
                      ),
                      if (_showCoverage && hasCoverage)
                        Opacity(
                          opacity: NightshadeTokens.opacityHalf,
                          child: Image.file(
                            File(widget.coverageMapPngPath!),
                            fit: BoxFit.contain,
                          ),
                        ),
                      if (_showRejection && hasRejection)
                        Opacity(
                          opacity: 0.55,
                          child: Image.file(
                            File(widget.rejectionMapPngPath!),
                            fit: BoxFit.contain,
                          ),
                        ),
                      if (_showAnnotations && hasAnnotations)
                        AnimatedBuilder(
                          animation: _transform,
                          builder: (context, _) => CustomPaint(
                            painter: _AnnotationPainter(
                              layer: layer,
                              viewport: viewport,
                              transform: _transform.value,
                              colors: colors,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        if (hasAnnotations && _showAnnotations)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceSm,
              vertical: NightshadeTokens.spaceXs,
            ),
            child: Text(
              '${layer.items.length} catalog objects annotated',
              style:
                  NightshadeTypography.caption.copyWith(color: colors.textMuted),
            ),
          ),
      ],
    );
  }
}

/// A labelled overlay-visibility toggle (icon + name + [NightshadeSwitch]).
class _OverlayToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _OverlayToggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: NightshadeTokens.iconXs,
            color: value ? colors.primary : colors.textSecondary),
        const SizedBox(width: NightshadeTokens.spaceXs),
        Text(
          label,
          style: NightshadeTypography.bodySm.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(width: NightshadeTokens.spaceXs),
        NightshadeSwitch(value: value, compact: true, onChanged: onChanged),
      ],
    );
  }
}

/// Paints the vector catalog annotations (an ellipse sized [Annotation.sizePx],
/// rotated [Annotation.paDeg], plus the label) in the un-zoomed image space the
/// base `Image.file` occupies. This painter lives inside the
/// [InteractiveViewer]'s child subtree, so the viewer's single
/// `Transform(matrix)` is what moves the annotations under zoom/pan — the
/// painter must NOT re-apply that matrix (doing so double-transforms and slides
/// labels off their objects). The [transform] is read only to damp stroke/label
/// sizes by 1/zoom so they stay readable while the enclosing Transform scales
/// everything else.
class _AnnotationPainter extends CustomPainter {
  final AnnotationLayer layer;
  final Size viewport;
  final Matrix4 transform;
  final NightshadeColors colors;

  _AnnotationPainter({
    required this.layer,
    required this.viewport,
    required this.transform,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (layer.items.isEmpty || layer.width <= 0 || layer.height <= 0) return;

    // This CustomPaint lives INSIDE the InteractiveViewer's child subtree, so
    // the viewer's own `Transform(matrix)` already applies the zoom/pan to this
    // canvas. We must therefore paint in the SAME un-zoomed local space the base
    // `Image.file` occupies and let the enclosing Transform move the annotations
    // — applying the matrix a second time here would double-transform every
    // ellipse/label and slide them off their catalog objects under zoom/pan.
    //
    // The base image is laid out with BoxFit.contain inside [viewport]; the
    // shared `annotationContainScale` / `annotationLocalCenter` map annotation
    // pixels into that un-zoomed local rect. No `canvas.transform(...)` — the
    // enclosing InteractiveViewer Transform is the single source of zoom/pan.
    final scale = annotationContainScale(viewport, layer.width, layer.height);

    // The enclosing Transform scales strokes + labels with the zoom; damp them
    // by 1/zoom so they stay a constant on-screen size (readable, not ballooning)
    // even though positions are driven entirely by that single Transform.
    final zoom = transform.getMaxScaleOnAxis().clamp(0.5, 8.0);
    final labelScale = 1.0 / zoom;

    for (final a in layer.items) {
      final center =
          annotationLocalCenter(a, viewport, layer.width, layer.height);
      final cx = center.dx;
      final cy = center.dy;
      final color = _kindColor(a.kind);

      final rPx = (a.sizePx * scale) / 2;
      final rx = rPx <= 0 ? 6.0 : rPx;
      final ry = a.paDeg != null ? rx * 0.6 : rx;

      final markerPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / zoom
        ..color = color.withValues(alpha: 0.9);

      canvas.save();
      canvas.translate(cx, cy);
      if (a.paDeg != null) {
        canvas.rotate(a.paDeg! * 3.1415926535897932 / 180.0);
      }
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
        markerPaint,
      );
      canvas.restore();

      if (a.label.isNotEmpty) {
        final span = TextSpan(
          text: a.label,
          style: NightshadeTypography.captionSm.copyWith(
            color: color,
            fontSize: NightshadeTypography.captionSm.fontSize! * labelScale,
            shadows: [
              Shadow(color: colors.background, blurRadius: 2 * labelScale),
            ],
          ),
        );
        final painter = TextPainter(
          text: span,
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          Offset(cx - painter.width / 2, cy + rx + (2 * labelScale)),
        );
      }
    }
  }

  /// Maps an [AnnotationKind] to its catalog display hue via the design-system
  /// [AnnotationTypeColors] helper, falling back to a semantic token.
  Color _kindColor(AnnotationKind kind) {
    switch (kind) {
      case AnnotationKind.galaxy:
        return AnnotationTypeColors.galaxy;
      case AnnotationKind.nebula:
        return AnnotationTypeColors.nebula;
      case AnnotationKind.cluster:
        return AnnotationTypeColors.starCluster;
      case AnnotationKind.star:
        return AnnotationTypeColors.star;
      case AnnotationKind.other:
        return colors.textSecondary;
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter old) =>
      old.layer != layer ||
      old.transform != transform ||
      old.viewport != viewport;
}

/// The BoxFit.contain scale that maps a [layerWidth]×[layerHeight] image into
/// [viewport] — the same scale the base `Image.file` is laid out with. Shared by
/// the painter and exposed for the annotation-registration test.
@visibleForTesting
double annotationContainScale(
  Size viewport,
  int layerWidth,
  int layerHeight,
) {
  if (layerWidth <= 0 || layerHeight <= 0) return 0;
  return (viewport.width / layerWidth)
      .clamp(0.0, viewport.height / layerHeight);
}

/// The un-zoomed local-space centre of [a] inside [viewport] for a
/// [layerWidth]×[layerHeight] annotation layer. This is intentionally
/// **independent of the InteractiveViewer transform**: the painter sits inside
/// the viewer's child subtree, so the viewer's single `Transform(matrix)` moves
/// the annotation under zoom/pan — the painter must never re-apply that matrix.
/// The annotation-registration test asserts this center is identical at identity
/// and at a zoomed/panned transform, proving the matrix is applied exactly once.
@visibleForTesting
Offset annotationLocalCenter(
  Annotation a,
  Size viewport,
  int layerWidth,
  int layerHeight,
) {
  final scale = annotationContainScale(viewport, layerWidth, layerHeight);
  final drawnW = layerWidth * scale;
  final drawnH = layerHeight * scale;
  final originX = (viewport.width - drawnW) / 2;
  final originY = (viewport.height - drawnH) / 2;
  return Offset(originX + a.x * scale, originY + a.y * scale);
}
