import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart' hide ConnectionState;
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../imaging/widgets/image_display.dart';

/// Live-frame tile for the Run dashboard.
///
/// Layout: the current sub-exposure fills the main area on the left, with a
/// vertical, scrollable column of recent-capture thumbnails pinned to the
/// right. This keeps the main image near-square (instead of the old wide/short
/// band that the horizontal history strip forced) while still surfacing the
/// session's frame history at a glance.
///
/// Interaction model (see [_LiveFrameViewer]):
/// - Zoom is driven by on-image **buttons** (in / out / fit), never the mouse
///   wheel — wheel-zoom let the image jump off-canvas with no way back.
/// - Pan is left-click-and-drag, clamped so the frame can never be dragged
///   fully off-canvas; "fit" recentres and rescales to fill.
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
    final sessionImages = ref.watch(sessionImagesProvider);

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
          );

          if (!showHistory) {
            return main;
          }

          return Row(
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
        },
      ),
    );
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

  const _FramePane({
    required this.colors,
    required this.image,
    required this.filterLabel,
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
            style: TextStyle(fontSize: 12, color: colors.textMuted),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _controller,
                // Wheel / pinch scaling is disabled on purpose — zoom is
                // button-only so the frame can never jump off-canvas.
                scaleEnabled: false,
                panEnabled: true,
                // `constrained: true` keeps the (scaled) child inside the
                // viewport, which clamps the pan so the image can't be dragged
                // fully off-canvas.
                constrained: true,
                minScale: _minScale,
                maxScale: _maxScale,
                child: ImageDisplayWidget(
                  imageData: widget.image,
                  zoomLevel: 1.0,
                  panOffset: Offset.zero,
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
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? colors.textSecondary : colors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Filter + exposure metadata badge for the current frame.
class _FrameBadge extends StatelessWidget {
  final NightshadeColors colors;
  final String? filterLabel;
  final double exposure;

  const _FrameBadge({
    required this.colors,
    required this.filterLabel,
    required this.exposure,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.filter, size: 10, color: colors.textMuted),
          const SizedBox(width: 4),
          Text(
            filterLabel ?? 'No filter',
            style: NightshadeTypography.withTabular(
              NightshadeTypography.captionSm.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 10, color: colors.border),
          const SizedBox(width: 8),
          Text(
            '${exposure.toStringAsFixed(exposure >= 10 ? 0 : 1)}s',
            style: NightshadeTypography.withTabular(
              NightshadeTypography.captionSm.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
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
                  fontSize: 10,
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

  String _filterLabel() => widget.image.settings.filter ?? 'L';

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
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
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
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: highlight ? colors.primary : colors.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _exposureLabel(),
                    style: NightshadeTypography.withTabular(
                      TextStyle(fontSize: 9, color: colors.textMuted),
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
                        fontSize: 14,
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
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
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
