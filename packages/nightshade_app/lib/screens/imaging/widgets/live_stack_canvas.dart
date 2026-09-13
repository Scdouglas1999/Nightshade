import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'depthlock/depthlock_hint.dart';
import 'depthlock/depthlock_region_layer.dart';
import 'depthlock/depthlock_selection.dart';
import 'preview_viewport.dart';
import 'stacking_panel.dart'
    show StackedPreviewStretch, stackedPreviewStretchProvider;

/// Where the live stack canvas is zoomed and panned to.
///
/// Its own state rather than the live view's: the two canvases show different
/// pictures at different scales, and carrying one's zoom onto the other means
/// switching tabs moves the frame under the operator.
@immutable
class StackCanvasView {
  const StackCanvasView({this.zoomLevel = 1.0, this.panOffset = Offset.zero});

  /// Multiplier on top of fit-to-window, matching the live view's convention.
  final double zoomLevel;
  final Offset panOffset;

  StackCanvasView copyWith({double? zoomLevel, Offset? panOffset}) =>
      StackCanvasView(
        zoomLevel: zoomLevel ?? this.zoomLevel,
        panOffset: panOffset ?? this.panOffset,
      );
}

final stackCanvasViewProvider = StateProvider<StackCanvasView>(
  (ref) => const StackCanvasView(),
);

/// The Live stack tab's canvas: the stacked image, pannable and zoomable, with
/// the DepthLock region tool and saved-goal overlay on it.
///
/// Marking here is legitimate because the stacker warps every frame into the
/// reference sub's pixel grid — a rectangle on this image is a rectangle in
/// that sub's pixels. `depthLockStackSelectionProvider` is what enforces the
/// conditions that make that true, including the size check.
class LiveStackCanvas extends ConsumerWidget {
  const LiveStackCanvas({super.key});

  /// Zoom step per press or wheel notch, matching the live view.
  static const double zoomStep = 1.25;
  static const double minZoom = 0.25;
  static const double maxZoom = 8.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.nightshadeColors;
    final stack = ref.watch(liveStackingProvider);
    final view = ref.watch(stackCanvasViewProvider);

    if (stack.previewData == null ||
        stack.previewWidth <= 0 ||
        stack.previewHeight <= 0) {
      return Container(
        color: colors.isRedNight
            ? colors.background
            : NightshadeColors.dark.background,
        child: Center(
          child: _OnCanvas(
            child: EmptyState(
              icon: NightshadeIcons.layers,
              title: stack.status == LiveStackingStatus.running
                  ? 'Waiting for the first stacked frame'
                  : 'No stack running',
              body: stack.status == LiveStackingStatus.running
                  ? 'The stacked image appears here as frames are added.'
                  : 'Start a stack from a reference sub and it appears here.',
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _StackCanvasToolbar(
          onZoomIn: () => _zoom(ref, zoomStep),
          onZoomOut: () => _zoom(ref, 1 / zoomStep),
          onFit: () => ref.read(stackCanvasViewProvider.notifier).state =
              const StackCanvasView(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NightshadeTokens.spaceMd,
            NightshadeTokens.spaceSm,
            NightshadeTokens.spaceMd,
            0,
          ),
          child: DepthLockHint(
            onMarkRegion: () => ref
                .read(depthLockRegionToolActiveProvider.notifier)
                .state = true,
          ),
        ),
        Expanded(
          child: StackedImageSource(
            data: stack.previewData!,
            width: stack.previewWidth,
            height: stack.previewHeight,
            channels: _previewChannels(stack),
            stretch: ref.watch(stackedPreviewStretchProvider),
            colors: colors,
            builder: (BuildContext context, ui.Image image) {
              return PreviewViewport(
                image: image,
                zoomLevel: view.zoomLevel,
                panOffset: view.panOffset,
                onZoomIn: () => _zoom(ref, zoomStep),
                onZoomOut: () => _zoom(ref, 1 / zoomStep),
                // While the region tool owns the canvas a drag DRAWS. Left
                // enabled, the viewport's pan recogniser competes with the
                // layer's in the same gesture arena, and the rectangle ends
                // up starting wherever the arena happened to resolve rather
                // than where the operator pressed.
                onPanUpdate: ref.watch(depthLockRegionToolActiveProvider)
                    ? null
                    : (Offset delta) => ref
                            .read(stackCanvasViewProvider.notifier)
                            .state = view.copyWith(
                          panOffset: view.panOffset + delta,
                        ),
                overlays: <PreviewOverlayBuilder>[
                  (BuildContext context, PreviewViewportGeometry geometry) {
                    return DepthLockRegionLayer(
                      zoomLevel: geometry.displayScale,
                      imageOffset: geometry.imageOffset,
                      imageSize: geometry.imageSize,
                      // The stack shares its reference sub's pixel grid, so
                      // the sub's astrometry is the stack's astrometry.
                      geometry:
                          ref.watch(depthLockStackSelectionProvider).geometry,
                    );
                  },
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _zoom(WidgetRef ref, double factor) {
    final notifier = ref.read(stackCanvasViewProvider.notifier);
    final current = notifier.state;
    notifier.state = current.copyWith(
      zoomLevel: (current.zoomLevel * factor).clamp(minZoom, maxZoom),
    );
  }

  /// 3 for an interleaved RGB16 stack, 1 for a luminance plane.
  int _previewChannels(LiveStackingState stack) {
    final int pixels = stack.previewWidth * stack.previewHeight;
    if (pixels <= 0) return 1;
    return (stack.previewData?.length ?? 0) >= pixels * 3 ? 3 : 1;
  }
}

/// The canvas's own strip: enter the region tool, and move the view.
class _StackCanvasToolbar extends ConsumerWidget {
  const _StackCanvasToolbar({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.nightshadeColors;
    final selection = ref.watch(depthLockStackSelectionProvider);
    final toolActive = ref.watch(depthLockRegionToolActiveProvider);
    final overlayVisible = ref.watch(depthLockGoalOverlayVisibleProvider);

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              selection.canSelect
                  ? 'Stacked image'
                  : selection.blocker ?? 'Stacked image',
              style: NightshadeTypography.caption.copyWith(
                color: selection.canSelect
                    ? colors.textMuted
                    : colors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Semantics(
            toggled: toolActive,
            child: NightshadeButton(
              label: toolActive ? 'Stop marking' : 'Mark region',
              icon: NightshadeIcons.crosshair,
              size: ButtonSize.small,
              variant: ButtonVariant.ghost,
              semanticsHint: selection.canSelect
                  ? 'Drag two boxes on the stacked image to define a '
                      'DepthLock goal'
                  : selection.blocker,
              onPressed: selection.canSelect
                  ? () {
                      if (toolActive) {
                        cancelDepthLockRegionTool(ref);
                      } else {
                        ref
                            .read(
                              depthLockRegionToolActiveProvider.notifier,
                            )
                            .state = true;
                      }
                    }
                  : null,
            ),
          ),
          NightshadeIconButton(
            icon: overlayVisible
                ? NightshadeIcons.visible
                : NightshadeIcons.hidden,
            tooltip: overlayVisible
                ? 'Hide saved goals on the stack'
                : 'Draw saved goals on the stack',
            size: IconButtonSize.sm,
            selected: overlayVisible,
            onPressed: () => ref
                .read(depthLockGoalOverlayVisibleProvider.notifier)
                .state = !overlayVisible,
          ),
          NightshadeIconButton(
            // The same three glyphs the live view's toolbar uses, so the two
            // canvases are driven by the same picture.
            icon: LucideIcons.zoomIn,
            tooltip: 'Zoom in',
            size: IconButtonSize.sm,
            onPressed: onZoomIn,
          ),
          NightshadeIconButton(
            icon: LucideIcons.zoomOut,
            tooltip: 'Zoom out',
            size: IconButtonSize.sm,
            onPressed: onZoomOut,
          ),
          NightshadeIconButton(
            icon: LucideIcons.scan,
            tooltip: 'Fit to window',
            size: IconButtonSize.sm,
            onPressed: onFit,
          ),
        ],
      ),
    );
  }
}

/// Turns the stacker's u16 buffer into a drawable image.
///
/// The same conversion the side panel's thumbnail does — the shared
/// MAD-based stretch from Rust, then one raw RGBA decode — hoisted so the
/// canvas can own the result and hand it to [PreviewViewport].
class StackedImageSource extends StatefulWidget {
  const StackedImageSource({
    super.key,
    required this.data,
    required this.width,
    required this.height,
    required this.channels,
    required this.stretch,
    required this.colors,
    required this.builder,
  });

  final Uint16List data;
  final int width;
  final int height;
  final int channels;
  final StackedPreviewStretch stretch;
  final NightshadeColors colors;
  final Widget Function(BuildContext context, ui.Image image) builder;

  @override
  State<StackedImageSource> createState() => _StackedImageSourceState();
}

class _StackedImageSourceState extends State<StackedImageSource> {
  ui.Image? _image;
  bool _decoding = false;

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(StackedImageSource oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.data, oldWidget.data) ||
        widget.width != oldWidget.width ||
        widget.height != oldWidget.height ||
        widget.channels != oldWidget.channels ||
        widget.stretch != oldWidget.stretch) {
      _build();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    if (_decoding) return;
    _decoding = true;
    final int w = widget.width;
    final int h = widget.height;
    final int pixels = w * h;
    final int samples = widget.channels == 3 ? 3 : 1;
    if (pixels <= 0 || widget.data.length < pixels * samples) {
      _decoding = false;
      return;
    }
    try {
      final Uint8List rgba = widget.stretch(
        width: w,
        height: h,
        data: widget.data,
        channels: samples,
      );
      if (rgba.length < pixels * 4) {
        developer.log(
          '[LiveStackCanvas] Stretched stack is ${rgba.length} bytes, '
          'expected ${pixels * 4}',
          name: 'LiveStackCanvas',
          level: 900,
        );
        return;
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: w,
        height: h,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
      } else {
        setState(() {
          _image?.dispose();
          _image = frame.image;
        });
      }
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    } catch (error) {
      developer.log(
        '[LiveStackCanvas] Error building the stacked image: $error',
        name: 'LiveStackCanvas',
        level: 900,
        error: error,
      );
    } finally {
      _decoding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return Container(
        color: widget.colors.isRedNight
            ? widget.colors.background
            : NightshadeColors.dark.background,
        child: Center(
          child: _OnCanvas(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.colors.primary,
                  ),
                ),
                const SizedBox(height: NightshadeTokens.spaceSm),
                Builder(
                  builder: (BuildContext inner) => Text(
                    'Rendering the stack…',
                    style: NightshadeTypography.caption.copyWith(
                      color: inner.nightshadeColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return widget.builder(context, image);
  }
}

/// Puts its child on the dark ladder, because what is behind it is a
/// photograph of the night sky in every theme but red night.
class _OnCanvas extends StatelessWidget {
  const _OnCanvas({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final inner = colors.isRedNight ? colors : NightshadeColors.dark;
    return Theme(
      data: Theme.of(
        context,
      ).copyWith(extensions: <ThemeExtension<dynamic>>[inner]),
      child: child,
    );
  }
}
