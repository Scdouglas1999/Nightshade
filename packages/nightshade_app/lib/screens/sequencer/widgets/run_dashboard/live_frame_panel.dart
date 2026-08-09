import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart' hide ConnectionState;
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../imaging/widgets/image_display.dart';
import '../../../../utils/filter_label.dart';

/// Live-frame tile for the Run dashboard.
///
/// Layout: the current sub-exposure fills the main area on the left, with a
/// vertical, scrollable column of recent-capture thumbnails pinned to the
/// right. This keeps the main image near-square (instead of the old wide/short
/// band that the horizontal history strip forced) while still surfacing the
/// session's frame history at a glance.
///
/// Interaction model (see [_LiveFrameViewer]):
/// - Zoom is driven by on-image **buttons** (in / out / fit) and by **pinch**
///   on touch; `constrained: true` clamps the scaled child to the viewport so
///   it can never be flung off-canvas, and the readout/buttons stay in sync
///   via `onInteractionUpdate`.
/// - Pan is drag, clamped so the frame can never be dragged fully off-canvas;
///   "fit" recentres and rescales to fill.
///
/// Reuses [ImageDisplayWidget] (the Imaging screen's decoder) so stretch /
/// decode logic is never reimplemented here.
class RunDashboardLiveFrame extends ConsumerWidget {
  const RunDashboardLiveFrame({super.key});

  /// Below this width the history column is dropped (the standalone "Recent
  /// Frames" tile still carries it) so the main image keeps a usable area on a
  /// narrow, user-resized panel.
  static const double _historyBreakpoint = 320.0;

  /// Fixed width of the vertical history column when shown.
  static const double _historyColumnWidth = 96.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final currentImage = ref.watch(currentImageProvider);
    final sessionImages = ref.watch(recentSessionFramesProvider);

    // The current frame's own settings can carry a null filter (the live
    // preview is published before the persisted history row is written); fall
    // back to the newest history entry, which is the same source the column
    // renders from, so the badge shows "L" instead of "no filter".
    final resolvedFilter =
        _resolveFilter(currentImage?.settings.filter, sessionImages);

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showHistory = constraints.maxWidth >= _historyBreakpoint &&
              sessionImages.isNotEmpty;

          final main = _FramePane(
            colors: colors,
            image: currentImage,
            filterLabel: resolvedFilter,
            hfrHistory: _hfrHistory(sessionImages),
          );

          // The dashboard lays its tiles out in a vertical scroll view, so this
          // widget is built with an UNBOUNDED height. Nothing below supplies one:
          // `Row(crossAxisAlignment: stretch)` hands `constraints.maxHeight`
          // straight to its children as a tight height, and [_FramePane] is a
          // Stack whose children are all `Positioned.fill`, so it takes whatever
          // it is given. The infinity reached InteractiveViewer's transform, the
          // engine logged "TransformLayer is constructed with an invalid matrix"
          // and dropped the layer subtree — which blanked not just this tile but
          // the whole primary column it shared. Bound the box here so every
          // descendant is finite; honour a real bound when the parent gives one.
          final Widget body = !showHistory
              ? main
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: main),
                    const SizedBox(width: NightshadeTokens.spaceSm),
                    SizedBox(
                      width: _historyColumnWidth,
                      child: _HistoryColumn(
                        colors: colors,
                        images: sessionImages,
                        currentImage: currentImage,
                      ),
                    ),
                  ],
                );

          if (constraints.hasBoundedHeight) {
            return body;
          }
          return SizedBox(
            height: _unboundedHeightFor(constraints.maxWidth),
            child: body,
          );
        },
      ),
    );
  }

  /// Height to adopt when the parent imposes none (a dashboard scroll zone).
  ///
  /// A 4:3 box is what this panel documents itself as; the clamp keeps it
  /// readable on a narrow tile and stops it eating the whole viewport on a
  /// wide one.
  static double _unboundedHeightFor(double maxWidth) {
    if (!maxWidth.isFinite) return 320;
    return (maxWidth * 3 / 4).clamp(180.0, 420.0);
  }

  /// Recent per-frame HFR values (oldest→newest) for the inline sparkline.
  /// Pulls from the same session history the column renders from; frames
  /// without a measured HFR are skipped so the trend reflects only real
  /// measurements. Capped to keep the sparkline readable.
  static List<double> _hfrHistory(List<CapturedImage> history) {
    const maxPoints = 40;
    final values = <double>[];
    for (final image in history) {
      final hfr = image.stats?.hfr;
      if (hfr != null && hfr > 0) values.add(hfr);
    }
    if (values.length > maxPoints) {
      return values.sublist(values.length - maxPoints);
    }
    return values;
  }

  static String? _resolveFilter(
    String? currentFilter,
    List<CapturedImage> history,
  ) {
    if (currentFilter != null && currentFilter.isNotEmpty) {
      return currentFilter;
    }
    for (final image in history.reversed) {
      final filter = image.settings.filter;
      if (filter != null && filter.isNotEmpty) {
        return filter;
      }
    }
    return null;
  }
}

/// The main image pane: the interactive viewer (or an empty-state) plus the
/// metadata badge overlay.
class _FramePane extends StatelessWidget {
  final NightshadeColors colors;
  final CapturedImageData? image;
  final String? filterLabel;
  final List<double> hfrHistory;

  const _FramePane({
    required this.colors,
    required this.image,
    required this.filterLabel,
    required this.hfrHistory,
  });

  @override
  Widget build(BuildContext context) {
    final img = image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: colors.background)),
          if (img != null)
            Positioned.fill(
              child: _LiveFrameViewer(image: img, colors: colors),
            )
          else
            Positioned.fill(child: _WaitingState(colors: colors)),
          if (img != null)
            Positioned(
              right: 8,
              top: 8,
              child: _FrameBadge(
                colors: colors,
                filterLabel: filterLabel,
                exposure: img.settings.exposureTime,
                stats: img.stats,
                hfrHistory: hfrHistory,
              ),
            ),
        ],
      ),
    );
  }
}

class _WaitingState extends StatelessWidget {
  final NightshadeColors colors;

  const _WaitingState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.image, size: 36, color: colors.textMuted),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            'Waiting for first frame…',
            style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Interactive image area: button-driven zoom + drag pan, wheel-zoom disabled.
class _LiveFrameViewer extends StatefulWidget {
  final CapturedImageData image;
  final NightshadeColors colors;

  const _LiveFrameViewer({required this.image, required this.colors});

  @override
  State<_LiveFrameViewer> createState() => _LiveFrameViewerState();
}

class _LiveFrameViewerState extends State<_LiveFrameViewer> {
  final TransformationController _controller = TransformationController();

  static const double _minScale = 1.0;
  static const double _maxScale = 8.0;
  static const double _zoomStep = 1.6;

  double _scale = 1.0;

  @override
  void didUpdateWidget(covariant _LiveFrameViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A brand-new frame resets the view so the operator always sees the full
    // fresh sub-exposure rather than a stale zoom/pan from the previous frame.
    if (oldWidget.image != widget.image) {
      _reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() {
    _controller.value = Matrix4.identity();
    if (mounted) {
      setState(() => _scale = 1.0);
    } else {
      _scale = 1.0;
    }
  }

  /// Zoom around the centre of the viewport by [factor], keeping the image
  /// clamped within bounds (InteractiveViewer's `constrained: true` handles the
  /// pan clamp; we re-centre the focal point so zoom feels anchored).
  void _zoomBy(double factor, Size viewport) {
    final current = _controller.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(_minScale, _maxScale);
    if (target == current) return;

    if (target <= _minScale) {
      _reset();
      return;
    }

    final focal = Offset(viewport.width / 2, viewport.height / 2);
    final change = target / current;
    final next = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1.0)
      ..scaleByDouble(change, change, 1.0, 1.0)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1.0);
    _controller.value = next * _controller.value;
    setState(() => _scale = target);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        // Decode only as many pixels as the panel can actually show. A ~300px
        // tile never needs a full sensor-resolution texture; the source width
        // clamp lives in ImageDisplayWidget so this is just the upper bound.
        final targetWidth =
            (viewport.width * devicePixelRatio).round().clamp(1, 1 << 30);
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _controller,
                // Pinch scaling is enabled; `constrained: true` keeps the
                // scaled child clamped inside the viewport so it can never be
                // flung off-canvas. The readout/buttons track the live scale
                // via onInteractionUpdate.
                scaleEnabled: true,
                panEnabled: true,
                // `constrained: true` keeps the (scaled) child inside the
                // viewport, which clamps the pan so the image can't be dragged
                // fully off-canvas.
                constrained: true,
                minScale: _minScale,
                maxScale: _maxScale,
                onInteractionUpdate: (_) {
                  final live = _controller.value.getMaxScaleOnAxis();
                  if ((live - _scale).abs() > 0.001) {
                    setState(() => _scale = live);
                  }
                },
                child: ImageDisplayWidget(
                  imageData: widget.image,
                  zoomLevel: 1.0,
                  panOffset: Offset.zero,
                  targetWidth: targetWidth,
                ),
              ),
            ),
            // Zoom percentage readout.
            Positioned(
              left: 8,
              top: 8,
              child: _ZoomReadout(colors: colors, scale: _scale),
            ),
            // Zoom / fit controls.
            Positioned(
              left: 8,
              bottom: 8,
              child: _ViewerControls(
                colors: colors,
                canZoomOut: _scale > _minScale + 0.001,
                canZoomIn: _scale < _maxScale - 0.001,
                onZoomIn: () => _zoomBy(_zoomStep, viewport),
                onZoomOut: () => _zoomBy(1 / _zoomStep, viewport),
                onFit: _reset,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ZoomReadout extends StatelessWidget {
  final NightshadeColors colors;
  final double scale;

  const _ZoomReadout({required this.colors, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
        border: Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      child: Text(
        '${(scale * 100).round()}%',
        style: NightshadeTypography.withTabular(
          NightshadeTypography.captionSm.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ViewerControls extends StatelessWidget {
  final NightshadeColors colors;
  final bool canZoomIn;
  final bool canZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  const _ViewerControls({
    required this.colors,
    required this.canZoomIn,
    required this.canZoomOut,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
        border: Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlButton(
            colors: colors,
            icon: LucideIcons.zoomOut,
            tooltip: 'Zoom out',
            onPressed: canZoomOut ? onZoomOut : null,
          ),
          _ControlDivider(colors: colors),
          _ControlButton(
            colors: colors,
            icon: LucideIcons.maximize,
            tooltip: 'Fit to view',
            onPressed: onFit,
          ),
          _ControlDivider(colors: colors),
          _ControlButton(
            colors: colors,
            icon: LucideIcons.zoomIn,
            tooltip: 'Zoom in',
            onPressed: canZoomIn ? onZoomIn : null,
          ),
        ],
      ),
    );
  }
}

class _ControlDivider extends StatelessWidget {
  final NightshadeColors colors;
  const _ControlDivider({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      color: colors.border.withValues(alpha: 0.5),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _ControlButton({
    required this.colors,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(
            icon,
            // Bumped from 16 to 20 so the zoom controls are comfortably
            // tappable on a touch tablet.
            size: 20,
            color: enabled ? colors.textSecondary : colors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Filter + exposure + live-quality metadata badge for the current frame.
///
/// Beyond filter/exposure this overlays the measured quality of the displayed
/// sub — HFR, eccentricity, star count, FWHM — colour-graded for HFR and
/// eccentricity, plus a compact HFR-vs-time sparkline so trends (focus
/// drifting, clouds rolling in) are visible at a glance. Quality fields appear
/// only when measured; an unanalysed frame shows just filter + exposure rather
/// than fabricated zeros.
///
/// Eccentricity is the per-frame median star roundness now measured by the
/// native star detector (carried on [ImageStats.eccentricity]); it renders only
/// when the detector could honestly measure it (enough reliable stars),
/// otherwise it is omitted — never shown as a fabricated 0.
class _FrameBadge extends StatelessWidget {
  final NightshadeColors colors;
  final String? filterLabel;
  final double exposure;
  final ImageStats? stats;
  final List<double> hfrHistory;

  const _FrameBadge({
    required this.colors,
    required this.filterLabel,
    required this.exposure,
    required this.stats,
    required this.hfrHistory,
  });

  Color _hfrColor(double hfr) {
    // Absolute HFR thresholds are arcsec-pixel dependent, but as a fraction-
    // free at-a-glance cue these match the conventional "tight/soft/bad"
    // bands most CMOS imaging trains read at. Relative trend is carried by
    // the sparkline; this is just a static colour cue for the latest value.
    if (hfr <= 3.0) return colors.success;
    if (hfr <= 5.0) return colors.warning;
    return colors.error;
  }

  Color _eccColor(double ecc) {
    // Eccentricity is 0 (round) → 1 (a line). These bands mirror the common
    // reject thresholds (≈0.6 catches trailed frames, ≈0.8 catastrophic
    // tracking): well-guided rigs sit comfortably under 0.5.
    if (ecc <= 0.5) return colors.success;
    if (ecc <= 0.7) return colors.warning;
    return colors.error;
  }

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final hfr = s?.hfr;
    final fwhm = s?.fwhm;
    final eccentricity = s?.eccentricity;
    final starCount = s?.starCount;

    final captionStyle = NightshadeTypography.withTabular(
      NightshadeTypography.captionSm.copyWith(
        fontWeight: FontWeight.w600,
        color: colors.textSecondary,
      ),
    );

    final firstRow = <Widget>[
      Icon(LucideIcons.filter, size: 10, color: colors.textMuted),
      const SizedBox(width: 4),
      Text(filterLabel ?? 'No filter', style: captionStyle),
      const SizedBox(width: 8),
      Container(width: 1, height: 10, color: colors.border),
      const SizedBox(width: 8),
      Text(
        '${exposure.toStringAsFixed(exposure >= 10 ? 0 : 1)}s',
        style: captionStyle,
      ),
    ];

    final qualityChips = <Widget>[
      if (hfr != null)
        _QualityChip(
          colors: colors,
          icon: LucideIcons.circleDot,
          label: 'HFR',
          value: hfr.toStringAsFixed(2),
          valueColor: _hfrColor(hfr),
        ),
      // Renders only when honestly measured (enough reliable stars).
      if (eccentricity != null)
        _QualityChip(
          colors: colors,
          icon: LucideIcons.circleDashed,
          label: 'Ecc',
          value: eccentricity.toStringAsFixed(2),
          valueColor: _eccColor(eccentricity),
        ),
      if (fwhm != null)
        _QualityChip(
          colors: colors,
          icon: LucideIcons.scan,
          label: 'FWHM',
          value: fwhm.toStringAsFixed(2),
        ),
      if (starCount != null)
        _QualityChip(
          colors: colors,
          icon: LucideIcons.star,
          label: 'Stars',
          value: '$starCount',
        ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: firstRow),
          if (qualityChips.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < qualityChips.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  qualityChips[i],
                ],
              ],
            ),
          ],
          // Sparkline needs at least 2 points to draw a line.
          if (hfrHistory.length >= 2) ...[
            const SizedBox(height: 5),
            SizedBox(
              width: 96,
              height: 18,
              child: CustomPaint(
                painter: _HfrSparklinePainter(
                  values: hfrHistory,
                  lineColor: colors.primary,
                  fillColor: colors.primary.withValues(alpha: 0.15),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One compact quality readout (HFR / FWHM / Stars) for the frame badge.
class _QualityChip extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _QualityChip({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: colors.textMuted),
        const SizedBox(width: 3),
        Text(
          '$label ',
          style: NightshadeTypography.captionSm.copyWith(
            color: colors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: NightshadeTypography.withTabular(
            NightshadeTypography.captionSm.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor ?? colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Minimal HFR-vs-time sparkline. Auto-scales to the data's min/max so the
/// trend fills the cell regardless of absolute HFR. Newest point on the right.
class _HfrSparklinePainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  final Color fillColor;

  const _HfrSparklinePainter({
    required this.values,
    required this.lineColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    var minV = values.first;
    var maxV = values.first;
    for (final v in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final range = (maxV - minV).abs();
    // Flat series: draw a centred line rather than dividing by zero.
    final span = range < 1e-6 ? 1.0 : range;

    final dx = size.width / (values.length - 1);
    double yFor(double v) {
      final norm = (v - minV) / span; // 0 (best/low) .. 1 (worst/high)
      // Lower HFR is better → draw it higher on screen (smaller y).
      return size.height - (1.0 - norm) * size.height;
    }

    final linePath = Path();
    for (var i = 0; i < values.length; i++) {
      final x = dx * i;
      final y = yFor(values[i]);
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }

    final fillPath = Path.from(linePath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fillPath, Paint()..color = fillColor);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeJoin = StrokeJoin.round,
    );

    // Marker on the latest point.
    final lastX = dx * (values.length - 1);
    final lastY = yFor(values.last);
    canvas.drawCircle(Offset(lastX, lastY), 1.8, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(covariant _HfrSparklinePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor;
  }
}

/// Vertical, scrollable column of recent-capture thumbnails to the right of the
/// main image. Newest-first; the cell matching the currently-displayed frame is
/// highlighted, and tapping any cell opens [_FrameInspectDialog].
class _HistoryColumn extends StatelessWidget {
  final NightshadeColors colors;
  final List<CapturedImage> images;
  final CapturedImageData? currentImage;

  /// Cap the column so a long night never builds an unbounded widget list;
  /// older frames roll off the top (newest-first).
  static const int _maxFrames = 24;

  const _HistoryColumn({
    required this.colors,
    required this.images,
    required this.currentImage,
  });

  @override
  Widget build(BuildContext context) {
    final total = images.length;
    final tail =
        total > _maxFrames ? images.sublist(total - _maxFrames) : images;
    final newestFirst = tail.reversed.toList(growable: false);

    // Identify which history row corresponds to the live frame so it can be
    // highlighted. The live frame and its persisted row share a file path; fall
    // back to the capture timestamp when the path is absent.
    final currentPath = currentImage?.filePath;
    final currentAt = currentImage?.capturedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(LucideIcons.galleryVerticalEnd,
                size: 12, color: colors.textMuted),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'History',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: colors.textMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        Expanded(
          child: ListView.separated(
            itemCount: newestFirst.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: NightshadeTokens.spaceSm),
            itemBuilder: (context, index) {
              final image = newestFirst[index];
              final isCurrent = _matchesCurrent(image, currentPath, currentAt);
              return _HistoryTile(
                colors: colors,
                image: image,
                isCurrent: isCurrent,
              );
            },
          ),
        ),
      ],
    );
  }

  bool _matchesCurrent(
    CapturedImage image,
    String? currentPath,
    DateTime? currentAt,
  ) {
    if (currentPath != null &&
        currentPath.isNotEmpty &&
        image.filePath.isNotEmpty) {
      return image.filePath == currentPath;
    }
    if (currentAt != null) {
      return image.capturedAt == currentAt;
    }
    return false;
  }
}

class _HistoryTile extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final CapturedImage image;
  final bool isCurrent;

  const _HistoryTile({
    required this.colors,
    required this.image,
    required this.isCurrent,
  });

  @override
  ConsumerState<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends ConsumerState<_HistoryTile> {
  Future<Uint8List?>? _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _loadBytes();
  }

  @override
  void didUpdateWidget(covariant _HistoryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.id != widget.image.id ||
        oldWidget.image.filePath != widget.image.filePath) {
      _bytesFuture = _loadBytes();
    }
  }

  Future<Uint8List?> _loadBytes() async {
    final imageId = int.tryParse(widget.image.id);
    if (imageId == null) return null;
    try {
      final backend = ref.read(imagingBackendProvider);
      final bytes = await backend.getImageThumbnail(imageId);
      if (bytes.isNotEmpty) return bytes;
    } catch (e) {
      // A missing thumbnail is a real condition but must not take down the
      // whole column; log it and fall back to the placeholder icon.
      ref.read(loggingServiceProvider).debug(
            'RunDashboardLiveFrame history thumbnail fetch failed for image '
            '${widget.image.id}: $e',
            source: 'RunDashboardLiveFrame',
          );
    }
    return null;
  }

  String _filterLabel() => filterLabel(widget.image.settings.filter);

  String _exposureLabel() {
    final secs = widget.image.settings.exposureTime;
    if (secs >= 1) return '${secs.toStringAsFixed(0)}s';
    return '${secs.toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final highlight = widget.isCurrent;
    return Tooltip(
      message: '${_filterLabel()} · ${_exposureLabel()}',
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
        onTap: () => _FrameInspectDialog.show(context, image: widget.image),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusSm),
                  border: Border.all(
                    color: highlight ? colors.primary : colors.border,
                    width: highlight ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _HistoryThumb(
                  bytesFuture: _bytesFuture,
                  fallbackFilePath: widget.image.filePath,
                  colors: colors,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  _filterLabel(),
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize9,
                    fontWeight: FontWeight.w700,
                    color: highlight ? colors.primary : colors.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _exposureLabel(),
                    style: NightshadeTypography.withTabular(
                      TextStyle(
                          fontSize: NightshadeTypography.fontSize9,
                          color: colors.textMuted),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Thumbnail image for a history cell. Mirrors the recent-frames strip: prefer
/// the backend thumbnail (a pre-rendered JPEG that decodes both locally and
/// remotely), then a local raster file, then a placeholder icon.
class _HistoryThumb extends ConsumerWidget {
  final Future<Uint8List?>? bytesFuture;
  final String fallbackFilePath;
  final NightshadeColors colors;

  const _HistoryThumb({
    required this.bytesFuture,
    required this.fallbackFilePath,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    return FutureBuilder<Uint8List?>(
      future: bytesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.4,
                valueColor: AlwaysStoppedAnimation<Color>(colors.textMuted),
              ),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _placeholder(),
          );
        }
        if (!isRemoteMode && _isImageLikePath(fallbackFilePath)) {
          return Image.file(
            File(fallbackFilePath),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _placeholder(),
          );
        }
        return _placeholder();
      },
    );
  }

  Widget _placeholder() => Center(
        child: Icon(LucideIcons.image, size: 16, color: colors.textMuted),
      );

  bool _isImageLikePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.tif') ||
        lower.endsWith('.tiff');
  }
}

/// Modal that inspects a previously-captured frame: a larger preview plus its
/// filter / exposure / capture-time metadata. Uses the same backend-thumbnail
/// path as the strip so it works both locally and against a remote host.
class _FrameInspectDialog extends ConsumerWidget {
  final CapturedImage image;

  const _FrameInspectDialog({required this.image});

  static Future<void> show(
    BuildContext context, {
    required CapturedImage image,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _FrameInspectDialog(image: image),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final dialogSize = AdaptiveDialogConstraints.dialogSize(
      context,
      designWidth: 560,
      designHeight: 560,
    );
    return Dialog(
      child: SizedBox(
        width: dialogSize.width,
        height: dialogSize.height,
        child: Padding(
          padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.image, size: 16, color: colors.primary),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Expanded(
                    child: Text(
                      _fileName(image.filePath),
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize14,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 16),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusMd),
                  child: Container(
                    color: colors.background,
                    width: double.infinity,
                    child: _InspectPreview(image: image, colors: colors),
                  ),
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              _MetaRow(image: image, colors: colors),
            ],
          ),
        ),
      ),
    );
  }

  String _fileName(String path) {
    if (path.isEmpty) return image.targetName ?? 'Captured frame';
    return path.split(RegExp(r'[/\\]')).last;
  }
}

class _InspectPreview extends ConsumerWidget {
  final CapturedImage image;
  final NightshadeColors colors;

  const _InspectPreview({required this.image, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageId = int.tryParse(image.id);
    if (imageId == null) {
      return _fallback();
    }
    return FutureBuilder<Uint8List>(
      future: ref.read(imagingBackendProvider).getImageThumbnail(imageId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.textMuted,
              ),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _fallback(),
            ),
          );
        }
        return _fallback();
      },
    );
  }

  Widget _fallback() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.imageOff, size: 32, color: colors.textMuted),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            'Preview unavailable',
            style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final CapturedImage image;
  final NightshadeColors colors;

  const _MetaRow({required this.image, required this.colors});

  @override
  Widget build(BuildContext context) {
    final settings = image.settings;
    final exposure = settings.exposureTime;
    final exposureLabel =
        '${exposure.toStringAsFixed(exposure >= 10 ? 0 : 1)}s';
    final captured = image.capturedAt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final timeLabel =
        '${two(captured.hour)}:${two(captured.minute)}:${two(captured.second)}';

    return Wrap(
      spacing: NightshadeTokens.spaceLg,
      runSpacing: NightshadeTokens.spaceSm,
      children: [
        _MetaChip(
          colors: colors,
          icon: LucideIcons.filter,
          label: settings.filter ?? 'L',
        ),
        _MetaChip(
          colors: colors,
          icon: LucideIcons.timer,
          label: exposureLabel,
        ),
        _MetaChip(
          colors: colors,
          icon: LucideIcons.clock,
          label: timeLabel,
        ),
        if (image.stats?.hfr != null)
          _MetaChip(
            colors: colors,
            icon: LucideIcons.star,
            label: 'HFR ${image.stats!.hfr!.toStringAsFixed(2)}',
          ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;

  const _MetaChip({
    required this.colors,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: colors.textMuted),
        const SizedBox(width: 4),
        Text(
          label,
          style: NightshadeTypography.withTabular(
            NightshadeTypography.labelSm.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
