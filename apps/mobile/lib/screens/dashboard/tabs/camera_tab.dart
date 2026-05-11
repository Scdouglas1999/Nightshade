import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Camera tab — phone-native imaging controls:
///   * Last image as a thumbnail (tap → fullscreen, long-press → copy path)
///   * Live exposure progress bar with elapsed/remaining/HFR
///   * Expose / Abort buttons (capture or cancel)
///   * Cooling status (sensor temp, cooler power)
///   * Filter selector (when a filter wheel is connected)
class CameraTab extends ConsumerWidget {
  const CameraTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraStateProvider);
    final filterState = ref.watch(filterWheelStateProvider);
    final current = ref.watch(currentImageProvider);
    final exposure = ref.watch(exposureProgressProvider);
    final settings = ref.watch(exposureSettingsProvider);

    if (cameraState.connectionState != DeviceConnectionState.connected) {
      return const EmptyState(
        icon: LucideIcons.camera,
        title: 'Camera not connected',
        body: 'Connect the camera from the Devices tab to start capturing '
            'and adjust cooling.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ThumbnailCard(image: current),
        const SizedBox(height: 12),
        _ExposureControls(
          state: cameraState,
          progress: exposure,
          settings: settings,
        ),
        const SizedBox(height: 12),
        _CoolingCard(state: cameraState),
        const SizedBox(height: 12),
        _FilterCard(state: filterState),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ThumbnailCard extends StatelessWidget {
  final CapturedImageData? image;
  const _ThumbnailCard({required this.image});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    if (image == null) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.image, size: 36, color: colors.textMuted),
            const SizedBox(height: 8),
            Text(
              'No image yet',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Take an exposure to see it here',
              style: TextStyle(color: colors.textMuted, fontSize: 11),
            ),
          ],
        ),
      );
    }

    final img = image!;
    return GestureDetector(
      onTap: () => _showFullscreen(context, img),
      onLongPress: () => _copyPath(context, img),
      child: Container(
        decoration: BoxDecoration(
          color: colors.background,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: img.width / img.height,
          child: _ImagePainterWidget(image: img),
        ),
      ),
    );
  }

  void _showFullscreen(BuildContext context, CapturedImageData img) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullscreenImage(image: img),
        // Why fullscreen route: a Dialog clips against the safe area and
        // leaves the bottom nav visible behind the image. A standalone
        // PageRoute lets us paint over the entire screen and pop with the
        // OS back gesture (swipe-back on iOS, back arrow on Android).
        fullscreenDialog: true,
      ),
    );
  }

  void _copyPath(BuildContext context, CapturedImageData img) {
    final path = img.filePath;
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image was not saved to disk')),
      );
      return;
    }
    // We surface the path via SnackBar rather than auto-copying to the
    // clipboard because mobile devices don't always have a writable user
    // gallery for FITS / raw frames — pasting the path into the desktop
    // file manager is the closest mobile equivalent.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved at: $path'),
        duration: const Duration(seconds: 6),
      ),
    );
  }
}

/// Async-decoded image painter — we can't render the RGBA buffer with
/// `Image.memory` because that expects encoded PNG/JPEG bytes.
class _ImagePainterWidget extends StatefulWidget {
  final CapturedImageData image;
  const _ImagePainterWidget({required this.image});

  @override
  State<_ImagePainterWidget> createState() => _ImagePainterWidgetState();
}

class _ImagePainterWidgetState extends State<_ImagePainterWidget> {
  ui.Image? _decoded;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(_ImagePainterWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _decoded = null;
      _decode();
    }
  }

  void _decode() {
    final img = widget.image;
    ui.decodeImageFromPixels(
      Uint8List.fromList(img.displayData),
      img.width,
      img.height,
      ui.PixelFormat.rgba8888,
      (decoded) {
        if (!mounted) return;
        setState(() => _decoded = decoded);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_decoded == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return CustomPaint(
      painter: _RawImagePainter(_decoded!),
      child: const SizedBox.expand(),
    );
  }
}

class _RawImagePainter extends CustomPainter {
  final ui.Image image;
  _RawImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    // Fit-inside scaling preserves the sensor aspect ratio.
    final fittedSrc = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, fittedSrc, dst, Paint());
  }

  @override
  bool shouldRepaint(_RawImagePainter old) => old.image != image;
}

class _FullscreenImage extends StatelessWidget {
  final CapturedImageData image;
  const _FullscreenImage({required this.image});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          image.targetName ?? 'Last capture',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          // Why InteractiveViewer: pinch-zoom and pan on a fullscreen
          // image is the table-stakes UX users expect from a phone photo
          // viewer.
          maxScale: 8.0,
          child: AspectRatio(
            aspectRatio: image.width / image.height,
            child: _ImagePainterWidget(image: image),
          ),
        ),
      ),
    );
  }
}

class _ExposureControls extends ConsumerStatefulWidget {
  final CameraState state;
  final ExposureProgress progress;
  final ExposureSettings settings;

  const _ExposureControls({
    required this.state,
    required this.progress,
    required this.settings,
  });

  @override
  ConsumerState<_ExposureControls> createState() => _ExposureControlsState();
}

class _ExposureControlsState extends ConsumerState<_ExposureControls> {
  bool _starting = false;

  Future<void> _expose() async {
    setState(() => _starting = true);
    try {
      final session = ref.read(sessionStateProvider);
      final stats = ref.read(lastImageStatsProvider.notifier);
      final result = await ref
          .read(imagingServiceProvider)
          .captureImage(
            settings: widget.settings,
            targetName: session.targetName,
          );
      if (result != null && mounted) {
        ref.read(currentImageProvider.notifier).state = result;
        stats.state = result.stats;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Capture failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _abort() {
    ref.read(imagingServiceProvider).cancelExposure();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final lastStats = ref.watch(lastImageStatsProvider);
    final isExposing = widget.state.isExposing || _starting;
    final pct = widget.progress.percent.clamp(0.0, 100.0);
    final hfr = lastStats?.hfr;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.timer, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Exposure',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${widget.settings.exposureTime.toStringAsFixed(1)} s • '
                'gain ${widget.settings.gain}',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
          if (isExposing) ...[
            const SizedBox(height: 12),
            NightshadeProgressBar(
              value: pct / 100.0,
              height: 8,
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${widget.progress.elapsed.toStringAsFixed(0)}s / '
                  '${(widget.progress.elapsed + widget.progress.remaining).toStringAsFixed(0)}s',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                if (widget.progress.isDownloading)
                  Text('Downloading…',
                      style:
                          TextStyle(color: colors.warning, fontSize: 12)),
                if (hfr != null && hfr > 0)
                  Text('HFR ${hfr.toStringAsFixed(2)}',
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 12)),
              ],
            ),
          ] else if (hfr != null && hfr > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Last HFR ${hfr.toStringAsFixed(2)} px',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: NightshadeButton(
                  label: isExposing ? 'Capturing…' : 'Expose',
                  icon: isExposing ? null : LucideIcons.zap,
                  size: ButtonSize.large,
                  isLoading: isExposing,
                  onPressed: isExposing ? null : _expose,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NightshadeButton(
                  label: 'Abort',
                  icon: LucideIcons.square,
                  size: ButtonSize.large,
                  variant: ButtonVariant.destructive,
                  onPressed: isExposing ? _abort : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoolingCard extends ConsumerWidget {
  final CameraState state;
  const _CoolingCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final service = ref.read(deviceServiceProvider);
    final temp = state.temperature;
    final power = state.coolerPower;

    Future<void> guard(Future<void> Function() fn) async {
      try {
        await fn();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.snowflake, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Cooling',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (state.isCooling)
                _Pill(label: 'On', color: colors.success)
              else if (state.isWarming)
                _Pill(label: 'Warming', color: colors.warning)
              else
                _Pill(label: 'Off', color: colors.textMuted),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'Sensor',
                  value: temp != null
                      ? '${temp.toStringAsFixed(1)} °C'
                      : '—',
                  colors: colors,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Target',
                  value: '${state.targetTemp.toStringAsFixed(0)} °C',
                  colors: colors,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Power',
                  value: power != null
                      ? '${power.toStringAsFixed(0)}%'
                      : '—',
                  colors: colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: NightshadeButton(
                  label: state.isCooling ? 'Stop cooling' : 'Cool to target',
                  icon: state.isCooling
                      ? LucideIcons.x
                      : LucideIcons.thermometerSnowflake,
                  size: ButtonSize.large,
                  variant: state.isCooling
                      ? ButtonVariant.outline
                      : ButtonVariant.primary,
                  onPressed: () => guard(() async {
                    if (state.isCooling) {
                      await service.warmCamera();
                    } else {
                      await service.setCameraCooling(
                        enabled: true,
                        targetTemp: state.targetTemp,
                      );
                    }
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterCard extends ConsumerWidget {
  final FilterWheelState state;
  const _FilterCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    if (state.connectionState != DeviceConnectionState.connected) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.filter, size: 18, color: colors.textMuted),
            const SizedBox(width: 8),
            Text(
              'Filter wheel not connected',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final filters = state.filterNames;
    final selected = state.currentPosition;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.filter, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Filter',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (state.isMoving)
                _Pill(label: 'Moving', color: colors.warning)
              else
                _Pill(
                  label: state.currentFilterName ?? 'Slot ${selected ?? "?"}',
                  color: colors.primary,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (filters.isEmpty)
            Text(
              'No filters defined in profile',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < filters.length; i++)
                  _FilterChip(
                    label: filters[i],
                    selected: i == selected,
                    disabled: state.isMoving,
                    onTap: () async {
                      try {
                        await ref
                            .read(deviceServiceProvider)
                            .setFilterWheelPosition(i);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Filter change failed: $e')));
                        }
                      }
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        // 44 pt height for HIG compliance.
        constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surfaceAlt,
          border: Border.all(
            color: selected ? colors.primary : colors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: disabled
                ? colors.textMuted
                : (selected ? colors.background : colors.textSecondary),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  const _Metric({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: colors.textMuted)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontFamily: 'monospace',
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
